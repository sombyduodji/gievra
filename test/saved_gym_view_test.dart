import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Aiempi salitreeni avautuu yhteenvetona (kuten liikunta), Muokkaa avaa liikelistan (käyttäjä 15.11.: Treeni valmis
// -näkymä heti treenin jälkeen, kalenterista ennen lukittu liikelista). Keskeneräinen avautuu liikelistaan.
void main() {
  final day = addDays(dateOnly(DateTime.now()), -2);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings
      ..name = 'Testi'
      ..introDone = true
      ..trainMode = 'gym'
      ..program = null;
  });
  tearDown(() => store.workouts = []);

  Workout done() => Workout(date: day, title: 'Treeni')
    ..minutes = 53
    ..feeling = 4
    ..exercises.addAll([
      ExerciseEntry('Taukopenkki', [SetEntry(60, 6), SetEntry(70, 6, pr: true)]),
      ExerciseEntry('Face pull', [SetEntry(15, 12)]),
    ]);

  Future<void> openFromRecent(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    await tester.tap(find.textContaining('Taukopenkki').first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('valmis salitreeni: yhteenveto liikkeineen, otsikkona treeni; Muokkaa avaa liikelistan', (tester) async {
    store.workouts = [done()];
    await openFromRecent(tester);
    expect(find.byType(SavedScreen), findsOneWidget);
    expect(find.textContaining('Giitu'), findsNothing, reason: 'aiempi treeni, ei onnittelua');
    final list = find.byKey(const ValueKey('savedExercises'));
    expect(find.descendant(of: list, matching: find.text('Taukopenkki')), findsOneWidget);
    expect(find.descendant(of: list, matching: find.textContaining('70 × 6 🏆')), findsOneWidget);
    expect(find.text('Uusi treeni'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500)); // suojaviive
    await tester.tap(find.byKey(const ValueKey('savedEdit')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(WorkoutScreen), findsOneWidget);
  });

  testWidgets('keskeneräinen avautuu suoraan liikelistaan', (tester) async {
    store.workouts = [
      Workout(date: day, title: 'Treeni')..exercises.add(ExerciseEntry('Taukopenkki', [SetEntry(60, 6)])),
    ];
    await openFromRecent(tester);
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(find.byType(SavedScreen), findsNothing);
  });
}
