import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/anim/cues.dart';
import 'package:treenipaivakirja/anim/cues_en.dart';
import 'package:treenipaivakirja/anim/motions.dart';
import 'package:treenipaivakirja/exercise_names_en.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/program.dart';

// Reiden koukistus istuen puuttui liikelistasta (käyttäjä 17.11. salilla); FitNotesin Seated Leg Curl tuotiin
// makuulla tehtäväksi.
void main() {
  test('istuen tehtävä reiden koukistus: lista, nimi, laite, ohje, animaatio, tuonti ja ohjelman paikka', () {
    const n = 'Reiden koukistus istuen';
    expect(exerciseCatalog.values.expand((l) => l), contains(n));
    expect(exerciseEnglish[n], 'Seated Leg Curl Machine');
    expect(exerciseEquipment[n], isNotEmpty);
    expect(exerciseCues[n], hasLength(3));
    expect(exerciseCuesEn[n], hasLength(3));
    expect(exerciseMotions[n], isNotNull);
    expect(fitnotesNames['Seated Leg Curl Machine'], n);
    expect(fitnotesNames['Lying Leg Curl Machine'], 'Reiden koukistus');
    expect(slotOf(n), slotOf('Reiden koukistus'));
  });
}
