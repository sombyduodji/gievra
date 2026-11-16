import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';

// Saman treenin päällekkäiset tallennukset ja poisto menevät levylle kutsujärjestyksessä (testikierros 15.11.).
// Keksitty treeni.
void main() {
  late Directory dir;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-order');
    settings.folder = dir.path;
  });
  tearDown(() {
    settings.folder = null;
    store.workouts = [];
    dir.deleteSync(recursive: true);
  });

  Workout workout(int reps) => Workout(
    date: DateTime(2026, 11, 15),
    title: 'Treeni',
    exercises: [
      ExerciseEntry('Penkkipunnerrus', [SetEntry(60, reps)]),
    ],
  );

  test('päällekkäiset tallennukset: viimeinen kutsu jää voimaan', () async {
    final all = [for (var i = 1; i <= 8; i++) store.save(workout(i))];
    await Future.wait(all);
    final file = File('${dir.path}/${store.fileName(DateTime(2026, 11, 15))}');
    expect(parseWorkout(file.readAsStringSync()).exercises.single.sets.single.reps, 8);
    expect(store.onDay(DateTime(2026, 11, 15)).single.exercises.single.sets.single.reps, 8);
  });

  test('poisto kesken tallennuksen: tiedosto ei palaa', () async {
    final s = store.save(workout(5));
    final d = store.delete(DateTime(2026, 11, 15));
    await Future.wait([s, d]);
    final file = File('${dir.path}/${store.fileName(DateTime(2026, 11, 15))}');
    expect(file.existsSync(), isFalse);
    expect(store.onDay(DateTime(2026, 11, 15)), isEmpty);
  });

  test('virhe yhdessä tallennuksessa ei pysäytä jonoa', () async {
    await store.save(workout(1));
    await store.save(workout(2));
    expect(store.onDay(DateTime(2026, 11, 15)).single.exercises.single.sets.single.reps, 2);
  });
}
