import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/progression.dart';

Workout bench(DateTime d, double kg, int reps, int? rir) => Workout(
  date: d,
  exercises: [
    ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 8), SetEntry(kg, reps, rir: rir), SetEntry(kg, reps, rir: rir)]),
  ],
);

void main() {
  setUp(() {
    settings
      ..weightStep = 2.5
      ..pauses = [];
  });

  test('RIR .md:ssä edestakaisin, myös käsin kirjoitettu', () {
    final w = Workout(
      date: DateTime(2026, 11, 6),
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(100, 5, rir: 0), SetEntry(100, 5, rir: 1), SetEntry(100, 5, rir: 3)]),
      ],
    );
    final md = workoutToMarkdown(w);
    expect(md, contains('1. 100 kg × 5 RIR 0\n2. 100 kg × 5 RIR 1-2\n3. 100 kg × 5 RIR 3+'));
    expect(parseWorkout(md).exercises.single.sets.map((s) => s.rir), [0, 1, 3]);
    expect(
      parseWorkout('---\ndate: 2026-11-06\n---\n## X\n1. 50 kg × 5 RIR 1–2\n2. 50 kg x 5 RIR 4').exercises.single.sets
          .map((s) => s.rir),
      [1, 3],
    );
  });

  test('RIR ohjaa ehdotusta; alavartalossa tuplalisäys', () {
    final d = DateTime(2026, 11, 6);
    // Reilusti varaa: tankoliike +5 kg (10 kg pudottaisi toistot alle 4), toistot pysyvät.
    store.workouts = [bench(DateTime(2026, 11, 3), 100, 5, 3)];
    expect((suggestNext('Penkkipunnerrus', d)!.kg, suggestNext('Penkkipunnerrus', d)!.reps), (105, 5));
    store.workouts = [bench(DateTime(2026, 11, 3), 80, 8, 3)];
    expect(suggestNext('Penkkipunnerrus', d)!.kg, 85, reason: 'tankoliikkeessä vain 5 tai 10 kg');
    store.workouts = [bench(DateTime(2026, 11, 3), 100, 5, 1)];
    final s = suggestNext('Penkkipunnerrus', d)!;
    expect((s.kg, s.reps), (100, 6));
    store.workouts = [bench(DateTime(2026, 11, 3), 100, 5, 0)];
    expect((suggestNext('Penkkipunnerrus', d)!.kg, suggestNext('Penkkipunnerrus', d)!.reps), (100, 5));
    store.workouts = [
      Workout(
        date: DateTime(2026, 11, 3),
        exercises: [
          ExerciseEntry('Takakyykky', [SetEntry(140, 5, rir: 3)]),
        ],
      ),
    ];
    expect(suggestNext('Takakyykky', d)!.kg, 150, reason: '140 × 5, reilusti varaa: +10 kg, toistot 4');
  });

  test('Toistoja ei lisätä loputtomiin: ylärajalla paino ylös ja toistot alas', () {
    final d = DateTime(2026, 11, 6);
    Workout one(String ex, double kg, int reps, int? rir) => Workout(
      date: DateTime(2026, 11, 3),
      exercises: [
        ExerciseEntry(ex, [SetEntry(kg, reps, rir: rir), SetEntry(kg, reps, rir: rir)]),
      ],
    );
    // Maastaveto 10 × 100, varaa 1–2: ei 10 × 102,5 vaan 110 × 6 (10 kg = 10 %, toistot pysyvät 6–10:ssä).
    store.workouts = [one('Maastaveto', 100, 10, 1)];
    var s = suggestNext('Maastaveto', d)!;
    expect((s.kg, s.reps), (110, 6));
    // Voima-alue (≤ 6 toistoa): 6 × 100 → 105 × 4 (10 kg pudottaisi kolmeen).
    store.workouts = [one('Maastaveto', 100, 6, 1)];
    s = suggestNext('Maastaveto', d)!;
    expect((s.kg, s.reps), (105, 4));
    // Alle 100 kg vain 5 kg kerrallaan.
    store.workouts = [one('Penkkipunnerrus', 80, 10, 1)];
    s = suggestNext('Penkkipunnerrus', d)!;
    expect((s.kg, s.reps), (85, 8));
    // Alle ylärajan: sama paino, toisto lisää.
    store.workouts = [one('Maastaveto', 100, 8, 1)];
    s = suggestNext('Maastaveto', d)!;
    expect((s.kg, s.reps), (100, 9));
    // Eristävä liike: yläraja 15, pienin lisäys.
    store.workouts = [one('Hauiskääntö', 15, 15, 1)];
    s = suggestNext('Hauiskääntö', d)!;
    expect(s.kg, 17.5);
    expect(s.reps, lessThan(15));
    store.workouts = [one('Hauiskääntö', 15, 12, 1)];
    expect(suggestNext('Hauiskääntö', d)!.reps, 13);
    expect(nextLoad('Maastaveto', 200).$1, 210);
    expect(nextLoad('Maastaveto', 90).$1, 95, reason: '10 kg olisi yli 10 %');
  });

  test('Varaa vaikuttaa: ei yhtään, muutama ja reilusti antavat eri ehdotuksen', () {
    final d = DateTime(2026, 11, 6);
    final out = <(double, int)>[];
    for (final rir in [null, 0, 1, 3]) {
      store.workouts = [bench(DateTime(2026, 11, 3), 80, 8, rir)];
      final s = suggestNext('Penkkipunnerrus', d)!;
      out.add((s.kg, s.reps));
    }
    expect(out, [(80, 8), (80, 8), (80, 9), (85, 7)]);
  });

  test('Raskaalta tuntunut kerta pitää painon, myös ilman syytä', () {
    final d = DateTime(2026, 11, 6);
    store.workouts = [bench(DateTime(2026, 11, 3), 80, 8, 3)..feeling = 2];
    var s = suggestNext('Penkkipunnerrus', d)!;
    expect((s.kg, s.reps), (80, 8));
    expect(s.reason, contains('raskaalta'));
    // Liikkeen oma fiilis voittaa koko treenin fiiliksen.
    store.workouts = [
      bench(DateTime(2026, 11, 3), 80, 8, 3)
        ..feeling = 2
        ..moveFeeling = {'Penkkipunnerrus': 4},
    ];
    expect(suggestNext('Penkkipunnerrus', d)!.kg, 85);
    store.workouts = [bench(DateTime(2026, 11, 3), 80, 8, 3)..feeling = 5];
    expect(suggestNext('Penkkipunnerrus', d)!.kg, 85);
  });

  test('Aikaliikkeissä "olisitko jaksanut pidempään" ohjaa aikaa', () {
    final d = DateTime(2026, 11, 6);
    Workout plank(int? rir) => Workout(
      date: DateTime(2026, 11, 3),
      exercises: [
        ExerciseEntry('Lankku', [SetEntry(0, 45, rir: rir)]),
      ],
    );
    store.workouts = [plank(3)];
    expect(suggestNext('Lankku', d)!.reps, 55);
    store.workouts = [plank(1)];
    expect(suggestNext('Lankku', d)!.reps, 50);
    store.workouts = [plank(0)];
    expect(suggestNext('Lankku', d)!.reps, 45);
    expect(reserveWords(Measure.seconds).question, 'Olisitko jaksanut pidempään?');
    expect(reserveWords(Measure.steps).answers.map((a) => a.$2), ['En yhtään', 'Vähän', 'Reilusti']);
    expect(reserveTarget(Measure.seconds, '1–3'), 'jätä vähän varaa');
    expect(reserveTarget(Measure.reps, '1–3'), 'varaa 1–3');
  });

  test('Paluu sairauslomalta: kevyemmät kuormat ja vähemmän sarjoja, palautuu 2 viikossa', () {
    store.workouts = [bench(DateTime(2026, 10, 20), 100, 5, 3)];
    settings.pauses = [Pause(DateTime(2026, 10, 22), 'sairas', DateTime(2026, 10, 31))]; // 10 pv
    final first = suggestNext('Penkkipunnerrus', DateTime(2026, 11, 1))!;
    expect(first.kg, 85); // −15 %
    expect(first.setsFactor, closeTo(2 / 3, 1e-9));
    expect(first.reason, contains('sairauden'));
    final later = suggestNext('Penkkipunnerrus', DateTime(2026, 11, 10))!;
    expect(later.kg, greaterThan(85));
    expect(returnFor(DateTime(2026, 11, 20)), isNull);
  });

  test('Lyhyt loma ei kevennä', () {
    store.workouts = [bench(DateTime(2026, 10, 20), 100, 5, 1)];
    settings.pauses = [Pause(DateTime(2026, 10, 25), 'loma', DateTime(2026, 10, 30))];
    expect(returnFor(DateTime(2026, 10, 31)), isNull);
  });

  test('Tauot asetukset.md:ssä', () {
    final s = Settings()
      ..pauses = [Pause(DateTime(2026, 10, 1), 'loma', DateTime(2026, 10, 14)), Pause(DateTime(2026, 11, 5), 'sairas')];
    final md = s.settingsToMarkdown();
    expect(md, contains('## Tauot\n- 2026-10-01 – 2026-10-14 loma\n- 2026-11-05 – sairas\n'));
    final r = Settings()..applyMarkdown(md);
    expect(r.pauses.length, 2);
    expect(r.pauses[0].end, DateTime(2026, 10, 14));
    expect(r.activePause!.sick, isTrue);
  });

  test('Ennätys ilman treenihistoriaa: ehdotus ennätyksestä, kahvakuulassa kuulakoko', () {
    final d = DateTime(2026, 11, 6);
    store.workouts = [];
    settings.program = Program(
      goal: 'kunto',
      experience: 'keski',
      days: 3,
      minutes: 60,
      start: DateTime(2026, 11, 2),
      deloadEvery: 0,
      maxes: {'Penkkipunnerrus': 100, 'Kahvakuulapystypunnerrus': 21},
    );
    final t = Target(3, 8, 12, '1–3', 120, 'Viikko 1');
    // 100 / (1 + (8 + 2) / 30) = 75 kg
    expect(suggestForTarget('Penkkipunnerrus', d, t)!.kg, 75);
    // 21 / 1,333 = 15,75 -> lähin kevyempi kuula 14 kg
    expect(suggestForTarget('Kahvakuulapystypunnerrus', d, t)!.kg, 14);
    // Ei ennätystä eikä historiaa: ei ehdotusta (käyttäjä valitsee painon itse).
    expect(suggestForTarget('Kulmasoutu', d, t), isNull);
    settings.program = null;
  });

  test('Kahvakuula: seuraava kuula vasta, kun sillä onnistuu toistoalueen verran (16 → 20 kg = +25 %)', () {
    final d = DateTime(2026, 11, 6);
    Workout kb(String ex, double kg, int reps, int rir) => Workout(
      date: DateTime(2026, 11, 3),
      exercises: [
        ExerciseEntry(ex, [SetEntry(kg, reps, rir: rir), SetEntry(kg, reps, rir: rir)]),
      ],
    );
    // Ei 20 kg × 1–2: samalla kuulalla lisää toistoja.
    store.workouts = [kb('Kahvakuulapystypunnerrus', 16, 10, 1)];
    var s = suggestNext('Kahvakuulapystypunnerrus', d)!;
    expect((s.kg, s.reps), (16, 11));
    expect(s.reason, contains('liian raskas'));
    store.workouts = [kb('Kahvakuulapystypunnerrus', 16, 5, 3)];
    s = suggestNext('Kahvakuulapystypunnerrus', d)!;
    expect((s.kg, s.reps), (16, 7), reason: 'reilusti varaa: +2 toistoa');
    // 15 toistoa 16 kg:lla → 20 kg × 6.
    store.workouts = [kb('Kahvakuulapystypunnerrus', 16, 15, 1)];
    s = suggestNext('Kahvakuulapystypunnerrus', d)!;
    expect((s.kg, s.reps), (20, 6));
    // Reilusti varaa nostaa vähintään yhtä aikaisin kuin muutama.
    store.workouts = [kb('Kahvakuulapystypunnerrus', 16, 14, 3)];
    expect(suggestNext('Kahvakuulapystypunnerrus', d)!.kg, 20);
    // Goblet-kyykky kuulakoon painolla: seuraava kuula, ei 21 kg.
    store.workouts = [kb('Goblet-kyykky', 16, 15, 1)];
    expect(suggestNext('Goblet-kyykky', d)!.kg, 20);
    // Yläraja 20 toistoa: sitten raskaampaan joka tapauksessa.
    store.workouts = [kb('Kahvakuulahauiskääntö', 16, 20, 1)];
    expect(suggestNext('Kahvakuulahauiskääntö', d)!.kg, 20);
  });
}
