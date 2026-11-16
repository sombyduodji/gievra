import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/picker.dart';
import 'package:treenipaivakirja/ui/suggest_exercise.dart';

// Käyttäjä 16.11.: oman liikkeen ehdotus Gievraan kysytään kerran treenin jälkeen. Keksityt tiedot.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings
      ..customExercises = ['Testiliike kumilla']
      ..customCategory = {'Testiliike kumilla': 'Selkä'}
      ..customMuscles = {};
  });
  tearDown(() {
    settings
      ..customExercises = []
      ..customCategory = {}
      ..customMuscles = {};
    customExerciseMuscles.clear();
  });

  Workout w(String name) => Workout(
    date: DateTime(2026, 11, 16),
    exercises: [
      ExerciseEntry(name, [SetEntry(10, 12)]),
    ],
  );

  testWidgets('kysytään vain kerran; valmis liike ei kysy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => maybeSuggestOwnExercises(context, w('Testiliike kumilla')),
                child: const Text('oma'),
              ),
              TextButton(
                onPressed: () => maybeSuggestOwnExercises(context, w('Takakyykky')),
                child: const Text('valmis'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('valmis'));
    await tester.pumpAndSettle();
    expect(find.text('Ehdotetaanko liikettä Gievraan?'), findsNothing);
    await tester.tap(find.text('oma'));
    await tester.pumpAndSettle();
    expect(find.text('Ehdotetaanko liikettä Gievraan?'), findsOneWidget);
    expect(find.textContaining('Testiliike kumilla'), findsOneWidget);
    await tester.tap(find.text('Ei kiitos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('oma'));
    await tester.pumpAndSettle();
    expect(find.text('Ehdotetaanko liikettä Gievraan?'), findsNothing, reason: 'vain kerran');
  });

  testWidgets('Ehdota avaa kuvauksen; Peruuta ei lähetä', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => maybeSuggestOwnExercises(context, w('Testiliike kumilla')),
            child: const Text('oma'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('oma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ehdota'));
    await tester.pumpAndSettle();
    expect(find.text('Ehdota liikettä Gievraan'), findsOneWidget);
    expect(find.byKey(const ValueKey('suggestDesc')), findsOneWidget);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(find.text('Ehdota liikettä Gievraan'), findsNothing);
  });

  test('oman liikkeen poisto poistaa myös sen lihakset', () {
    settings.setCustomMuscles('Testiliike kumilla', ['yläselkä']);
    expect(customExerciseMuscles['Testiliike kumilla'], ['yläselkä']);
    settings.removeCustomExercise('Testiliike kumilla');
    expect(settings.customMuscles.containsKey('Testiliike kumilla'), isFalse);
    expect(customExerciseMuscles.containsKey('Testiliike kumilla'), isFalse);
  });

  testWidgets('oman liikkeen poisto valitsimesta pitkällä painalluksella (Peruuta ei poista)', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ExercisePickerScreen()));
    await tester.enterText(find.byType(TextField).first, 'Testiliike');
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Testiliike kumilla'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(settings.customExercises, contains('Testiliike kumilla'));
    await tester.longPress(find.text('Testiliike kumilla'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Poista'));
    await tester.pumpAndSettle();
    expect(settings.customExercises, isNot(contains('Testiliike kumilla')));
    expect(find.text('Testiliike kumilla'), findsNothing);
  });
}
