import 'app_state.dart';
import 'exercises.dart';
import 'models.dart';
import 'program.dart';

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
    minutes: 60,
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
}
