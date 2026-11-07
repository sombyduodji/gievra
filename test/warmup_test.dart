import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/progression.dart';
import 'package:treenipaivakirja/session_compare.dart';

void main() {
  test('lämmittely 120 kg takakyykkyyn: tanko, ~50 %, ~70 %, ~85 %', () {
    final w = warmupSets('Takakyykky', 120);
    expect(w.map((s) => '${s.kg}×${s.reps}').toList(), ['20.0×10', '60.0×5', '85.0×3', '102.5×1']);
    expect(w.every((s) => s.warmup), isTrue);
  });

  test('kevyt paino ja eristävä liike: vähemmän tai ei lainkaan lämmittelyä', () {
    expect(warmupSets('Takakyykky', 25), isEmpty);
    expect(warmupSets('Hauiskääntö tangolla', 40), isEmpty);
    expect(warmupSets('Penkkipunnerrus', 60).length, lessThan(4));
  });

  test('lämmittelysarja tallentuu ja luetaan, ei lasketa volyymiin', () {
    final w = Workout(date: DateTime(2026, 11, 7), title: 'Jalat')
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(20, 10, warmup: true), SetEntry(100, 5)]));
    final md = workoutToMarkdown(w);
    expect(md, contains('20 kg × 10 (lämmittely)'));
    final back = parseWorkout(md);
    expect(back.exercises.first.sets.first.warmup, isTrue);
    expect(back.exercises.first.workSets.length, 1);
    expect(workVolume(back), 500);
  });
}
