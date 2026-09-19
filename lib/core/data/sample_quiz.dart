/// The demo question bank and team roster used by the prototype.
///
/// Everything here is `const`, which makes it a drop-in replacement target for
/// a future repository that loads quizzes from disk or from a REST API.
library;

import '../engine/scoring_rules.dart';
import '../models/models.dart';

/// Two coloured teams, enough to exercise team scoring end to end.
const Map<String, Team> sampleTeams = {
  'team-red': Team(id: 'team-red', name: 'Red Foxes', colorValue: 0xFFE5484D),
  'team-blue': Team(id: 'team-blue', name: 'Blue Whales', colorValue: 0xFF3E63DD),
};

/// The prototype quiz: one multiple choice round and two buzzer rounds.
const List<Question> sampleQuestionBank = [
  MultipleChoiceQuestion(
    id: 'q-capital',
    category: 'Geography',
    prompt: 'Which city is the capital of Australia?',
    options: [
      AnswerOption(id: 'a', label: 'Sydney'),
      AnswerOption(id: 'b', label: 'Canberra'),
      AnswerOption(id: 'c', label: 'Melbourne'),
      AnswerOption(id: 'd', label: 'Perth'),
    ],
    correctOptionId: 'b',
    scoringRule: SpeedBonusRule(basePoints: 10, maxSpeedBonus: 10),
    timeLimit: Duration(seconds: 25),
  ),
  BuzzerQuestion(
    id: 'q-buzzer-element',
    category: 'Science',
    prompt: 'Which chemical element has the symbol "Au"?',
    expectedAnswer: 'Gold',
    scoringRule: FirstBuzzerRule(points: 15, penalty: -5),
    timeLimit: Duration(seconds: 20),
  ),
  MultipleChoiceQuestion(
    id: 'q-dart',
    category: 'Tech',
    prompt: 'Which Dart 3 feature makes a class hierarchy exhaustively '
        'switchable?',
    options: [
      AnswerOption(id: 'a', label: 'abstract'),
      AnswerOption(id: 'b', label: 'sealed'),
      AnswerOption(id: 'c', label: 'mixin'),
      AnswerOption(id: 'd', label: 'extension'),
    ],
    correctOptionId: 'b',
    scoringRule: FixedPointsRule(correctPoints: 10),
  ),
  BuzzerQuestion(
    id: 'q-buzzer-ocean',
    category: 'Geography',
    prompt: 'Name the deepest point of the world ocean.',
    expectedAnswer: 'Challenger Deep (Mariana Trench)',
    scoringRule: FirstBuzzerRule(points: 20, penalty: -5, rankDecay: 8),
  ),
];

