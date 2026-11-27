import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/new_question_fields.dart';

Future<Map<String, Object?>> Function() pumpFields(
  WidgetTester tester,
  EstimationQuestion question,
) {
  var fields = <String, Object?>{};
  return () async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              child: NewQuestionFields(
                question: question,
                onChanged: (value) => fields = value,
              ),
            ),
          ),
        ),
      ),
    );
    return fields;
  };
}

EstimationQuestion estimation({double? target = 655, double scale = 1}) =>
    EstimationQuestion(
      id: 'q',
      prompt: 'Wie viele?',
      correctValue: target,
      zeroScale: scale,
      minAccepted: 599,
      maxAccepted: 701,
    );

void main() {
  final zeroScale = find.byKey(const ValueKey('estimation-zero-scale'));

  testWidgets('the zero scale only shows for the target 0', (tester) async {
    await pumpFields(tester, estimation())();
    expect(zeroScale, findsNothing);
    final target = find.byType(TextFormField).first;
    await tester.enterText(target, '0');
    await tester.pump();
    expect(zeroScale, findsOneWidget);
    await tester.enterText(target, '12');
    await tester.pump();
    expect(zeroScale, findsNothing);
  });

  testWidgets('hiding keeps a stored scale', (tester) async {
    var fields = <String, Object?>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NewQuestionFields(
              question: estimation(scale: 50),
              onChanged: (value) => fields = value,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '700');
    await tester.pump();
    expect(fields['zeroScale'], 50);
    expect(fields['correctValue'], 700);
  });

  testWidgets('tolerance only hides formula and scale, limits are required', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    var fields = <String, Object?>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: NewQuestionFields(
                question: estimation(target: 0),
                onChanged: (value) => fields = value,
              ),
            ),
          ),
        ),
      ),
    );
    expect(zeroScale, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('estimation-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nur Toleranz (richtig/falsch)').last);
    await tester.pumpAndSettle();
    expect(fields['toleranceOnly'], isTrue);
    expect(zeroScale, findsNothing);
    expect(find.textContaining('relative Abweichung'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('estimation-min')), '');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Pflichtfeld bei „Nur Toleranz“.'), findsOneWidget);
  });

  testWidgets('an invalid target is reported at once', (tester) async {
    await pumpFields(tester, estimation())();
    await tester.enterText(find.byType(TextFormField).first, '33:58x');
    await tester.pump();
    expect(find.text('Endliche Zahl angeben.'), findsOneWidget);
  });
}
