/// The pop-up in which the host judges all answers of a question together.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/engine/answer_evaluation.dart';
import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';
import '../common/question_media_view.dart';
import '../common/question_result_view.dart';
import '../l10n/app_localizations.dart';
import '../common/media_playback.dart';

/// One line of the pop-up: a team, or a player without a team.
final class GradingRow {
  const GradingRow({
    required this.id,
    required this.name,
    this.color,
    this.playerId,
    this.answer,
    this.sender,
    this.recommended,
    this.recommendation,
    this.adopted = false,
    this.practice = false,
  });

  /// Team id, or the player id of a player who answers alone.
  final String id;
  final String name;
  final Color? color;

  /// Player the verdict is booked on; `null` when there is nothing to judge.
  final String? playerId;
  final AnswerSubmission? answer;

  /// Who sent the answer of a team.
  final String? sender;

  /// What the app would decide, `null` without a recommendation.
  final bool? recommended;
  final String? recommendation;

  /// Taken over when the answers closed.
  final bool adopted;

  /// A bankrupt poker team that only plays for practice.
  final bool practice;

  /// Whether a verdict is needed before the grades can be confirmed.
  bool get needsVerdict => answer != null;
}

/// Everybody who took part in the round on stage, in a stable order.
List<GradingRow> gradingRows(GameState game) {
  final round = game.round;
  final question = round.question;
  if (question == null) return const [];
  final poker = game.poker;

  GradingRow row({
    required String id,
    required String name,
    required Iterable<Player> members,
    Color? color,
    String? teamId,
  }) {
    final answer = teamId == null
        ? round.answers[id]
        : game.teamAnswerOf(teamId);
    // A spoken answer may be judged although nobody typed one.
    final judged =
        answer?.playerId ??
        (round.verbal
            ? members
                  .where((player) => game.mayJudgeVerbally(player.id))
                  .map((player) => player.id)
                  .firstOrNull
            : null);
    final typed = answer != null && answer is! VerbalAnswer;
    final (recommended, recommendation) = switch ((question, answer)) {
      _ when !typed || !question.hasSolution => (null, null),
      (
        ShortAnswerQuestion(:final acceptedAnswers?, :final maxEdits),
        ShortAnswer(:final text),
      ) =>
        switch (recommendTextAnswer(text, acceptedAnswers, maxEdits)) {
          TextAnswerRecommendation.exactMatch => (
            true,
            'Empfehlung: Passt zur Lösung.',
          ),
          TextAnswerRecommendation.possibleTypo => (
            true,
            'Empfehlung: Fast richtig, vermutlich ein Tippfehler.',
          ),
          TextAnswerRecommendation.different => (
            false,
            'Empfehlung: Weicht von den hinterlegten Lösungen ab.',
          ),
        },
      (_, final AnswerSubmission submitted) =>
        question.accuracy(submitted) == 1
            ? (true, 'Automatische Prüfung: richtig.')
            : (false, 'Automatische Prüfung: nicht ganz richtig.'),
      _ => (null, null),
    };
    return GradingRow(
      id: id,
      name: name,
      color: color,
      playerId: judged,
      answer: answer,
      sender: teamId == null || answer == null
          ? null
          : game.players[answer.playerId]?.name,
      recommended: recommended,
      recommendation: recommendation,
      adopted:
          answer != null && round.adoptedPlayerIds.contains(answer.playerId),
      practice:
          poker != null &&
          teamId != null &&
          (poker.wagers[teamId] ?? 0) == 0 &&
          (poker.chips[teamId] ?? 0) == 0,
    );
  }

  bool takesPart(String? teamId, Iterable<Player> members) {
    if (members.any((player) => round.answers.containsKey(player.id))) {
      return true;
    }
    if (poker != null) {
      return (poker.wagers[teamId] ?? 0) > 0 || (poker.chips[teamId] ?? 0) == 0;
    }
    return members.any(
      (player) => player.isConnected && game.mayAnswerQuestion(player.id),
    );
  }

  final shared = game.sharesTeamAnswers;
  return [
    if (shared)
      for (final team in game.teams.values)
        if ([
              for (final id in game.orderedPlayerIds)
                if (game.players[id]!.teamId == team.id) game.players[id]!,
            ]
            case final members
            when members.isNotEmpty && takesPart(team.id, members))
          row(
            id: team.id,
            name: team.name,
            members: members,
            color: Color(team.colorValue),
            teamId: team.id,
          ),
    for (final id in game.orderedPlayerIds)
      if (game.players[id] case final player?
          when (!shared || player.teamId == null) &&
              takesPart(player.teamId, [player]))
        row(id: id, name: player.name, members: [player]),
  ];
}

/// The host's choices for one round; kept while the pop-up is closed.
final class GradingSelection extends ChangeNotifier {
  final Map<String, bool> _verdicts = {};
  final Map<String, String> reasons = {};

  bool? operator [](String rowId) => _verdicts[rowId];

  void select(String rowId, bool? correct) {
    if (correct == null) {
      _verdicts.remove(rowId);
    } else {
      _verdicts[rowId] = correct;
    }
    notifyListeners();
  }

