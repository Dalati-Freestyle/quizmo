import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  Future<void> flush(QuizEngineBloc engine) async {
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'creating a team joins its creator and reset keeps team and chip balance',
    () async {
      final engine = QuizEngineBloc(
        teams: const {'old': Team(id: 'old', name: 'Old')},
        pokerStartingChips: 100,
      );
      addTearDown(engine.close);
      engine.add(
        const PlayerJoinedEvent(
          Player(id: 'p', name: 'Ada', teamId: 'new'),
          createdTeam: Team(id: 'new', name: 'New'),
        ),
      );
      await flush(engine);
      expect(engine.state.game.players['p']?.teamId, 'new');
      expect(engine.state.game.poker!.chips['new'], 100);
      engine.add(const RenameTeamEvent(playerId: 'p', name: ' Renamed '));
      await flush(engine);
      engine.add(const ResetGameEvent());
      await flush(engine);
      expect(engine.state.game.teams['new']?.name, 'Renamed');
      expect(engine.state.game.poker!.chips['new'], 100);
    },
  );

  test('every member may rename their own team; solo and disconnected players cannot', () async {
    final engine = QuizEngineBloc(
      teams: const {
        'a': Team(id: 'a', name: 'A', colorValue: 42),
        'b': Team(id: 'b', name: 'B'),
      },
    );
    addTearDown(engine.close);
    for (final player in const [
      Player(id: 'p1', name: 'One', teamId: 'a'),
      Player(id: 'p2', name: 'Two', teamId: 'a'),
      Player(id: 'solo', name: 'Solo'),
    ]) {
      engine.add(PlayerJoinedEvent(player));
    }
    await flush(engine);
    for (final id in ['p1', 'p2']) {
      engine.add(RenameTeamEvent(playerId: id, name: id));
      await flush(engine);
      expect(engine.state.game.teams['a']?.name, id);
    }
    engine.add(const RenameTeamEvent(playerId: 'solo', name: 'Bad'));
    engine.add(const RenameTeamEvent(playerId: 'p1', name: '   '));
    engine.add(const PlayerLeftEvent('p1'));
    await flush(engine);
    engine.add(const RenameTeamEvent(playerId: 'p1', name: 'Bad'));
    await flush(engine);
    expect(
      engine.state.game.teams['a'],
      const Team(id: 'a', name: 'p2', colorValue: 42),
    );
    expect(engine.state.game.teams['b']?.name, 'B');
  });

  test('joining an unknown team leaves the roster untouched', () async {
    final engine = QuizEngineBloc();
    addTearDown(engine.close);
    engine.add(
      const PlayerJoinedEvent(Player(id: 'p', name: 'Ada', teamId: 'missing')),
    );
    await flush(engine);
    expect(engine.state.game.players, isEmpty);
  });
}
