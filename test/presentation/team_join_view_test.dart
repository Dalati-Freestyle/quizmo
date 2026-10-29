import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/protocol/messages.dart';
import 'package:quizmo/presentation/player/team_join_view.dart';

void main() {
  testWidgets('code is obscured and sent with the selected admission', (
    tester,
  ) async {
    String? received;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamJoinView(
            lobby: const LobbySnapshotMessage(
              teams: {},
              codeRequired: true,
              requireApproval: true,
            ),
            onJoin: (_, code) => received = code,
            onCreate: (_, _) {},
            onBack: () {},
          ),
        ),
      ),
    );
    final code = find.widgetWithText(TextField, 'Join code');
    expect(tester.widget<TextField>(code).obscureText, isTrue);
    await tester.enterText(code, 'secret-code');
    await tester.tap(find.text('Spiel beitreten'));
    expect(received, 'secret-code');
    expect(find.text('New participants need host approval.'), findsOneWidget);
  });

  testWidgets('locked lobby explains reconnect and disables new admissions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamJoinView(
            lobby: const LobbySnapshotMessage(teams: {}, locked: true),
            onJoin: (_, _) => fail('Locked join'),
            onCreate: (_, _) => fail('Locked team creation'),
            onBack: () {},
          ),
        ),
      ),
    );
    expect(
      find.text('The lobby is locked. Existing players can still reconnect.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'Owls');
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });

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
            onJoin: (id, _) => joined = id,
            onCreate: (_, _) {},
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
            onJoin: (_, _) {},
            onCreate: (name, _) => created = name,
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