  /// Takes the recommendation for every row that is still open.
  void acceptRecommendations(Iterable<GradingRow> rows) {
    for (final row in rows) {
      if (row.recommended case final recommended?) {
        _verdicts.putIfAbsent(row.id, () => recommended);
      }
    }
    notifyListeners();
  }

  int graded(Iterable<GradingRow> rows) => rows
      .where((row) => row.needsVerdict && _verdicts.containsKey(row.id))
      .length;
}

/// Opens the pop-up once per round as soon as the answers are closed, and
/// again on request ([GradingHost.maybeOf]). Shared by dashboard and preview.
class GradingHost extends StatefulWidget {
  const GradingHost({required this.engine, required this.child, super.key});

  final QuizEngineBloc engine;
  final Widget child;

  static GradingHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<GradingHostState>();

  @override
  State<GradingHost> createState() => GradingHostState();
}

class GradingHostState extends State<GradingHost> {
  final Set<String> _opened = {};
  String? _selectionKey;
  GradingSelection _selection = GradingSelection();
  bool _isOpen = false;

  static String? _key(GameState game) => game.round.question == null
      ? null
      : '${game.round.question!.id}:${game.round.startedAtHostMicros}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpen());
  }

  bool get canGrade {
    final game = widget.engine.state.game;
    return !game.recoveryPaused &&
        game.round.manualGrading &&
        game.round.status == RoundStatus.locked &&
        !widget.engine.isWaitingForDrafts;
  }

  void _maybeOpen() {
    if (!mounted || widget.engine.isClosed || !canGrade) return;
    final key = _key(widget.engine.state.game);
    if (key == null || !_opened.add(key)) return;
    open();
  }

  /// Opens the pop-up for the closed answers on stage.
  Future<void> open() async {
    final game = widget.engine.state.game;
    final key = _key(game);
    if (_isOpen || key == null || !canGrade) return;
    _opened.add(key);
    if (_selectionKey != key) {
      _selectionKey = key;
      _selection = GradingSelection();
    }
    // Verdicts that were given before (for example by preview bots).
    for (final row in gradingRows(game)) {
      final verdict = game.round.answerVerdicts[row.playerId];
      if (verdict != null && _selection[row.id] == null) {
        _selection.select(row.id, verdict == 1);
      }
    }
    _isOpen = true;
    await showDialog<void>(
      context: context,
      builder: (_) => GradingDialog(
        engine: widget.engine,
        roundKey: key,
        selection: _selection,
      ),
    );
    _isOpen = false;
    if (mounted) _maybeOpen();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<QuizEngineBloc, QuizEngineState>(
        bloc: widget.engine,
        listener: (_, _) => _maybeOpen(),
        child: widget.child,
      );
}

/// See [GradingHost].
class GradingDialog extends StatelessWidget {
  const GradingDialog({
    required this.engine,
    required this.roundKey,
    required this.selection,
    super.key,
  });

