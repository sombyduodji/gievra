import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';

// Luvut tiedostoon ja näytölle: liukulukuvirhe ei näy (käsin kirjoitettu 3,3 kg ja painikkeella −1 kg).
void main() {
  test('Pyöristysvirhe pois, enintään kolme desimaalia', () {
    expect(fileNum(3.3 - 1), '2,3');
    expect(fileNum(1.1 - 1), '0,1');
    expect(fileNum(60 + 169 * .2), '93,8');
    expect(fileNum(100 / 60), '1,667');
    expect(fileNum(2.5), '2,5');
    expect(fileNum(1.25), '1,25');
    expect(fileNum(100), '100');
    expect(fileNum(0), '0');
  });

  test('Sarja tallentuu .md-tiedostoon ilman pyöristysvirhettä ja luetaan samana', () {
    final w = Workout(date: DateTime(2026, 11, 2), title: 'Koko keho A')
      ..exercises.add(ExerciseEntry('Vipunosto sivulle', [SetEntry(3.3 - 1, 12)]));
    final md = workoutToMarkdown(w);
    expect(md, contains('2,3 kg × 12'));
    expect(md, isNot(contains('2,29999')));
    expect(parseWorkout(md).exercises.single.sets.single.kg, 2.3);
  });
}
