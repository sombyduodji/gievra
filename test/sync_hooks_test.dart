import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';

// Jokainen tallennus, tuonti ja poisto ilmoittaa polun synkronoinnille (Drive-jono).
void main() {
  test('Tuonti, tallennus ja poisto menevät synkronoinnin jonoon', () async {
    final dir = await Directory.systemTemp.createTemp('koukut');
    settings.folder = dir.path;
    store.workouts = [];
    final calls = <String>[];
    onLocalChange = calls.add;

    final r = readMdFiles({
      '2026-11-05.md': '---\ndate: 2026-11-05\ntitle: PC:llä tehty\n---\n## Takakyykky\n1. 100 kg × 5\n',
      'muistiinpano.md': 'ei päivämäärää',
    });
    expect(r.workouts.length, 1);
    expect(await store.saveMany(r.workouts), 1);
    expect(calls, ['2026/2026-11-05.md']);

    await store.save(
      Workout(
        date: DateTime(2026, 11, 6),
        exercises: [
          ExerciseEntry('Lankku', [SetEntry(0, 45)]),
        ],
      ),
    );
    await store.delete(DateTime(2026, 11, 5));
    expect(calls, ['2026/2026-11-05.md', '2026/2026-11-06.md', '2026/2026-11-05.md']);
    onLocalChange = null;
    settings.folder = null;
    await dir.delete(recursive: true);
  });

  test('Kansion vaihto: kopiointi ei ylikirjoita, alkuperäiset jäävät', () async {
    final a = await Directory.systemTemp.createTemp('vanha');
    final b = await Directory.systemTemp.createTemp('uusi');
    File('${a.path}/asetukset.md').writeAsStringSync('vanhat asetukset');
    File('${a.path}/2026/2026-11-06.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('treeni');
    File('${a.path}/muistio.txt').writeAsStringSync('ei kopioida');
    File('${b.path}/asetukset.md').writeAsStringSync('uuden kansion asetukset');
    final (c, s) = await Settings.copyMdFiles(a, b);
    expect((c, s), (1, 1));
    expect(File('${b.path}/2026/2026-11-06.md').readAsStringSync(), 'treeni');
    expect(File('${b.path}/asetukset.md').readAsStringSync(), 'uuden kansion asetukset');
    expect(File('${b.path}/muistio.txt').existsSync(), isFalse);
    expect(File('${a.path}/2026/2026-11-06.md').existsSync(), isTrue);
    await a.delete(recursive: true);
    await b.delete(recursive: true);
  });
}
