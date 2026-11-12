import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/bug_report.dart';
import 'package:treenipaivakirja/ui/home.dart';

// Lukukelvottomat treenitiedostot: ennen ne ohitettiin hiljaa. Nyt etusivu kertoo niistä, väärän merkistön
// (Windowsin Latin-1, UTF-16) voi korjata, ja ne voi lähettää ongelmaraporttina. Keksityt treenit.
const _md = '---\ndate: 2026-11-04\ntitle: Kävely\nactivity: Kävely\nduration: 40 min\n---\n\n# Kävely 2026-11-04\n';

List<int> _utf16le(String s) => [
  0xFF,
  0xFE,
  for (final u in s.codeUnits) ...[u & 0xFF, u >> 8],
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Merkistön tunnistus: Latin-1 ja UTF-16 korjataan, muuta ei', () {
    expect(decodeLegacyText(latin1.encode(_md)), _md);
    expect(decodeLegacyText(_utf16le(_md.replaceAll('\n', '\r\n'))), _md, reason: 'Muistion rivinvaihdot');
    expect(decodeLegacyText(utf8.encode(_md)), isNull, reason: 'kelvollinen UTF-8: vika ei ole merkistössä');
    expect(decodeLegacyText([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46]), isNull, reason: 'kuva .md-nimellä');
    expect(decodeLegacyText(latin1.encode('Ostoslista: maitoa, leipää')), isNull, reason: 'ei treeni');
  });

  test('Kansio: lukukelvottomat listataan, Latin-1 korjataan ja alkuperäinen jää .bak-tiedostoksi', () async {
    final dir = Directory.systemTemp.createTempSync('gievra-unread');
    addTearDown(() {
      settings.folder = null;
      store.workouts = [];
      store.unreadable = {};
      dir.deleteSync(recursive: true);
    });
    File('${dir.path}/2026/2026-11-03.md')
      ..createSync(recursive: true)
      ..writeAsStringSync(_md.replaceAll('2026-11-04', '2026-11-03'));
    File('${dir.path}/2026/2026-11-04.md').writeAsBytesSync(latin1.encode(_md));
    File('${dir.path}/2026/2026-11-05.md').writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0xC3]);
    File('${dir.path}/muistiinpanot.md').writeAsBytesSync(latin1.encode('Omia äänimuistiinpanoja'));
    settings.folder = dir.path;

    await store.reload();
    expect(store.workouts.map((w) => w.date.day), [3]);
    expect(store.unreadable, {
      '2026/2026-11-04.md': 'Väärä merkistö (voidaan korjata)',
      '2026/2026-11-05.md': 'Ei tekstitiedosto: vaurioitunut tai väärä tiedosto',
    }, reason: 'muu kuin treeni ei kuulu listaan; syy jokaiselle');

    expect(await store.repairUnreadable(), 1);
    expect(store.unreadable.keys, ['2026/2026-11-05.md'], reason: 'kuvaa ei kosketa');
    expect(store.workouts.map((w) => (w.date.day, w.title)), [(4, 'Kävely'), (3, 'Kävely')]);
    expect(File('${dir.path}/2026/2026-11-04.md').readAsStringSync(), _md);
    expect(File('${dir.path}/2026/2026-11-04.md.bak').readAsBytesSync(), latin1.encode(_md));
    expect(File('${dir.path}/2026/2026-11-05.md').readAsBytesSync().length, 9, reason: 'ei muutettu');
  });

  testWidgets('Etusivu kertoo lukukelvottomista; raportissa tiedosto liitteenä', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    settings.folder = Directory.systemTemp.path;
    store.unreadable = {'2026/2026-11-05.md': 'Ei tekstitiedosto: vaurioitunut tai väärä tiedosto'};
    addTearDown(() {
      store.unreadable = {};
      settings.folder = null;
    });
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Treenitiedostoja ei voitu lukea: 1'), findsOneWidget);
    await tester.tap(find.text('Treenitiedostoja ei voitu lukea: 1'));
    await tester.pumpAndSettle();
    expect(find.text('• 2026/2026-11-05.md'), findsOneWidget);
    expect(find.text('Yritä korjata'), findsOneWidget);
    await tester.tap(find.text('Lähetä ongelmaraportti'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byType(BugReportScreen), findsOneWidget);
    final screen = tester.widget<BugReportScreen>(find.byType(BugReportScreen));
    expect(screen.type, 'save');
    expect(screen.attach.single.$1, '2026-11-05.md');
    expect(screen.attach.single.$2, endsWith('2026/2026-11-05.md'));
    expect(find.text('2026-11-05.md'), findsWidgets, reason: 'liite näkyy listassa');

    // Ei ilmoitusta, kun kaikki luettiin.
    store.unreadable = {};
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('ei voitu lukea'), findsNothing);
  });

  test('Palautus varmuuskopiosta: väärä merkistö luetaan oikein, lukukelvoton syineen raporttiin', () {
    final jpg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0xC3];
    final zip = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('Treenit/2026/2026-11-04.md', latin1.encode(_md).length, latin1.encode(_md)))
        ..addFile(ArchiveFile('Treenit/2026/2026-11-05.md', jpg.length, jpg)),
    );
    final r = readZip(zip);
    expect(r.workouts.single.title, 'Kävely', reason: 'ennen: K\uFFFDvely hiljaa');
    expect(r.repaired, 1);
    expect(r.unreadable.keys, ['2026-11-05.md']);
    expect(r.unreadable['2026-11-05.md'], jpg, reason: 'alkuperäinen sisältö liitteeksi');
    expect(r.unreadableWhy, {'2026-11-05.md': 'Ei tekstitiedosto: vaurioitunut tai väärä tiedosto'});
  });

  test('.md-tuonti: sama tunnistus kuin palautuksessa', () {
    final r = readMdBytes({
      '2026-11-04.md': _utf16le(_md),
      '2026-11-05.md': [0, 1, 2, 3],
      '2026-11-06.md': <int>[],
    });
    expect(r.workouts.single.title, 'Kävely');
    expect(r.repaired, 1);
    expect(r.unreadableWhy, {
      '2026-11-05.md': 'Ei tekstitiedosto: vaurioitunut tai väärä tiedosto',
      '2026-11-06.md': 'Tiedosto on tyhjä',
    });
  });

  test('Mahdoton päivä etusivulla: päivä tiedoston nimestä, ei siirry toiseen päivään', () {
    Workout parse(String date) => parseWorkout(
      '---\ndate: $date\ntitle: Salitreeni\n---\n\n## Liikkeet\n- Takakyykky: 100 kg × 5\n',
      fallbackDate: DateTime(2026, 10, 26),
    );
    // Ennen 2026-13-40 → 2027-02-09 (tulevaisuuteen) ja 2026-02-30 → 2026-03-02.
    expect(parse('2026-13-40').date, DateTime(2026, 10, 26));
    expect(parse('2026-02-30').date, DateTime(2026, 10, 26));
    expect(parse('2026-10-25').date, DateTime(2026, 10, 25));
    expect(parse('2026-10-25T07:30').date, DateTime(2026, 10, 25));
    expect(() => parseWorkout('---\ndate: 2026-13-40\n---\n'), throwsFormatException);
  });
}
