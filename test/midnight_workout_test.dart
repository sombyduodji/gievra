import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ongoing.dart';

// Päivätesti 14.11.: yli puolenyön jatkuva salitreeni pysyy käynnissä (ilmoitus, etusivun Jatka), ja sen kesto
// tallentuu. Keksityt treenit.
void main() {
  Workout gym(DateTime date, DateTime started) => Workout(date: date, title: 'Treeni')
    ..started = started
    ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(60, 5)]));

  test('23:55 aloitettu treeni on käynnissä vielä 00:20 seuraavana päivänä', () {
    final w = gym(DateTime(2026, 11, 14), DateTime(2026, 11, 14, 23, 55));
    expect(Ongoing.gymInProgress([w], DateTime(2026, 11, 15, 0, 20)), same(w));
  });

  test('Yli 5 h vanha tai valmis treeni ei ole käynnissä; tuleva aloitus ei myöskään', () {
    final old = gym(DateTime(2026, 11, 14), DateTime(2026, 11, 14, 18));
    expect(Ongoing.gymInProgress([old], DateTime(2026, 11, 15, 0, 20)), isNull);
    final done = gym(DateTime(2026, 11, 14), DateTime(2026, 11, 14, 23, 55))..minutes = 25;
    expect(Ongoing.gymInProgress([done], DateTime(2026, 11, 15, 0, 20)), isNull);
    final future = gym(DateTime(2026, 11, 15), DateTime(2026, 11, 15, 1));
    expect(Ongoing.gymInProgress([future], DateTime(2026, 11, 15, 0, 20)), isNull);
  });
}
