import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';
import 'package:treenipaivakirja/program_edit.dart';
import 'package:treenipaivakirja/session_compare.dart';

Program hyp(int days) => generateProgram(
  goal: 'lihaskasvu',
  experience: 'keski',
  days: days,
  minutes: 75,
  injuries: const [],
  start: DateTime(2026, 11, 2),
);

void main() {
  setUp(() {
    settings
      ..pauses = []
      ..program = null;
    store.workouts = [];
  });

  test('Lähes jokaisella liikkeellä on liikemalli', () {
    const none = {
      'Lonkan lähennys',
      'Olankohautus',
      'Ranteen koukistus',
      'Ranteen ojennus',
      'Roikunta',
      'Lapaluuveto roikkuen',
    };
    final missing = [
      for (final x in exerciseCatalog.values.expand((x) => x))
        if (slotOf(x).isEmpty && !none.contains(x)) x,
    ];
    expect(missing, isEmpty);
  });

  test('Saman liikemallin vaihto on hyvä, eri mallin vaihto näyttää kuorman muutoksen', () {
    final p = hyp(4);
    final day = p.plan.first;
    final row = day.items.firstWhere((i) => i.slot == 'VVE');
    final (same, other) = swapCandidates(row);
    expect(same, containsAll(['Kulmasoutu', 'T-tankosoutu', 'Pendlay-soutu']));
    expect(other, contains('Penkkipunnerrus'));
    final (ok, _) = assessSwap(p, day, row, 'T-tankosoutu');
    expect(ok, isTrue);
    final (ok2, msgs) = assessSwap(p, day, row, 'Hauiskääntö tangolla');
    expect(ok2, isFalse);
    expect(msgs.join('\n'), contains('selkä'));
    applySwap(row, 'Hauiskääntö tangolla');
    expect(row.slot, 'HAU');
    expect(validateProgram(p).join(), contains('eristävän jälkeen'));
  });

  test('Mittaustavan vaihto vaihtaa toistoalueen', () {
    final it = PlanItem('Vatsarutistus', 'KES', 3, 10, 15, '0–2', 90);
    applySwap(it, 'Lankku');
    expect((it.lo, it.hi), (20, 40));
  });

  test('Toistoaluevalinta ja sen tallennus', () {
    final p = generateProgram(
      goal: 'lihaskasvu',
      experience: 'keski',
      days: 3,
      minutes: 75,
      injuries: const [],
      repStyle: 'kevyt',
    );
    final iso = p.plan.expand((d) => d.items).firstWhere((i) => i.slot == 'OSI');
    expect(iso.lo, greaterThan(12));
    expect(parseProgram(programToMarkdown(p))!.repStyle, 'kevyt');
    expect(assessItem(p, PlanItem('Vipunosto sivulle', 'OSI', 3, 30, 40, '0–2', 90)).join(), contains('30'));
  });

  test('Viikkokuorma: valmis ohjelma on suositusalueella päälihaksille', () {
    final load = weeklyLoad(hyp(4));
    for (final m in load.where((m) => ['rinta', 'selkä', 'etureisi'].contains(m.muscle))) {
      expect(m.level, LoadLevel.ok, reason: '${m.muscle} ${m.sets}');
    }
  });

  test('Palautuminen: eilen jalat -> tänään ylävartalo', () {
    final p = hyp(4); // Ylävartalo A, Alavartalo A, Ylävartalo B, Alavartalo B
    store.workouts = [
      Workout(
        date: DateTime(2026, 11, 3),
        title: 'Ylävartalo A',
        exercises: [
          ExerciseEntry('Penkkipunnerrus', [SetEntry(80, 8)]),
        ],
      ),
      Workout(
        date: DateTime(2026, 11, 4),
        title: 'Takakyykkypäivä',
        exercises: [
          ExerciseEntry('Takakyykky', [SetEntry(100, 5)]),
        ],
      ),
    ];
    final (day, why) = suggestDay(p, store.workouts..sort((a, b) => b.date.compareTo(a.date)), DateTime(2026, 11, 5));
    expect(day.name, startsWith('Ylävartalo'));
    expect(why, contains('etureisi'));
  });

  test('Tänään jo tehty ohjelmapäivä ei ole enää ehdotus', () {
    final p = hyp(4);
    final today = DateTime(2026, 11, 5);
    final first = suggestDay(p, const [], today).$1;
    final done = Workout(
      date: today,
      title: first.display,
      programDay: first.name,
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(100, 5)]),
      ],
    );
    final next = suggestDay(p, [done], today).$1;
    expect(next.name, isNot(first.name));
    expect(p.plan, contains(next)); // seuraava päivä tai palautumisen takia sitä seuraava
    // Vinkki: tänään jo kuormittuneet lihakset (ei eilisiä), jos seuraava päivä kuormittaa samoja.
    final (_, why) = suggestDay(p, [done], today);
    if (why != null) expect(why, startsWith('Tänään kuormittui jo'));
    // Aloitettu mutta tyhjä treeni ei vielä siirrä ehdotusta.
    final empty = Workout(date: today, title: first.display, programDay: first.name);
    expect(suggestDay(p, [empty], today).$1.name, first.name);
  });

  test('Kesto ja aloitusaika tallentuvat .md:hen', () {
    final w = Workout(date: DateTime(2026, 11, 7), started: DateTime(2026, 11, 7, 17, 5), minutes: 63, feeling: 4);
    final md = workoutToMarkdown(w);
    expect(md, contains('feeling: 4 🙂 Hyvä'));
    final r = parseWorkout(md);
    expect((r.started!.hour, r.started!.minute, r.minutes, r.feeling), (17, 5, 63, 4));
  });

  test('Treeni valmis: vertailu edelliseen, kevennysviikko ja sairaus ohitetaan', () {
    Workout leg(DateTime d, double kg) => Workout(
      date: d,
      title: 'Jalat',
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(kg, 5)]),
      ],
    );
    final now = leg(DateTime(2026, 10, 30), 105);
    final all = [leg(DateTime(2026, 10, 6), 100), leg(DateTime(2026, 10, 13), 90), now];
    settings.pauses = [Pause(DateTime(2026, 10, 12), 'sairas', DateTime(2026, 10, 12))];
    final c = compareSession(now, all, null);
    expect(c.previous!.date, DateTime(2026, 10, 6)); // sairauden jälkeinen kerta ohitettu
    expect(c.exercises.single.trend, 1);
    expect(compareSession(leg(DateTime(2026, 10, 14), 80), all, null).skipReason, isNotNull);
  });

  test('Välinetoive: kahvakuula ja kehonpaino suosivat omia liikkeitään', () {
    Set<String> picks(Set<String> eq) => {
      for (final i in generateProgram(
        goal: 'lihaskasvu',
        experience: 'keski',
        days: 3,
        minutes: 75,
        injuries: const [],
        equipment: eq,
      ).plan.expand((d) => d.items))
        i.exercise,
    };
    final kb = picks({'kahvakuula'});
    expect(kb, containsAll(['Kahvakuulasoutu', 'Kahvakuulapystypunnerrus']));
    expect(kb.where((x) => fitsEquipment(x, {'kahvakuula'})).length / kb.length, greaterThan(.6));
    final bw = picks({'kehonpaino'});
    expect(bw, contains('Leuanveto'));
    expect(bw.intersection({'Punnerrus', 'Dipit'}), isNotEmpty);
    final p = generateProgram(
      goal: 'lihaskasvu',
      experience: 'keski',
      days: 3,
      minutes: 75,
      injuries: const [],
      equipment: {'kahvakuula'},
    );
    expect(parseProgram(programToMarkdown(p))!.equipment, {'kahvakuula'});
    // Voimanoston kilpaliikkeet pysyvät tangolla.
    final pl = generateProgram(
      goal: 'voimanosto',
      experience: 'keski',
      days: 3,
      minutes: 90,
      injuries: const [],
      equipment: {'kahvakuula'},
    );
    expect(pl.plan.expand((d) => d.items).where((i) => i.kind == 'H').map((i) => i.exercise).toSet(), {
      'Takakyykky',
      'Penkkipunnerrus',
      'Maastaveto',
    });
  });

  test('Jokaisella liikkeellä on välinetieto', () {
    expect([
      for (final x in exerciseCatalog.values.expand((x) => x))
        if (!exerciseEquipment.containsKey(x)) x,
    ], isEmpty);
  });

  test('Päivän oma nimi: tallentuu ja vertailu toimii nimen vaihdon jälkeen', () {
    final p = hyp(3);
    p.plan.first.label = 'Maanantai';
    final r = parseProgram(programToMarkdown(p))!;
    expect((r.plan.first.name, r.plan.first.label, r.plan.first.display), ('Koko keho A', 'Maanantai', 'Maanantai'));
    expect(r.plan[1].label, isNull);
    final w = Workout(date: DateTime(2026, 11, 9), title: 'Maanantai', programDay: 'Koko keho A');
    final back = parseWorkout(workoutToMarkdown(w));
    expect(back.dayKey, 'Koko keho A');
    // Vanha tiedosto ilman day-kenttää: otsikko toimii tunnisteena.
    expect(parseWorkout('---\ndate: 2026-11-02\ntitle: Koko keho A\n---\n').dayKey, 'Koko keho A');
    r.plan.first.label = 'Veto';
    expect(r.plan.first.matches(back.dayKey), isTrue);
  });

  test('Kehonpaino-ohjelma ilman salia: vain kehonpainoliikkeitä, pätevä', () {
    for (final goal in ['lihaskasvu', 'kunto', 'rasvanpoltto']) {
      for (var d = 2; d <= 5; d++) {
        final p = generateProgram(
          goal: goal,
          experience: 'keski',
          days: d,
          minutes: 60,
          injuries: const [],
          equipment: {'kehonpaino'},
        );
        final other = [
          for (final i in p.plan.expand((x) => x.items))
            if (!fitsEquipment(i.exercise, {'kehonpaino'})) i.exercise,
        ];
        expect(other, isEmpty, reason: '$goal $d pv');
        expect(validateProgram(p), isEmpty, reason: '$goal $d pv');
      }
    }
  });
}
