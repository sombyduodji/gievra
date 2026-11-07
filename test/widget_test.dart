import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/widgets.dart';

void main() {
  test('Markdown edestakaisin säilyttää treenin', () {
    final w = Workout(
      date: DateTime(2026, 11, 6),
      title: 'Jalkapäivä',
      warmup: Warmup('Crosstrainer', 10),
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(100, 5), SetEntry(127.5, 3, rpe: 8.5, pr: true)]),
        ExerciseEntry('Tyhjä'),
      ],
      notes: 'Polvi ok.\nEnsi kerralla 130.',
    );
    final md = workoutToMarkdown(w);
    expect(md, contains('2. 127,5 kg × 3 @8,5 🏆 ennätys'));
    expect(md, isNot(contains('## Tyhjä')));

    final r = parseWorkout(md);
    expect(r.date, DateTime(2026, 11, 6));
    expect(r.title, 'Jalkapäivä');
    expect(r.warmup!.equipment, 'Crosstrainer');
    expect(r.warmup!.minutes, 10);
    expect(r.exercises.single.name, 'Takakyykky');
    expect(r.exercises.single.sets[1].kg, 127.5);
    expect(r.exercises.single.sets[1].rpe, 8.5);
    expect(r.exercises.single.sets[1].pr, isTrue);
    expect(r.exercises.single.sets[0].pr, isFalse);
    expect(r.notes, 'Polvi ok.\nEnsi kerralla 130.');
    expect(workoutToMarkdown(r), md);
  });

  test('Käsin kirjoitettu tiedosto ilman frontmatteria', () {
    const md = '# Penkki 2026-10-31\n\n## Penkkipunnerrus\n- 100kg x 3\n* 90 kg × 5\nroskaa\n';
    final r = parseWorkout(md, fallbackDate: DateTime(2026, 10, 31));
    expect(r.title, 'Penkki');
    expect(r.exercises.single.sets.map((s) => s.kg), [100, 90]);
  });

  test('Tervehdys vuorokaudenajan mukaan', () {
    expect(greeting(DateTime(2026, 1, 1, 7)), 'Hyvää huomenta');
    expect(greeting(DateTime(2026, 1, 1, 14)), 'Hyvää päivää');
    expect(greeting(DateTime(2026, 1, 1, 20)), 'Hyvää iltaa');
    expect(greeting(DateTime(2026, 1, 1, 2)), 'Hyvää yötä');
    expect(seGreeting(DateTime(2026, 1, 1, 7)), 'Buorre iđit');
    expect(seGreeting(DateTime(2026, 1, 1, 14)), 'Buorre beaivi');
    expect(seGreeting(DateTime(2026, 1, 1, 20)), 'Buorre eahket');
    expect(seGreeting(DateTime(2026, 1, 1, 2)), 'Buorre idja');
    expect(seDate(DateTime(2026, 11, 7)), 'lávvardat, skábmamánu 7. beaivi');
    expect(seDate(DateTime(2026, 1, 5)), 'vuossárga, ođđajagemánu 5. beaivi');
  });
}
