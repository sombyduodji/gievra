import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/new_workout.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Keskeneräinen salitreeni (ei kestoa eikä fiilistä): päivänäkymässä "Jatka" kuten etusivulla, ja uuden treenin
// valinnassa ohjelman päivä "kesken", ei "tehty tänään ✓" (yötesti 15.11.).
void main() {
  final today = dateOnly(DateTime.now());
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings
      ..started = true
      ..introDone = true
      ..trainMode = 'both'
      ..program = generateProgram(goal: 'lihaskasvu', experience: 'keski', days: 3, minutes: 60, injuries: const []);
  });
  tearDown(() {
    store.workouts = [];
    settings.program = null;
  });

  Workout open() {
    final day = settings.program!.plan.first;
    return Workout(date: today, title: day.name, programDay: day.name)
      ..exercises.add(ExerciseEntry(day.items.first.exercise, [SetEntry(40, 8)]));
  }

  testWidgets('Päivänäkymä: keskeneräinen salitreeni → Jatka', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    store.workouts = [open()];
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    showDay(tester.element(find.byType(HomeScreen)), today);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Jatka'), findsWidgets);
  });

  testWidgets('Uusi treeni: keskeneräinen ohjelman päivä on "kesken", ei "tehty tänään"', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    store.workouts = [open()];
    await tester.pumpWidget(MaterialApp(home: NewWorkoutScreen(date: today)));
    await tester.pump();
    expect(find.text('tehty tänään ✓'), findsNothing);
    expect(find.text('kesken'), findsOneWidget);
    // Valmis (kesto ja fiilis): tehty tänään.
    store.workouts = [
      open()
        ..minutes = 50
        ..feeling = 4,
    ];
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: NewWorkoutScreen(date: today)));
    await tester.pump();
    expect(find.text('tehty tänään ✓'), findsOneWidget);
    expect(find.text('kesken'), findsNothing);
  });

  testWidgets('Valmis salitreeni: ei kesken-merkkiä eikä + sarjaa; yhteenvedossa päivän syyt', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final w = open()
      ..minutes = 40
      ..feeling = 2
      ..dayReasons.addAll(['väsynyt', 'stressi']);
    store.workouts = [w];
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutScreen(workout: w, planDay: settings.program!.plan.first),
      ),
    );
    await tester.pump();
    expect(find.text('kesken'), findsNothing);
    expect(find.textContaining('+ 2'), findsNothing);
    await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w)));
    await tester.pump();
    expect(find.textContaining('väsynyt, stressi'), findsOneWidget);
  });
}
