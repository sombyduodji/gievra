import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';

void main() {
  test('Valmiiksi merkityt liikkeet säilyvät .md-tiedostossa', () {
    final w = Workout(
      date: DateTime(2026, 11, 8),
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(100, 5)]),
        ExerciseEntry('Penkkipunnerrus', [SetEntry(80, 5)]),
      ],
    )..doneMoves = {'Takakyykky'};
    final md = workoutToMarkdown(w);
    expect(md, contains('done: Takakyykky'));
    expect(parseWorkout(md).doneMoves, {'Takakyykky'});
    expect(parseWorkout(workoutToMarkdown(Workout(date: DateTime(2026, 11, 8)))).doneMoves, isEmpty);
  });
}