  final QuizEngineBloc engine;
  final String roundKey;
  final GradingSelection selection;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final fullscreen = size.width < 600 || size.height < 480;
    final body = BlocConsumer<QuizEngineBloc, QuizEngineState>(
      bloc: engine,
      listener: (context, state) {
        // Confirmed here or settled elsewhere: never judge another round.
        if (GradingHostState._key(state.game) != roundKey ||
            state.game.round.status != RoundStatus.locked) {
          final route = ModalRoute.of(context);
          if (route != null && route.isActive) {
            Navigator.of(context).removeRoute(route);
          }
        }
      },
      builder: (context, state) => GradingHostState._key(state.game) != roundKey
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: selection,
              builder: (context, _) => _content(context, state.game),
            ),
    );
    return fullscreen
        ? Dialog.fullscreen(child: SafeArea(child: body))
        : Dialog(
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 820,
                maxHeight: size.height * .9,
              ),
              child: body,
            ),
          );
  }

  Widget _content(BuildContext context, GameState game) {
    final theme = Theme.of(context);
    final question = game.round.question!;
    final rows = gradingRows(game);
    final needed = rows.where((row) => row.needsVerdict).length;
    final graded = selection.graded(rows);
    final open = needed - graded;
    final recommendable = rows.any(
      (row) =>
          row.needsVerdict &&
          row.recommended != null &&
          selection[row.id] == null,
    );
    // Very little height (phone in landscape, large text): everything scrolls.
    return LayoutBuilder(
      builder: (context, constraints) {
        final header = _header(context, game, question);
        final list = [
          for (final row in rows)
            _GradingTile(
              key: ValueKey('grading-${row.id}'),
              row: row,
              question: question,
              selection: selection,
            ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.tr('Niemand hat geantwortet.')),
            ),
        ];
        final actions = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  context.tr('{0} von {1} bewertet', [graded, needed]),
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (recommendable)
                OutlinedButton.icon(
                  key: const ValueKey('accept-recommendations'),
                  onPressed: () => selection.acceptRecommendations(
                    rows.where((row) => row.needsVerdict),
                  ),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(context.tr('Empfehlungen übernehmen')),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('Später')),
              ),
              FilledButton.icon(
                key: const ValueKey('confirm-grades'),
                onPressed: open > 0 ? null : () => _confirm(game, rows),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  open > 0
                      ? context.tr('Bestätigen (noch {0})', [open])
                      : context.tr('Bestätigen'),
                ),
              ),
            ],
          ),
        );
        if (constraints.maxHeight / MediaQuery.textScalerOf(context).scale(1) <
            360) {
          return ListView(children: [header, ...list, actions]);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .4,
              ),
              child: SingleChildScrollView(primary: false, child: header),
            ),
            const Divider(height: 1),
            Flexible(child: ListView(shrinkWrap: true, children: list)),
            const Divider(height: 1),
            actions,
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, GameState game, Question question) {
    final theme = Theme.of(context);
    final solution = question.hasSolution ? question.solutionLabel.trim() : '';
    final notes = question.adminNotes.trim();
    return Padding(
      key: const ValueKey('grading-header'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('Antworten bewerten'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(question.prompt, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      solution.isEmpty
                          ? context.tr('Keine Musterlösung hinterlegt.')
                          : context.tr('Musterlösung: {0}', [
                              question is TrueFalseQuestion
                                  ? context.tr(solution)
                                  : solution,
                            ]),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (notes.isNotEmpty || question.solutionMedia.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.tr('Notizen und Lösungsmedien')),
              children: [
                if (notes.isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(notes),
                  ),
                if (question.solutionMedia.isNotEmpty)
                  QuestionMediaView(
                    media: question.solutionMedia,
                    playback: MediaPlayback.stopped,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  void _confirm(GameState game, List<GradingRow> rows) => engine.add(
    ConfirmGradesEvent(
      questionId: game.round.question!.id,
      startedAtHostMicros: game.round.startedAtHostMicros!,
      grades: {
        for (final row in rows)
          if (row.playerId case final playerId?)
            if (selection[row.id] case final correct?)
              playerId: (
                correct: correct,
                reason: selection.reasons[row.id]?.trim() ?? '',
              ),
      },
    ),
  );
}

class _GradingTile extends StatefulWidget {
  const _GradingTile({
    required this.row,
    required this.question,
    required this.selection,
    super.key,
  });

  final GradingRow row;
  final Question question;
  final GradingSelection selection;

  @override
  State<_GradingTile> createState() => _GradingTileState();
}

class _GradingTileState extends State<_GradingTile> {
  late bool _showReason =
      widget.selection.reasons[widget.row.id]?.isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final answer = row.answer;
    final typed = answer != null && answer is! VerbalAnswer;
    final marks = [
      ?row.sender,
      if (row.adopted) context.tr('beim Ablauf übernommen'),
      if (row.practice) context.tr('Nur Übung'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (row.color case final color?) ...[
                Icon(Icons.circle, size: 14, color: color),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: row.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (marks.isNotEmpty)
                        TextSpan(
                          text: '  ${marks.join(' · ')}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
              if (row.playerId != null)
                IconButton(
                  tooltip: context.tr('Grund (optional)'),
                  isSelected: _showReason,
                  onPressed: () => setState(() => _showReason = !_showReason),
                  icon: const Icon(Icons.comment_outlined),
                ),
            ],
          ),
          if (typed)
            SelectableText(
              answerLabel(answer, widget.question, context: context),
              style: theme.textTheme.bodyLarge,
            )
          else
            Text(
              context.tr(
                row.playerId == null
                    ? 'Keine Antwort'
                    : 'Nichts eingetippt (mündliche Antwort)',
              ),
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.outline,
              ),
            ),
          if (row.recommendation case final recommendation?)
            Text(context.tr(recommendation), style: theme.textTheme.bodySmall),
          if (row.playerId != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                for (final correct in [true, false]) ...[
                  if (!correct) const SizedBox(width: 12),
                  Expanded(child: _choice(context, correct)),
                ],
              ],
            ),
            if (_showReason) ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: widget.selection.reasons[row.id],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: context.tr('Grund (optional)'),
                ),
                onChanged: (text) => widget.selection.reasons[row.id] = text,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _choice(BuildContext context, bool correct) {
    final scheme = Theme.of(context).colorScheme;
    final row = widget.row;
    final selected = widget.selection[row.id] == correct;
    final color = correct ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final label = Text(context.tr(correct ? 'Richtig' : 'Falsch'));
    final icon = Icon(
      correct
          ? (selected ? Icons.check_circle : Icons.check)
          : (selected ? Icons.cancel : Icons.close),
    );
    // A verdict on an answer nobody typed can be withdrawn again.
    void press() => widget.selection.select(
      row.id,
      selected && !row.needsVerdict ? null : correct,
    );
    return Semantics(
      key: ValueKey('grade-${row.id}-$correct'),
      selected: selected,
      child: selected
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                backgroundColor: color,
                foregroundColor: Colors.white,
              ),
              onPressed: press,
              icon: icon,
              label: label,
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52),
                foregroundColor: scheme.onSurface,
              ),
              onPressed: press,
              icon: icon,
              label: label,
            ),
    );
  }
}
