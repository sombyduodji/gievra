import 'app_state.dart';
import 'body.dart';
import 'exercises.dart';
import 'models.dart';
import 'program.dart';
import 'sports.dart';

/// Verkkodemon esimerkkitiedot: kolmen päivän ohjelma ja neljän viikon treenit, jotta etusivu, kalenteri ja
/// tilastot näyttävät jotain. Kaikki on vain muistissa (MemoryTrainingFiles); mitään ei tallenneta.
Future<void> seedDemo() async {
  settings.name = 'Demo';
  final today = dateOnly(DateTime.now());
  final monday = addDays(today, 1 - today.weekday);
  final start = addDays(monday, -21); // neljä viikkoa, viimeinen on kuluva viikko
  final p = generateProgram(
    goal: 'lihaskasvu',
    experience: 'keski',
    days: 3,
    minutes: 75, // 3 × 75 min riittää lihaskasvun viikkosuositukseen (Viikon kuorma vihreä)
    injuries: const [],
    start: start,
  );
  await settings.setProgram(p); // asettaa myös introDone
  // Aloituspainot liikemallin mukaan (kg), nousevat viikoittain.
  const base = {'KYY': 60.0, 'LON': 70.0, 'VTY': 45.0, 'PTY': 30.0, 'VVE': 40.0, 'PVE': 40.0, 'YKS': 20.0};
  const feelings = [4, 3, 4, 5, 4, 3, 4, 4, 5, 4, 3, 5];
  var n = 0;
  for (var week = 0; week < 4; week++) {
    for (final (i, offset) in [(0, 0), (1, 2), (2, 4)]) {
      final date = addDays(start, week * 7 + offset);
      if (!date.isBefore(today)) continue;
      final day = p.plan[i % p.plan.length];
      final w = Workout(date: date, title: day.display, programDay: day.name, minutes: 55 + (n % 3) * 5)
        ..feeling = feelings[n % feelings.length];
      for (final it in day.items) {
        final m = measureOf(it.exercise);
        // Noin 2 % nousu viikossa, pyöristys 2,5 kg:aan.
        final b = base[family(it.slot)] ?? 20.0;
        final kg = m == Measure.reps ? ((b * (1 + .02 * week)) / 2.5).round() * 2.5 : 0.0;
        final reps = m == Measure.reps ? (it.hi - 1).clamp(it.lo, it.hi) : m.initial;
        w.exercises.add(
          ExerciseEntry(it.exercise, [
            for (var s = 0; s < it.sets; s++) SetEntry(kg, reps, rir: s == it.sets - 1 ? 1 : 3),
          ]),
        );
      }
      await store.save(w);
      n++;
    }
  }

  await _seedRuns(today);
  await _seedBody(today);
}

/// Kehonpainon seuranta: punnituksia kahdentoista viikon ajalta (paino laskee hiljalleen), ei tältä päivältä,
/// jotta etusivulla näkyy Merkitse aamupaino. Lauantaisin kävely askelineen.
Future<void> _seedBody(DateTime today) async {
  settings.bodyTracker = true;
  final weights = <DateTime, double>{};
  for (var d = 1; d <= 84; d += d % 7 == 3 ? 4 : 3) {
    weights[addDays(today, -d)] = ((80.4 + d * .03 + (d % 5 == 0 ? .3 : 0)) * 10).round() / 10;
  }
  await settings.setBody(BodyLog(heightCm: 180, weights: weights));
  final monday = addDays(today, 1 - today.weekday);
  for (var week = 0; week < 4; week++) {
    final date = addDays(monday, -7 * (3 - week) + 5);
    if (!date.isBefore(today)) continue;
    final km = 4.0 + week * .5;
    await store.save(
      Workout(
          date: date,
          title: 'Kävely',
          activity: 'Kävely',
          distanceKm: km,
          minutes: (km * 12).round(),
          intensity: 'kevyt',
          session: store.nextSession(date),
        )
        ..steps = (km * 1350).round()
        ..feeling = 4,
    );
  }
}

/// Esimerkkijuoksut kahdeksalta viikolta (tiistai, torstai, sunnuntai): kevyiden lenkkien vauhti paranee ja syke
/// laskee hiljalleen, sunnuntaisin pitkä lenkki, välillä vauhtikestävyys tai intervallit ja lopuksi 5 km testi.
Future<void> _seedRuns(DateTime today) async {
  settings.sports = true;
  settings.watch = true;
  settings.restTimer = true; // demossa näkyy palautusajastin (oikeassa sovelluksessa oletus pois)
  final monday = addDays(today, 1 - today.weekday);
  for (var week = 0; week < 8; week++) {
    final ws = addDays(monday, -7 * (7 - week));
    final easyPace = 375 - week * 3.5; // s/km: 6:15 -> n. 5:51
    final hr = 148 - week;
    final runs = <(int, String, double, double, int)>[
      (1, 'kevyt', 6.0 + (week % 3) * .5, easyPace, hr),
      (3, week.isEven ? 'vauhti' : 'intervallit', week.isEven ? 7.0 : 6.5, easyPace - (week.isEven ? 45 : 35), hr + 16),
      (6, 'pitka', 10.0 + week * .7, easyPace + 12, hr + 3),
      if (week == 6) (5, 'kilpailu', 5.0, 285, hr + 24), // 5 km testi: 23:45
    ];
    for (final (day, type, km, pace, h) in runs) {
      final date = addDays(ws, day);
      if (!date.isBefore(today)) continue;
      final sec = (km * pace).round();
      await store.save(
        Workout(
          date: date,
          title: 'Juoksu',
          activity: 'Juoksu',
          distanceKm: km,
          seconds: sec,
          minutes: (sec / 60).round(),
          runType: type,
          intensity: runTypeOf(type)!.$4,
          hrAvg: h,
          hrMax: h + 22,
          kcal: (km * 68).round(),
        )..feeling = type == 'kevyt' ? 4 : 3,
      );
    }
  }
}
