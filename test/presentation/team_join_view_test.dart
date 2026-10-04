import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/protocol/messages.dart';
import 'package:quizmo/presentation/player/team_join_view.dart';

void main() {
  testWidgets('joins a host-provided team and displays its live rename', (
    tester,
  ) async {
    String? joined;
    Future<void> show(String teamName) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamJoinView(
            lobby: LobbySnapshotMessage(
              teams: {'custom': Team(id: 'custom', name: teamName)},
            ),
            onJoin: (id) => joined = id,
            onCreate: (_) {},
            onBack: () {},
          ),
        ),
      ),
    );
    await show('Custom Team');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Team').last);
    await tester.pumpAndSettle();
    await show('Renamed Team');
    expect(find.text('Renamed Team'), findsOneWidget);
    expect(find.text('Custom Team'), findsNothing);
    await tester.tap(find.text('Spiel beitreten'));
    expect(joined, 'custom');
  });

  testWidgets('creates a named team from an empty lobby', (tester) async {
    String? created;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamJoinView(
            lobby: const LobbySnapshotMessage(teams: {}, requiresTeam: true),
            onJoin: (_) {},
            onCreate: (name) => created = name,
            onBack: () {},
          ),
        ),
      ),
    );
    expect(find.text('Es gibt noch keine Teams.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '  Owls  ');
    await tester.pump();
    await tester.tap(find.text('Team erstellen und beitreten'));
    expect(created, 'Owls');
  });

  testWidgets('rename dialog rejects blank names and returns a trimmed name', (
    tester,
  ) async {
    String? renamed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  renamed = await showTeamNameDialog(context, 'Old'),
              child: const Text('Rename'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(find.text('Teamnamen eingeben'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), ' New name ');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(renamed, 'New name');
  });
}
