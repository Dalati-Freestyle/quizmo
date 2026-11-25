import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/common/question_result_view.dart';
import 'package:quizmo/presentation/common/tv_instruction.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

const _options = [
  AnswerOption(id: 'a', label: 'Alpha'),
  AnswerOption(id: 'b', label: 'Beta'),
  AnswerOption(id: 'c', label: 'Gamma'),
  AnswerOption(id: 'd', label: 'Delta'),
];

final _kinds = <String, Question>{
  'text': const ShortAnswerQuestion(
    id: 'q',
    prompt: 'Q',
    acceptedAnswers: ['x'],
  ),
  'manual': const ShortAnswerQuestion(
    id: 'q',
    prompt: 'Q',
    acceptedAnswers: ['x'],
    manualGrading: true,
  ),
  'order': const OrderingQuestion(
    id: 'q',
    prompt: 'Q',
    items: _options,
    correctOrder: ['a', 'b', 'c', 'd'],
  ),
  'match': const MatchingQuestion(
    id: 'q',
    prompt: 'Q',
    leftItems: _options,
    rightItems: _options,
    correctPairs: {'a': 'a', 'b': 'b', 'c': 'c', 'd': 'd'},
  ),
  'estimate': const EstimationQuestion(
    id: 'q',
    prompt: 'Q',
    correctValue: 3,
    unit: 'km',
  ),
  'bool': const TrueFalseQuestion(id: 'q', prompt: 'Q', correctAnswer: true),
  'one': const MultipleChoiceQuestion(
    id: 'q',
    prompt: 'Q',
    options: _options,
    correctOptionIds: ['a', 'b'],
  ),
  'multi': const MultipleChoiceQuestion(
    id: 'q',
    prompt: 'Q',
    options: _options,
    correctOptionIds: ['a', 'b'],
    allowMultipleAnswers: true,
  ),
  'buzzer': const BuzzerQuestion(id: 'q', prompt: 'Q'),
};

String? say(
  Question question, {
  bool teams = true,
  RoundStatus status = RoundStatus.acceptingAnswers,
  SnowflakeScoring? snowflake,
  bool verbal = false,
  PokerState? poker,
  JeopardyState? jeopardy,
  String? activePlayerId,
}) => tvInstruction(
  (key, [args = const []]) => AppLocalizations.formatMessage(key, args),
  GameState(
    isStarted: true,
    mode: teams ? const TeamMode() : const SoloMode(),
    teams: const {
      'red': Team(id: 'red', name: 'Rot'),
      'blue': Team(id: 'blue', name: 'Blau'),
      'green': Team(id: 'green', name: 'Grün'),
    },
    poker: poker,
    jeopardy: jeopardy,
    snowflake: snowflake,
    round: RoundState(
      question: question.redacted(),
      status: status,
      startedAtHostMicros: 1,
      snowflake: snowflake,
      verbal: verbal,
      activePlayerId: activePlayerId,
    ),
  ),
)?.text;

void main() {
  test('every kind says what to do, for teams and for single players', () {
    expect(
      {for (final e in _kinds.entries) e.key: say(e.value)},
      {
        'text': 'Gebt eure Antwort auf eurem Gerät ein.',
        'manual':
            'Gebt eure Antwort auf eurem Gerät ein. Die Spielleitung bewertet.',
        'order':
            'Bringt die Elemente auf eurem Gerät in die richtige Reihenfolge.',
        'match': 'Ordnet jedem Begriff den passenden zu.',
        'estimate': 'Schätzt und gebt eine Zahl ein (in km).',
        'bool': 'Wahr oder falsch? Wählt auf eurem Gerät.',
        'one': 'Wählt eine Antwort.',
        'multi': 'Wählt alle richtigen Antworten.',
        'buzzer': 'Drückt den Buzzer und antwortet laut.',
      },
    );
    expect(
      say(_kinds['text']!, teams: false),
      'Gib deine Antwort auf deinem Gerät ein.',
    );
    expect(
      say(_kinds['buzzer']!, teams: false),
      'Drück den Buzzer und antworte laut.',
    );
  });

  test('nothing tells the solution or how many answers are right', () {
    for (final question in _kinds.values) {
      expect(say(question), isNot(contains('Alpha')));
      expect(say(question), isNot(contains('2')));
    }
  });

  test('snowflake never speaks of a right answer', () {
    for (final kind in ['order', 'match', 'bool', 'one', 'multi']) {
      final text = say(
        _kinds[kind]!.withoutSolution(),
        snowflake: SnowflakeScoring.winnerOnly,
      )!;
      expect(text, contains('niemand'), reason: kind);
      expect(text.toLowerCase(), isNot(contains('richtig')), reason: kind);
    }
  });

  test('phases: betting, closed, verbal, revealed, buzzer answering', () {
    final question = _kinds['text']!;
    expect(
      say(question, poker: const PokerState(startingChips: 10, betting: true)),
      'Setzt eure Chips.',
    );
    expect(
      say(question, status: RoundStatus.locked),
      'Antworten sind geschlossen.',
    );
    expect(
      say(_kinds['manual']!, status: RoundStatus.locked),
      'Antworten sind geschlossen. Die Spielleitung bewertet.',
    );
    expect(say(question, verbal: true), 'Sagt eure Antwort laut.');
    expect(say(question, status: RoundStatus.revealed), isNull);
    expect(
      say(_kinds['buzzer']!, status: RoundStatus.locked, activePlayerId: 'p'),
      isNull,
    );
    expect(
      say(_kinds['buzzer']!, status: RoundStatus.locked),
      'Der Buzzer ist geschlossen.',
    );
  });

  test('a board names who may answer, also in a steal round', () {
    const board = JeopardyBoard(
      rowPoints: [100],
      categories: [
        JeopardyCategory(
          name: 'C',
          cells: [JeopardyCell(questionId: 'q')],
        ),
      ],
    );
    final turn = JeopardyState.start(board, [
      'red',
      'blue',
      'green',
    ]).copyWith(currentTeamId: 'red', activePoints: 100);
    expect(say(_kinds['one']!, jeopardy: turn), 'Rot: Wählt eine Antwort.');
    expect(
      say(_kinds['one']!, jeopardy: turn.copyWith(isStealRound: true)),
      'Blau, Grün: Wählt eine Antwort.',
    );
  });

  testWidgets('the TV shows it for every kind, lists stay mixed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final entry in _kinds.entries) {
      for (final media in [false, true]) {
        final question = media
            ? Question.fromJson({
                ...entry.value.toJson(),
                'media': [
                  const GeoAttachment(
                    latitude: 1,
                    longitude: 2,
                    zoom: 3,
                  ).toJson(),
                ],
              })
            : entry.value;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TvScreen(
                state: SpectatorSessionState(
                  status: QuizClientStatus.connected,
                  game: GameState(
                    isStarted: true,
                    round: RoundState(
                      question: question.redacted(),
                      status: RoundStatus.acceptingAnswers,
                      startedAtHostMicros: 1,
                    ),
                  ),
                ),
                joinUri: Uri.parse('http://localhost:8080'),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        final reason = '${entry.key} media=$media';
        expect(
          find.text(say(entry.value, teams: false)!),
          findsOneWidget,
          reason: reason,
        );
        expect(tester.takeException(), isNull, reason: reason);
        if (entry.key == 'match' && media) {
          expect(find.byKey(const ValueKey('tv-matching-lists')), findsOne);
        }
      }
    }
    final once = mixed(_options, 'q');
    expect(mixed(_options, 'q'), once, reason: 'stable per question');
    expect(once.toSet(), _options.toSet());
  });
}
