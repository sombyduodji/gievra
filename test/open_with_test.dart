import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/open_files.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/import_export.dart';

// "Avaa sovelluksella" / "Jaa → Gievra" (15.11.): avattu tiedosto tunnistetaan kuten Tuo tiedosto -painikkeella
// (aiemmin vain ohjelmapohja; FitNotes-varmuuskopio sai "ei ole ohjelmapohja"). Keksityt tiedot.
void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gievra-open');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    settings
      ..name = 'Testi'
      ..introDone = true;
    store.workouts = [];
  });

  Future<void> open(WidgetTester tester, OpenedFile f) async {
    await tester.pumpWidget(MaterialApp(home: ImportExportScreen(opened: f)));
    // Tiedostot ja SQLite oikeassa ajassa, sitten ruudut.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('FitNotes-varmuuskopio: tuonnin esikatselu', (tester) async {
    final path = '${tmp.path}/x.fitnotes';
    final bytes = await tester.runAsync(() async {
      await writeFitnotes(path, [
        Workout(date: DateTime(2026, 3, 2), title: 'Treeni')
          ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 5), SetEntry(80, 5)])),
      ]);
      return File(path).readAsBytes();
    });
    await open(tester, OpenedFile('FitNotes_Backup.fitnotes', bytes!));
    expect(find.text('Tuo: FitNotes'), findsOneWidget);
    expect(find.text('Ei ole Gievran ohjelmapohja.'), findsNothing);
  });

  testWidgets('Ohjelmapohja nimettömänä (jaettu teksti): pohjan dialogi', (tester) async {
    final p = generateProgram(goal: 'voima', experience: 'keski', days: 3, minutes: 60, injuries: const []);
    await open(tester, OpenedFile('', Uint8List.fromList(utf8.encode(programToMarkdown(p)))));
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Tuntematon tiedosto: ilmoitus, ei kaatumista', (tester) async {
    await open(tester, OpenedFile('kuva.bin', Uint8List.fromList(List.generate(4000, (i) => i % 251))));
    expect(find.textContaining('Tiedostoa ei tunnistettu'), findsOneWidget);
  });

  testWidgets('Liian suuri: ilmoitus', (tester) async {
    await open(tester, OpenedFile('iso.zip', Uint8List(0), size: (importMaxFileMb + 1) * 1024 * 1024, tooLarge: true));
    expect(find.textContaining('liian suuri'), findsOneWidget);
  });

  test('kanavan viesti: väliaikainen kopio luetaan ja poistetaan; teksti; roska', () async {
    final f = File('${tmp.path}/file')..writeAsBytesSync([1, 2, 3]);
    final o = await openedFromMessage({'path': f.path, 'name': 'a.zip', 'tooLarge': false});
    expect(o!.name, 'a.zip');
    expect(o.bytes, [1, 2, 3]);
    expect(f.existsSync(), isFalse);
    expect(utf8.decode((await openedFromMessage({'text': 'goal: x'}))!.bytes), 'goal: x');
    expect(await openedFromMessage(null), isNull);
    expect(await openedFromMessage('content://jotain'), isNull);
    expect(await openedFromMessage({'path': '${tmp.path}/puuttuu'}), isNull);
  });

  testWidgets('Uusi avattu tiedosto korvaa edellisen avatun näkymän; Takaisin vie etusivulle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigator,
        home: const Scaffold(body: Text('koti')),
      ),
    );
    final template = programToMarkdown(
      generateProgram(goal: 'voima', experience: 'keski', days: 3, minutes: 60, injuries: const []),
    );
    // Pohja jättää dialogin auki; seuraavat avaukset sulkevat sen ja edellisen näkymän.
    for (var i = 0; i < 3; i++) {
      final junk = {'text': i == 0 ? template : 'roskaa $i'};
      await tester.runAsync(() => showOpened(junk).timeout(const Duration(milliseconds: 300), onTimeout: () {}));
      for (var k = 0; k < 20; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(find.byType(ImportExportScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    appNavigator.currentState!.pop();
    for (var k = 0; k < 20; k++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('koti'), findsOneWidget);
  });
}
