import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/drafts.dart';
import 'package:treenipaivakirja/models.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gievra-luonnos');
    ActivityDraft.dirOverride = tmp;
  });
  tearDown(() {
    ActivityDraft.dirOverride = null;
    tmp.deleteSync(recursive: true);
  });

  test('Keskeneräinen kirjaus palautuu: arvot, muistiinpanot ja näkymän oma tila', () async {
    final w = Workout(date: DateTime(2026, 11, 8), activity: 'Juoksu', title: 'Juoksu', session: 2)
      ..seconds = 1830
      ..minutes = 31
      ..distanceKm = 5.2
      ..intensity = 'kova'
      ..notes = 'tuulinen ilta';
    await ActivityDraft.save(w, extra: {'stopwatchMs': 61000});
    final d = await ActivityDraft.load();
    expect(d, isNotNull);
    final (back, extra) = d!;
    expect(
      (back.activity, back.session, back.seconds, back.distanceKm, back.intensity),
      ('Juoksu', 2, 1830, 5.2, 'kova'),
    );
    expect(back.notes.trim(), 'tuulinen ilta');
    expect(extra['stopwatchMs'], 61000);
    await ActivityDraft.clear();
    expect(await ActivityDraft.load(), isNull);
  });

  test('Yli vuorokauden vanha luonnos ei palaudu', () async {
    final w = Workout(date: DateTime(2026, 11, 8), activity: 'Kävely', title: 'Kävely');
    await ActivityDraft.save(w);
    final f = File('${tmp.path}/liikunta-luonnos.json');
    final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    m['saved'] = DateTime.now().subtract(const Duration(hours: 25)).toIso8601String();
    f.writeAsStringSync(jsonEncode(m));
    expect(await ActivityDraft.load(), isNull);
    expect(f.existsSync(), isFalse);
  });

  test('Rikkinäinen luonnostiedosto ei kaada sovellusta', () async {
    File('${tmp.path}/liikunta-luonnos.json').writeAsStringSync('{ei jsonia');
    expect(await ActivityDraft.load(), isNull);
  });
}
