import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';

// Muistiinpanoissa Markdown-merkkejä (#, ---, - [ ], *, rivinvaihdot): tiedosto luetaan takaisin samana.
// Testikierros 15.11.: pitkä muistiinpano merkeillä # * [ ] ---. Keksitty treeni.
void main() {
  test('muistiinpano Markdown-merkeillä säilyy tallennuksessa', () {
    const notes = '---\n# Otsikko\n- [ ] tehtävä\n* tähti\n## Penkkipunnerrus\n- 60 × 8\nkcal: 999\n---\nloppu';
    final w =
        Workout(
            date: DateTime(2026, 11, 15),
            title: 'Treeni',
            exercises: [
              ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 8)]),
            ],
          )
          ..minutes = 30
          ..notes = notes;
    final back = parseWorkout(workoutToMarkdown(w));
    expect(back.notes, notes);
    expect(back.exercises.map((e) => e.name), ['Penkkipunnerrus']);
    expect(back.exercises.single.sets.length, 1);
    expect(back.minutes, 30);
    expect(back.kcal, isNull);
  });
}
