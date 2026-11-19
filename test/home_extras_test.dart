import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/home_extras.dart';
import 'package:treenipaivakirja/insights.dart' show weekStart;
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart';

// Etusivun lisäkortit (17.11.): viikkoputki, seuraava ohjelman päivä ja yön alin syke. Keksityt tiedot.
void main() {
  final today = DateTime(2026, 11, 18); // keskiviikko
  final thisMon = weekStart(today);

  Workout gym(DateTime d) =>
      Workout(date: d, title: 'Treeni')..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 5)]));
  Workout run(DateTime d, int min) => Workout(date: d, title: 'Juoksu', activity: 'Juoksu')
    ..distanceKm = min / 6
    ..seconds = min * 60;
  // Viikko, jolla molemmat suositukset: 2 salipäivää + 3 × 60 min juoksua.
  List<Workout> fullWeek(DateTime mon) => [
    gym(mon),
    gym(addDays(mon, 2)),
    run(addDays(mon, 1), 60),
    run(addDays(mon, 3), 60),
    run(addDays(mon, 5), 60),
  ];

  test('yötesti 18.11.: pelkät tulevat treenit eivät kaada viikkoputkea', () {
    final s = whoStreak([gym(addDays(thisMon, 14))], today);
    expect(s.weeks, isNotEmpty);
    expect(s.weeks.last.$1, thisMon);
    expect(s.current, 0);
  });

  test('viikkoputki: täydet viikot, katkos, kuluva viikko kesken ei katkaise', () {
    final ws = [
      ...fullWeek(addDays(thisMon, -42)),
      // -35: vain sali (yksi suositus) katkaisee
      gym(addDays(thisMon, -35)),
      gym(addDays(thisMon, -33)),
      ...fullWeek(addDays(thisMon, -28)),
      ...fullWeek(addDays(thisMon, -21)),
      ...fullWeek(addDays(thisMon, -14)),
      ...fullWeek(addDays(thisMon, -7)),
      gym(thisMon),
    ];
    final s = whoStreak(ws, today);
    expect(s.current, 4);
    expect(s.best, 4);
    expect(s.weeks.last, (thisMon, WeekMark.open));
    expect(s.weeks.map((w) => w.$2), [
      WeekMark.both,
      WeekMark.one,
      WeekMark.both,
      WeekMark.both,
      WeekMark.both,
      WeekMark.both,
      WeekMark.open,
    ]);
    // Kuluva viikko täyttyy: lasketaan mukaan.
    expect(whoStreak([...ws, ...fullWeek(thisMon)], today).current, 5);
  });

  test('viikkoputki: tyhjä viikko katkaisee, taukoviikko ei', () {
    final ws = [...fullWeek(addDays(thisMon, -21)), ...fullWeek(addDays(thisMon, -7))];
    expect(whoStreak(ws, today).current, 1);
    expect(whoStreak(ws, today).best, 1);
    final pause = Pause(addDays(thisMon, -14), 'sairas', addDays(thisMon, -9));
    final s = whoStreak(ws, today, pauses: [pause]);
    expect(s.current, 2);
    expect(s.weeks[1].$2, WeekMark.pause);
    expect(whoStreak(const [], today).current, 0);
  });

  test('yön alin syke: viimeisin, 3 yön keskiarvo ja mediaani 28 yöstä', () {
    final nights = <DateTime, int>{
      for (var i = 3; i < 20; i++) addDays(today, -i): 50 + i % 3, // 50–52, mediaani 51
      addDays(today, -2): 56,
      addDays(today, -1): 57,
      today: 58,
    };
    final n = nightHr(nights, today)!;
    expect(n.last, 58);
    expect(n.recent, 57);
    expect(n.base, 51);
    expect(n.delta, 6);
    // Liian vähän öitä vertailuun.
    expect(nightHr({today: 50, addDays(today, -1): 52}, today)!.base, isNull);
    // Viimeisin yö yli 3 päivää sitten: ei näytetä.
    expect(nightHr({addDays(today, -5): 50}, today), isNull);
    expect(nightHr(const {}, today), isNull);
  });

  testWidgets('kortit: putki, seuraava päivä ohjelmasta ja korkea yösyke', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = dateOnly(DateTime.now());
    final mon = weekStart(now);
    store.workouts = [...fullWeek(addDays(mon, -14)), ...fullWeek(addDays(mon, -7))];
    settings.program = generateProgram(goal: 'kunto', experience: 'keski', days: 3, minutes: 60, injuries: const []);
    // Terveys ja hyvinvointi käytössä: WHO-putki (pelkässä treenipäiväkirjassa treeniputki, testi alla).
    settings.bodyTracker = true;
    addTearDown(() => settings.bodyTracker = false);
    NightHrData.debugNights = {
      for (var i = 3; i < 20; i++) addDays(now, -i): 50,
      addDays(now, -2): 57,
      addDays(now, -1): 57,
      now: 57,
    };
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: Column(children: [StreakCard(), NextDayCard(), NightHrCard()])),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('streakCard')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey('nextDayCard')), findsOneWidget);
    expect(find.text(settings.program!.plan.first.uiName), findsOneWidget);
    expect(find.byKey(const ValueKey('nightHrCard')), findsOneWidget);
    // Uusi ulkoasu (18.11.): yösyke ruutuna punaisella reunalla ja ⚠; napautus avaa neuvon.
    expect(find.byKey(const ValueKey('nightTile_nighthr')), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nightTile_nighthr')));
    await tester.pumpAndSettle();
    expect(find.text('Yösyke selvästi koholla'), findsOneWidget);
    expect(find.textContaining('Mishra 2020'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    // Ei omaa ?-painiketta kortissa (ohje etusivun ?-ohjeessa, 18.11.).
    expect(find.byKey(const ValueKey('recoveryHelp')), findsNothing);
    // Yösyke valittavissa kuten muutkin ruudut (18.11.): pois valittuna ruutu ja kortti katoavat.
    settings.setNightTile('nighthr', false);
    await tester.pump();
    expect(find.byKey(const ValueKey('nightTile_nighthr')), findsNothing);
    settings.setNightTile('nighthr', true);
    await tester.pump();
    settings.program = null;
    NightHrData.debugNights = const {};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Column(children: [NextDayCard(), NightHrCard()])),
      ),
    );
    expect(find.byKey(const ValueKey('nextDayCard')), findsNothing);
    expect(find.byKey(const ValueKey('nightHrCard')), findsNothing);
  });

  test('treeniputki (19.11.): ohjelman päivät viikossa, vajaa viikko katkaisee, kuluva kesken ei', () {
    final ws = [
      for (final w in [-3, -2, -1]) ...[
        gym(addDays(thisMon, 7 * w)),
        gym(addDays(thisMon, 7 * w + 2)),
        gym(addDays(thisMon, 7 * w + 4)),
      ],
      gym(thisMon),
    ];
    final s = trainingStreak(ws, today, 3);
    expect((s.current, s.best), (3, 3));
    expect(s.weeks.last.$2, WeekMark.open);
    // Juoksut eivät kerrytä salitreenaajan putkea, mutta kerryttävät molempien.
    final runs = [
      for (final d in [0, 2, 4]) run(addDays(thisMon, -7 + d), 30),
    ];
    expect(trainingStreak(runs, today, 3).current, 0);
    expect(trainingStreak(runs, today, 3, mode: 'both').current, 1);
    // Vajaa viikko (2/3) katkaisee.
    final short = [
      gym(addDays(thisMon, -14)),
      gym(addDays(thisMon, -12)),
      gym(addDays(thisMon, -10)),
      gym(addDays(thisMon, -7)),
    ];
    final s2 = trainingStreak(short, today, 3);
    expect((s2.current, s2.best), (0, 1));
    expect(s2.weeks[s2.weeks.length - 2].$2, WeekMark.one);
  });

  testWidgets('pelkkä treenipäiväkirja: Treeniputki-kortti ohjelman tavoitteella', (tester) async {
    SharedPreferences.setMockInitialValues({});
    settings
      ..bodyTracker = false
      ..dailySteps = false
      ..trainMode = 'gym';
    final now = dateOnly(DateTime.now());
    final mon = weekStart(now);
    settings.program = generateProgram(
      goal: 'lihaskasvu',
      experience: 'keski',
      days: 3,
      minutes: 60,
      injuries: const [],
    );
    store.workouts = [
      for (final w in [-2, -1])
        for (final d in [0, 2, 4]) gym(addDays(mon, 7 * w + d)),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: StreakCard())),
      ),
    );
    expect(find.text('Treeniputki'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('treenitavoitteessa (3 treeniä)'), findsOneWidget);
    expect(find.textContaining('WHO'), findsNothing);
  });
}
