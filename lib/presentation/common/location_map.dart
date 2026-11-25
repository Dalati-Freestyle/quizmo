/// The map of a map question: in the editor, for the players' guess and for
/// the solution with all guesses.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/engine/geo.dart';
import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

/// A marker on a [LocationMap].
final class LocationPin {
  const LocationPin({
    required this.point,
    required this.color,
    this.label,
    this.isTarget = false,
  });

  final GeoPoint point;
  final Color color;
  final String? label;
  final bool isTarget;
}

/// Shared map with OpenStreetMap tiles and attribution.
///
/// With [onTap] a tap sets a marker; nothing is ever sent by a tap alone.
class LocationMap extends StatefulWidget {
  const LocationMap({
    required this.center,
    required this.zoom,
    this.pins = const [],
    this.onTap,
    this.fitPins = false,
    this.controller,
    this.labelSize = 14,
    super.key,
  });

  final GeoPoint center;
  final double zoom;
  final List<LocationPin> pins;
  final ValueChanged<GeoPoint>? onTap;

  /// Shows every pin (solution with all guesses).
  final bool fitPins;
  final MapController? controller;
  final double labelSize;

  /// The tile servers want to know which app asks.
  static const userAgent = 'com.quizapp.quizmo';

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  bool _failed = false;

  CameraFit? get _fit {
    if (!widget.fitPins || widget.pins.isEmpty) return null;
    final points = [
      for (final pin in widget.pins)
        LatLng(pin.point.latitude, pin.point.longitude),
    ];
    if (points.length == 1) return null;
    return CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(48),
      maxZoom: 12,
    );
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.fitPins && widget.pins.length == 1
        ? widget.pins.single.point
        : null;
    return Stack(
      children: [
        FlutterMap(
          // A new fit for new pins (e.g. the reveal).
          key: ValueKey(widget.fitPins ? widget.pins.length : 0),
          mapController: widget.controller,
          options: MapOptions(
            initialCenter: LatLng(
              single?.latitude ?? widget.center.latitude,
              single?.longitude ?? widget.center.longitude,
            ),
            initialZoom: single != null ? 6 : widget.zoom,
            initialCameraFit: _fit,
            minZoom: 1,
            maxZoom: 18,
            onTap: widget.onTap == null
                ? null
                : (_, point) => widget.onTap!(
                    GeoPoint(
                      point.latitude.clamp(-90, 90),
                      // Wrapped: a tap one world further is the same place.
                      ((point.longitude + 180) % 360 + 360) % 360 - 180,
                    ),
                  ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: LocationMap.userAgent,
              errorTileCallback: (_, _, _) {
                if (!_failed && mounted) setState(() => _failed = true);
              },
            ),
            MarkerLayer(
              markers: [
                for (final pin in widget.pins)
                  Marker(
                    point: LatLng(pin.point.latitude, pin.point.longitude),
                    width: pin.label == null ? 44 : 220,
                    height: 44 + (pin.label == null ? 0 : widget.labelSize * 2),
                    alignment: Alignment.topCenter,
                    child: _PinView(pin: pin, labelSize: widget.labelSize),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_failed)
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Material(
              key: const ValueKey('map-unavailable'),
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  context.tr(
                    'Die Karte konnte nicht geladen werden. Sie braucht Internet.',
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PinView extends StatelessWidget {
  const _PinView({required this.pin, required this.labelSize});

  final LocationPin pin;
  final double labelSize;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        pin.isTarget ? Icons.flag : Icons.location_on,
        size: 44,
        color: pin.color,
        shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
      ),
      if (pin.label case final label?)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: labelSize,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );
}

/// Guesses of a revealed round with their distance, nearest first.
List<({String playerId, LocationAnswer answer, double km})> locationGuesses(
  GameState game,
  LocationQuestion question,
) => [
  for (final answer in game.round.answers.values)
    if (answer case final LocationAnswer guess)
      if (question.distanceOf(guess) case final km?)
        (playerId: guess.playerId, answer: guess, km: km),
]..sort((a, b) => a.km.compareTo(b.km));

/// The solution: the place, every guess with its name or team colour and the
/// distances, framed so that all of them are visible.
class LocationResultView extends StatelessWidget {
  const LocationResultView({
    required this.game,
    required this.question,
    this.large = false,
    this.maxRows = 8,
    super.key,
  });

  final GameState game;
  final LocationQuestion question;
  final bool large;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final target = question.target;
    final guesses = locationGuesses(game, question);
    final palette = Theme.of(context).colorScheme;
    Color colorOf(String playerId) =>
        switch (game.teams[game.players[playerId]?.teamId]) {
          final team? => Color(team.colorValue),
          null => palette.primary,
        };
    String nameOf(String playerId) {
      final player = game.players[playerId];
      final team = game.teams[player?.teamId];
      return team != null && game.sharesTeamAnswers
          ? team.name
          : player?.name ?? playerId;
    }

    final pins = [
      for (final guess in guesses)
        LocationPin(
          point: GeoPoint(guess.answer.latitude, guess.answer.longitude),
          color: colorOf(guess.playerId),
          label: nameOf(guess.playerId),
        ),
      if (target != null)
        LocationPin(
          point: target,
          color: Colors.red.shade700,
          label: question.targetLabel.trim().isEmpty
              ? null
              : question.targetLabel,
          isTarget: true,
        ),
    ];
    final fontSize = large ? 24.0 : 14.0;
    final list = Column(
      key: const ValueKey('location-distances'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, guess) in guesses.take(maxRows).indexed)
          Text(
            '${index + 1}. ${nameOf(guess.playerId)}: ${formatDistance(guess.km)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize),
          ),
        if (guesses.length > maxRows)
          Text(
            context.tr('… und {0} weitere', [guesses.length - maxRows]),
            style: TextStyle(fontSize: fontSize),
          ),
      ],
    );
    final map = ClipRRect(
      borderRadius: BorderRadius.circular(large ? 24 : 12),
      child: LocationMap(
        key: ValueKey('location-result-${question.id}'),
        center: target ?? question.startCenter,
        zoom: question.startZoom,
        pins: pins,
        fitPins: true,
        labelSize: large ? 22 : 12,
      ),
    );
    if (large) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: map),
          const SizedBox(width: 24),
          Expanded(flex: 2, child: SingleChildScrollView(child: list)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: math.min(MediaQuery.sizeOf(context).height * 0.5, 420),
          child: map,
        ),
        const SizedBox(height: 8),
        list,
      ],
    );
  }
}
