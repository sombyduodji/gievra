import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/bug_report.dart';

// Vikailmoituksen liitteet: 3 uusinta treeniä valmiiksi, vanhemmat "Näytä lisää" -erissä valitsemattomina.
// Keksityt treenit väliaikaisessa kansiossa.
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gievra_bug');
    settings.folder = dir.path;
    store.workouts.clear();
    for (var i = 0; i < 15; i++) {
      final d = DateTime(2026, 10, 1 + i);
      final w = Workout(date: d, title: 'Treeni');
      store.workouts.add(w);
      final f = File(p.join(dir.path, workoutPath(d)));
      await f.parent.create(recursive: true);
      await f.writeAsString('# Treeni\n');
    }
  });
  tearDown(() async {
    settings.folder = null;
    store.workouts.clear();
    await dir.delete(recursive: true);
  });

  test('Oletus: 3 uusinta valittuna', () async {
    final a = await defaultReportAttachments();
    expect(a.map((x) => x.$1), ['2026-10-15.md', '2026-10-14.md', '2026-10-13.md']);
    expect(a.every((x) => x.$3), isTrue);
  });

  test('Lisää: seuraavat vanhemmat, valitsemattomina', () async {
    final more = await workoutAttachments(3, 10, on: false);
    expect(more.length, 10);
    expect(more.first.$1, '2026-10-12.md');
    expect(more.last.$1, '2026-10-03.md');
    expect(more.any((x) => x.$3), isFalse);
    expect((await workoutAttachments(13, 10, on: false)).map((x) => x.$1), ['2026-10-02.md', '2026-10-01.md']);
  });

  test('Syke, kalorit ja henkilötiedot omina liitteinään, oletuksena pois', () async {
    final f = File(p.join(dir.path, workoutPath(DateTime(2026, 10, 15))));
    await f.writeAsString(
      '# Treeni\nduration: 50 min\nkcal: 321\nhr_avg: 128\nhr_max: 165\nhr_source: syke\n'
      'hr_series: 5 17:32:10 112 115 0 118\n\n## Takakyykky\n- 100 kg × 5\n',
    );
    await File(p.join(dir.path, 'asetukset.md')).writeAsString('text_size: normal\nbirth_year: 1980\nsex: mies\nhr_recovery: 55\nkcal_adjust: -10\n');
    final a = {for (final x in await defaultReportAttachments()) x.$1: x};
    final w = await File(a['2026-10-15.md']!.$2).readAsString();
    expect(w, contains('Takakyykky'));
    expect(w, isNot(contains('hr_')));
    expect(w, isNot(contains('kcal')));
    expect(a['2026-10-15.md']!.$3, isTrue);
    final hrFile = a['2026-10-15-syke.md']!;
    expect(hrFile.$3, isFalse, reason: 'terveystieto: oletuksena pois');
    expect(hrFile.$4, isNotNull);
    expect(await File(hrFile.$2).readAsString(), contains('hr_series: 5 17:32:10'));
    final s = await File(a['asetukset.md']!.$2).readAsString();
    expect(s, contains('text_size'));
    expect(s, isNot(contains('birth_year')));
    expect(s, isNot(contains('hr_recovery')));
    expect(s, isNot(contains('kcal_adjust')));
    expect(await File(a['asetukset-henkilotiedot.md']!.$2).readAsString(), contains('kcal_adjust: -10'));
    expect(a['asetukset-henkilotiedot.md']!.$3, isFalse);
    expect(a.containsKey('2026-10-14-syke.md'), isFalse, reason: 'ei sykettä: ei erillistä liitettä');
  });
}
