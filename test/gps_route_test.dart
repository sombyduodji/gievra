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
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/bug_report.dart';
import 'package:treenipaivakirja/ui/record_screen.dart';

// Keksityt reitit ja paikat (ei oikeita lenkkejä).

/// Testin paikannuslähde: paikannukset syötetään käsin, kello on testin hallussa.
class FakeGps implements GpsSource {
  final ctl = StreamController<Map<String, Object?>>.broadcast();
  final saved = <GpsFix>[];
  bool on = false;

  void send(GpsFix f) {
    saved.add(f);
    ctl.add({'t': f.time.millisecondsSinceEpoch, 'lat': f.lat, 'lon': f.lon, 'acc': f.accuracy});
  }

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
  Future<List<GpsFix>> savedFixes() async => List.of(saved);
  @override
  Future<void> clearSaved() async => saved.clear();
  @override
  Future<void> openSettings() async {}
}

const lat0 = 62.0, lon0 = 25.0;

/// Piste [m] metriä itään origosta.
GpsFix east(DateTime t, double m, {double acc = 5}) =>
    GpsFix(t, lat0, lon0 + m / (111320 * 0.4694715627858908), acc); // cos(62°)

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gievra-gps');
    GpsRecorder.stateDirOverride = tmp;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    settings.folder = null;
    GpsRecorder.stateDirOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('GPX edestakaisin: osuudet, ajat ja koordinaatit säilyvät', () {
    final t = DateTime.utc(2026, 1, 1, 12);
    final segs = [
      [TrackPoint(t, 62.0, 25.0), TrackPoint(t.add(const Duration(seconds: 5)), 62.0001, 25.0002)],
      [TrackPoint(t.add(const Duration(minutes: 2)), 62.001, 25.001)],
    ];
    final gpx = routeToGpx(segs, name: 'Juoksu <testi>', type: 'Juoksu');
    expect(gpx, contains('<name>Juoksu &lt;testi&gt;</name>'));
    final back = parseGpx(gpx);
    expect(back.length, 2);
    expect(back[0].length, 2);
    expect(back[0][1].lat, closeTo(62.0001, 1e-9));
    expect(back[0][1].time, t.add(const Duration(seconds: 5)));
    expect(routeLength(back), greaterThan(10));
  });

  test('Muiden ohjelmien GPX: korkeudet, heittomerkit, puuttuva aika', () {
    const gpx = '''<?xml version="1.0"?><gpx><trk><trkseg>
      <trkpt lat='62.0' lon='25.0'><ele>120</ele><time>2026-01-01T12:00:00Z</time></trkpt>
      <trkpt lat="62.0001" lon="25.0001"><ele>121</ele></trkpt>
      <trkpt lat="999" lon="25.0"><time>2026-01-01T12:00:09Z</time></trkpt>
      <trkpt lat="62.0002" lon="25.0002"><time>2026-01-01T12:00:10Z</time></trkpt>
    </trkseg></trk></gpx>''';
    final segs = parseGpx(gpx);
    expect(segs.single.length, 3); // rikkinäinen piste ohitettu
    expect(segs.single[1].time, DateTime.utc(2026, 1, 1, 12)); // ei aikaa -> edellisen aika
  });

  test('.md: reittitiedoston nimi edestakaisin, polut hylätään', () {
    final w = Workout(date: DateTime(2026, 11, 8), title: 'Juoksu', activity: 'Juoksu', session: 2)
      ..route = '2026-11-08-2.gpx';
    final md = workoutToMarkdown(w);
    expect(md, contains('route: 2026-11-08-2.gpx'));
    expect(parseWorkout(md).route, '2026-11-08-2.gpx');
    final bad = md.replaceFirst('route: 2026-11-08-2.gpx', 'route: ../../salaisuus.gpx');
    expect(parseWorkout(bad).route, isNull);
    expect(routePath(DateTime(2026, 11, 8), 2), '2026/2026-11-08-2.gpx');
  });

  test('Tallennus kirjoittaa .gpx:n treenin viereen, poisto poistaa sen, varmuuskopio kuljettaa sen', () async {
    settings.folder = tmp.path;
    store.workouts = [];
    final t = DateTime.utc(2026, 11, 8, 10);
    final gpx = routeToGpx([
      [TrackPoint(t, 62.0, 25.0), TrackPoint(t.add(const Duration(seconds: 30)), 62.0, 25.002)],
    ], name: 'Kävely');
    final w = Workout(date: DateTime(2026, 11, 8), title: 'Kävely', activity: 'Kävely', distanceKm: 0.1)
      ..routeGpx = gpx;
    await store.save(w);
    final gpxFile = File('${tmp.path}/2026/2026-11-08.gpx');
    expect(gpxFile.existsSync(), isTrue);
    expect(File('${tmp.path}/2026/2026-11-08.md').readAsStringSync(), contains('route: 2026-11-08.gpx'));
    await store.reload();
    final saved = store.onDay(DateTime(2026, 11, 8)).single;
    expect(saved.route, '2026-11-08.gpx');
    expect(await store.readRoute(saved), gpx);

    // Varmuuskopio ja palautus tyhjään kansioon.
    final zip = await exportZip();
    final r = readZip(zip);
    expect(r.workouts.single.routeGpx, gpx);
    final other = Directory.systemTemp.createTempSync('gievra-palautus');
    settings.folder = other.path;
    store.workouts = [];
    expect(await store.saveMany(r.workouts), 1);
    expect(File('${other.path}/2026/2026-11-08.gpx').readAsStringSync(), gpx);
    other.deleteSync(recursive: true);

    settings.folder = tmp.path;
    await store.reload();
    await store.delete(DateTime(2026, 11, 8));
    expect(gpxFile.existsSync(), isFalse);
  });

  test('Tallennin: odotus, aloitus, tauko ei kerrytä matkaa eikä aikaa, lopetus', () async {
    var clock = DateTime.utc(2026, 11, 8, 10);
    final gps = FakeGps();
    final rec = GpsRecorder(source: gps, now: () => clock);
    await rec.open('Juoksu', title: 't', text: 'x', channel: 'c');
    expect(rec.state, RecState.searching);
    expect(gps.on, isTrue);

    var m = 0.0;
    Future<void> runFor(int secs, double speed) async {
      for (var i = 0; i < secs; i++) {
        clock = clock.add(const Duration(seconds: 1));
        m += speed;
        gps.send(east(clock, m));
        await Future<void>.delayed(Duration.zero);
      }
    }

    await runFor(5, 0); // signaali löytyy
    expect(rec.goodSignal, isTrue);
    expect(rec.distanceKm, 0);
    await rec.start();
    await runFor(300, 3); // 900 m
    await rec.pause();
    await runFor(120, 3); // tauolla siirrytään 360 m (ei lasketa)
    await rec.resume();
    await runFor(200, 3); // 600 m
    final r = await rec.finish(name: 'Juoksu');
    expect(r, isNotNull);
    expect(r!.seconds, 500);
    expect(r.distanceKm, closeTo(1.5, 0.05));
    expect(r.segments.length, 2);
    expect(parseGpx(r.gpx).length, 2);
    expect(r.gpx, contains('<desc>Gievra: '));
    expect(r.gpx, contains('paikannusta'));
    expect(gps.on, isFalse);
    expect(await GpsRecorder.pendingSport(), isNull);
  });

  test('Kesken jäänyt tallennus palautuu tiedostoista', () async {
    var clock = DateTime.utc(2026, 11, 8, 10);
    final gps = FakeGps();
    final rec = GpsRecorder(source: gps, now: () => clock);
    await rec.open('Kävely', title: 't', text: 'x', channel: 'c');
    await rec.start();
    for (var i = 1; i <= 200; i++) {
      clock = clock.add(const Duration(seconds: 1));
      gps.send(east(clock, i * 1.4));
    }
    rec.dispose(); // sovellus suljettiin; palvelu ja tiedostot jäävät
    expect(await GpsRecorder.pendingSport(), 'Kävely');

    final again = GpsRecorder(source: gps, now: () => clock);
    expect(await again.recover(title: 't', text: 'x', channel: 'c'), isTrue);
    expect(again.state, RecState.recording);
    expect(again.elapsed.inSeconds, 200);
    expect(again.distanceKm, closeTo(0.28, 0.03));
    await again.discard();
    expect(await GpsRecorder.pendingSport(), isNull);
  });

  test('Palautus kahden tauon jälkeen: kumpikaan tauon aikana kuljettu matka ei kerry', () async {
    var clock = DateTime.utc(2026, 11, 8, 10);
    final gps = FakeGps();
    final rec = GpsRecorder(source: gps, now: () => clock);
    await rec.open('Juoksu', title: 't', text: 'x', channel: 'c');
    var m = 0.0;
    Future<void> runFor(int secs, double speed) async {
      for (var i = 0; i < secs; i++) {
        clock = clock.add(const Duration(seconds: 1));
        m += speed;
        gps.send(east(clock, m));
        await Future<void>.delayed(Duration.zero);
      }
    }

    await rec.start();
    await runFor(200, 3); // 600 m
    await rec.pause();
    await runFor(150, 2); // 300 m tauolla
    await rec.resume();
    await runFor(200, 3); // 600 m
    await rec.pause();
    await runFor(150, 2); // 300 m tauolla
    await rec.resume();
    await runFor(100, 3); // 300 m
    final live = rec.distanceKm;
    rec.dispose(); // Android sulki sovelluksen

    final again = GpsRecorder(source: gps, now: () => clock);
    expect(await again.recover(title: 't', text: 'x', channel: 'c'), isTrue);
    expect(again.distanceKm, closeTo(1.5, 0.05));
    expect(again.distanceKm, closeTo(live, 0.02));
    expect(again.filter.segments.where((x) => x.length >= 2).length, 3);
    await again.discard();
  });

  test('Signaali: puhelimen kello väärässä ei estä aloitusta', () async {
    var clock = DateTime.utc(2026, 11, 8, 10);
    final gps = FakeGps();
    final rec = GpsRecorder(source: gps, now: () => clock);
    await rec.open('Juoksu', title: 't', text: 'x', channel: 'c');
    // GPS-aika on 2 min puhelimen kelloa edellä.
    gps.send(east(clock.add(const Duration(minutes: 2)), 0));
    await Future<void>.delayed(Duration.zero);
    expect(rec.goodSignal, isTrue);
    clock = clock.add(const Duration(seconds: 10));
    expect(rec.goodSignal, isFalse);
    await rec.discard();
  });

  testWidgets('Tallennusnäkymä: signaalin haku, aloitus ja tauko', (tester) async {
    var clock = DateTime.utc(2026, 11, 8, 10);
    final gps = FakeGps();
    final rec = GpsRecorder(source: gps, now: () => clock);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(sport: 'Juoksu', recorder: rec),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(find.text('Etsitään GPS-signaalia…'), findsOneWidget);
    expect(find.textContaining('Aloita silti'), findsOneWidget);
    gps.send(east(clock, 0));
    await tester.pump();
    await tester.pump();
    expect(find.text('GPS valmis'), findsOneWidget);
    // Aloita: ensin 5 s laskenta (puhelin taskuun), sitten tallennus alkaa itsestään.
    await tester.tap(find.text('Aloita'));
    await tester.pump();
    expect(find.text('Laita puhelin taskuun'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(rec.state, RecState.searching);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('3'), findsOneWidget);
    // Peruuta palaa signaalinäkymään; uusi yritys ja laskennan loppuun odotus.
    await tester.tap(find.text('Peruuta'));
    await tester.pump();
    expect(find.text('GPS valmis'), findsOneWidget);
    await tester.tap(find.text('Aloita'));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(rec.state, RecState.recording);
    expect(find.text('Tauko'), findsOneWidget);
    await tester.tap(find.text('Tauko'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(rec.state, RecState.paused);
    expect(find.text('Jatka'), findsOneWidget);
    await tester.runAsync(rec.discard);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('GPS-laskennan voi ohittaa: tallennus alkaa heti', (tester) async {
    final clock = DateTime.utc(2026, 11, 8, 10);
    final gps = FakeGps();
    final rec = GpsRecorder(source: gps, now: () => clock);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordScreen(sport: 'Kävely', recorder: rec),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.tap(find.textContaining('Aloita silti'));
    await tester.pump();
    expect(find.byKey(const ValueKey('countdown')), findsOneWidget);
    await tester.tap(find.text('Ohita laskenta'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(rec.state, RecState.recording);
    expect(find.text('Laita puhelin taskuun'), findsNothing);
    await tester.runAsync(rec.discard);
    await tester.pumpWidget(const SizedBox());
  });

  test('Useampi GPS-treeni samana päivänä: omat .gpx-tiedostot, poisto koskee vain omaa reittiä', () async {
    settings.folder = tmp.path;
    store.workouts = [];
    final day = DateTime(2026, 11, 8);
    String gpxAt(double lon) {
      final t = DateTime.utc(2026, 11, 8, 8);
      return routeToGpx([
        [TrackPoint(t, 62.0, lon), TrackPoint(t.add(const Duration(seconds: 60)), 62.0, lon + .003)],
      ], name: 'testi');
    }

    final run = Workout(date: day, title: 'Juoksu', activity: 'Juoksu', session: 1)..routeGpx = gpxAt(25.0);
    final walk = Workout(date: day, title: 'Kävely', activity: 'Kävely', session: 2)..routeGpx = gpxAt(26.0);
    final ride = Workout(date: DateTime(2026, 11, 9), title: 'Pyöräily', activity: 'Pyöräily')..routeGpx = gpxAt(27.0);
    await store.save(run);
    await store.save(walk);
    await store.save(ride);
    expect(File('${tmp.path}/2026/2026-11-08.gpx').existsSync(), isTrue);
    expect(File('${tmp.path}/2026/2026-11-08-2.gpx').existsSync(), isTrue);
    expect(File('${tmp.path}/2026/2026-11-09.gpx').existsSync(), isTrue);
    await store.reload();
    final day1 = store.onDay(day);
    expect([for (final w in day1) w.route], ['2026-11-08.gpx', '2026-11-08-2.gpx']);
    // Jokainen treeni lukee oman reittinsä.
    expect(parseGpx((await store.readRoute(day1[0]))!).first.first.lon, 25.0);
    expect(parseGpx((await store.readRoute(day1[1]))!).first.first.lon, 26.0);
    // Ensimmäisen poisto ei koske toista.
    await store.delete(day, 1);
    expect(File('${tmp.path}/2026/2026-11-08.gpx').existsSync(), isFalse);
    expect(File('${tmp.path}/2026/2026-11-08-2.gpx').existsSync(), isTrue);
    // Varmuuskopio kuljettaa kaikki jäljellä olevat reitit.
    final r = readZip(await exportZip());
    expect({for (final w in r.workouts) w.route}, {'2026-11-08-2.gpx', '2026-11-09.gpx'});
    expect(r.workouts.every((w) => w.routeGpx != null), isTrue);
  });

  test('Vikailmoitus: GPS-reitit liitteinä valittavissa, oletuksena pois ja varoituksen kera', () async {
    settings.folder = tmp.path;
    store.workouts = [];
    final t = DateTime.utc(2026, 11, 8, 8);
    await store.save(
      Workout(date: DateTime(2026, 11, 8), title: 'Juoksu', activity: 'Juoksu')
        ..routeGpx = routeToGpx([
          [TrackPoint(t, 62.0, 25.0), TrackPoint(t.add(const Duration(seconds: 60)), 62.0, 25.003)],
        ], name: 'testi'),
    );
    final a = {for (final x in await defaultReportAttachments()) x.$1: x};
    expect(a['2026-11-08.md']!.$3, isTrue);
    expect(a['2026-11-08.gpx']!.$3, isFalse);
    expect(a['2026-11-08.gpx']!.$4, contains('GPS-reitin'));
  });
}
