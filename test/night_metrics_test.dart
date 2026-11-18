import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/home_layout.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart';

// Yöarvot-kortti (17.11.): tiedostomuoto, omaan tasoon vertailu tutkimusten rajoilla ja kortti. Keksityt arvot.
void main() {
  final today = DateTime(2026, 11, 18);

  Map<DateTime, NightMetrics> series(NightMetrics Function(int i) f, {int n = 40}) => {
    for (var i = 0; i < n; i++) addDays(today, -i): f(i),
  };

  test('uni.md:n Yöarvot-osio tiedostoon ja takaisin', () {
    final m = {
      today: const NightMetrics(hrv: 52, spo2: 96.4, spo2Min: 91, rr: 14.2, temp: 0.31, rest: 51),
      addDays(today, -1): const NightMetrics(hrv: 47, temp: -0.12),
    };
    final md = metricsToMarkdown(m);
    expect(md, contains('- 2026-11-18: hrv 52, spo2 96,4 (alin 91,0), hengitys 14,2, lämpö +0,31, leposyke 51'));
    expect(md, contains('- 2026-11-17: hrv 47, lämpö -0,12'));
    expect(parseMetrics(md), m);
    // Unirivit (kellonajat) eivät sekoitu yöarvoiksi.
    expect(parseMetrics('- 2026-11-18: 23:10–07:00, 7 h 30 min, syke 50 (Oura)'), isEmpty);
  });

  test('rajat: alle 14 yötä ei vertailua; sairastumisen merkit', () {
    final calm = series((i) => NightMetrics(hrv: 50.0 + i % 3, rest: 50.0 + i % 2, rr: 14.0, temp: 0.0, spo2: 96));
    for (final k in nightMetricKeys) {
      expect(metricFlag(k, metricStat(calm, k, today)!), 0, reason: k);
    }
    final short = series((i) => const NightMetrics(rest: 50), n: 10);
    expect(metricFlag('rest', metricStat(short, 'rest', today)!), -1);
    // Kolme viimeistä yötä: leposyke +6, hengitys +3,5, lämpö +0,7, HRV alas, happi 2,5 alas.
    final ill = series(
      (i) => i < 3
          ? const NightMetrics(hrv: 30, rest: 56, rr: 17.5, temp: 0.7, spo2: 93.5)
          : NightMetrics(hrv: 50.0 + i % 3, rest: 50.0 + i % 2, rr: 14.0, temp: 0.0, spo2: 96),
    );
    for (final k in nightMetricKeys) {
      expect(metricFlag(k, metricStat(ill, k, today)!), 1, reason: k);
    }
    expect(metricUsual('hrv', metricStat(ill, 'hrv', today)!), closeTo(51, 1));
  });

  test('yötesti 18.11.: hengitys "kaksi yötä peräkkäin" vaatii peräkkäiset yöt', () {
    NightMetrics rr(double v) => NightMetrics(rr: v);
    final base = {for (var i = 3; i < 30; i++) addDays(today, -i): rr(14)};
    // +2,5 tänään ja toissa yönä, eilinen yö puuttuu: ei peräkkäisiä.
    final gap = {...base, today: rr(16.5), addDays(today, -2): rr(16.5)};
    expect(metricFlag('rr', metricStat(gap, 'rr', today)!), 0);
    final both = {...base, today: rr(16.5), addDays(today, -1): rr(16.5)};
    expect(metricFlag('rr', metricStat(both, 'rr', today)!), 1);
  });

  test('yötesti 18.11.: HRV ei liputa tasaisella vertailujaksolla pientä laskua eikä yhdestä yöstä', () {
    NightMetrics h(double v) => NightMetrics(hrv: v);
    final flat = {for (var i = 7; i < 40; i++) addDays(today, -i): h(50)};
    // 7 viimeistä yötä 49 ms: ln-ero ~0,02 < 0,5 × 0,05.
    final small = {...flat, for (var i = 0; i < 7; i++) addDays(today, -i): h(49)};
    expect(metricFlag('hrv', metricStat(small, 'hrv', today)!), 0);
    // Vain yksi yö viimeiseltä viikolta, vaikka iso lasku: ei liputa.
    final one = {...flat, today: h(30)};
    expect(metricStat(one, 'hrv', today)!.recentN, 1);
    expect(metricFlag('hrv', metricStat(one, 'hrv', today)!), 0);
    // Kolme yötä selvästi alempana: liputtaa.
    final three = {...flat, for (var i = 0; i < 3; i++) addDays(today, -i): h(35)};
    expect(metricFlag('hrv', metricStat(three, 'hrv', today)!), 1);
  });

  test('HRV-vihje vasta toisena päivänä peräkkäin (18.11.)', () {
    NightMetrics h(double v) => NightMetrics(hrv: v);
    final base = {for (var i = 9; i < 70; i++) addDays(today, -i): h(i.isEven ? 40 : 60)};
    // Kahdeksan matalaa yötä: 7 yön keskiarvo alle vaihteluvälin sekä tänään että eilen.
    final long = {...base, for (var i = 0; i < 9; i++) addDays(today, -i): h(36)};
    expect(hrvLowSustained(long, today), isTrue);
    // Vain kaksi viimeistä yötä matalia: tänään alle vaihteluvälin, eilen vielä ei.
    final fresh = {
      ...base,
      for (var i = 2; i < 9; i++) addDays(today, -i): h(50),
      for (var i = 0; i < 2; i++) addDays(today, -i): h(30),
    };
    final st = metricStat(fresh, 'hrv', today)!;
    expect(metricFlag('hrv', st), 1);
    expect(hrvLowSustained(fresh, today), isFalse, reason: 'yksi päivä ei vielä riitä');
  });

  testWidgets('kortti: ruudut valituista arvoista ja yhteinen vihje', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = dateOnly(DateTime.now());
    sleepData.metrics
      ..clear()
      ..addAll({
        for (var i = 0; i < 30; i++)
          addDays(now, -i): i < 3
              ? const NightMetrics(hrv: 30, rest: 57, rr: 18, temp: 0.8, spo2: 96)
              : const NightMetrics(hrv: 50, rest: 50, rr: 14, temp: 0, spo2: 96),
      });
    settings.nightTiles = {'hrv', 'rest', 'temp'};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: NightMetricsCard())),
      ),
    );
    expect(find.byKey(const ValueKey('nightTile_hrv')), findsOneWidget);
    expect(find.byKey(const ValueKey('nightTile_rr')), findsNothing, reason: 'ei valittu');
    expect(find.textContaining('Useampi yöarvo poikkeaa'), findsOneWidget);
    expect(find.text('+0,8 °C'), findsOneWidget);
    expect(tester.takeException(), isNull);
    settings.nightTiles = {'hrv', 'rest', 'rr', 'spo2', 'temp'};
    sleepData.metrics.clear();
  });

  testWidgets('saame: pitkät otsikot tavutetaan sanaliitoksesta ja arvot ovat samalla korkeudella (18.11.)', (
    tester,
  ) async {
    debugSetCatalog('se', parsePo(File('assets/l10n/se.po').readAsStringSync()));
    addTearDown(() => debugSetCatalog('fi', const {}));
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(411 * 2.6, 2000);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final now = dateOnly(DateTime.now());
    sleepData.metrics
      ..clear()
      ..addAll({
        for (var i = 0; i < 30; i++) addDays(now, -i): const NightMetrics(hrv: 50, rest: 50, rr: 14, temp: 0, spo2: 96),
      });
    settings.nightTiles = {'hrv', 'rest', 'rr', 'spo2', 'temp'};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: EdgeInsets.all(16), child: NightMetricsCard()),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Vuoiŋŋastan-\npulsa'), findsOneWidget);
    expect(find.text('HRV'), findsOneWidget);
    // Ensimmäisen rivin kolmen ruudun arvot samalla korkeudella.
    double valueY(String k) => tester
        .getTopLeft(find.descendant(of: find.byKey(ValueKey('nightTile_$k')), matching: find.byType(FittedBox)))
        .dy;
    expect(valueY('rest'), valueY('hrv'));
    expect(valueY('rr'), valueY('hrv'));
    sleepData.metrics.clear();
  });

  testWidgets('yöarvot Palautuminen-kortissa (18.11.): ei omaa korttia, ei leposyke-ruutua; vanha asetus siirtyy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final now = dateOnly(DateTime.now());
    sleepData.metrics
      ..clear()
      ..addAll({for (var i = 0; i < 30; i++) addDays(now, -i): const NightMetrics(hrv: 50, rest: 50, rr: 14)});
    settings.homeHidden = {'sleep'}; // Palautuminen ja Yöarvot päällä
    settings.nightTiles = {'hrv', 'rest', 'rr', 'spo2', 'temp'};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: NightHrCard())),
      ),
    );
    expect(find.text('Palautuminen'), findsOneWidget);
    expect(find.byKey(const ValueKey('nightTile_hrv')), findsOneWidget);
    expect(find.byKey(const ValueKey('nightTile_rest')), findsNothing, reason: 'yön alin syke näkyy jo');
    expect(find.text('Yöarvot'), findsNothing, reason: 'ei omaa otsikkoa');
    expect(tester.takeException(), isNull);
    // Vanha tiedosto: Yöarvot päällä omana korttinaan, Palautuminen pois -> Palautuminen päälle.
    settings.applyMarkdown('---\nhome_cards: next, -recovery, night\n---\n');
    expect(settings.homeCardOn('recovery'), isTrue);
    expect(settings.homeCardOn('night'), isTrue);
    settings.homeHidden = {...homeCardsOffByDefault};
    sleepData.metrics.clear();
  });

  test('haku: yöarvot unen ajalta tai klo 21–10 ja tallennus uni.md:hen', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('gievra-night');
    settings
      ..folder = dir.path
      ..homeHidden = {'sleep'}; // Yöarvot päällä, Uni pois
    await sleepData.load();
    final t0 = dateOnly(DateTime.now());
    Map<DateTime, (DateTime, DateTime)>? asked;
    sleepData.debugMetrics = (w) async {
      asked = w;
      return {t0: const NightMetrics(hrv: 44, rest: 52)};
    };
    await sleepData.refresh(force: true);
    expect(asked![t0], (DateTime(t0.year, t0.month, t0.day - 1, 21), DateTime(t0.year, t0.month, t0.day, 10)));
    expect(File('${dir.path}/$sleepFileName').readAsStringSync(), contains('${isoDate(t0)}: hrv 44, leposyke 52'));
    sleepData.debugMetrics = null;
    sleepData.metrics.clear();
    settings
      ..folder = null
      ..homeHidden = {...homeCardsOffByDefault};
    dir.deleteSync(recursive: true);
  });

  test('lämpö: nollan lähellä ei miinusta (18.11.)', () {
    expect(NightMetricsCard.value('temp', -0.04), '0,0 °C');
    expect(NightMetricsCard.value('temp', 0.31), '+0,3 °C');
    expect(NightMetricsCard.value('temp', -0.26), '-0,3 °C');
  });
}
