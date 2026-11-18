import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/insights.dart';
import 'package:treenipaivakirja/models.dart';

// Kantamisen ennätys on paras paino, ei arvioitu maksimi (käyttäjä 17.11.: 132 kg × 2 edestakaisin näytti 141 kg).
void main() {
  test('farmer walk: ennätys = paino; toistoliikkeessä Epley; lämmittely ei ennätys', () {
    final day = DateTime(2026, 11, 17);
    final ws = [
      Workout(date: day, title: 'Treeni')
        ..exercises.addAll([
          ExerciseEntry('Farmer walk hex barilla', [SetEntry(122, 2), SetEntry(132, 2)]),
          ExerciseEntry('Reiden ojennus', [SetEntry(70, 10)..warmup = true, SetEntry(60, 4)]),
        ]),
    ];
    expect(bestLift(ws, 'Farmer walk hex barilla')!.e1rm, 132);
    expect(bestLift(ws, 'Reiden ojennus')!.kg, 60, reason: 'lämmittely ohitetaan');
    expect(bestLift(ws, 'Reiden ojennus')!.e1rm, closeTo(68, 0.01));
  });
}
