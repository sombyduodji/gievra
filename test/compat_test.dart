import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';

// Taaksepäin yhteensopivuus: vanhat, käsin muokatut ja tulevien versioiden tiedostot luetaan aina.
// Puuttuva tai outo kenttä jää tyhjäksi, ei virhettä eikä pysähdystä.
void main() {
  test('Vanha treeni ilman uusia kenttiä', () {
    final w = parseWorkout('---\ndate: 2026-01-05\ntitle: Jalat\n---\n## Takakyykky\n1. 100 kg × 5\n');
    expect((w.feeling, w.minutes, w.started), (null, null, null));
    expect(w.exercises.single.sets.single.kg, 100);
  });

  test('Oudot arvot ja tuntemattomat kentät ohitetaan', () {
    final w = parseWorkout(
      '---\ndate: 2026-01-05\nfeeling: hyvä\nduration: pitkä\nstart: aamulla\n'
      'tulevaisuuden_kenttä: 42\nbodyweight: ?\n---\n## Lankku\n1. 45 s\n2. jotain outoa\n## \n- x\n',
    );
    expect((w.feeling, w.minutes, w.started, w.bodyweight), (null, null, null, null));
    expect(w.exercises.first.sets.length, 1);
    expect(parseWorkout('---\ndate: 2026-01-05\nstart: 25:99\n---\n').started, isNull);
    expect(parseWorkout('---\ndate: 2026-01-05\nfeeling: 9\n---\n').feeling, isNull); // asteikon ulkopuolella
    expect(parseWorkout('---\ndate: 2026-01-05\nfeeling: 4\n---\n').feeling, 4); // pelkkä numero käy
  });

  test('Satunnainen roska ei kaada lukemista (treeni, ohjelma, asetukset)', () {
    final r = Random(7);
    const pieces = [
      '---',
      'date: 2026-01-05',
      'feeling:',
      'duration: 5',
      '## ',
      '## Penkki',
      '1.',
      '1. kg × ',
      '1. 50 kg × 5 RIR',
      '- ',
      '- Penkki | 3 × | varaa | tauko x',
      'start: 25:99',
      '# ',
      '> ',
      'reps: ???',
      'equipment: , ,x',
      'goal:',
      'days: -1',
      'name:',
      'theme: sininen',
      '### ',
      '×',
      '🏆',
      ':',
      '',
    ];
    for (var i = 0; i < 3000; i++) {
      final text = List.generate(r.nextInt(14), (_) => pieces[r.nextInt(pieces.length)]).join('\n');
      parseWorkout(text, fallbackDate: DateTime(2026, 1, 5));
      parseProgram(text);
      Settings().applyMarkdown(text);
    }
  });
}
