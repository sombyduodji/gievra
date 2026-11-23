import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/home_layout.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart' show NightHrData;
import 'package:treenipaivakirja/ui/stats_screen.dart';

// Tilastot → Uni ja palautuminen (käyttäjä 23.11.): jakson yöt, univaiheet, palautuminen; vain kun uni tai
// palautuminen on käytössä. Keksityt yöt.
void main() {
  const min = 60 * 1000;
  SleepNight night(DateTime day, int bedH, int bedM, int minutes, {String app = 'Sormus'}) {
    final bed = DateTime(day.year, day.month, day.day - (bedH >= 12 ? 1 : 0), bedH, bedM);
    return SleepNight(
      day,
      bed,
      bed.add(Duration(minutes: minutes + 30)),
      Duration(minutes: minutes),
      app: app,
    );
  }

  group('sleepPeriod', () {
    final d0 = DateTime(2026, 3, 1);
    final all = {
      for (final n in [
        night(d0, 23, 30, 420),
        night(DateTime(2026, 3, 2), 0, 30, 360), // keskiyön jälkeen
        night(DateTime(2026, 3, 3), 23, 0, 480),
        night(DateTime(2026, 3, 4), 23, 0, 450),
        night(DateTime(2026, 2, 27), 22, 0, 300), // ennen jaksoa
      ])
        n.day: n,
    };

    test('keskiarvo, kellonajat keskiyön yli, tavoitteen alitukset, pisin ja lyhin', () {
      final p = sleepPeriod(all, d0, DateTime(2026, 3, 5));
      expect(p.nights.length, 4);
      expect(p.avg, const Duration(minutes: 428)); // (420 + 360 + 480 + 450) / 4 = 427,5
      expect(p.bedMin, 23 * 60 + 30); // 23.30, 0.30, 23.00, 23.00 → 23.30
      expect(p.belowGoal, 1); // 6 h < 7 h
      expect(p.longest!.asleep.inMinutes, 480);
      expect(p.shortest!.asleep.inMinutes, 360);
      expect(p.spread, isNotNull);
      expect(sleepPeriod(all, DateTime(2026, 4, 1), DateTime(2026, 5, 1)).nights, isEmpty);
    });

    test('jakson univaiheet yhdellä haulla, vain yön oma sovellus', () async {
      final ns = sleepPeriod(all, d0, DateTime(2026, 3, 5)).nights;
      final (s, n) = await periodStages(
        ns,
        source: (a, b) async => [
          for (final x in ns.take(2)) ...[
            SleepSession(x.bed, x.wake, app: 'Sormus', stageMs: {4: 200 * min, 5: 60 * min, 6: 90 * min, 1: 30 * min}),
            SleepSession(x.bed, x.wake, app: 'Kello', stageMs: {4: 999 * min}),
          ],
        ],
      );
      expect(n, 2, reason: 'kahdella yöllä vaiheet');
      // Sama yö kahdesti (uudelleensynkronointi): vaiheet vain kerran.
      final (s2, _) = await periodStages(
        ns.take(1).toList(),
        source: (a, b) async => [
          for (var k = 0; k < 2; k++)
            SleepSession(ns.first.bed, ns.first.wake, app: 'Sormus', stageMs: {4: 200 * min, 1: 30 * min}),
        ],
      );
      expect(s2.light, const Duration(minutes: 200));
      expect(s.light, const Duration(minutes: 400));
      expect(s.rem, const Duration(minutes: 180));
    });
  });

  group('välilehti', () {
    final today = dateOnly(DateTime.now());
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      debugSetCatalog('fi', const {});
      store.workouts = [];
    });
    tearDown(() {
      settings.homeHidden = {...homeCardsOffByDefault};
      sleepData.nights.clear();
      sleepData.debugSource = null;
      NightHrData.debugNights = const {};
    });

    testWidgets('pelkkä treenaaja ei näe välilehteä', (tester) async {
      settings.homeHidden = {...homeCardsOffByDefault};
      await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Uni ja palautuminen'), findsNothing);
    });

    testWidgets('uni päällä: yhteenveto, pylväät, keskimääräiset vaiheet, yön napautus, palautuminen', (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      settings.homeHidden = {'night'}; // Uni ja Palautuminen päällä
      for (var i = 0; i < 10; i++) {
        final n = night(addDays(today, -i), 23, 0, 400 + i * 5);
        sleepData.nights[n.day] = n;
      }
      NightHrData.debugNights = {for (var i = 0; i < 10; i++) addDays(today, -i): 52};
      sleepData.debugSource = (a, b) async => [
        for (final n in sleepData.nights.values)
          SleepSession(n.bed, n.wake, app: 'Sormus', stageMs: {4: 240 * min, 5: 60 * min, 6: 100 * min, 1: 30 * min}),
      ];
      await tester.pumpWidget(const MaterialApp(home: StatsScreen(tab: 'sleep')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.text('Uni ja palautuminen'), findsOneWidget);
      expect(find.byKey(const ValueKey('sleepStatsTab')), findsOneWidget);
      expect(find.byKey(const ValueKey('sleepAvg')), findsOneWidget);
      expect(find.byKey(const ValueKey('nightBars')), findsOneWidget);
      expect(find.byKey(const ValueKey('periodStages')), findsOneWidget);
      expect(find.text('1 h 40 min · 25 %'), findsOneWidget); // REM 100 / 400
      expect(find.byKey(const ValueKey('periodRec_nighthr')), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget); // pisin yö
      // Ruudunlukija: pylväs on painike, jossa päivä ja kesto, ja sen voi avata (testi 23.11.).
      final sem = tester.ensureSemantics();
      final bar = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^\S+ \d+\.\d+\.: \d+ h')).first);
      expect(bar.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      sem.dispose();
      await tester.tap(find.byKey(ValueKey('nightBar_${isoDate(today)}')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sleepStages')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tekstikoko 2,0: ei ylivuotoa, ruutujen nimet eivät katkea kesken sanan (testi 23.11.)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 9000);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      settings.homeHidden = {'night'};
      for (var i = 0; i < 10; i++) {
        final n = night(addDays(today, -i), 23, 0, 400 + i * 5);
        sleepData.nights[n.day] = n;
      }
      NightHrData.debugNights = {for (var i = 0; i < 10; i++) addDays(today, -i): 52};
      sleepData.debugSource = (a, b) async => [
        for (final n in sleepData.nights.values)
          SleepSession(n.bed, n.wake, app: 'Sormus', stageMs: {4: 240 * min, 5: 60 * min, 6: 100 * min, 1: 30 * min}),
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: const StatsScreen(tab: 'sleep'),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sleepAvg')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Kehitys-välilehdellä ei enää palautumisen kehitystä', (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      settings.homeHidden = {'night'};
      await tester.pumpWidget(const MaterialApp(home: StatsScreen(tab: 'progress')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recoveryTrends')), findsNothing);
    });
  });
}
