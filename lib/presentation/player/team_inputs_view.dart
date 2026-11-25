import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../common/question_result_view.dart';
import '../l10n/app_localizations.dart';
import 'player_session_cubit.dart';

/// "Your team": what every other member enters right now, live and read only.
class TeamInputsView extends StatefulWidget {
  const TeamInputsView({
    required this.state,
    required this.hostNowMicros,
    super.key,
  });

  final PlayerSessionState state;

  /// Estimated host clock, for "is typing".
  final int Function() hostNowMicros;

  /// How long a change counts as typing.
  static const typingMicros = 3000000;

  /// Whether the panel is shown at all.
  static bool isShown(PlayerSessionState state) {
    final question = state.question;
    final game = state.game;
    final teamId = game?.sharedAnswerTeamOf(state.playerId);
    return question != null &&
        game != null &&
        teamId != null &&
        question is! BuzzerQuestion &&
        state.answers != null &&
        game.round.status != RoundStatus.revealed &&
        state.mayAnswerQuestion &&
        state.mayAnswerPoker &&
        game.players.values.any(
          (player) => player.teamId == teamId && player.id != state.playerId,
        );
  }

  @override
  State<TeamInputsView> createState() => _TeamInputsViewState();
}

class _TeamInputsViewState extends State<TeamInputsView> {
  Timer? _typing;

  @override
  void initState() {
    super.initState();
    _watchTyping();
  }

  @override
  void didUpdateWidget(TeamInputsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _watchTyping();
  }

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  bool _isTyping(AnswerDraft draft) =>
      widget.hostNowMicros() - draft.hostTimestampMicros <
      TeamInputsView.typingMicros;

  /// Rebuilds once when the last "is typing" mark has to disappear.
  void _watchTyping() {
    _typing?.cancel();
    final now = widget.hostNowMicros();
    var left = 0;
    for (final draft in widget.state.answers?.drafts ?? const <AnswerDraft>[]) {
      final remaining =
          draft.hostTimestampMicros + TeamInputsView.typingMicros - now;
      if (remaining > left) left = remaining;
    }
    if (left <= 0) return;
    _typing = Timer(Duration(microseconds: left + 50000), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (!TeamInputsView.isShown(state)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final game = state.game!;
    final answers = state.answers!;
    final teamId = game.sharedAnswerTeamOf(state.playerId);
    final counting = answers.countingPlayerId;
    final members = [
      for (final player in game.players.values)
        if (player.teamId == teamId && player.id != state.playerId) player,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Card(
      key: const ValueKey('team-inputs'),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Dein Team'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final member in members)
                      _row(context, member, counting == member.id),
                  ],
                ),
              ),
            ),
            if (counting == state.playerId)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _counts(context, context.tr('Deine Eingabe zählt')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _counts(BuildContext context, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.star, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    ],
  );

  Widget _row(BuildContext context, Player member, bool counts) {
    final theme = Theme.of(context);
    final question = widget.state.question!;
    final answers = widget.state.answers!;
    final sent = answers.team
        .where((answer) => answer.playerId == member.id)
        .firstOrNull;
    final draft = answers.drafts
        .where((draft) => draft.playerId == member.id)
        .firstOrNull;
    final content = draft?.content;
    // Input that was changed after sending is shown instead of the answer.
    final edited =
        draft != null &&
        (sent == null ||
            (draft.hostTimestampMicros > sent.hostTimestampMicros &&
                (content == null || !sameAnswerContent(content, sent))));
    final shown = edited ? content : sent;
    final (icon, status) = !edited && sent != null
        ? (Icons.check_circle_outline, 'abgeschickt')
        : draft != null && _isTyping(draft)
        ? (Icons.edit, 'tippt …')
        : content != null
        ? (Icons.edit_note, 'bearbeitet')
        : (Icons.hourglass_empty, 'noch nichts eingegeben');
    return Padding(
      key: ValueKey('team-input-${member.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.outline),
              Text(
                member.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                [
                  context.tr(status),
                  if (!member.isConnected) context.tr('getrennt'),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              if (counts) _counts(context, context.tr('zählt')),
            ],
          ),
          if (shown != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 26),
              child: Text(
                answerLabel(shown, question, context: context),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
