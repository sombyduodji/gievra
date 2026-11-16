import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program_edit.dart';
import 'package:treenipaivakirja/progression.dart';
import 'package:treenipaivakirja/rest.dart';

// Testikierros 16.11.: päivän toinen salitreeni ei nähnyt saman päivän ensimmäistä ("Edellinen kerta: ei",
// oletuspaino 20 kg, ei ennätystä). Saman päivän aiempi treeni on nyt "edellinen kerta".
void main() {
  final day = DateTime(2026, 11, 16);
  Workout w(DateTime d, int session, double kg) => Workout(
    date: d,
    session: session,
    exercises: [
      ExerciseEntry('Penkkipunnerrus', [SetEntry(kg, 5, rir: 2), SetEntry(kg, 5, rir: 2)]),
    ],
  );

  setUp(() {
    settings
      ..weightStep = 2.5
      ..pauses = [];
  });
  tearDown(() => store.workouts = []);

  test('saman päivän aiempi treeni on edellinen kerta', () {
    store.workouts = [w(day, 1, 80), w(DateTime(2026, 11, 10), 1, 70)];
    expect(store.lastBefore('Penkkipunnerrus', day, 2)?.$2.sets.first.kg, 80);
    expect(
      store.lastBefore('Penkkipunnerrus', day)?.$2.sets.first.kg,
      70,
      reason: 'ensimmäinen treeni: edellinen päivä',
    );
    expect(suggestNext('Penkkipunnerrus', day, session: 2), isNotNull);
    expect(suggestNext('Penkkipunnerrus', day, session: 2)!.kg, greaterThanOrEqualTo(80));
    expect(bestE1rmBefore('Penkkipunnerrus', day, 2), greaterThan(bestE1rmBefore('Penkkipunnerrus', day)));
  });

  test('saman päivän uusin aiempi treeni voittaa, myöhempi ei kelpaa', () {
    store.workouts = [w(day, 3, 90), w(day, 1, 80), w(day, 2, 85)];
    expect(store.lastBefore('Penkkipunnerrus', day, 3)?.$2.sets.first.kg, 85);
    expect(store.lastBefore('Penkkipunnerrus', day, 2)?.$2.sets.first.kg, 80);
    expect(store.lastBefore('Penkkipunnerrus', day, 1), isNull);
  });

  test('samana päivänä kuormittuneet lihakset: muut salitreenit, ei nykyistä eikä liikuntaa (käyttäjä 16.11.)', () {
    final chest = heavyMusclesOf('Penkkipunnerrus');
    expect(chest, isNotEmpty);
    store.workouts = [w(day, 1, 80), Workout(date: day, session: 3, activity: 'Juoksu')];
    expect(musclesTrainedToday(store.workouts, day, exceptSession: 2).intersection(chest), chest);
    expect(musclesTrainedToday(store.workouts, day, exceptSession: 1), isEmpty, reason: 'oma treeni ei lasketa');
    expect(musclesTrainedToday(store.workouts, DateTime(2026, 11, 17)), isEmpty, reason: 'eri päivä');
    expect(heavyMusclesOf('Takakyykky').intersection(musclesTrainedToday(store.workouts, day)), isEmpty);
  });
}
