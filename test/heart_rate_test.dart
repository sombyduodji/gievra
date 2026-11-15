import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/heart_rate.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/hr_calc.dart';
import 'package:treenipaivakirja/rest.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/hr_ui.dart';
import 'package:treenipaivakirja/ui/workout.dart';

/// Keksitty sykevyö: testi lähettää tapahtumat itse.
class FakeHr implements HrSource {
  final _c = StreamController<Map<String, Object?>>.broadcast();
  final calls = <String>[];
  bool on = true;
  bool allowed = true;
  void send(Map<String, Object?> e) => _c.add(e);
  void bpm(int v, {bool? contact}) => send({'type': 'hr', 'bpm': v, 'contact': contact, 't': 0});

  @override
  Stream<Map<String, Object?>> get events => _c.stream;
  @override
  Future<bool> supported() async => true;
  @override
  Future<bool> enabled() async => on;
  @override
  Future<void> scan(int seconds) async => calls.add('scan');
  @override
  Future<void> stopScan() async => calls.add('stopScan');
  @override
  Future<void> connect(String address) async {
    calls.add('connect $address');
    send({'type': 'state', 'state': 'connected'});
  }

  @override
  Future<void> disconnect() async => calls.add('disconnect');
  @override
  Future<void> requestEnable() async => calls.add('enable');
  @override
  Future<bool> needsLocation() async => false;
  @override
  Future<bool> permitted() async => allowed;
}

