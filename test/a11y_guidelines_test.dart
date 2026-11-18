import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/home_layout.dart' show homeCardsOffByDefault;
import 'package:treenipaivakirja/insights.dart' show weekStart;
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/theme.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart';
import 'package:treenipaivakirja/ui/home_settings.dart';
import 'package:treenipaivakirja/ui/start_panels.dart';

// Yötesti 18.11.: Flutterin saavutettavuusohjeet (tekstin kontrasti, kosketusalueen koko, nimetyt painikkeet)
// 17.11. tulleille etusivun korteille ja Asetukset → Etusivu -näkymälle vaaleassa ja tummassa teemassa.
// Keksityt tiedot.
void main() {
  setUpAll(() {
    final tmp = Directory.systemTemp.createTempSync('gievra-a11y').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp,
    );
  });
  tearDown(() {
    store.workouts = [];
    settings.program = null;
    settings.trainMode = 'gym';
    settings.homeHidden = {...homeCardsOffByDefault};
    NightHrData.debugNights = const {};
    sleepData.nights.clear();
    sleepData.metrics.clear();
  });

  Workout gym(DateTime d) =>
      Workout(date: d, title: 'Treeni')..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 5)]));

  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };
  for (final (b, scale, lang, w) in [
    (Brightness.light, 1.0, 'fi', 400.0),
    (Brightness.dark, 1.0, 'fi', 400.0),
    (Brightness.light, 2.0, 'fi', 400.0),
    (Brightness.dark, 2.0, 'se', 360.0),
    (Brightness.light, 1.3, 'en', 360.0),
  ]) {
    testWidgets('etusivun kortit ja asetukset: ${b.name}, fontti $scale, $lang, ${w.round()} dp', (tester) async {
      debugSetCatalog(lang, lang == 'fi' ? const {} : po[lang]!);
      addTearDown(() => debugSetCatalog('fi', const {}));
      SharedPreferences.setMockInitialValues({});
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = Size(w * 2.7, 7200 * scale);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      final now = dateOnly(DateTime.now());
      final mon = weekStart(now);
      store.workouts = [gym(addDays(mon, -7)), gym(addDays(mon, -5)), gym(addDays(mon, -14))];
      settings.program = generateProgram(goal: 'kunto', experience: 'keski', days: 3, minutes: 60, injuries: const []);
      settings.trainMode = 'both';
      settings.homeHidden = {};
      NightHrData.debugNights = {for (var i = 0; i < 20; i++) addDays(now, -i): 50 + i % 3};
      sleepData.nights.addAll({
        for (var i = 0; i < 10; i++)
          addDays(now, -i): SleepNight(
            addDays(now, -i),
            DateTime(now.year, now.month, now.day - i - 1, 23),
            DateTime(now.year, now.month, now.day - i, 6, 30),
            Duration(minutes: 420 - i * 5),
            app: 'Oura',
          ),
      });
      sleepData.metrics.addAll({
        for (var i = 0; i < 30; i++)
          addDays(now, -i): NightMetrics(hrv: 50.0 + i % 4, rest: 50, rr: 14, spo2: 96, temp: 0),
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(b),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: const [
                StartSplitButton(),
                StreakCard(),
                NextDayCard(),
                NightHrCard(),
                SleepCard(),
                HomeLayoutSettings(),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      for (final k in ['streakCard', 'nextDayCard', 'nightHrCard', 'sleepCard', 'nightTile_hrv', 'homeStartGym']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(tester.takeException(), isNull, reason: 'ei ylivuotoja');
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }
}
