import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/csv_export.dart';
import 'package:treenipaivakirja/daily_steps.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/ui/widgets.dart' show longDateYear;
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sync/sync_engine.dart';
import 'package:treenipaivakirja/ui/drawer.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/onboarding.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';
import 'package:treenipaivakirja/ui/steps_ui.dart';

// Päivän askeleet: Health Connectin päiväluvut korvaavat tallennetut (Oura päivittää myöhemmin, ei tuplausta),
// treeneihin ei kosketa, ja askeleet.md kulkee varmuuskopiossa, palautuksessa, tuonnissa, CSV:ssä ja
// synkronoinnissa. Keksityt luvut.
const _walk =
    '---\ndate: 2026-11-10\ntitle: Kävely\nactivity: Kävely\nduration: 40 min\nsteps: 4032\n---\n\n# Kävely 2026-11-10\n';

void main() {
  late Directory dir;
  final today = dateOnly(DateTime.now());
  final y = addDays(today, -1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-steps');
    File('${dir.path}/2026/2026-11-10.md')
      ..createSync(recursive: true)
      ..writeAsStringSync(_walk);
    settings
      ..folder = dir.path
      ..dailySteps = true;
    await store.reload();
    await dailySteps.load();
    debugStepsSupported = true;
  });
  tearDown(() {
    dailySteps.debugSource = null;
    dailySteps.debugRange = null;
    dailySteps.loading = false; // widget-testin kesken jäänyt haku
    debugStepsSupported = null;
    settings
      ..folder = null
      ..dailySteps = false;
    store.workouts = [];
    dailySteps.days.clear();
    dailySteps.apps.clear();
    dailySteps.added.clear();
    dailySteps.skipped.clear();
    dailySteps.hcTotal.clear();
    dir.deleteSync(recursive: true);
  });

  test('askeleet.md edestakaisin', () {
    final md = stepsToMarkdown(
      {DateTime(2026, 11, 12): 6412, DateTime(2026, 11, 11): 11204},
      {
        DateTime(2026, 11, 11): ['Oura', 'Puhelimen askelmittari'],
      },
    );
    expect(md, contains('- 2026-11-12: 6412\n- 2026-11-11: 11204 (Oura, Puhelimen askelmittari)'));
    final (d, a) = parseSteps(md);
    expect(d[DateTime(2026, 11, 11)], 11204);
    expect(a[DateTime(2026, 11, 11)], ['Oura', 'Puhelimen askelmittari']);
    expect(parseSteps('- 2026-13-40: 5\n- roskaa').$1, isEmpty);
  });

  test('Myöhemmin synkronoiva Oura korvaa eilisen luvun (ei lisää), treenit ennallaan', () async {
    final before = store.workouts.map(workoutToMarkdown).toList();
    dailySteps.debugSource = (a, b) async => {
      y: (9800, ['Puhelimen askelmittari']),
      today: (2100, ['Puhelimen askelmittari']),
    };
    await dailySteps.refresh();
    expect(dailySteps.yesterday, 9800);
    // Oura synkronoi yöllä: Health Connectin koonti antaa eiliselle uuden luvun.
    dailySteps.debugSource = (a, b) async => {
      y: (10450, ['Oura', 'Puhelimen askelmittari']),
      today: (2600, ['Puhelimen askelmittari']),
    };
    await dailySteps.refresh();
    expect(dailySteps.yesterday, 10450, reason: 'korvattu, ei 9800 + 10450');
    expect(dailySteps.today, 2600);
    final file = File('${dir.path}/$stepsFileName').readAsStringSync();
    expect(file, contains('${isoDate(y)}: 10450 (Oura, Puhelimen askelmittari)'));
    expect(file, isNot(contains('9800')));
    // Treenit ennallaan: ei uusia treenejä, kävelyn askeleet eivät muuttuneet.
    await store.reload();
    expect(store.workouts.map(workoutToMarkdown).toList(), before);
    expect(Directory('${dir.path}/2026').listSync().length, 1);
  });

  test('Päivä ilman askeleita poistuu vain, jos Health Connect palauttaa sen tyhjänä', () async {
    dailySteps.debugSource = (a, b) async => {y: (5000, <String>[])};
    await dailySteps.refresh();
    dailySteps.debugSource = (a, b) async => {y: (0, <String>[])};
    await dailySteps.refresh();
    expect(dailySteps.yesterday, isNull);
  });

  test('Varmuuskopio, palautus, .md-tuonti, CSV ja synkronointi sisältävät askeleet', () async {
    dailySteps.debugSource = (a, b) async => {
      y: (7000, ['Oura']),
    };
    await dailySteps.refresh();
    // Oma varmuuskopio (zip) sisältää askeleet.md:n ja palautus lukee sen.
    final zip = await exportZip();
    expect(ZipDecoder().decodeBytes(zip).files.map((f) => f.name), contains('Treenit/$stepsFileName'));
    final r = readZip(zip);
    expect(r.stepsMd, isNotNull);
    expect(r.unreadable, isEmpty);
    // Palautus toiseen laitteeseen: puuttuvat päivät lisätään, olemassa olevat pysyvät.
    dailySteps.days
      ..clear()
      ..[addDays(today, -3)] = 1234;
    await applyImport(r);
    expect(dailySteps.yesterday, 7000);
    expect(dailySteps.at(addDays(today, -3)), 1234);
    // .md-tuonti: askeleet.md ei ole lukukelvoton treeni.
    final imp = readMdFiles({
      stepsFileName: stepsToMarkdown({y: 7000}, {}),
      '2026-11-10.md': _walk,
    });
    expect(imp.unreadable, isEmpty);
    expect(imp.workouts.length, 1);
    expect(imp.stepsMd, isNotNull);
    // CSV (valinnainen).
    final csv = buildCsvExport(
      store.workouts,
      BodyLog(),
      CsvExportOptions(from: addDays(today, -30), to: today, steps: true),
      steps: dailySteps.days,
    );
    expect(csv.map((f) => f.name), contains('askeleet.csv'));
    // Synkronointi ja kansion vaihto.
    expect(isSyncable(stepsFileName), isTrue);
    expect(await Settings.mdFiles(dir), contains(stepsFileName));
  });

  testWidgets('Etusivun kortti: Edistyminen | Askeleet, Askeleet avaa tilastojen välilehden', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      dailySteps.debugSource = (a, b) async => {
        y: (11204, ['Oura']),
        today: (6412, ['Puhelimen askelmittari']),
      };
      await dailySteps.refresh();
    });
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HomeStatsCard), findsOneWidget);
    expect(find.textContaining('6412', findRichText: true), findsWidgets); // myös korkeuden mitoituskopio
    expect(find.textContaining(RegExp(r'Eilen 11.204')), findsWidgets);
    // Kortin napautus (ei pylväs: se avaa päivän erittelyn).
    await tester.tap(find.textContaining('askelta tänään', findRichText: true).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.text('Treenit'), findsOneWidget);
    expect(find.text('Askeleet'), findsWidgets);
    expect(find.byType(StepsStatsView), findsOneWidget);
    expect(find.textContaining(RegExp(r'^11.204$')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Etusivun kortti: Viikko-puoli näyttää WHO-viikon, napautus avaa laskutavan', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Viikko'), findsOneWidget, reason: 'puolten valitsimessa');
    await tester.tap(find.text('Viikko'));
    await tester.pumpAndSettle();
    expect(find.textContaining('min reipasta'), findsWidgets);
    expect(find.text('Viikon liikunta'), findsNothing, reason: 'ei omaa korttia');
    await tester.tap(find.textContaining('min reipasta').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Viikon liikunta'), findsOneWidget);
    expect(find.textContaining('WHO suosittelee'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kortin viikkokaavio: viivat 0, 5k ja 10k; tavoitteen ylittävä osa vihreä ja ✓', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      dailySteps.debugSource = (a, b) async => {
        addDays(today, -2): (15300, ['Ánden askelmittari']),
        y: (4100, <String>[]),
        today: (10000, <String>[]),
      };
      await dailySteps.refresh();
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StepsCardBody())));
    await tester.pump();
    for (final l in ['0', '5k', '10k']) {
      expect(find.text(l), findsOneWidget);
    }
    // Asteikko 16 000 (paras päivä pyöristettynä ylös): ylitys 5 300 → 60 * 5300 / 16000 px.
    final over = find.byKey(const ValueKey('stepsOver4'));
    expect(over, findsOneWidget);
    expect(tester.getSize(over).height, closeTo(60 * 5300 / 16000, .01));
    expect(find.byWidgetPredicate((w) => w is Container && '${w.key}'.contains('stepsOver')), findsOneWidget);
    // ✓ päivillä, joilla tavoite täyttyi (myös tasan 10 000).
    expect(find.textContaining('✓', findRichText: true), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Askeleet pois: ei korttia eikä välilehtiä', (tester) async {
    settings.dailySteps = false;
    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    await tester.pump();
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('Ensimmäinen käynnistys kysyy päivän askeleista (Android)', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pump();
    expect(find.textContaining(RegExp('seurataanko päivän askeleita', caseSensitive: false)), findsOneWidget);
    debugStepsSupported = false;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pump();
    expect(
      find.textContaining(RegExp('seurataanko päivän askeleita', caseSensitive: false)),
      findsNothing,
      reason: 'ei verkossa eikä iOS:llä',
    );
  });

  testWidgets('Juoksut: kortin Juoksu-puoli; ei erillisiä linkkejä etusivulla', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    store.workouts = [
      ...store.workouts,
      Workout(date: addDays(today, -2), title: 'Juoksu')
        ..activity = 'Juoksu'
        ..distanceKm = 8.2
        ..seconds = 2700,
    ];
    await tester.runAsync(() async {
      dailySteps.debugSource = (a, b) async => {today: (3000, <String>[])};
      await dailySteps.refresh();
    });
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Juoksu'), findsWidgets);
    expect(find.text('Juoksun kehitys'), findsNothing);
    expect(find.text('Toinen salitreeni tälle päivälle'), findsNothing);
    await tester.tap(find.text('Juoksu').last);
    await tester.pump();
    expect(find.byType(RunningCardBody), findsWidgets);
    expect(find.textContaining('8,2 km', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('Kävelymaton askeleet: puuttuvat lisätään, jo mukana olevia ei tuplata', () async {
    // Puhelin on tärkeysjärjestyksessä ylempänä eikä liiku maton päällä: koonnissa vain 1746.
    final walk = Workout(date: today, title: 'Kävely')
      ..activity = 'Kävely'
      ..started = DateTime(today.year, today.month, today.day, 10)
      ..seconds = 3 * 3600 + 20 * 60
      ..distanceKm = 6.68
      ..steps = 9000
      ..healthSource = 'WalkingPad';
    store.workouts = [...store.workouts, walk];
    dailySteps.debugSource = (a, b) async => {
      today: (1746, ['Puhelimen askelmittari']),
    };
    dailySteps.debugRange = (s, e) async => 200; // koonnissa maton ajalta vain puhelimen 200
    await dailySteps.refresh();
    expect(dailySteps.error, isNull);
    expect(dailySteps.today, 1746 + 9000 - 200);
    expect(dailySteps.hcTotal[today], 1746);
    expect(dailySteps.added[today]!.single.source, 'WalkingPad');
    expect(dailySteps.added[today]!.single.had, 200);
    // Koonnissa liikunnan ajalta yli puolet (4600 / 9000): ero johtuu sovellusten laskutavasta, ei lisätä.
    dailySteps.debugRange = (s, e) async => 4600;
    await dailySteps.refresh();
    expect(dailySteps.today, 1746);
    expect(dailySteps.added[today], isNull);
    expect(dailySteps.skipped[today]!.single.had, 4600, reason: 'näkyy koostumuksessa: ei lisätty');
    // WalkingPad nostettu Health Connectissa ylemmäs: koonti sisältää jo maton askeleet, mitään ei lisätä.
    dailySteps.debugSource = (a, b) async => {
      today: (10546, ['WalkingPad', 'Puhelimen askelmittari']),
    };
    dailySteps.debugRange = (s, e) async => 9000;
    await dailySteps.refresh();
    expect(dailySteps.today, 10546);
    // Gievrassa tallennettu ulkokävely (ei laitteen sovellusta): Oura kirjaa päivän yhtenä tietueena, joten koonti
    // antaa kävelyn ajalle vain tasaisesti jaetun osuuden (70). Askeleet ovat silti Ouran luvussa: ei lisätä.
    final gps = Workout(date: today, title: 'Kävely', session: 2)
      ..activity = 'Kävely'
      ..started = DateTime(today.year, today.month, today.day, 14, 24)
      ..seconds = 19 * 60
      ..steps = 1210
      ..healthSource = '';
    store.workouts = [...store.workouts, gps];
    dailySteps.debugSource = (a, b) async => {
      today: (5480, ['Oura']),
    };
    dailySteps.debugRange = (s, e) async => s.hour == 14 ? 70 : 800;
    await dailySteps.refresh();
    expect(dailySteps.today, 5480 + 9000 - 800, reason: 'vain kävelymatto lisätään');
    expect(dailySteps.added[today]!.map((a) => a.source), ['WalkingPad']);
    store.workouts = [...store.workouts]..remove(gps);
    // Liikunta ilman aloitusaikaa tai askelia ei vaikuta.
    walk.started = null;
    dailySteps.debugSource = (a, b) async => {today: (1746, <String>[])};
    await dailySteps.refresh();
    expect(dailySteps.today, 1746);
  });

  testWidgets('Kortin puolet samankorkuisia; kalenterissa päivän askeleet', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    store.workouts = [
      ...store.workouts,
      Workout(date: addDays(today, -2), title: 'Juoksu')
        ..activity = 'Juoksu'
        ..distanceKm = 8.2
        ..seconds = 2700,
    ];
    await tester.runAsync(() async {
      dailySteps.debugSource = (a, b) async => {y: (3949, <String>[]), today: (1746, <String>[])};
      await dailySteps.refresh();
    });
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    final h1 = tester.getSize(find.byType(HomeStatsCard)).height;
    await tester.tap(find.text('Juoksu').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byType(HomeStatsCard)).height, h1, reason: 'etusivu ei hypi');
    // Kalenterissa askelrenkaat päivämäärien ympärillä (tarkka luku päivän näkymässä).
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && '${w.painter?.runtimeType}' == '_StepsRing'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  test('Vanhoja tallennettuja päiviä ei poisteta, vaikka Health Connect antaa niille nollan', () async {
    final old = addDays(today, -60);
    dailySteps.days[old] = 8123;
    dailySteps.debugSource = (a, b) async => {for (var d = a; !d.isAfter(b); d = addDays(d, 1)) d: (0, <String>[])};
    await dailySteps.refresh(from: addDays(today, -90), to: today);
    expect(dailySteps.at(old), 8123);
  });

  testWidgets('Kalenterin päivä avaa päivän yhteenvedon: askeleet ja treeni, myös kun treenejä on yksi', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    store.workouts = [
      Workout(date: today, title: 'Kävely')
        ..activity = 'Kävely'
        ..distanceKm = 4.2
        ..seconds = 2520
        ..steps = 5600,
    ];
    await tester.runAsync(() async {
      dailySteps.debugSource = (a, b) async => {
        today: (8123, ['Oura']),
      };
      await dailySteps.refresh();
    });
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('${today.day}').last);
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^8.?123$')), findsOneWidget);
    expect(find.textContaining(RegExp('treenit \\(1\\)', caseSensitive: false)), findsOneWidget);
    expect(find.textContaining(RegExp(r'^5.?600$')), findsOneWidget);
    expect(find.text('Sali'), findsOneWidget);
    // Pyyhkäisy oikealle: edellinen päivä (ei treenejä eikä tämän päivän askeleita); vasemmalle takaisin.
    await tester.fling(find.byType(PageView), const Offset(250, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text(longDateYear(addDays(today, -1))), findsOneWidget);
    expect(find.textContaining(RegExp(r'^8.?123$')), findsNothing);
    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^8.?123$')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Laskusäännön muutos: tallennetut päivät luetaan kerran uudelleen (enintään 60 päivää)', () async {
    SharedPreferences.setMockInitialValues({});
    final old = addDays(today, -20);
    dailySteps.days[old] = 18420;
    dailySteps.days[addDays(today, -90)] = 5000;
    final asked = <(DateTime, DateTime)>[];
    dailySteps.debugSource = (a, b) async {
      asked.add((a, b));
      return {
        old: (7900, <String>['Oura']),
      };
    };
    await dailySteps.refresh();
    expect(asked.single.$1, addDays(today, -(stepsRuleDays - 1)), reason: 'vanhin tallennettu, raja 60 päivää');
    expect(dailySteps.at(old), 7900);
    expect(dailySteps.at(addDays(today, -90)), 5000, reason: 'Health Connectin historiaa vanhempi pysyy');
    asked.clear();
    await dailySteps.refresh();
    expect(asked.single.$1, addDays(today, -(stepsRefreshDays - 1)), reason: 'vain kerran');
  });

  test('Vanhempien askelten haku: kaksi vuotta taaksepäin, uudet päivät tallentuvat, vanhoja ei poisteta', () async {
    final kept = addDays(today, -400);
    dailySteps.days[kept] = 6000;
    final got = addDays(today, -300);
    final asked = <DateTime>[];
    dailySteps.debugSource = (a, b) async {
      asked.add(a);
      return {
        got: (7200, <String>['Oura']),
      };
    };
    final n = await dailySteps.readHistory();
    expect(asked.last, addDays(today, -(stepsHistoryDays - 1)));
    expect(n, 1);
    expect(dailySteps.at(got), 7200);
    expect(dailySteps.at(kept), 6000);
  });

  testWidgets('Asetuksissa Hae vanhemmat askeleet, kun Health Connect tukee historiaa', (tester) async {
    StepsHistoryTile.debugAvailable = true;
    addTearDown(() => StepsHistoryTile.debugAvailable = null);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.text(SettingsScreen.title(SettingsGroup.body)));
    await tester.pumpAndSettle();
    expect(find.text('Hae vanhemmat askeleet'), findsOneWidget);
    StepsHistoryTile.debugAvailable = false;
    settings.dailySteps = false;
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.text(SettingsScreen.title(SettingsGroup.body)));
    await tester.pumpAndSettle();
    expect(find.text('Hae vanhemmat askeleet'), findsNothing);
  });

  testWidgets('Päivän yhteenveto: treenit aloitusajan mukaan', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    store.workouts = [
      Workout(date: today, title: 'Sali', session: 1)..started = DateTime(today.year, today.month, today.day, 17),
      Workout(date: today, title: 'Kävely', session: 2)
        ..activity = 'Kävely'
        ..started = DateTime(today.year, today.month, today.day, 8)
        ..seconds = 1800,
    ];
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('${today.day}').last);
    await tester.pumpAndSettle();
    final walk = tester.getTopLeft(find.text('8:00')).dy;
    final gym = tester.getTopLeft(find.text('17:00')).dy;
    expect(walk, lessThan(gym));
  });

  test('Viimeksi: saman päivän treenit aloitusajan mukaan, uusin ensin', () {
    final a = Workout(date: today, title: 'Sali', session: 1)
      ..started = DateTime(today.year, today.month, today.day, 10);
    final b = Workout(date: today, title: 'Juoksu', session: 2)
      ..started = DateTime(today.year, today.month, today.day, 15);
    final c = Workout(date: today, title: 'Kävely', session: 3)
      ..started = DateTime(today.year, today.month, today.day, 8);
    final old = Workout(date: addDays(today, -1), title: 'Eilen');
    expect(latestWorkouts([old, a, b, c], 3).map((w) => w.title), ['Juoksu', 'Sali', 'Kävely']);
  });
}
