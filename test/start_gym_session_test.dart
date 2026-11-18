import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/new_workout.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Etusivun salipaneeli: uusi salitreeni ei avaa saman päivän liikuntaa (testi 17.11.: Koko keho C avasi koripallon).
void main() {
  testWidgets('päivällä liikunta: aloitus tekee uuden salitreenin seuraavalla numerolla', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final today = dateOnly(DateTime.now());
    final saved = settings.equipment;
    settings.equipment = [];
    addTearDown(() {
      settings.equipment = saved;
      store.workouts = [];
    });
    store.workouts = [Workout(date: today, title: 'Koripallo', activity: 'Koripallo', session: 1)..minutes = 2];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => askWarmupAndStart(c, date: today),
            child: const Text('aloita'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aloita'));
    await tester.pumpAndSettle();
    final ws = tester.widget<WorkoutScreen>(find.byType(WorkoutScreen));
    expect(ws.workout.activity, isNull);
    expect(ws.workout.session, 2);
    // Keskeneräinen salitreeni jatkuu.
    await tester.pumpWidget(const SizedBox());
    store.workouts = [
      ...store.workouts,
      Workout(date: today, title: 'Treeni', session: 2)..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 5)])),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => askWarmupAndStart(c, date: today),
            child: const Text('aloita'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aloita'));
    await tester.pumpAndSettle();
    final ws2 = tester.widget<WorkoutScreen>(find.byType(WorkoutScreen));
    expect(ws2.workout.session, 2);
    expect(ws2.workout.exercises.single.name, 'Takakyykky');
  });

  testWidgets('yötesti 18.11.: lämmittelypaneeli (laitteet asetuksissa) asettuu ilman virhettä', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final today = dateOnly(DateTime.now());
    expect(settings.equipment, isNotEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => askWarmupAndStart(c, date: today),
            child: const Text('aloita'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aloita'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('startWarmup')), findsOneWidget);
    // Kesto-säädin toimii.
    await tester.tap(find.byTooltip('Lisää'));
    await tester.pump();
    expect(find.textContaining('11'), findsOneWidget);
  });
}
