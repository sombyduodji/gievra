import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/progression.dart';
import 'package:treenipaivakirja/rest.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';

// Oma lämmittelysarja (käyttäjä 17.11. salilla: uudessa liikkeessä kolme kevyttä sarjaa täytti tavoitteen 4/4).
// Painike on ainoa lämmittelyehdotus: ei sovelluksen oman lämmittelyn rinnalla, ei kehonpaino- eikä aikaliikkeissä.
// Keksityt treenit ja painot.
void main() {
  final warmBtn = find.byKey(const ValueKey('saveWarmupSet'));
  final rampBtn = find.text('Tallenna lämmittelysarja');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    settings
      ..program = null
      ..pauses = []
      ..injuries = []
      ..restTimer = false;
    debugSetCatalog('fi', const {});
    SetLoggerScreen.repeatGuard = Duration.zero;
  });
  tearDown(() {
    rest.stop();
    store.workouts = [];
    SetLoggerScreen.repeatGuard = const Duration(milliseconds: 600);
  });

  Future<ExerciseEntry> open(WidgetTester tester, String name, {Target? target, List<SetEntry>? sets}) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final e = ExerciseEntry(name, sets);
    await tester.pumpWidget(
      MaterialApp(
        home: SetLoggerScreen(date: DateTime(2026, 11, 17), entry: e, target: target, onChanged: () async {}),
      ),
    );
    await tester.pump();
    return e;
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump(const Duration(seconds: 1));
    rest.stop();
    await tester.pump();
  }

  testWidgets('uusi painoliike: lämmittelysarjat eivät täytä tavoitetta; painike katoaa työsarjasta', (tester) async {
    final e = await open(tester, 'Farmer walk hex barilla', target: Target(4, 4, 4, '1–2', 120, '4 × 4'));
    expect(rampBtn, findsNothing);
    for (var i = 0; i < 3; i++) {
      await tap(tester, warmBtn);
    }
    expect(e.sets.length, 3);
    expect(e.workSets, isEmpty);
    expect(find.text('0/4'), findsOneWidget, reason: 'tavoitelaskuri vain työsarjoista');
    expect(find.text('Sarja 1'), findsOneWidget, reason: 'seuraava on ensimmäinen työsarja');
    await tap(tester, find.widgetWithText(FilledButton, 'Vähän'));
    expect(e.workSets.length, 1);
    expect(find.text('1/4'), findsOneWidget);
    expect(warmBtn, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('jälkikäteen: sarja lämmittelyksi ja takaisin työsarjaksi kynästä', (tester) async {
    final e = await open(tester, 'Farmer walk hex barilla', sets: [SetEntry(42, 2, rir: 3), SetEntry(102, 2, rir: 1)]);
    expect(warmBtn, findsNothing);
    await tap(tester, find.text('Sarja 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editWarmup')));
    await tester.pump();
    expect(find.text('Sarjan tyyppi'), findsNothing, reason: 'lämmittelyllä ei tyyppiä eikä varaa');
    await tester.tap(find.text('Tallenna'));
    await tester.pumpAndSettle();
    expect((e.sets[0].warmup, e.sets[0].rir, e.sets[0].kg), (true, null, 42.0));
    expect(e.workSets.single.kg, 102);
    // Takaisin työsarjaksi.
    await tap(tester, find.text('Lämmittely'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editWarmup')));
    await tester.pump();
    await tester.tap(find.text('Tallenna'));
    await tester.pumpAndSettle();
    expect(e.sets.every((s) => !s.warmup), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tankoliike, työpaino tiedossa: vain painike (ei vanhaa lämmittelytilaa eikä painovinkkejä)', (
    tester,
  ) async {
    store.workouts = [
      Workout(date: DateTime(2026, 11, 10), title: 'Treeni')
        ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5, rir: 2), SetEntry(100, 5, rir: 2)])),
    ];
    final e = await open(tester, 'Takakyykky');
    expect(rampBtn, findsNothing);
    expect(find.text('Ohita lämmittely'), findsNothing);
    expect(find.byKey(const ValueKey('rampChip_0')), findsNothing);
    expect(find.textContaining('Työsarjat: '), findsOneWidget);
    expect(warmBtn, findsOneWidget);
    expect(find.text('Sarja 1'), findsOneWidget, reason: 'esitäyttö on työsarja');
    final work = e.sets.isEmpty ? null : e.sets.last.kg;
    expect(work, isNull);
    // Kevyempi lämmittely: paino alas ja painike.
    await tap(tester, find.byIcon(Icons.remove).first);
    await tap(tester, warmBtn);
    expect(e.sets.single.warmup, isTrue);
    // Palattaessa esitäyttö on työpaino, ei lämmittelysarjan paino.
    await tester.pumpWidget(const SizedBox());
    final e2 = await open(tester, 'Takakyykky', sets: [...e.sets]);
    expect(warmBtn, findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Muutama'));
    expect(e2.workSets.single.kg, greaterThanOrEqualTo(100));
    expect(warmBtn, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ei painiketta kehonpaino- eikä aikaliikkeissä; käsipainoliikkeessä on', (tester) async {
    await open(tester, 'Leuanveto');
    expect(warmBtn, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester, 'Lankku');
    expect(warmBtn, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester, 'Hauiskääntö käsipainoilla');
    expect(warmBtn, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await open(tester, 'Kahvakuulaheilautus');
    expect(warmBtn, findsOneWidget, reason: 'kahvakuula');
    expect(tester.takeException(), isNull);
  });

  test('lämmittelysarjat eivät vaikuta seuraavan kerran ehdotukseen', () {
    store.workouts = [
      Workout(date: DateTime(2026, 11, 10), title: 'Treeni')
        ..exercises.add(
          ExerciseEntry('Farmer walk hex barilla', [
            SetEntry(42, 2, warmup: true),
            SetEntry(62, 2, warmup: true),
            SetEntry(102, 2, rir: 1),
          ]),
        ),
    ];
    final w = store.workouts.single.exercises.single;
    expect(w.workSets.map((s) => s.kg), [102]);
    expect(trName('Farmer walk hex barilla'), 'Farmer walk hex barilla');
  });

  test('paras paino: aiemmat päivät ja saman päivän aiemmat treenit, ei lämmittelyä', () {
    final d = DateTime(2026, 11, 17);
    store.workouts = [
      Workout(date: DateTime(2026, 11, 15), title: 'Treeni')
        ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(20, 9, rir: 2)])),
      Workout(date: d, title: 'Treeni', session: 1)
        ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 10, rir: 1)])),
      Workout(date: d, title: 'Treeni', session: 3)
        ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(140, 1, warmup: true), SetEntry(120, 3, rir: 0)])),
    ];
    expect(store.maxKgBefore('Takakyykky', d), 20, reason: 'ilman sessiota vain aiemmat päivät');
    expect(store.maxKgBefore('Takakyykky', d, session: 2), 100);
    expect(store.maxKgBefore('Takakyykky', d, session: 4), 120, reason: 'lämmittely 140 ei ole paras');
    expect(store.maxKgBefore('Takakyykky', d, session: 1), 20);
  });

  test('ehdotus vain työsarjoista: painava lämmittely tai pelkkä lämmittely ei muuta sitä', () {
    final t = Target(3, 8, 10, '0–2', 90, '3 × 8–10');
    store.workouts = [
      Workout(date: DateTime(2026, 11, 12), title: 'Treeni')
        ..exercises.add(
          ExerciseEntry('Reiden ojennus', [
            SetEntry(30, 10, warmup: true),
            SetEntry(45, 12, warmup: true), // yli 90 % työpainosta
            SetEntry(50, 8, rir: 1),
            SetEntry(50, 8, rir: 1),
            SetEntry(50, 8, rir: 1),
          ]),
        ),
      // Myöhempi kerta, jossa vain lämmittely (liike jäi kesken): ei ole edellinen kerta.
      Workout(date: DateTime(2026, 11, 15), title: 'Treeni')
        ..exercises.add(ExerciseEntry('Reiden ojennus', [SetEntry(20, 10, warmup: true)])),
    ];
    final sg = suggestForTarget('Reiden ojennus', DateTime(2026, 11, 17), t)!;
    expect((sg.kg, sg.reps), (50.0, 9), reason: 'sama paino, yksi toisto lisää työsarjoista (8 → 9)');
    final nx = suggestNext('Reiden ojennus', DateTime(2026, 11, 17))!;
    expect(nx.kg, 50);
  });
}
