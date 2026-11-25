/// Editor of a map question: the place by marker, search or coordinates, the
/// radii of the scoring and the view players start with.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/engine/answer_evaluation.dart';
import '../../../core/models/models.dart';
import '../../../core/net/place_search.dart';
import '../../common/location_map.dart';
import '../../l10n/app_localizations.dart';

class LocationQuestionFields extends StatefulWidget {
  const LocationQuestionFields({
    required this.question,
    required this.onChanged,
    this.search,
    super.key,
  });

  final LocationQuestion question;

  /// The changed kind specific fields, as JSON of the question.
  final ValueChanged<Map<String, Object?>> onChanged;

  /// Replaceable for tests; the public Nominatim service by default.
  final PlaceSearch? search;

  @override
  State<LocationQuestionFields> createState() => _LocationQuestionFieldsState();
}

class _LocationQuestionFieldsState extends State<LocationQuestionFields> {
  late GeoPoint? _target = widget.question.target;
  late String _label = widget.question.targetLabel;
  late final _latitude = TextEditingController(
    text: _target == null ? '' : formatNumber(_target!.latitude),
  );
  late final _longitude = TextEditingController(
    text: _target == null ? '' : formatNumber(_target!.longitude),
  );
  late final _full = TextEditingController(
    text: formatNumber(widget.question.fullPointsKm),
  );
  late final _zero = TextEditingController(
    text: formatNumber(widget.question.zeroPointsKm),
  );
  final _query = TextEditingController();
  final _map = MapController();
  late GeoPoint _startCenter = widget.question.startCenter;
  late double _startZoom = widget.question.startZoom;
  late final PlaceSearch _search = widget.search ?? NominatimPlaceSearch();
  List<PlaceHit>? _hits;
  String? _searchError;
  bool _searching = false;

  @override
  void dispose() {
    for (final controller in [_latitude, _longitude, _full, _zero, _query]) {
      controller.dispose();
    }
    _map.dispose();
    super.dispose();
  }

  static double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  void _changed() => widget.onChanged({
    'target': _target?.toJson(),
    'targetLabel': _label.trim(),
    'fullPointsKm': _parse(_full.text) ?? double.nan,
    'zeroPointsKm': _parse(_zero.text) ?? double.nan,
    'startCenter': _startCenter.toJson(),
    'startZoom': _startZoom,
  });

  /// Marker, search and coordinates always show the same place.
  void _setTarget(GeoPoint point, {String? label, bool move = false}) {
    setState(() {
      _target = point;
      if (label != null) _label = label;
      _latitude.text = point.latitude.toStringAsFixed(6);
      _longitude.text = point.longitude.toStringAsFixed(6);
    });
    if (move) _map.move(LatLng(point.latitude, point.longitude), 12);
    _changed();
  }

  void _typedCoordinates() {
    final latitude = _parse(_latitude.text);
    final longitude = _parse(_longitude.text);
    final point = latitude == null || longitude == null
        ? null
        : GeoPoint(latitude, longitude);
    setState(() => _target = point != null && point.isValid ? point : null);
    _changed();
  }

  Future<void> _find() async {
    final words = _query.text.trim();
    if (words.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _hits = null;
    });
    try {
      final hits = await _search.search(
        words,
        language: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      setState(() {
        _hits = hits;
        if (hits.isEmpty) _searchError = 'Kein Ort gefunden.';
      });
    } on PlaceSearchException catch (error) {
      if (mounted) setState(() => _searchError = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String? _number(String? text, {bool positive = false}) {
    final value = _parse(text ?? '');
    if (value == null || !value.isFinite || (positive && value < 0)) {
      return context.tr('Endliche Zahl angeben.');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapHeight = (MediaQuery.sizeOf(context).height * 0.45).clamp(
      240.0,
      420.0,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Zielort'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('place-search'),
                    controller: _query,
                    decoration: InputDecoration(
                      labelText: context.tr('Ort suchen (z. B. Eiffelturm)'),
                    ),
                    onSubmitted: (_) => _find(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  key: const ValueKey('place-search-button'),
                  onPressed: _searching ? null : _find,
                  icon: const Icon(Icons.search),
                  label: Text(context.tr('Suchen')),
                ),
              ],
            ),
            if (_searching) const LinearProgressIndicator(),
            if (_searchError case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr(error),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_hits case final hits? when hits.isNotEmpty) ...[
              for (final hit in hits)
                ListTile(
                  key: ValueKey('place-hit-${hits.indexOf(hit)}'),
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(hit.name),
                  subtitle: Text(hit.description),
                  onTap: () {
                    _setTarget(
                      GeoPoint(hit.latitude, hit.longitude),
                      label: hit.name,
                      move: true,
                    );
                    setState(() => _hits = null);
                  },
                ),
              Text(
                NominatimPlaceSearch.attribution,
                style: theme.textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: mapHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LocationMap(
                  controller: _map,
                  center: _target ?? _startCenter,
                  zoom: _target == null ? _startZoom : 10,
                  pins: [
                    if (_target case final target?)
                      LocationPin(
                        point: target,
                        color: Colors.red.shade700,
                        isTarget: true,
                      ),
                  ],
                  onTap: (point) => _setTarget(point),
                ),
              ),
            ),
            Text(
              context.tr(
                'Tippe auf die Karte, um den Zielort zu setzen; ein weiterer Tipp verschiebt ihn.',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('target-latitude'),
                    controller: _latitude,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: context.tr('Breitengrad'),
                    ),
                    onChanged: (_) => _typedCoordinates(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('target-longitude'),
                    controller: _longitude,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: context.tr('Längengrad'),
                    ),
                    onChanged: (_) => _typedCoordinates(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('target-label'),
              initialValue: _label,
              decoration: InputDecoration(
                labelText: context.tr(
                  'Name des Orts (optional, Teil der Lösung)',
                ),
              ),
              onChanged: (value) {
                _label = value;
                _changed();
              },
            ),
            const SizedBox(height: 20),
            Text(
              context.tr('Punkte nach Entfernung'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('full-points-km'),
                    controller: _full,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('Volle Punkte bis (km)'),
                    ),
                    validator: (value) => _number(value, positive: true),
                    onChanged: (_) => _changed(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('zero-points-km'),
                    controller: _zero,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('Keine Punkte ab (km)'),
                    ),
                    validator: (value) => _number(value, positive: true),
                    onChanged: (_) => _changed(),
                  ),
                ),
              ],
            ),
            Text(
              context.tr(
                'Dazwischen fallen die Punkte gleichmäßig ab. Gemessen wird die Luftlinie.',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text(
              context.tr('Startausschnitt der Spieler'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _startZoom <= 2
                  ? context.tr('Weltkarte (verrät nichts)')
                  : context.tr('Mitte {0}, Zoom {1}', [
                      _startCenter.label,
                      _startZoom.toStringAsFixed(1),
                    ]),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () {
                    final camera = _map.camera;
                    setState(() {
                      _startCenter = GeoPoint(
                        camera.center.latitude,
                        camera.center.longitude,
                      );
                      _startZoom = camera.zoom.clamp(1, 18);
                    });
                    _changed();
                  },
                  icon: const Icon(Icons.crop_free),
                  label: Text(
                    context.tr('Aktuellen Kartenausschnitt übernehmen'),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _startCenter = const GeoPoint(20, 0);
                      _startZoom = 1.5;
                    });
                    _changed();
                  },
                  icon: const Icon(Icons.public),
                  label: Text(context.tr('Weltkarte')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
