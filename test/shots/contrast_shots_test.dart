import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/theme.dart';
import 'package:treenipaivakirja/gps_recorder.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/program_view.dart';
import 'package:treenipaivakirja/ui/record_screen.dart';
import 'package:treenipaivakirja/ui/workout.dart';
import 'package:treenipaivakirja/ui/picker.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';

import '../gps_route_test.dart' show FakeGps, east;

// Kuvakaappaukset tumman teeman värien vertailuun (ei kuulu tavalliseen ajoon):
// GIEVRA_SHOTS=<kansio> [GIEVRA_THEME=light] flutter test test/shots
// Keksityt treenit. Fontit Flutterin omasta välimuistista, jotta teksti näkyy oikeana.
final _out = Platform.environment['GIEVRA_SHOTS'];
Map<String, String> _en = const {};

Future<void> _font(String family, List<String> files) async {
  final root =
      '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/sdk/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  final l = FontLoader(family);
  for (final f in files) {
    final b = File(f.startsWith('/') ? f : '$root/$f').readAsBytesSync();
    l.addFont(Future.value(b.buffer.asByteData()));
  }
  await l.load();
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 2.0);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

final _base = buildTheme(Platform.environment['GIEVRA_THEME'] == 'light' ? Brightness.light : Brightness.dark);
final _theme = _base.copyWith(textTheme: _base.textTheme.apply(fontFamilyFallback: const ['DejaVu', 'Emoji']));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    if (_out == null) return;
    Directory(_out!).createSync(recursive: true);
    final tmp = Directory.systemTemp.createTempSync('gievra-shots').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp,
    );
    await _font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
    await _font('MaterialIcons', ['MaterialIcons-Regular.otf']);
    // Nuolet ja ⚠ puhelimessa järjestelmän varafontista.
    await _font('DejaVu', ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']);
    await _font('Emoji', ['/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf']);
    _en = parsePo(await rootBundle.loadString('assets/l10n/en.po'));
    debugSetCatalog('en', _en, english: _en);
  });

  Future<void> app(WidgetTester tester, GlobalKey key, Widget home) async {
    tester.view.physicalSize = const Size(1080, 1500);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: _theme, home: home),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Liikkeen valinta: vammarivi ja Peruuta-painike', (tester) async {
    final key = GlobalKey();
    settings.injuries = ['nivus_lahentaja', 'polvi_etu']; // Sumo Deadlift: Vältä; kyykyt: muokkaa
    await app(tester, key, const ExercisePickerScreen());
    await _shot(tester, key, 'picker');
    // Liikunnan poiston vahvistus (activity.dart): Peruuta on tekstipainike kuten ~100 muuta.
    showDialog<void>(
      context: tester.element(find.byType(ExercisePickerScreen)),
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko liikunta?')),
        content: Text(t('Tiedosto {0}.md poistetaan.', ['2026-11-10'])),
        actions: [
          TextButton(onPressed: () {}, child: Text(t('Peruuta'))),
          FilledButton(onPressed: () {}, child: Text(t('Poista'))),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, key, 'dialog');
    settings.injuries = [];
  }, skip: _out == null);

  testWidgets('Tilastot: lasku edelliseen viikkoon', (tester) async {
    final key = GlobalKey();
    final today = dateOnly(DateTime.now());
    Workout gym(DateTime d, double kg) => Workout(date: d, title: 'Koko keho A')
      ..exercises.addAll([
        ExerciseEntry('Takakyykky', [for (var i = 0; i < 5; i++) SetEntry(kg, 5)]),
        ExerciseEntry('Penkkipunnerrus', [for (var i = 0; i < 5; i++) SetEntry(80, 5)]),
      ]);
    store.workouts = [gym(today, 95), for (var i = 7; i < 11; i++) gym(today.subtract(Duration(days: i)), 100)];
    await app(tester, key, const StatsScreen());
    await _shot(tester, key, 'stats');
    store.workouts = [];
  }, skip: _out == null);

  testWidgets('Etusivu suomeksi: viikkokalenteri ja tilastot-painike', (tester) async {
    final key = GlobalKey();
    debugSetCatalog('fi', const {});
    settings.name = 'Ánde'; // keksitty nimi
    store.workouts = [];
    await app(tester, key, const HomeScreen());
    await _shot(tester, key, 'home');
    settings.name = null;
    debugSetCatalog('en', _en, english: _en);
  }, skip: _out == null);

  testWidgets('GPS-tallennus tauolla', (tester) async {
    final key = GlobalKey();
    var clock = DateTime.utc(2026, 11, 8, 10);
    final gps = FakeGps();
    final rec = GpsRecorder(source: gps, now: () => clock);
    await app(tester, key, RecordScreen(sport: 'Juoksu', recorder: rec));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    gps.send(east(clock, 0));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text(t('Aloita')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    clock = clock.add(const Duration(minutes: 12));
    gps.send(east(clock, 2100));
    await tester.pump();
    await tester.tap(find.text(t('Tauko')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await _shot(tester, key, 'record-paused');
    await tester.runAsync(rec.discard);
  }, skip: _out == null);

  testWidgets('Viikon kuorma (sininen toteutunut) ja tallennettu treeni ennätyksellä', (tester) async {
    final key = GlobalKey();
    final p = generateProgram(goal: 'lihaskasvu', experience: 'keski', days: 4, minutes: 60, injuries: const []);
    await app(
      tester,
      key,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [WeeklyLoadCard(program: p, done: const {})],
        ),
      ),
    );
    await _shot(tester, key, 'weekly-load');
    final w = Workout(date: DateTime(2026, 11, 10), title: 'Koko keho A')
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5), SetEntry(105, 5, pr: true)]));
    await app(tester, key, SavedScreen(workout: w));
    await _shot(tester, key, 'saved-pr');
  }, skip: _out == null);
}
