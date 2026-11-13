import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/program.dart';

// Vammatila kahvakuulaliikkeille: ohje lähimmältä käsipaino- tai tankoliikkeeltä (injuryEquivalent).

void main() {
  test('Vastineet ovat liikeluettelossa, ja kaikki kahvakuulan pään yli -liikkeet on katettu', () {
    final all = exerciseCatalog.values.expand((x) => x).toSet();
    for (final e in injuryEquivalent.entries) {
      expect(all, contains(e.key));
      expect(all, contains(e.value));
    }
    for (final x in [
      'Kahvakuulapystypunnerrus',
      'Tuplakahvakuulapystypunnerrus',
      'Kahvakuulatempaus',
      'Tuplakahvakuulatyöntö',
      'Kahvakuula-thruster',
      'Turkkilainen ylösnousu',
    ]) {
      expect(injuryEquivalent, contains(x));
    }
  });

  test('Olkapää (kiertäjäkalvosin): kahvakuulapunnerrus kevyesti, tempaus ja työntö vältetään', () {
    const inj = ['olkapaa_kiertajakalvosin'];
    final press = injuryStatus('Kahvakuulapystypunnerrus', inj);
    expect(press.avoid, isEmpty);
    expect(press.modify.single, contains('vain jos kivuton'));
    expect(injuryStatus('Kahvakuulatempaus', inj).avoid, isNotEmpty);
    expect(injuryStatus('Tuplakahvakuulatyöntö', inj).avoid, isNotEmpty);
    expect(injuryStatus('Kahvakuulan sumoveto', inj).avoid, isNotEmpty, reason: '= pystysoutu');
    expect(injuryStatus('Kahvakuulaheilautus', inj).flagged, isFalse, reason: 'ei olkapäärasitusta');
    // Ilman vammoja ei merkintöjä.
    expect(injuryStatus('Kahvakuulatempaus', const []).flagged, isFalse);
  });

  test('Kahvakuulaohjelma olkapäävaivalla: ei vältettäviä liikkeitä ilman merkintää', () {
    for (final inj in [
      ['olkapaa_kiertajakalvosin'],
      ['olkapaa_epavakaus'],
      ['ranne'],
    ]) {
      for (final focus in kbFocuses.keys) {
        final p = generateProgram(
          goal: 'kunto',
          experience: 'keski',
          days: 3,
          minutes: 60,
          injuries: inj,
          equipment: {'kahvakuula'},
          kbFocus: focus,
        );
        for (final it in p.plan.expand((d) => d.items)) {
          if (injuryStatus(it.exercise, inj).avoid.isEmpty) continue;
          expect(it.note ?? '', contains('Varo'), reason: '${inj.first}/$focus: ${it.exercise}');
        }
      }
    }
  });
}
