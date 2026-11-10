import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/gps_filter.dart';
import 'package:treenipaivakirja/gps_recorder.dart';
import 'package:treenipaivakirja/gpx.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/new_workout.dart';
import 'package:treenipaivakirja/ui/home.dart';

// Muistin ja vakauden rasitustesti (ei kuulu tavalliseen ajoon): GIEVRA_STRESS=1 flutter test test/stress
// Toistaa raskaat toiminnot monta kertaa ja seuraa prosessin muistia (RSS). Kasvu, joka ei tasaannu,
// viittaa vuotoon. Keksityt treenit väliaikaisessa kansiossa.
final _on = Platform.environment['GIEVRA_STRESS'] == '1';
int get _mb => ProcessInfo.currentRss ~/ (1024 * 1024);

/// Ajaa [rounds] kierrosta, kirjaa muistin ja tarkistaa, että loppupuolisko ei kasva alkupuoliskoa enempää.
Future<void> _rounds(String name, int rounds, Future<void> Function(int) body, {int slackMb = 40}) async {
  final rss = <int>[];
  final sw = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    await body(i);
    rss.add(_mb);
  }
  final half = rounds ~/ 2;
  final firstPeak = rss.take(half).reduce((a, b) => a > b ? a : b);
  final lastPeak = rss.skip(half).reduce((a, b) => a > b ? a : b);
  // ignore: avoid_print
  print('STRESS $name: ${rounds}x ${sw.elapsed.inSeconds}s · RSS alku ${rss.first} Mt, huippu '
      '${rss.reduce((a, b) => a > b ? a : b)} Mt, loppu ${rss.last} Mt · puoliskojen huiput $firstPeak → $lastPeak Mt');
  expect(lastPeak - firstPeak, lessThan(slackMb), reason: '$name: muisti kasvaa kierros kierrokselta ($rss)');
}

class _FakeGps implements GpsSource {
  final ctl = StreamController<Map<String, Object?>>.broadcast();
  bool on = false;
  void send(DateTime t, double lat, double lon) =>
      ctl.add({'t': t.millisecondsSinceEpoch, 'lat': lat, 'lon': lon, 'acc': 5.0});
  @override
  Stream<Map<String, Object?>> get events => ctl.stream;
  @override
  Future<bool> enabled() async => true;
  @override
  Future<void> start({required String title, required String text, required String channel}) async => on = true;
  @override
  Future<void> stop() async => on = false;
  @override
  Future<bool> running() async => on;
  @override
  Future<List<GpsFix>> savedFixes() async => const [];
  @override
  Future<void> clearSaved() async {}
  @override
  Future<void> openSettings() async {}
}

Workout _gym(DateTime d, int i) => Workout(date: d, title: 'Koko keho ${'ABC'[i % 3]}')
  ..exercises.addAll([
    ExerciseEntry('Takakyykky', [for (var s = 0; s < 5; s++) SetEntry(100 + (i % 20).toDouble(), 5)]),
    ExerciseEntry('Penkkipunnerrus', [for (var s = 0; s < 5; s++) SetEntry(80, 5)]),
    ExerciseEntry('Kulmasoutu', [for (var s = 0; s < 4; s++) SetEntry(70, 8)]),
    ExerciseEntry('Hauiskääntö tangolla', [for (var s = 0; s < 3; s++) SetEntry(30, 10)]),
  ])
  ..notes = 'Keksitty treeni $i';

void main() {
  late Directory dir;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-stress');
    settings.folder = dir.path;
    store.workouts = [];
    if (!_on) return;
    // 3000 treeniä (noin 8 vuotta lähes päivittäin), kaksi treeniä joka kymmenes päivä.
    final start = DateTime(2018, 1, 1);
    final list = <Workout>[];
    for (var i = 0; i < 3000; i++) {
      final d = start.add(Duration(days: i));
      list.add(_gym(d, i));
    }
    await store.saveMany(list);
  });
  tearDownAll(() {
    settings.folder = null;
    store.workouts = [];
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('Kansion lataus: 3000 treeniä, 15 latausta', () async {
    await _rounds('reload-3000', 15, (_) async {
      await store.reload();
      expect(store.workouts.length, 3000);
    });
  }, skip: !_on, timeout: const Timeout(Duration(minutes: 10)));

  test('Asetusten kirjoitus ja luku 6000 kertaa', () async {
    await _rounds('settings-6000', 60, (_) async {
      for (var k = 0; k < 100; k++) {
        final md = settings.settingsToMarkdown();
        Settings().applyMarkdown(md);
      }
    }, slackMb: 20);
  }, skip: !_on);

  test('Ohjelmien luonti: kaikki tavoitteet, tasot ja päivämäärät 30 kertaa', () async {
    await _rounds('programs', 30, (_) async {
      for (final g in ['voimanosto', 'lihaskasvu', 'rasvanpoltto', 'kunto']) {
        for (final e in ['aloittelija', 'keski', 'kokenut']) {
          for (final d in [2, 3, 4, 5, 6]) {
            final p = generateProgram(goal: g, experience: e, days: d, minutes: 60, injuries: const []);
            programToMarkdown(p);
          }
        }
      }
    }, slackMb: 20);
  }, skip: !_on);

  test('Varmuuskopio edestakaisin 3000 treenillä, 24 kertaa', () async {
    await _rounds('backup-3000', 24, (_) async {
      final zip = await exportZip();
      final r = readZip(zip);
      expect(r.workouts.length, 3000);
    }, slackMb: 80);
  }, skip: !_on, timeout: const Timeout(Duration(minutes: 10)));

  test('GPS: 4 tunnin tallennus (14 400 paikannusta), 3 kertaa', () async {
    await _rounds('gps-4h', 3, (_) async {
      var clock = DateTime.utc(2026, 11, 8, 6);
      final gps = _FakeGps();
      final rec = GpsRecorder(source: gps, now: () => clock);
      await rec.open('Juoksu', title: 't', text: 'x', channel: 'c');
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(seconds: 1));
        gps.send(clock, 62.0, 25.0);
        await Future<void>.delayed(Duration.zero);
      }
      await rec.start();
      for (var i = 0; i < 14400; i++) {
        clock = clock.add(const Duration(seconds: 1));
        gps.send(clock, 62.0 + (i % 600) * 0.00002, 25.0 + i * 0.000025);
        if (i % 50 == 0) await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);
      final r = await rec.finish(name: 'Juoksu');
      expect(r, isNotNull);
      // Tallennin harventaa lähekkäiset pisteet (tässä noin 1,3 m sekunnissa): puolet jää.
      expect(parseGpx(r!.gpx).expand((s) => s).length, greaterThan(5000));
      await gps.ctl.close();
    }, slackMb: 60);
  }, skip: !_on, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('Näkymät: etusivu ja uusi treeni kolmella kielellä 40 kertaa', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    settings.program = generateProgram(goal: 'voimanosto', experience: 'keski', days: 4, minutes: 60, injuries: const []);
    final po = {
      for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
    };
    await tester.runAsync(() async {
      await _rounds('screens-3-lang', 40, (i) async {
        final lang = ['fi', 'en', 'se'][i % 3];
        debugSetCatalog(lang, lang == 'fi' ? const {} : po[lang]!, english: po['en']);
        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(MaterialApp(home: NewWorkoutScreen(date: DateTime(2026, 11, 10))));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(const SizedBox());
      }, slackMb: 60);
    });
    debugSetCatalog('fi', const {});
    settings.program = null;
  }, skip: !_on);
}