// Sykevyö (Polar H10 ym.): valinta muistetaan tällä puhelimella, treeni kerää sykkeet, keskisyke ja maksimi
// treeniin. Keksityt sykkeet.
void main() {
  late FakeHr fake;
  var clock = DateTime(2026, 11, 13, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    hrDeviceMemory = {};
    debugSetCatalog('fi', const {});
    store.workouts = [];
    fake = FakeHr();
    hr.source = fake;
    hr.error = null;
    await hr.forget();
    fake.calls.clear();
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('Kalorit ja sykealueet (lähteet hr_calc.dart)', () {
    const man = HrProfile(birthYear: 1986, male: true, heightCm: 180, weightKg: 80);
    const woman = HrProfile(birthYear: 1986, male: false, heightCm: 165, weightKg: 62);
    final d = DateTime(2026, 11, 13, 17);

    test('Keytel 2005 käsin laskettua vastaan; alle 90/min lepotaso (Mifflin–St Jeor)', () {
      // Mies 40 v, 80 kg, syke 140: −55,0969 + 0,6309·140 + 0,1988·80 + 0,2017·40 = 57,20 kJ/min = 13,67 kcal/min.
      expect(man.kcalPerMin(140, d), closeTo(57.2016 / 4.184, 0.001));
      // Nainen 40 v, 62 kg, syke 140: −20,4022 + 0,4472·140 − 0,1263·62 + 0,074·40 = 38,35 kJ/min.
      expect(woman.kcalPerMin(140, d), closeTo((-20.4022 + 0.4472 * 140 - 0.1263 * 62 + 0.074 * 40) / 4.184, 0.001));
      // Lepo: (10·80 + 6,25·180 − 5·40 + 5) / 1440 kcal/min.
      expect(man.restKcalPerMin(d), closeTo(1730 / 1440, 0.0001));
      expect(man.kcalPerMin(70, d), man.restKcalPerMin(d), reason: 'alle 90/min: lepotaso');
      expect(man.maxHr(d), 180, reason: 'Tanaka: 208 − 0,7·40');
    });

    test('Juoksu 30 min syke 140: noin 410 kcal; sali 60 min ka 110 (61 %): 5,0 MET noin 360 kcal', () {
      final run = HrSeries(d, 5, List.filled(360, 140));
      expect(man.kcalEndurance(run), closeTo(410, 2));
      final gym = HrSeries(d, 5, List.filled(720, 110));
      expect(man.gymMet(gym), 5.0);
      expect(man.kcalGym(gym, 60), closeTo(5.0 * 1730 / 1440 * 60, 1));
      expect(man.gymMet(HrSeries(d, 5, List.filled(10, 95))), 3.5);
      expect(man.gymMet(HrSeries(d, 5, List.filled(10, 135))), 6.0);
    });

    test('Käyrä: 5 s jaksot, aukot nollina, tiedostomuoto ja alueet', () {
      final t0 = DateTime(2026, 11, 13, 17, 30, 0);
      final s = HrSeries.fromSamples([
        (t0, 100),
        (t0.add(const Duration(seconds: 2)), 110),
        (t0.add(const Duration(seconds: 12)), 150),
        (t0.add(const Duration(seconds: 16)), 170),
      ])!;
      expect(s.values, [105, 0, 150, 170]);
      expect(s.encode(), '5 17:30:00 105 0 150 170');
      final back = HrSeries.decode(s.encode(), DateTime(2026, 11, 13))!;
      expect(back.values, s.values);
      expect(back.start, t0);
      expect(s.coverage(20), closeTo(.75, .001));
      expect(zoneSeconds(s, 180), [5, 0, 0, 5, 5], reason: '105 = 58 %, 150 = 83 %, 170 = 94 %');
    });
  });

  test('Treenitiedosto: käyrä, lähteet; vanhat tiedostot ennallaan; sali ja kestävyys omalla tavallaan', () {
    settings
      ..birthYear = 1986
      ..sex = 'mies'
      ..body = BodyLog(heightCm: 180, weights: {DateTime(2026, 11, 1): 80});
    final d = DateTime(2026, 11, 13);
    final run = Workout(date: d, title: 'Juoksu', activity: 'Juoksu')..seconds = 1800;
    applyHeartRate(run, HrStats(140, 140, 360, HrSeries(DateTime(2026, 11, 13, 17), 5, List.filled(360, 140))));
    expect(run.hrSource, 'sykevyö');
    expect(run.kcalSource, 'syke');
    expect(run.kcal, closeTo(410, 2));
    final md = workoutToMarkdown(run);
    expect(md, contains('hr_source: sykevyö'));
    expect(md, contains('kcal_source: syke'));
    expect(md, contains('hr_series: 5 17:00:00 140 140'));
    final back = parseWorkout(md);
    expect(back.hrSeries!.values.length, 360);
    expect(back.kcalSource, 'syke');
    expect(
      workoutToMarkdown(parseWorkout('---\ndate: 2026-11-13\ntitle: Juoksu\nactivity: Juoksu\nhr_avg: 150\n---\n')),
      isNot(contains('hr_source')),
    );
    // Sali: MET-menetelmä.
    final gym = Workout(date: d, title: 'Treeni')..minutes = 60;
    applyHeartRate(gym, HrStats(110, 130, 720, HrSeries(DateTime(2026, 11, 13, 17), 5, List.filled(720, 110))));
    expect(gym.kcal, closeTo(360, 1));
    // Käsin kirjattu syke ja kalorit pysyvät.
    final manual = Workout(date: d, title: 'Treeni')
      ..minutes = 60
      ..hrAvg = 120
      ..hrSource = 'käsin'
      ..kcal = 500
      ..kcalSource = 'käsin';
    applyHeartRate(manual, HrStats(110, 130, 720, HrSeries(DateTime(2026, 11, 13, 17), 5, List.filled(720, 110))));
    expect((manual.hrAvg, manual.kcal), (120, 500));
    expect(manual.hrSeries, isNotNull, reason: 'käyrä tallentuu silti');
    // Ilman profiilia: syke kyllä, kalorit ei.
    settings.birthYear = null;
    final noProfile = Workout(date: d, title: 'Treeni')..minutes = 60;
    applyHeartRate(noProfile, HrStats(110, 130, 720, HrSeries(DateTime(2026, 11, 13, 17), 5, List.filled(720, 110))));
    expect((noProfile.hrAvg, noProfile.kcal), (110, null));
    settings.sex = null;
  });

  test('Health Connect ei korvaa sykevyön tietoja ilman vahvistusta', () {
    final w = Workout(date: DateTime(2026, 11, 13), title: 'Juoksu', activity: 'Juoksu')
      ..hrAvg = 140
      ..hrMax = 165
      ..hrSource = 'sykevyö'
      ..kcal = 410
      ..kcalSource = 'syke'
      ..hrSeries = HrSeries(DateTime(2026, 11, 13, 17), 5, [138, 142, 140]);
    final c = HealthCandidate(
      session: true,
      id: 'x',
      start: DateTime(2026, 11, 13, 17),
      end: DateTime(2026, 11, 13, 17, 30),
      title: 'Running',
      hrAvg: 150,
      hrMax: 175,
      kcal: 520,
    );
    expect(protectedHr(w, c), isTrue);
    applyCandidate(w, c);
    expect((w.hrAvg, w.kcal, w.hrSource), (140, 410, 'sykevyö'));
    expect(w.hrSeries, isNotNull, reason: 'Pidä nykyiset: vyön käyrä säilyy');
    applyCandidate(w, c, replace: true);
    expect((w.hrAvg, w.hrMax, w.kcal, w.hrSource, w.kcalSource), (150, 175, 520, 'kello', 'kello'));
    expect(w.hrSeries, isNull, reason: 'kellon luvut: vyön käyrä ja alueet eivät enää vastaa niitä');
  });

  test('Valinta muistetaan, istunto yhdistää ja kerää sykkeet; ilman kontaktia ei lasketa', () async {
    final m = HeartRateMonitor(now: () => clock)..source = fake;
    await m.scan();
    expect(fake.calls, contains('scan'));
    fake.send({'type': 'device', 'address': 'AA:BB', 'name': 'Polar H10 1234ABCD', 'rssi': -60});
    await flush();
    expect(m.found.keys, ['AA:BB']);
    hrDeviceMemory = null;
    hrDeviceDirOverride = await Directory.systemTemp.createTemp('sykevyo');
    await m.choose(m.found['AA:BB']!);
    final f = File('${hrDeviceDirOverride!.path}/laite/sykevyo.txt');
    expect(await f.readAsString(), 'AA:BB\nPolar H10 1234ABCD\n');
    expect((await SharedPreferences.getInstance()).getString('hrAddress'), isNull, reason: 'ei varmuuskopioon');
    expect(m.state, HrState.connected);

    await m.begin('gym');
    for (final v in [100, 120, 140]) {
      fake.bpm(v);
    }
    fake.bpm(160, contact: false); // vyö ei tunne ihoa: ei mukaan
    await flush();
    expect(m.bpm, 160, reason: 'näytetään, mutta ei lasketa');
    expect(m.peek('gym')!.max, 140);
    // Tauko (treenistä poistuttu): ei kerää, yhteys poikki.
    await m.pause('gym');
    expect(fake.calls.last, 'disconnect');
    fake.bpm(150);
    await flush();
    await m.begin('gym');
    fake.bpm(130);
    await flush();
    final s = await m.end('gym');
    expect(s!.avg, ((100 + 120 + 140 + 130) / 4).round());
    expect(s.max, 140);
    expect(m.recording, isFalse);
    // Vanha lukema vanhenee 5 s:ssa.
    clock = clock.add(const Duration(seconds: 6));
    expect(m.bpm, isNull);
    // Toisen näkymän tulos kerran (GPS → liikunta).
    await m.begin('gps');
    fake.bpm(150);
    await flush();
    await m.end('gps');
    expect(m.take('gps')!.avg, 150);
    expect(m.take('gps'), isNull);
    await m.forget();
    expect(await f.exists(), isFalse);
    await hrDeviceDirOverride!.delete(recursive: true);
    hrDeviceDirOverride = null;
  });

  test(
    'Vanha tallennus (SharedPreferences, varmuuskopioituva) siirtyy laite/-kansioon ja poistuu asetuksista',
    () async {
      SharedPreferences.setMockInitialValues({'hrAddress': 'CC:DD', 'hrName': 'Garmin HRM'});
      hrDeviceMemory = null;
      hrDeviceDirOverride = await Directory.systemTemp.createTemp('sykevyo');
      addTearDown(() async {
        await hrDeviceDirOverride!.delete(recursive: true);
        hrDeviceDirOverride = null;
      });
      final m = HeartRateMonitor(now: () => clock)..source = fake;
      await m.load();
      expect((m.address, m.name), ('CC:DD', 'Garmin HRM'));
      expect((await SharedPreferences.getInstance()).getString('hrAddress'), isNull);
      final again = HeartRateMonitor(now: () => clock)..source = fake;
      await again.load();
      expect((again.address, again.name), ('CC:DD', 'Garmin HRM'));
      await again.forget();
    },
  );

  test('Kävely, jonka sykettä vain 2 %: kalorit matkasta ja ajasta (ACSM), ei 100 s:n sykkeestä (kaveri 14.11.)', () {
    settings
      ..birthYear = 1978
      ..sex = 'mies'
      ..body = BodyLog(heightCm: 177, weights: {DateTime(2026, 11, 13): 84.4});
    addTearDown(() {
      settings
        ..birthYear = null
        ..sex = null
        ..body = BodyLog();
    });
    // Keksityt, mutta samat luvut: 1:07:46, 6,44 km, syke 100 s alusta.
    final series = HrSeries.decode(
      '5 12:38:56 67 70 75 80 86 87 91 92 93 91 90 90 89 92 93 93 90 86 88 86',
      DateTime(2026, 11, 14),
    )!;
    final w = Workout(date: DateTime(2026, 11, 14), title: 'Kävely', activity: 'Kävely', distanceKm: 6.44)
      ..seconds = 4066
      ..started = DateTime(2026, 11, 14, 12, 38, 55);
    applyHeartRate(w, HrStats(86, 95, 20, series));
    // ACSM: 95 m/min → VO2 13,0 ml/kg/min × 84,4 kg × 5 kcal/l × 67,8 min ≈ 372.
    expect(w.kcalSource, 'nopeus');
    expect(w.kcal, inInclusiveRange(360, 385));
    expect((w.hrAvg, w.hrMax), (86, 95), reason: 'mitattu syke säilyy');
    // Kattava syke (yli puolet): kalorit sykkeestä kuten ennen.
    final full = Workout(date: DateTime(2026, 11, 14), title: 'Kävely', activity: 'Kävely', distanceKm: 0.2)
      ..seconds = 100;
    applyHeartRate(full, HrStats(86, 95, 20, series));
    expect(full.kcalSource, 'syke');
    // Laji ilman matkaa (esim. sulkapallo): sykkeestä ekstrapoloiden kuten ennen.
    final other = Workout(date: DateTime(2026, 11, 14), title: 'Sulkapallo', activity: 'Sulkapallo')..seconds = 4066;
    applyHeartRate(other, HrStats(86, 95, 20, series));
    expect(other.kcalSource, 'syke');
    expect(other.kcal, greaterThan(200));
  });

  test('Puuttuvat lukemat sekunteina (katkon varoitus treenin aikana)', () {
    final s = HrSeries(DateTime(2026, 11, 14, 12), 5, [70, 72, 0, 0, 0, 0, 0, 0, 0, 80, 82]);
    expect(s.missingSec, 35);
    expect(s.readingCount, 4);
    expect(HrSeries(DateTime(2026, 11, 14, 12), 5, [70, 72, 74]).missingSec, 0);
  });

  test('Vanha tallennus: kävelyn kalorit 2 %:n sykkeestä korjataan luettaessa matkasta; muut ennallaan', () {
    settings
      ..birthYear = 1985
      ..sex = 'nainen'
      ..body = BodyLog(heightCm: 168, weights: {DateTime(2026, 11, 1): 66.0});
    addTearDown(() {
      settings
        ..birthYear = null
        ..sex = null
        ..body = BodyLog();
    });
    // Keksitty vanha tiedosto (ennen 0.6.6): 60 min, 5,5 km, syke vain 75 s alusta, kalorit sykkeestä 5.
    Workout old({String source = 'syke', String activity = 'Kävely', String km = '5,5'}) => parseWorkout(
      '---\ndate: 2026-11-10\ntitle: $activity\nactivity: $activity\ndistance: $km km\nstart: 09:00\n'
      'duration: 60 min\ntime: 1:00:00\nkcal: 5\nhr_avg: 85\nhr_max: 92\nhr_source: sykevyö\n'
      'kcal_source: $source\nhr_series: 5 09:00:05 80 82 84 85 86 88 90 92 90 88 86 85 84 83 82\n---\n',
    );
    final w = old();
    expect(repairLowCoverageKcal(w, hrProfile()), isTrue);
    expect(w.kcalSource, 'nopeus');
    // ACSM: 91,7 m/min → VO2 12,7 ml/kg/min × 66 kg × 5 kcal/l × 60 min ≈ 251.
    expect(w.kcal, inInclusiveRange(240, 262));
    expect((w.hrAvg, w.hrMax), (85, 92), reason: 'mitattu syke säilyy');
    expect(repairLowCoverageKcal(w, hrProfile()), isFalse, reason: 'kerran');
    // Ei muuteta: käsin kirjatut, juoksu ilman matkaa, laji ilman askelia, ilman profiilia.
    expect(repairLowCoverageKcal(old(source: 'käsin'), hrProfile()), isFalse);
    expect(repairLowCoverageKcal(old(km: '0'), hrProfile()), isFalse);
    expect(repairLowCoverageKcal(old(activity: 'Pyöräily'), hrProfile()), isFalse);
    expect(repairLowCoverageKcal(old(), null), isFalse);
  });

  testWidgets('Sykekortti: aika alle alueiden näkyy omana rivinään, jolloin rivit summautuvat mitattuun', (
    tester,
  ) async {
    settings
      ..birthYear = 1985
      ..sex = 'nainen'
      ..body = BodyLog(heightCm: 168, weights: {DateTime(2026, 11, 1): 66.0});
    addTearDown(() {
      settings
        ..birthYear = null
        ..sex = null
        ..body = BodyLog();
    });
    // Keksitty: maksimi 208 − 0,7 × 41 = 179, raja 50 % = 89,5. 6 jaksoa (30 s) alle, 6 jaksoa (30 s) alueella 1.
    final w = Workout(date: DateTime(2026, 11, 10), title: 'Kävely', activity: 'Kävely')
      ..seconds = 60
      ..hrSeries = HrSeries.decode('5 09:00:00 70 72 75 78 80 85 95 96 97 98 99 100', DateTime(2026, 11, 10));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: HrDetails(w))),
      ),
    );
    expect(find.text('Alle alueiden'), findsOneWidget);
    expect(find.text('0:30'), findsNWidgets(2), reason: 'alle alueiden 0:30 ja alue 1 0:30');
    // Kaikki alueella: ei riviä.
    w.hrSeries = HrSeries.decode('5 09:00:00 95 96 97 98', DateTime(2026, 11, 10));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: HrDetails(w))),
      ),
    );
    expect(find.text('Alle alueiden'), findsNothing);
  });

  testWidgets(
    'Kellon käyrä (Health Connect): lähde kellosta, ei vyön katkovaroitusta; alueet pelkällä syntymävuodella',
    (tester) async {
      addTearDown(() => settings.birthYear = null);
      // Keksitty: Health Sync 5 s, harva alku (vain osa ajasta), ei profiilia.
      final w = Workout(date: DateTime(2026, 11, 12), title: 'Treeni')
        ..minutes = 72
        ..hrSource = 'kello'
        ..healthSource = 'Health Sync'
        ..hrAvg = 115
        ..hrMax = 138
        ..hrSeries = HrSeries.decode('5 17:46:00 110 112 115 118 120 138', DateTime(2026, 11, 12));
      Future<void> pump() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: HrDetails(w))),
        ),
      );
      await pump();
      expect(find.text('Health Connect · Health Sync'), findsOneWidget);
      expect(find.textContaining('Sykevyö'), findsNothing);
      expect(find.textContaining('Syke katkesi'), findsNothing, reason: 'vyön varoitus ei koske kelloa');
      expect(find.textContaining('Sykealueisiin tarvitaan syntymävuosi'), findsOneWidget);
      expect(find.textContaining('Kaloreihin'), findsNothing, reason: 'kalorit tulevat kellosta');
      settings.birthYear = 1985;
      await pump();
      expect(find.textContaining('Sykealueisiin tarvitaan'), findsNothing);
      expect(find.textContaining('arvio iästä'), findsOneWidget);
    },
  );

  testWidgets('Sykekortti: alueiden ajat eivät katkea fontilla 2,0 ("15:0/0", yötesti 15.11.)', (tester) async {
    settings
      ..birthYear = 1985
      ..sex = 'nainen'
      ..body = BodyLog(heightCm: 168, weights: {DateTime(2026, 11, 1): 66.0});
    addTearDown(() {
      settings
        ..birthYear = null
        ..sex = null
        ..body = BodyLog();
    });
    // 15 min alle alueiden (80), 5 min alueella 1 (100): "15:00" ja "5:00".
    final vals = [for (var i = 0; i < 180; i++) 80, for (var i = 0; i < 60; i++) 100].join(' ');
    final w = Workout(date: DateTime(2026, 11, 10), title: 'Kävely', activity: 'Kävely')
      ..seconds = 1200
      ..hrSeries = HrSeries.decode('5 09:00:00 $vals', DateTime(2026, 11, 10));
    tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final origOnError = FlutterError.onError;
    final errors = <String>[];
    // Testin oletusfontti (Ahem) on leveä: ylivuodot eivät kerro oikeasta laitteesta, joten ne vain kerätään.
    FlutterError.onError = (d) => errors.add(d.toString());
    addTearDown(() => FlutterError.onError = origOnError);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 2400), textScaler: TextScaler.linear(2.0)),
          child: Scaffold(body: SingleChildScrollView(child: HrDetails(w))),
        ),
      ),
    );
    for (final txt in ['15:00', '5:00']) {
      final f = find.text(txt);
      expect(f, findsOneWidget);
      // Yksi rivi: korkeus alle puolitoista riviä (12 pt × 2,0 × ~1,3).
      expect(tester.getSize(f).height, lessThan(24 * 1.6), reason: '$txt rivittyi');
    }
  });

  test('Suunta, katkennut yhteys, palautumisraja ja kalorien korjaus', () async {
    final m = HeartRateMonitor(now: () => clock)..source = fake;
    clock = DateTime(2026, 11, 13, 10);
    await m.choose(const HrDevice('AA:BB', 'Polar H10', -50));
    await m.begin('gym');
    fake.bpm(160);
    await flush();
    clock = clock.add(const Duration(seconds: 60));
    fake.bpm(126);
    await flush();
    expect(m.trend, -34);
    fake.send({'type': 'state', 'state': 'connecting'});
    await flush();
    expect(m.lost, isTrue, reason: 'yhdistetty vyö katosi');
    fake.bpm(70); // alle 25 lyönnin muutos: piikkisuodatin ei pidätä
    await flush();
    expect(m.lost, isFalse);
    settings
      ..birthYear = 1986
      ..sex = 'mies'
      ..body = BodyLog(heightCm: 180, weights: {DateTime(2026, 11, 1): 80});
    expect(m.recoveryBpm(DateTime(2026, 11, 13)), 108, reason: '60 % × (208 − 0,7·40)');
    settings.hrRecoveryPct = 65;
    expect(m.recoveryBpm(DateTime(2026, 11, 13)), 117);
    // Kalorien korjaus ±10 %.
    final run = HrSeries(DateTime(2026, 11, 13, 17), 5, List.filled(360, 140));
    final base = hrProfile()!.kcalEndurance(run);
    settings.kcalAdjustPct = 10;
    expect(hrProfile()!.kcalEndurance(run), closeTo(base * 1.1, 1));
    final md = settings.settingsToMarkdown();
    expect(md, contains('kcal_adjust: 10'));
    expect(md, contains('hr_recovery: 65'));
    settings
      ..kcalAdjustPct = 0
      ..hrRecoveryPct = 60
      ..birthYear = null
      ..sex = null;
    await m.end('gym');
  });

  test('Piikkisuodatin: yksittäinen hyppy hylätään, pysyvä muutos hyväksytään', () async {
    var t0 = DateTime(2026, 11, 13, 10);
    final m = HeartRateMonitor(now: () => t0)..source = fake;
    await m.choose(const HrDevice('AA:BB', 'Polar H10', -50));
    await m.begin('run');
    Future<void> at(int sec, int v) async {
      t0 = DateTime(2026, 11, 13, 10).add(Duration(seconds: sec));
      fake.bpm(v);
      await flush();
    }

    await at(0, 140);
    await at(1, 141);
    await at(2, 210); // piikki
    await at(3, 142);
    expect(m.bpm, 142);
    expect(m.peek('run')!.max, 142, reason: '210 ei mukana');
    // Pysyvä nousu (spurtti): taso pysyy 3 s → hyväksytään.
    for (var i = 4; i <= 8; i++) {
      await at(i, 175);
    }
    expect(m.bpm, 175);
    expect(m.peek('run')!.max, 175);
    await at(9, 250); // mahdoton
    expect(m.bpm, 175);
    await m.end('run');
  });

  test('Oma maksimisyke: alueet, palautumisraja ja tiedosto', () {
    settings
      ..birthYear = 1986
      ..sex = 'mies'
      ..body = BodyLog(heightCm: 180, weights: {DateTime(2026, 11, 1): 80})
      ..maxHr = 192;
    final d = DateTime(2026, 11, 13);
    expect(hrProfile()!.maxHr(d), 192);
    expect(hrProfile()!.maxHrMeasured, isTrue);
    expect(zoneOf(173, 192), 4, reason: '173 / 192 = 90 %');
    expect(settings.settingsToMarkdown(), contains('max_hr: 192'));
    settings.maxHr = null;
    expect(hrProfile()!.maxHr(d), 180);
    settings
      ..birthYear = null
      ..sex = null;
  });

  test('Ilman valittua vyötä istunto ei yhdistä; Bluetooth pois kysyy päälle', () async {
    final m = HeartRateMonitor()..source = fake;
    await m.begin('gym');
    expect(fake.calls, isEmpty);
    expect(await m.end('gym'), isNull);
    fake.on = false;
    expect(await m.scan(), isFalse);
    expect(m.error, 'off');
    expect(fake.calls, contains('enable'));
  });

  testWidgets('Kävelymatto: sykevyöllä kävelty saa laitteen askeleet ja matkan, syke pysyy', (tester) async {
    final w = Workout(date: DateTime(2026, 11, 13), title: 'Kävely', activity: 'Kävely')
      ..started = DateTime(2026, 11, 13, 17)
      ..seconds = 2400
      ..minutes = 40
      ..hrAvg = 118
      ..hrMax = 131
      ..hrSource = 'sykevyö'
      ..kcal = 210
      ..kcalSource = 'syke';
    expect(PadMatch.wanted(w), isTrue);
    var calls = 0;
    var applied = false;
    Future<List<HealthCandidate>> fetch(DateTime a, DateTime b) async {
      calls++;
      return calls == 1
          ? []
          : [
              HealthCandidate(
                session: true,
                start: DateTime(2026, 11, 13, 17, 1),
                end: DateTime(2026, 11, 13, 17, 41),
                app: 'Kävelymatto',
                hrAvg: 99,
                kcal: 150,
                steps: 4100,
                meters: 3200,
              ),
            ];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PadMatch(w: w, fetch: fetch, onApplied: () async => applied = true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ei vielä löytynyt'), findsOneWidget);
    await tester.tap(find.text('Hae uudelleen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('askelta'), findsOneWidget);
    expect(find.textContaining('3,2 km'), findsOneWidget);
    await tester.tap(find.text('Lisää askeleet ja matka'));
    await tester.pumpAndSettle();
    expect(applied, isTrue);
    expect((w.steps, w.distanceKm, w.hrAvg, w.kcal), (4100, 3.2, 118, 210));
    expect(find.byKey(const ValueKey('padMatch')), findsNothing);
  });

  testWidgets('Sykevyö-sivu: haku, valinta, syke ja unohda', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HrScreen()));
    await tester.tap(find.text('Etsi sykevyö'));
    await tester.pump();
    expect(find.text('Lopeta haku'), findsOneWidget);
    fake.send({'type': 'device', 'address': 'AA:BB', 'name': 'Polar H10 1234ABCD', 'rssi': -60});
    await tester.pump();
    await tester.tap(find.text('Polar H10 1234ABCD'));
    await tester.pumpAndSettle();
    // Käyttöönotto kysyy kalorilaskennan tiedot (ei vielä annettu).
    expect(find.byKey(const ValueKey('birthYear')), findsOneWidget);
    await tester.tap(find.text('Ei nyt'));
    await tester.pumpAndSettle();
    fake.bpm(72);
    fake.send({'type': 'battery', 'percent': 87});
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('hrNow')), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
    expect(find.textContaining('akku 87 %'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Unohda vyö'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(find.text('Unohda vyö'));
    await tester.pump();
    expect(hr.address, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('Oma lupatarkistus: kielletty lupa estää haun ja yhteyden, vaikka lupakirjasto väittäisi muuta', () async {
    fake.allowed = false;
    expect(await hr.scan(), isFalse);
    expect(hr.error, 'permission');
    expect(fake.calls, isNot(contains('scan')));
    await hr.choose(const HrDevice('AA:BB', 'Polar H10', -50));
    expect(fake.calls.where((c) => c.startsWith('connect')), isEmpty);
    expect(hr.state, HrState.none);
    await hr.forget();
    fake.allowed = true;
    expect(await hr.scan(), isTrue);
    expect(fake.calls, contains('scan'));
    await hr.stopScan();
    hr.error = null;
  });

  testWidgets('Luvan kieltäminen: Android 11:ssä viesti nimeää sijaintiluvan, uudemmissa Bluetooth-luvan', (
    tester,
  ) async {
    addTearDown(() {
      hr.error = null;
      hr.locationPermission = false;
    });
    await tester.pumpWidget(const MaterialApp(home: HrScreen()));
    hr.error = 'permission';
    hr.locationPermission = true;
    hr.notifyListeners();
    await tester.pump();
    expect(find.text('Sijaintilupa tarvitaan sykevyön hakuun (Android 11 ja vanhemmat).'), findsOneWidget);
    expect(find.text('Avaa sovelluksen luvat'), findsOneWidget);
    hr.locationPermission = false;
    hr.notifyListeners();
    await tester.pump();
    expect(find.text('Bluetooth-lupa tarvitaan sykevyön hakuun.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Salitreeni: syke yläpalkissa, keskisyke ja maksimi treeniin lopussa', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await hr.choose(const HrDevice('AA:BB', 'Polar H10', -50));
    settings
      ..birthYear = DateTime.now().year - 40
      ..sex = 'mies'
      ..body = BodyLog(heightCm: 180, weights: {DateTime(2026, 11, 1): 80});
    addTearDown(() {
      settings
        ..birthYear = null
        ..sex = null;
    });
    final w = Workout(date: dateOnly(DateTime.now()), title: 'Treeni')
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)]));
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: w)));
    await tester.pump();
    expect(fake.calls, contains('connect AA:BB'));
    fake.bpm(110);
    fake.bpm(130);
    fake.bpm(150);
    await tester.pump();
    await tester.pump();
    // Sykenauha: iso luku, alue (150 / 180 = 83 % → alue 4) ja kaloriarvio.
    expect(find.descendant(of: find.byKey(const ValueKey('hrStrip')), matching: find.text('150')), findsOneWidget);
    expect(find.textContaining('Alue 4'), findsOneWidget);
    // Kaloriarvio näkyy vasta, kun sitä on kertynyt (alussa 0 kcal piilossa).
    expect(find.byKey(const ValueKey('hrStripKcal')), findsNothing);
    // Lopetus: fiilis ohitetaan, syke treeniin.
    await tester.tap(find.textContaining('Treeni valmis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ohita'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(w.hrAvg, 130);
    expect(w.hrMax, 150);
    await hr.forget();
    await tester.pump(const Duration(seconds: 6)); // sykkeen vanhenemisen ajastin
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tyhjästä salitreenistä poistuminen hylkää sykkeet: uusi avaus ei peri leposykettä', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await hr.choose(const HrDevice('AA:BB', 'Polar H10', -50));
    final today = dateOnly(DateTime.now());
    final key = 'gym:${isoDate(today)}-1';
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutScreen(
          workout: Workout(date: today, title: 'Treeni'),
        ),
      ),
    );
    await tester.pump();
    fake.bpm(55);
    fake.bpm(56);
    await tester.pump();
    expect(hr.peek(key)?.samples, 2);
    // Avattiin vahingossa ja poistuttiin ennen ensimmäistä sarjaa: sykkeet pois.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(hr.peek(key), isNull);
    // Uusi avaus: vain uudet sykkeet.
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutScreen(
          workout: Workout(date: today, title: 'Treeni'),
        ),
      ),
    );
    await tester.pump();
    fake.bpm(70); // alle 25 lyönnin muutos: piikkisuodatin ei pidätä
    await tester.pump();
    expect(hr.peek(key)?.avg, 70);
    expect(hr.peek(key)?.samples, 1);
    await hr.forget();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Salitreenin kesto pyöristetään lopussa: 1:55 → 2 min (ennen katkaistiin 1 minuutiksi)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final w = Workout(date: dateOnly(DateTime.now()), title: 'Treeni')
      ..started = DateTime.now().subtract(const Duration(seconds: 115))
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)]));
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: w)));
    await tester.pump();
    await tester.tap(find.textContaining('Treeni valmis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ohita'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(w.minutes, 2);
    await tester.pumpWidget(const SizedBox());
  });

  group('Palautus sykkeen mukaan (rest_hr)', () {
    late DateTime now;
    final messages = <String>[];
    setUp(() async {
      now = DateTime(2026, 11, 13, 17);
      RestTimer.clock = () => now;
      messages.clear();
      rest.onDone = messages.add;
      settings
        ..birthYear = 1986
        ..sex = 'mies'
        ..hrRecoveryPct = 60
        ..body = BodyLog(heightCm: 180, weights: {DateTime(2026, 11, 1): 80});
      await hr.choose(const HrDevice('AA:BB', 'Polar H10', -50));
      await hr.begin('gym:test');
    });
    tearDown(() async {
      rest.stop();
      rest.onDone = null;
      RestTimer.clock = DateTime.now;
      settings.restByHr = false;
      await hr.end('gym:test');
    });

    test('Asetus pois: tavallinen ajastin', () async {
      settings.restByHr = false;
      fake.bpm(150);
      await flush();
      rest.start(120, 'Takakyykky');
      expect((rest.byHr, rest.total), (false, 120));
    });

    test('Syke laskee rajan alle: palautus päättyy, "palautunut"-tila jää ilmoitukseen', () async {
      settings.restByHr = true;
      fake.bpm(150);
      await flush();
      rest.start(120, 'Takakyykky');
      expect((rest.byHr, rest.total), (true, RestTimer.hrWaitSeconds));
      now = now.add(const Duration(seconds: 10));
      for (final v in [135, 120, 105]) {
        fake.bpm(v); // laskee vähitellen (piikkisuodatin ei pidättele); alle 108, mutta alle 20 s tauosta
        await flush();
      }
      rest.tick();
      expect(rest.running, isTrue);
      now = now.add(const Duration(seconds: 25));
      expect(rest.elapsed, 35);
      fake.bpm(104);
      await flush();
      rest.tick();
      expect(rest.running, isFalse);
      expect(rest.over, isTrue);
      expect(messages.single, contains('Palautunut'));
      rest.start(120, 'Takakyykky'); // seuraava sarja
      expect(rest.over, isFalse);
    });

    test('Ei palaudu 5 minuutissa: kohtelias muistutus', () async {
      settings.restByHr = true;
      fake.bpm(150);
      await flush();
      rest.start(90, 'Kahvakuulaheilautus');
      now = now.add(const Duration(seconds: RestTimer.hrWaitSeconds));
      fake.bpm(130);
      await flush();
      rest.tick();
      expect((rest.running, rest.over), (false, true));
      expect(messages.single, contains('tarkista syke'));
    });

    test('Ilman sykettä (vyötä ei valittu) käytetään palautusaikaa', () async {
      settings.restByHr = true;
      await hr.forget();
      rest.start(90, 'Takakyykky');
      expect((rest.byHr, rest.total), (false, 90));
    });
  });

  group('Vyön akku loppuu kesken treenin (keksityt lukemat)', () {
    late DateTime now;
    setUp(() async {
      now = DateTime(2026, 11, 13, 17);
      RestTimer.clock = () => now;
      rest.onDone = null;
      settings
        ..birthYear = 1986
        ..sex = 'mies'
        ..hrRecoveryPct = 60
        ..body = BodyLog(heightCm: 180, weights: {DateTime(2026, 11, 1): 80});
      await hr.choose(const HrDevice('AA:BB', 'Polar H10', -50));
      await hr.begin('gym:akku');
    });
    tearDown(() async {
      rest.stop();
      RestTimer.clock = DateTime.now;
      settings.restByHr = false;
      await hr.end('gym:akku');
    });

    test('Sykkeen mukainen palautus: syke katoaa → tavallinen palautusaika tauon alusta', () async {
      settings.restByHr = true;
      fake.bpm(150);
      await flush();
      rest.start(120, 'Takakyykky');
      expect(rest.byHr, isTrue);
      // Akku loppui: lukemia ei tule. 10 s: vielä odotetaan.
      now = now.add(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 5, milliseconds: 200)); // hr.bpm vanhenee (5 s)
      expect(hr.bpm, isNull);
      rest.tick();
      expect(rest.byHr, isTrue);
      // Viimeinen lukema nähtiin 10 s kohdalla; 15 s ilman sykettä (25 s): tavallinen 120 s palautus, josta 25 s
      // on jo kulunut.
      now = now.add(const Duration(seconds: 15));
      rest.tick();
      expect(rest.byHr, isFalse);
      expect(rest.total, 120);
      expect(rest.remaining, 95);
    });

    test('Ei tuoretta sykettä tauon alkaessa: tavallinen palautusaika heti', () async {
      settings.restByHr = true;
      rest.start(90, 'Takakyykky'); // vyö valittu, mutta yhtään lukemaa ei ole tullut
      expect((rest.byHr, rest.total), (false, 90));
    });

    test('Yhteys katkeaa: tila "yhdistetään uudelleen", ja vyö palaa itsestään', () async {
      fake.send({'type': 'state', 'state': 'connected'});
      fake.bpm(140);
      await flush();
      fake.send({'type': 'state', 'state': 'connecting'}); // Android huomasi vyön kadonneen
      await flush();
      expect(hr.lost, isTrue);
      expect(hrStatusText(), 'Yhteys katkesi, yhdistetään…');
      fake.bpm(120); // uusi paristo: yhteys palasi
      await flush();
      expect((hr.lost, hr.bpm), (false, 120));
    });

    test('Akku vähissä: varoitus', () async {
      fake.send({'type': 'battery', 'percent': 12});
      await flush();
      expect(hr.batteryLow, isTrue);
      fake.send({'type': 'battery', 'percent': 60});
      await flush();
      expect(hr.batteryLow, isFalse);
    });
  });

  test('Kalorit, kun vyö sammui 10 min kohdalla 60 min lenkillä: puuttuva aika mitatun tason mukaan', () {
    const p = HrProfile(birthYear: 1986, male: true, heightCm: 180, weightKg: 80);
    final s = HrSeries(DateTime(2026, 11, 13, 17), 5, List.filled(120, 140)); // 10 min lukemia
    final measured = p.kcalEndurance(s);
    expect(p.kcalEnduranceFor(s, 600), measured, reason: 'koko treeni mitattu');
    expect(p.kcalEnduranceFor(s, 3600), closeTo(measured * 6, 2), reason: '6 × mitattu');
    expect(p.kcalEnduranceFor(s, null), measured);
    final tiny = HrSeries(DateTime(2026, 11, 13, 17), 5, List.filled(6, 140)); // 30 s: liian vähän arvioon
    expect(p.kcalEnduranceFor(tiny, 3600), p.kcalEndurance(tiny));
  });

  test('Häiriö: vyö katkeaa 8 s ja palaa – tila, käyrä, keskisyke, alueet ja kalorit', () async {
    var t = DateTime(2026, 11, 13, 17);
    final m = HeartRateMonitor(now: () => t)..source = fake;
    await m.choose(const HrDevice('AA:BB', 'Polar H10', -50));
    await m.begin('run');
    Future<void> beat(int bpm, int seconds) async {
      for (var i = 0; i < seconds; i++) {
        fake.bpm(bpm);
        await flush();
        t = t.add(const Duration(seconds: 1));
      }
    }

    fake.send({'type': 'state', 'state': 'connected'});
    await beat(140, 120); // 2 min 140
    // Häiriö: Android ilmoittaa yhteyden katkenneen, 8 s ei lukemia.
    fake.send({'type': 'state', 'state': 'connecting'});
    await flush();
    expect(m.lost, isTrue);
    t = t.add(const Duration(seconds: 8));
    expect(m.bpm, isNull, reason: 'yli 5 s vanha lukema ei ole enää syke');
    // Yhteys palaa itsestään; syke on hieman laskenut (alle 25 hypyn: hyväksytään heti).
    await beat(130, 120);
    expect(m.lost, isFalse);
    expect(m.bpm, 130);
    final s = (await m.end('run'))!;
    final series = s.series!;
    expect(series.values.where((v) => v == 0).length, inInclusiveRange(1, 2), reason: '8 s aukko = 1–2 jaksoa');
    expect(s.avg, 135);
    expect(s.max, 140);
    expect(series.coverage(248), greaterThan(.95));
    const p = HrProfile(birthYear: 1986, male: true, heightCm: 180, weightKg: 80);
    final full = HrSeries(series.start, 5, List.filled(series.values.length, 135));
    expect(p.kcalEnduranceFor(series, 248), closeTo(p.kcalEndurance(full), 3), reason: 'aukko vaikuttaa vain vähän');
    expect(zoneSeconds(series, 180).reduce((a, b) => a + b), series.readingCount * 5, reason: 'aukko ei alue');
  });

  test('Häiriö ja hyppy: 8 s katkon jälkeen yli 25 lyönnin muutos hyväksytään 3 s pysyttyään', () async {
    var t = DateTime(2026, 11, 13, 17);
    final m = HeartRateMonitor(now: () => t)..source = fake;
    await m.choose(const HrDevice('AA:BB', 'Polar H10', -50));
    await m.begin('gym');
    for (var i = 0; i < 10; i++) {
      fake.bpm(150);
      await flush();
      t = t.add(const Duration(seconds: 1));
    }
    t = t.add(const Duration(seconds: 8)); // katko
    fake.bpm(110);
    await flush();
    expect(m.bpm, isNull, reason: 'hyppy pidätetään hetki (voi olla häiriö)');
    for (var i = 0; i < 3; i++) {
      t = t.add(const Duration(seconds: 1));
      fake.bpm(111);
      await flush();
    }
    expect(m.bpm, 111, reason: 'taso pysyi: oikea muutos (palautuminen katkon aikana)');
    await m.end('gym');
  });

  test('Haku ilman vyötä: "ei löytynyt" -tila; uusi haku nollaa sen', () async {
    final m = HeartRateMonitor()..source = fake;
    await m.scan();
    fake.send({'type': 'scanDone'});
    await flush();
    expect((m.scanning, m.scanEmpty), (false, true));
    await m.scan();
    expect(m.scanEmpty, isFalse);
    fake.send({'type': 'device', 'address': 'AA:BB', 'name': 'Polar H10', 'rssi': -60});
    fake.send({'type': 'scanDone'});
    await flush();
    expect(m.scanEmpty, isFalse, reason: 'vyö löytyi');
  });
}
