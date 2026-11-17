import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/home_layout.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/home_settings.dart';

// Muokattava etusivu (käyttäjä 17.11.): WHO-renkaat aina, omat tavoitteet (1 rivissä, 2–3 omana korttinaan) ja
// valittavat kortit omassa järjestyksessään. Keksityt treenit.
void main() {
  final today = dateOnly(DateTime.now());
  final mon = addDays(today, 1 - today.weekday);

  Workout act(DateTime d, String sport, {double? km, int min = 30}) => Workout(date: d, title: sport, activity: sport)
    ..distanceKm = km
    ..seconds = min * 60;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings
      ..trainMode = 'both'
      ..program = null
      ..homeOrder = [...homeCardIds]
      ..homeHidden = {};
    settings.setGoals([]);
  });
  tearDown(() {
    store.workouts = [];
    settings
      ..trainMode = 'gym'
      ..homeOrder = [...homeCardIds]
      ..homeHidden = {};
  });

  test('tavoitteet ja kortit tiedostoon ja takaisin', () {
    const gs = [Goal('gym', null, 3), Goal('km', 'Juoksu', 20.5), Goal('min', null, 150)];
    expect(goalsToFile(gs), 'gym:*:3; km:Juoksu:20,5; min:*:150');
    expect(goalsFromFile(goalsToFile(gs)), gs);
    expect(goalsFromFile('x:*:3; km:Juoksu:-1; times:Uinti:2; gym:Juoksu:2; min:*:1; min:*:2'), const [
      Goal('times', 'Uinti', 2),
      Goal('gym', null, 2),
      Goal('min', null, 1),
    ]);
    expect(homeCardsToFile(['running', 'recent'], {'recent'}), 'running, -recent');
    final (o, h) = homeCardsFromFile('running, -recent, roskaa, running');
    expect(o, ['running', 'recent', 'goals', 'strength', 'weight']);
    expect(h, {'recent'});
    settings.applyMarkdown('---\nhome_goals: km:Pyöräily:100\nhome_cards: -goals, weight, recent\n---\n');
    expect(settings.goals, const [Goal('km', 'Pyöräily', 100)]);
    expect(settings.homeOrder.take(3), ['goals', 'weight', 'recent']);
    expect(settings.homeCardOn('goals'), isFalse);
    expect(settings.settingsToMarkdown(), contains('home_goals: km:Pyöräily:100'));
    expect(settings.settingsToMarkdown(), contains('home_cards: -goals, weight, recent, strength, running'));
  });

  test('tavoitteen toteuma: laji, matka, aika, kerrat ja salipäivät; kuukausi skaalautuu', () {
    final ws = [
      act(mon, 'Juoksu', km: 5),
      act(mon, 'Juoksu', km: 7.5),
      act(addDays(mon, 2), 'Pyöräily', km: 30, min: 60),
      act(addDays(mon, -1), 'Juoksu', km: 10), // edellinen viikko
      Workout(date: addDays(mon, 1), title: 'Treeni')..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 5)])),
    ];
    final next = addDays(mon, 7);
    expect(const Goal('km', 'Juoksu', 20).value(ws, mon, next), 12.5);
    expect(const Goal('km', null, 20).value(ws, mon, next), 42.5);
    expect(const Goal('min', null, 150).value(ws, mon, next), 120);
    expect(const Goal('times', 'Juoksu', 3).value(ws, mon, next), 2);
    expect(const Goal('gym', null, 3).value(ws, mon, next), 1);
    expect(const Goal('km', null, 7).target(30), 30);
  });

  test('ohjelman salipäivät oletustavoitteena, kunnes käyttäjä valitsee omat', () {
    settings.debugGoals = null; // ei home_goals-riviä tiedostossa
    settings.program = generateProgram(goal: 'kunto', experience: 'keski', days: 3, minutes: 60, injuries: const []);
    expect(settings.goals, const [Goal('gym', null, 3)]);
    settings.setGoals([]);
    expect(settings.goals, isEmpty, reason: 'tyhjä valinta säilyy');
    expect(settings.settingsToMarkdown(), contains('home_goals: \n'));
    settings.program = null;
  });

  testWidgets('yksi tavoite WHO-rivissä, kaksi omana korttinaan; piilotettu kortti ei näy', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    store.workouts = [act(today, 'Juoksu', km: 6)];
    settings.setGoals(const [Goal('km', 'Juoksu', 20)]);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('lihaskuntopäivää'), findsOneWidget);
    expect(find.text('6/20'), findsOneWidget);
    expect(find.text('km · juoksu'), findsOneWidget);
    expect(find.byKey(const ValueKey('goalsCard')), findsNothing);
    expect(find.text('Viimeksi'), findsOneWidget);

    settings.setGoals(const [Goal('km', 'Juoksu', 20), Goal('times', null, 4)]);
    settings.setHomeCard('recent', false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('goalsCard')), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('Viimeksi'), findsNothing);
    // Kuukausinäkymässä tavoite skaalautuu kuun päivillä.
    await tester.tap(find.byKey(const ValueKey('periodMonth')));
    await tester.pumpAndSettle();
    final days = DateTime(today.year, today.month + 1, 0).day;
    expect(find.text('1/${(4 * days / 7).round()}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asetukset: tavoitteen lisäys ja poisto, kortin piilotus', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: settings,
            builder: (_, _) => ListView(children: [HomeLayoutSettings()]),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('goalAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goalKind_min')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('goalAmount')), '0');
    await tester.tap(find.byKey(const ValueKey('goalSave')));
    await tester.pump();
    expect(find.textContaining('Anna luku'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('goalAmount')), '200');
    await tester.tap(find.byKey(const ValueKey('goalSave')));
    await tester.pumpAndSettle();
    expect(settings.goals, const [Goal('min', null, 200)]);
    expect(find.textContaining('200 min liikuntaa'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('homeCardSwitch_strength')));
    await tester.pump();
    expect(settings.homeCardOn('strength'), isFalse);
    await tester.tap(find.byKey(const ValueKey('goalRemove_0')));
    await tester.pump();
    expect(settings.goals, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asetukset: tavoitteiden ja korttien järjestys vetämällä', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    settings.setGoals(const [Goal('gym', null, 3), Goal('km', null, 20), Goal('times', null, 4)]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: settings,
            builder: (_, _) => ListView(children: [HomeLayoutSettings()]),
          ),
        ),
      ),
    );
    Future<void> drag(Finder handle, double dy) async {
      final g = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(kLongPressTimeout);
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, dy / 10));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    // Ensimmäinen tavoite viimeiseksi.
    final h = find.descendant(of: find.byKey(const ValueKey('goal_0')), matching: find.byIcon(Icons.drag_indicator));
    await drag(h, tester.getSize(find.byKey(const ValueKey('goal_0'))).height * 2.6);
    expect(settings.goals.map((g) => g.kind), ['km', 'times', 'gym']);
    // Viimeksi-kortti ensimmäiseksi.
    final c = find.descendant(
      of: find.byKey(const ValueKey('homeCard_recent')),
      matching: find.byIcon(Icons.drag_indicator),
    );
    await drag(c, -tester.getSize(find.byKey(const ValueKey('homeCard_recent'))).height * 1.2);
    expect(settings.homeOrder.first, 'recent');
    expect(tester.takeException(), isNull);
  });
}
