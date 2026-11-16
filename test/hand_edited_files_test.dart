import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/daily_steps.dart';
import 'package:treenipaivakirja/import_detect.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';

// Käsin muokatut tiedostot eivät saa kaataa lukua (testikierros 15.11. ilta). Keksityt arvot.
void main() {
  test('sarjalta näyttävä rivi Liikunta-osion alla ei kaada treenin lukua', () {
    final w = Workout(date: DateTime(2026, 11, 15), title: 'Kävely', activity: 'Kävely')
      ..distanceKm = 3
      ..minutes = 40;
    final md = workoutToMarkdown(w);
    expect(md, contains('## $activityHeading'));
    final edited = md.replaceFirst('## $activityHeading\n', '## $activityHeading\n- 5 kg x 3\n1. 30\n');
    expect(edited, isNot(md));
    final back = parseWorkout(edited);
    expect(back.activity, 'Kävely');
    expect(back.exercises, isEmpty);
    expect(back.minutes, 40);
  });

  test('ohjelman väärinpäin kirjoitettu toistoväli ja nolla sarjaa korjataan luettaessa', () {
    final p = Program(
      goal: 'voima',
      experience: 'keski',
      days: 1,
      minutes: 60,
      start: DateTime(2026, 11, 2),
      deloadEvery: 0,
      maxes: {},
      notes: [],
      plan: [
        PlanDay('Koko keho A', [
          PlanItem('Penkkipunnerrus', 'VT', 3, 8, 12, '1–2', 180),
          PlanItem('Leuanveto', 'VV', 2, 6, 10, '1–3', 90),
        ]),
      ],
    );
    final md = programToMarkdown(p);
    expect(md, contains('3 × 8–12'));
    final back = parseProgram(md.replaceFirst('3 × 8–12', '3 × 12–8').replaceFirst('2 × 6–10', '0 × 0'))!;
    final items = back.plan.single.items;
    expect((items[0].lo, items[0].hi), (8, 12));
    expect((items[1].sets, items[1].lo, items[1].hi), (1, 1, 1));
  });

  test('rikkinäiset tuontitiedostot eivät kaada tunnistusta eivätkä lukua', () {
    final r = Random(7);
    final garbage = Uint8List.fromList([for (var i = 0; i < 3000; i++) r.nextInt(256)]);
    final brokenZip = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, ...utf8.encode('roskaa, ei zip')]);
    expect(detectImport('tyhja.zip', Uint8List(0)), ImportKind.unknown);
    expect(detectImport('rikki.zip', brokenZip), ImportKind.unknown);
    expect(detectImport('roskaa.gmd', garbage), ImportKind.unknown);
    const odd =
        '---\ndate: 2026-13-45\n---\n# x\n## Liikunta\n- 5 kg x 3\n## Penkkipunnerrus\n'
        '- 99999999999999999999999 kg x 99999999999999999999\n- 60 kg x 8\n';
    // Lukukelvoton treeni raportoidaan (unreadable), ei poikkeusta.
    final res = readMdFiles({'2026-11-01.md': odd});
    expect(res.workouts.length + res.unreadable.length, 1);
    // Ohjelmapohja, jossa on roskarivejä.
    parseProgram(
      '# Ohjelma\n\n## Koko keho A\n- Penkkipunnerrus | 3 x 12-8\n- | | |\n## \n- 9999999999999999999999 x 5\n',
    );
  });

  test('askeleet.md: liian pitkä luku ohitetaan, muut päivät säilyvät', () {
    final (days, _) = parseSteps(
      '- 2026-11-14: 8000\n- 2026-11-15: 99999999999999999999999\n- 2026-11-13: 5000 (Oura)\n',
    );
    expect(days.length, 2);
    expect(days[DateTime(2026, 11, 14)], 8000);
  });

  test('sarjarivi ilman kg-merkintää luetaan ("- 40 × 8", testikierros 16.11.)', () {
    final w = parseWorkout('---\ndate: 2026-11-02\n---\n## Penkkipunnerrus\n- 40 × 8\n- 42,5 x 6\n1. 45 kg × 5\n');
    expect(w.exercises.single.sets.map((s) => (s.kg, s.reps)), [(40.0, 8), (42.5, 6), (45.0, 5)]);
  });

  test('vanha ohjelma, jossa pyramidi (poistettu 16.11.), luetaan tavallisina sarjoina', () {
    final p = parseProgram(
      '---\ngoal: voima\nexperience: keski\ndays: 1\nminutes: 60\nstart: 2026-11-02\ndeloadEvery: 6\n---\n\n'
      '## Koko keho A\n- Takakyykky | 4 × 6–12 | varaa 1–2 | tauko 3 min | KYY | pyramidi 12-10-8-6\n',
    )!;
    final it = p.plan.single.items.single;
    expect((it.sets, it.lo, it.hi), (4, 6, 12));
    expect(programToMarkdown(p), isNot(contains('pyramidi')));
  });

  test('tuntematon liikemalli pohjassa ("VT"): käytetään liikkeen omaa (testikierros 16.11.)', () {
    final p = parseProgram(
      '---\ntemplate: gievra-1\ngoal: voima\nexperience: keski\ndays: 1\nminutes: 60\ndeloadEvery: 6\n---\n\n'
      '## A\n- Penkkipunnerrus | 3 × 5 | varaa 1–2 | tauko 3 min | VT\n',
    )!;
    expect(p.plan.single.items.single.slot, slotOf('Penkkipunnerrus'));
    expect(p.plan.single.items.single.slot, isNotEmpty);
  });
}
