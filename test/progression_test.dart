import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/models.dart';
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
    store.workouts = [bench(DateTime(2026, 11, 3), 100, 5, 3)];
    expect(suggestNext('Penkkipunnerrus', d)!.kg, 102.5);
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
    expect(suggestNext('Takakyykky', d)!.kg, 145);
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
}
