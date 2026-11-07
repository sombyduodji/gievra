import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/history_profile.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/insights.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';

Workout w(DateTime d, List<(String, double, int, int)> ex) => Workout(
  date: d,
  exercises: [
    for (final (n, kg, reps, sets) in ex) ExerciseEntry(n, [for (var i = 0; i < sets; i++) SetEntry(kg, reps)]),
  ],
);

void main() {
  test('Voimanostaja: kilpanostot matalilla toistoilla, 3 x viikossa, 2 vuotta', () {
    final start = DateTime(2024, 11, 4);
    final ws = <Workout>[
      for (var i = 0; i < 104; i++) ...[
        w(addDays(start, i * 7), [('Takakyykky', 140, 3, 5), ('Penkkipunnerrus', 100, 3, 5), ('Kulmasoutu', 80, 8, 3)]),
        w(addDays(start, i * 7 + 2), [('Maastaveto', 180, 2, 4), ('Penkkipunnerrus', 90, 5, 4)]),
        w(addDays(start, i * 7 + 4), [('Takakyykky', 120, 5, 4), ('Taukopenkki', 85, 3, 4), ('Leuanveto', 0, 6, 3)]),
      ],
    ];
    final p = analyzeHistory(ws, now: DateTime(2026, 11, 7))!;
    expect((p.goal, p.days, p.experience, p.repStyle), ('voimanosto', 3, 'keski', 'raskas'));
    expect(p.favorites['VVE'], 'Kulmasoutu');
    expect(p.why['goal'], contains('%'));
  });

  test('Kehonrakentaja: paljon eristäviä, suosikit päätyvät ohjelmaan', () {
    final start = DateTime(2025, 6, 2);
    final ws = <Workout>[
      for (var i = 0; i < 20; i++) ...[
        w(addDays(start, i * 7), [
          ('Vinokäsipainopenkki', 30, 10, 3),
          ('Kaapeliristikkäis', 20, 12, 3),
          ('Vipunosto sivulle', 10, 15, 4),
        ]),
        w(addDays(start, i * 7 + 1), [
          ('Hack-kyykky', 120, 10, 4),
          ('Reiden ojennus', 60, 12, 3),
          ('Reiden koukistus', 50, 12, 3),
        ]),
        w(addDays(start, i * 7 + 3), [
          ('Ylätalja', 70, 10, 4),
          ('Alatalja', 70, 10, 3),
          ('Hauiskääntö taljassa', 30, 12, 3),
        ]),
        w(addDays(start, i * 7 + 4), [('Romanialainen maastaveto', 100, 8, 3), ('Hip thrust', 120, 10, 3)]),
      ],
    ];
    final p = analyzeHistory(ws, now: DateTime(2025, 10, 20))!;
    expect((p.goal, p.days, p.experience), ('lihaskasvu', 4, 'aloittelija'));
    final prog = generateProgram(
      goal: p.goal,
      experience: 'keski',
      days: p.days,
      minutes: p.minutes,
      injuries: const [],
      repStyle: p.repStyle,
      favorites: p.favorites,
    );
    final names = prog.plan.expand((d) => d.items).map((i) => i.exercise).toSet();
    expect(names, containsAll(['Hack-kyykky', 'Ylätalja', 'Alatalja', 'Kaapeliristikkäis']));
    expect(validateProgram(prog), isEmpty);
  });

  test('Liian vähän historiaa: ei ehdotuksia', () {
    expect(
      analyzeHistory([
        w(DateTime(2026, 1, 1), [('Takakyykky', 60, 5, 3)]),
      ]),
      isNull,
    );
  });

  test('Maksimit: ennätys koko historiasta, ehdotus viimeiseltä 6 kk:lta', () {
    final ws = [
      w(DateTime(2025, 1, 10), [('Takakyykky', 160, 3, 1)]), // ennätys, yli 6 kk sitten
      w(DateTime(2026, 9, 1), [('Takakyykky', 140, 5, 1)]),
      w(DateTime(2026, 10, 1), [('Takakyykky', 145, 3, 1)]),
      w(DateTime(2024, 5, 1), [('Maastaveto', 200, 1, 1)]), // ei 6 kk:n sisällä lainkaan
      w(DateTime(2024, 3, 1), [('Maastaveto', 180, 3, 1)]),
    ];
    final now = DateTime(2026, 11, 7);
    final pr = bestLift(ws, 'Takakyykky')!;
    expect((pr.kg, pr.reps, pr.date), (160, 3, DateTime(2025, 1, 10)));
    final (sug, old) = suggestedMax(ws, 'Takakyykky', now);
    expect((sug!.kg, old), (140, null)); // 140×5 ≈ 163 > 145×3 ≈ 160
    final (dl, dlOld) = suggestedMax(ws, 'Maastaveto', now);
    expect((dl!.kg, dlOld), (200, DateTime(2024, 5, 1)));
    expect(suggestedMax(ws, 'Penkkipunnerrus', now).$1, isNull);
  });

  test('Oikea FitNotes-varmuuskopio', () {
    final r = readFitnotes(Platform.environment['FITNOTES']!);
    final p = analyzeHistory(r.workouts)!;
    for (final l in ['Takakyykky', 'Penkkipunnerrus', 'Maastaveto']) {
      final pr = bestLift(r.workouts, l);
      final s = suggestedMax(r.workouts, l, DateTime.now());
      // ignore: avoid_print
      print(
        '$l: ennätys ${pr?.kg}×${pr?.reps} ${pr?.date} (~${pr?.e1rm.round()}), ehdotus ${s.$1?.kg}×${s.$1?.reps} ${s.$1?.date} (~${s.$1?.e1rm.round()}) vanha ${s.$2}',
      );
    }
    // ignore: avoid_print
    print(
      '${p.workouts} treeniä: ${p.goal} ${p.experience} ${p.days} pv ${p.minutes} min ${p.repStyle} '
      '${p.equipment} sarjoja ${p.typicalSets}\n${p.why.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n'
      '  suosikit: ${p.favorites}',
    );
  }, skip: Platform.environment['FITNOTES'] == null ? 'FITNOTES ei asetettu' : false);
}
