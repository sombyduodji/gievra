import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/progression.dart';

void main() {
  setUp(() {
    settings
      ..weightStep = 2.5
      ..pauses = [];
  });

  test('liikepalaute ja päivän syyt tallentuvat .md:hen', () {
    final w = Workout(date: DateTime(2026, 11, 6), title: 'Jalat')
      ..feeling = 2
      ..moveFeeling = {'Takakyykky': 1, 'Jalkaprässi': 4}
      ..tooHeavy = {'Takakyykky'}
      ..dayReasons = ['väsynyt', 'rankka päivä']
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5, rir: 3), SetEntry(100, 5, rir: 3)]));
    final md = workoutToMarkdown(w);
    expect(md, contains('move_feeling: Takakyykky=1 liian raskas; Jalkaprässi=4'));
    expect(md, contains('day_feeling: väsynyt, rankka päivä'));
    final back = parseWorkout(md);
    expect(back.moveFeeling, {'Takakyykky': 1, 'Jalkaprässi': 4});
    expect(back.tooHeavy, {'Takakyykky'});
    expect(back.dayReasons, ['väsynyt', 'rankka päivä']);
  });

  test('liian raskas -> seuraava ehdotus kevyempi; rankka päivä -> ei nostoa', () {
    final heavy = Workout(date: DateTime(2026, 11, 2))
      ..feeling = 1
      ..tooHeavy = {'Takakyykky'}
      ..moveFeeling = {'Takakyykky': 1}
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5, rir: 3), SetEntry(100, 5, rir: 3)]));
    store.workouts = [heavy];
    final s = suggestNext('Takakyykky', DateTime(2026, 11, 6))!;
    expect(s.kg, lessThan(100));

    final tired = Workout(date: DateTime(2026, 11, 2))
      ..feeling = 2
      ..dayReasons = ['väsynyt']
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5, rir: 3), SetEntry(100, 5, rir: 3)]));
    store.workouts = [tired];
    expect(suggestNext('Takakyykky', DateTime(2026, 11, 6))!.kg, 100);
  });
}
