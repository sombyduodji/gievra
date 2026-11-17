import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/stats.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';
import 'package:treenipaivakirja/ui/widgets.dart' show numDate;
import 'package:treenipaivakirja/insights.dart' show weekStart;

// Edistyminen ja tilastot: jaksot 1 kk, 3 kk, 6 kk ja oma aikaväli (alku ja loppu, pikapainikkeet
// Ensimmäisestä treenistä, Tänään ja Viime viikon loppu). Keksityt treenit päivinä tästä päivästä taaksepäin.
void main() {
  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };
  final today = dateOnly(DateTime.now());
  final first = addDays(today, -900);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [
      for (final d in [900, 600, 400, 200, 60, 20, 3])
        Workout(date: addDays(today, -d), title: 'Koko keho A')
          ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)])),
    ];
  });
  tearDown(() {
    store.workouts = [];
    debugSetCatalog('fi', const {});
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    // Testifontti (Ahem) on leveämpi kuin oikea.
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    await tester.pumpWidget(const MaterialApp(home: StatsScreen(kind: 'all')));
    await tester.pumpAndSettle();
  }

  String range(DateTime a, DateTime b) => '${numDate(a, year: true)} – ${numDate(b, year: true)}';

  test('Vuosittaiset määrät pitkälle aikavälille', () {
    final ys = yearlyCounts(store.workouts, first, today);
    expect(ys.length, today.year - first.year + 1);
    expect(ys.fold<int>(0, (a, y) => a + y.$2), 7);
  });

  testWidgets('Lajeittain: alle minuutin laji näkyy tarkkana (0:16), pidempi minuutteina', (tester) async {
    store.workouts.addAll([
      Workout(date: today, title: 'Koripallo', activity: 'Koripallo', minutes: 1, seconds: 16, session: 2),
      Workout(date: today, title: 'Jooga', activity: 'Jooga', minutes: 45, seconds: 45 * 60 + 2, session: 3),
    ]);
    await open(tester);
    expect(find.text('1 krt · 0:16'), findsOneWidget);
    expect(find.text('1 krt · 45 min'), findsOneWidget);
  });

  testWidgets('1 kk: 12 viikon kaavio päättyy kuluvaan viikkoon, ei tulevia tyhjiä viikkoja (päätös 14.11.)', (
    tester,
  ) async {
    await open(tester);
    final thisWeek = numDate(weekStart(today));
    final nextWeek = numDate(addDays(weekStart(today), 7));
    final elevenAgo = numDate(addDays(weekStart(today), -77));
    expect(find.text(thisWeek), findsWidgets, reason: 'kuluva viikko oikeassa reunassa');
    expect(find.text(elevenAgo), findsWidgets, reason: '12 viikkoa: 11 aiempaa + kuluva');
    expect(find.text(nextWeek), findsNothing, reason: 'ei tulevia viikkoja');
  });

  testWidgets('Ruudunlukija: viikkokaavio on yksi yhteenveto ("9.11.: 2"), ei irrallisia lukuja', (tester) async {
    final h = tester.ensureSemantics();
    await open(tester);
    final week = numDate(weekStart(addDays(today, -3)));
    expect(find.bySemanticsLabel(RegExp('${RegExp.escape(week)}: 1')), findsOneWidget);
    h.dispose();
  });

  testWidgets('Yhteenvetolause: jakson treenit ja ero edelliseen (uusi ulkoasu)', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('statsHeadline')), findsOneWidget);
    expect(find.textContaining('treeniä'), findsWidgets);
  });

  testWidgets('Yhteenvetolause Kestävyys-välilehdellä: liikuntakerrat ja matka', (tester) async {
    store.workouts.addAll([
      Workout(date: addDays(today, -2), title: 'Juoksu', activity: 'Juoksu')
        ..seconds = 1800
        ..distanceKm = 5.2,
      Workout(date: addDays(today, -1), title: 'Kävely', activity: 'Kävely')
        ..seconds = 2400
        ..distanceKm = 3,
    ]);
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    await tester.pumpWidget(const MaterialApp(home: StatsScreen(kind: 'cardio')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('statsHeadline')), findsOneWidget);
    expect(find.textContaining('2 liikuntakertaa · 8,2 km'), findsOneWidget);
  });

  testWidgets('Jaksot: 1 kk oletuksena, viikko ja vuosi poistuneet', (tester) async {
    await open(tester);
    for (final l in ['1 kk', '3 kk', '6 kk', 'Oma']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    // Viikko on oma välilehtensä, ei jakson vaihtoehto.
    expect(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('Viikko')), findsNothing);
    expect(find.text('Vuosi'), findsNothing);
    final seg = tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>).last);
    expect(seg.selected, {'month'});
    // Kuluva kuukausi on kesken: verrataan edellisen kuukauden samoihin päiviin (ei koko kuukauteen), paitsi
    // kuun viimeisenä päivänä, jolloin jakso on täysi.
    final today = DateTime.now();
    final lastDay = DateTime(today.year, today.month + 1, 0).day == today.day;
    expect(
      find.textContaining(lastDay ? 'Vertailu edelliseen kuukauteen' : 'Vertailu edellisen jakson samoihin päiviin'),
      findsOneWidget,
    );
  });

  testWidgets('Oma aikaväli: ensimmäisestä treenistä tähän päivään, vuosittaiset pylväät', (tester) async {
    await open(tester);
    await tester.tap(find.text('Oma'));
    await tester.pumpAndSettle();
    expect(find.text('Oma aikaväli'), findsOneWidget);
    // Oletuksena ensimmäisestä treenistä tähän päivään.
    expect(find.text(numDate(first, year: true)), findsOneWidget);
    expect(find.text(numDate(today, year: true)), findsOneWidget);
    await tester.tap(find.text('Näytä'));
    await tester.pumpAndSettle();
    expect(find.text(range(first, today)), findsOneWidget);
    expect(find.text('Ensimmäisestä treenistä tähän päivään · 901 pv'), findsOneWidget);
    expect(find.text('Ei vertailua: ennen jaksoa ei ole treenejä'), findsOneWidget);
    expect(find.text('Treenit vuosittain (${today.year - first.year + 1} v)'.toUpperCase()), findsOneWidget);
    expect(find.text('7'), findsWidgets, reason: '7 treeniä');
  });

  testWidgets('Oma aikaväli: Viime viikon loppu ja muokkaus; peruutus säilyttää jakson', (tester) async {
    await open(tester);
    // Peruutus ensimmäisellä kerralla: 1 kk jää.
    await tester.tap(find.text('Oma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>).last).selected, {'month'});

    await tester.tap(find.text('Oma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viime viikon loppu'));
    await tester.pump();
    await tester.tap(find.text('Näytä'));
    await tester.pumpAndSettle();
    final sunday = addDays(weekStart(today), -1);
    expect(find.text(range(first, sunday)), findsOneWidget);
    expect(find.text('Vertailu yhtä pitkään jaksoon ennen'), findsNothing);

    // Muokkaus: alku ensimmäisestä treenistä säilyy, loppu takaisin tähän päivään.
    await tester.tap(find.byTooltip('Muuta aikaväliä'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tänään'));
    await tester.pump();
    await tester.tap(find.text('Näytä'));
    await tester.pumpAndSettle();
    expect(find.text(range(first, today)), findsOneWidget);
  });

  testWidgets('Oma aikaväli: tulevaisuuteen päivätty treeni ei kaada kalenteria', (tester) async {
    // Ainoa treeni ensi viikolla (esim. päivä kirjoitettu väärin): alku ei saa olla tämän päivän jälkeen.
    store.workouts = [Workout(date: addDays(today, 10), title: 'Koko keho A')];
    await open(tester);
    await tester.tap(find.text('Oma'));
    await tester.pumpAndSettle();
    expect(find.text(numDate(today, year: true)), findsNWidgets(2), reason: 'alku ja loppu tänään');
    await tester.tap(find.byIcon(Icons.calendar_today_outlined).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Valitse päivä'), findsOneWidget);
  });

  testWidgets('Oma aikaväli: vanhimpien treenien poiston jälkeen aiempi alku rajoihin', (tester) async {
    await open(tester);
    await tester.tap(find.text('Oma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Näytä'));
    await tester.pumpAndSettle();
    // Vanhimmat poistetaan: aiemmin valittu alku (900 pv sitten) on nyt kalenterin rajan ulkopuolella.
    store.workouts.removeWhere((w) => w.date.isBefore(addDays(today, -30)));
    await tester.tap(find.byTooltip('Muuta aikaväliä'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today_outlined).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Valitse päivä'), findsOneWidget);
  });

  testWidgets('Oma aikaväli: lyhyt väli, viikot ja päivä yksikössä', (tester) async {
    // Kaksi treeniä: tänään ja eilen. Väli ensimmäisestä tähän päivään = 2 päivää.
    store.workouts = [
      for (final d in [1, 0]) Workout(date: addDays(today, -d), title: 'Koko keho A'),
    ];
    await open(tester);
    await tester.tap(find.text('Oma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Näytä'));
    await tester.pumpAndSettle();
    expect(find.text('Ensimmäisestä treenistä tähän päivään · 2 pv'), findsOneWidget);
    // Maanantaina eilinen on edellisellä viikolla: kaksi viikkopylvästä, muuten yksi.
    final weeks = today.weekday == DateTime.monday ? 2 : 1;
    final label = weeks == 1 ? 'Treenit viikoittain (1 viikko)' : 'Treenit viikoittain (2 viikkoa)';
    expect(find.text(label.toUpperCase()), findsOneWidget);
    // Yksi päivä: Tänään-pikapainike alkuun ei ole, joten loppu eiliseen ("Viime viikon loppu" ei käy aina).
    store.workouts = [Workout(date: today, title: 'Koko keho A')];
    await tester.tap(find.byTooltip('Muuta aikaväliä'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ensimmäisestä treenistä'));
    await tester.pump();
    await tester.tap(find.text('Näytä'));
    await tester.pumpAndSettle();
    expect(find.text('Ensimmäisestä treenistä tähän päivään · 1 päivä'), findsOneWidget);
    expect(find.text('Treenit viikoittain (1 viikko)'.toUpperCase()), findsOneWidget);
  });

  test('Englanniksi yksi päivä ja viikko yksikössä', () {
    expect(po['en']!['1 päivä'], '1 day');
    expect(po['en']!['Treenit viikoittain (1 viikko)'], 'Workouts per week (1 week)');
  });

  for (final l in ['fi', 'en', 'se']) {
    testWidgets('Oma aikaväli ($l): valinta ja tulos ilman virheitä', (tester) async {
      debugSetCatalog(l, l == 'fi' ? const {} : po[l]!, english: po['en']);
      await open(tester);
      await tester.tap(find.text(t('Oma')));
      await tester.pumpAndSettle();
      for (final s in [
        'Oma aikaväli',
        'Alkaen',
        'Päättyen',
        'Ensimmäisestä treenistä',
        'Tänään',
        'Viime viikon loppu',
      ]) {
        expect(find.text(t(s)), findsOneWidget, reason: s);
      }
      await tester.tap(find.text(t('Näytä')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          t('Ensimmäisestä treenistä tähän päivään · {0}', [
            t('{0} pv', [901]),
          ]),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
