import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/auto_backup.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/ui/bug_report.dart';
import 'package:treenipaivakirja/ui/drawer.dart';
import 'package:treenipaivakirja/ui/maps_screen.dart' show fmtBytes;

// Päivityksen jälkeinen automaattinen varmuuskopio treenikansion backup/-alikansioon: tehdään kerran per versio,
// enintään kolme säilyy, oma varmuuskopio korvaa ne, eikä backup/ kuulu treeneihin (luku, vienti, kansion kopio).
// Keksityt treenit.
const _md = '---\ndate: 2026-11-04\ntitle: Kävely\nactivity: Kävely\nduration: 40 min\n---\n\n# Kävely 2026-11-04\n';

void main() {
  late Directory dir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-auto');
    File('${dir.path}/2026/2026-11-04.md')
      ..createSync(recursive: true)
      ..writeAsStringSync(_md);
    File('${dir.path}/2026/2026-11-05.md').writeAsStringSync(_md.replaceAll('2026-11-04', '2026-11-05'));
    // Joku purki varmuuskopion backup/-kansioon: ei saa tuplata historiaa.
    File('${dir.path}/backup/Treenit/2026/2026-11-04.md')
      ..createSync(recursive: true)
      ..writeAsStringSync(_md);
    settings.folder = dir.path;
    await store.reload();
  });
  tearDown(() async {
    await autoBackup.deleteAll();
    settings.folder = null;
    store.workouts = [];
    dir.deleteSync(recursive: true);
  });

  List<String> backups() => [
    for (final f in Directory('${dir.path}/backup').listSync().whereType<File>())
      if (f.path.endsWith('.zip')) f.uri.pathSegments.last,
  ]..sort();

  test('backup/ ei kuulu treeneihin: luku, vienti ja kansion kopio ohittavat sen', () async {
    expect(store.workouts.length, 2);
    final names = ZipDecoder().decodeBytes(await exportZip()).files.map((f) => f.name).toList();
    expect(names, containsAll(['Treenit/2026/2026-11-04.md', 'Treenit/2026/2026-11-05.md']));
    expect(names.where((n) => n.contains('backup')), isEmpty);
    expect((await Settings.mdFiles(dir)).where((r) => r.startsWith('backup')), isEmpty);
  });

  test('Uusi versio: kopio backup/-kansioon kerran, sisältönä treenit ilman backup/-kansiota', () async {
    await autoBackup.runIfUpdated('0.6', '0.6+100', now: DateTime(2026, 11, 12, 7, 5));
    expect(backups(), ['gievra-automaattinen-2026-11-12-0705-ennen-0.6.zip']);
    expect(autoBackup.running, isFalse);
    expect(autoBackup.error, isNull);
    final zip = ZipDecoder().decodeBytes(File('${dir.path}/backup/${backups().single}').readAsBytesSync());
    expect(zip.files.map((f) => f.name), containsAll(['Treenit/2026/2026-11-04.md', 'Treenit/2026/2026-11-05.md']));
    expect(zip.files.where((f) => f.name.contains('backup')), isEmpty, reason: 'ei sisäkkäisiä kopioita');
    // Sama koontiversio uudelleen: ei uutta kopiota.
    await autoBackup.runIfUpdated('0.6', '0.6+100', now: DateTime(2026, 11, 12, 8, 0));
    expect(backups().length, 1);
    // Kopio ei näy treeneinä.
    await store.reload();
    expect(store.workouts.length, 2);
  });

  test('Enintään kolme automaattista kopiota; oma varmuuskopio poistaa ne', () async {
    for (var i = 1; i <= 5; i++) {
      await autoBackup.runIfUpdated('0.6.$i', '0.6.$i+$i', now: DateTime(2026, 11, 10 + i, 12));
    }
    expect(backups(), [
      'gievra-automaattinen-2026-11-13-1200-ennen-0.6.3.zip',
      'gievra-automaattinen-2026-11-14-1200-ennen-0.6.4.zip',
      'gievra-automaattinen-2026-11-15-1200-ennen-0.6.5.zip',
    ]);
    await autoBackup.deleteAll();
    expect(backups(), isEmpty);
  });

  test('Uusi asennus ilman treenejä: ei kopiota', () async {
    store.workouts = [];
    await autoBackup.runIfUpdated('0.6', '0.6+100');
    expect(Directory('${dir.path}/backup').listSync().whereType<File>().where((f) => f.path.endsWith('.zip')), isEmpty);
  });

  test('Kansiota ei voitu lukea: ei merkitä tehdyksi, kopio seuraavalla käynnistyksellä', () async {
    // Esim. kansion lupa puuttui käynnistyksessä: treenit näyttivät tyhjiltä, ja ennen versio merkittiin
    // varmuuskopioiduksi, joten kopiota ei tehty koskaan.
    store.workouts = [];
    store.error = 'lupa puuttuu';
    await autoBackup.runIfUpdated('0.6', '0.6+100');
    expect(backups(), isEmpty);
    store.error = null;
    await store.reload();
    await autoBackup.runIfUpdated('0.6', '0.6+100');
    expect(backups(), hasLength(1));
  });

  test('Vain lukukelvottomia treenejä: kopio silti tehdään', () async {
    store.workouts = [];
    store.unreadable = {'2026/2026-11-06.md': 'Tiedosto on tyhjä'};
    await autoBackup.runIfUpdated('0.6', '0.6+100');
    expect(backups(), hasLength(1));
    store.unreadable = {};
  });

  test('Ongelmaraportti: tiedostot yhtenä zipinä, kuvakaappaus erikseen', () async {
    final out = Directory('${dir.path}/out')..createSync();
    final shot = File('${dir.path}/kuva.png')..writeAsBytesSync([137, 80, 78, 71]);
    final files = [
      ('2026-11-04.md', '${dir.path}/2026/2026-11-04.md'),
      ('2026-11-05.md', '${dir.path}/2026/2026-11-05.md'),
      ('kuva.png', shot.path),
    ];
    final zipped = await reportAttachments(files, out, zip: true);
    expect(zipped.length, 2);
    expect(zipped.first, endsWith('.zip'));
    expect(zipped.last, endsWith('kuva.png'));
    final names = ZipDecoder().decodeBytes(File(zipped.first).readAsBytesSync()).files.map((f) => f.name);
    expect(names, ['2026-11-04.md', '2026-11-05.md']);
    final plain = await reportAttachments(files, Directory('${dir.path}/out2')..createSync(), zip: false);
    expect(plain.length, 3);
  });

  testWidgets('Ongelmaraportti: zip-valinta näkyy, kun liitteitä on useampi', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BugReportScreen(
          attach: [
            ('2026-11-04.md', '${dir.path}/2026/2026-11-04.md'),
            ('2026-11-05.md', '${dir.path}/2026/2026-11-05.md'),
          ],
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Lähetä tiedostot yhtenä zip-liitteenä'), findsOneWidget);
  });

  test('Lyhyt versio: koontitiedot pois', () {
    expect(AutoBackup.shortVersion('0.5.9.1.20261111.35+muokattu'), '0.5.9.1');
    expect(AutoBackup.shortVersion('0.6.20261120.1'), '0.6');
    expect(AutoBackup.shortVersion('0.6'), '0.6');
    expect(AutoBackup.shortVersion('0.6+12'), '0.6');
  });

  test('Koko: alle megatavun kilotavuina (ei 0 Mt)', () {
    expect(fmtBytes(87612), '88 kt');
    expect(fmtBytes(1500000), '1,5 Mt');
    expect(fmtBytes(144000000), '144 Mt');
    expect(fmtBytes(1930000000), '1,93 Gt');
  });

  test('Kopion nimestä aika ja versio', () {
    expect(AutoBackup.parseName('gievra-automaattinen-2026-11-12-0705-ennen-0.6.zip'), (
      DateTime(2026, 11, 12, 7, 5),
      '0.6',
    ));
    expect(AutoBackup.parseName('gievra-2026-11-12.zip'), isNull, reason: 'oma varmuuskopio ei ole automaattinen');
  });

  Future<void> storagePage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.text('Tallennus'));
    await tester.pumpAndSettle();
    // Kansion luku testin simuloidussa kellossa ei valmistu: lista luetaan uudelleen oikeassa ajassa
    // (dismissError ilmoittaa kuuntelijoille kuten kopion valmistuminen).
    await tester.runAsync(() async {
      autoBackup.dismissError();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('Tallennus: automaattiset kopiot listana, tallenna ja jaa', (tester) async {
    await tester.runAsync(() async {
      await autoBackup.runIfUpdated('0.6', '0.6+1', now: DateTime(2026, 11, 12, 7, 5));
      await autoBackup.runIfUpdated('0.6.1', '0.6.1+2', now: DateTime(2026, 11, 20, 18, 30));
    });
    await storagePage(tester);
    expect(find.text('Automaattiset varmuuskopiot'), findsOneWidget);
    final titles = find.textContaining(' klo ').evaluate().map((e) => (e.widget as Text).data).toList();
    expect(titles, ['20.11.2026 klo 18.30', '12.11.2026 klo 7.05'], reason: 'uusin ensin');
    expect(find.textContaining('ennen 0.6.1 · '), findsOneWidget);
    expect(find.textContaining('ennen 0.6 · '), findsOneWidget);
    expect(find.textContaining(' kt'), findsNWidgets(2), reason: 'pieni kopio ei näy nollana megatavuna');
    expect(find.byTooltip('Tallenna'), findsNWidgets(2));
    expect(find.byTooltip('Jaa'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // Poisto vahvistuksen jälkeen; peruutus ei poista.
    await tester.tap(find.byTooltip('Poista').first);
    await tester.pumpAndSettle();
    expect(find.text('Poistetaanko "20.11.2026 klo 18.30"?'), findsOneWidget);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Poista').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Poista'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      autoBackup.dismissError();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(backups(), ['gievra-automaattinen-2026-11-12-0705-ennen-0.6.zip']);
    expect(find.textContaining(' klo '), findsOneWidget);
  });

  testWidgets('Tallennus: ei vielä kopioita', (tester) async {
    await storagePage(tester);
    expect(find.text('Ei vielä automaattisia varmuuskopioita.'), findsOneWidget);
  });
}
