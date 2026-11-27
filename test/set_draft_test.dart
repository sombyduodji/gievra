import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/rest.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';

// Tallentamaton seuraava sarja (käyttäjä 24.11.: paino ja toistot vaihdettu, käyty liikelistassa ja palattu:
// arvot palasivat edelliseen sarjaan). Keksityt painot.
void main() {
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

  Future<void> open(WidgetTester tester, ExerciseEntry e) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SetLoggerScreen(date: DateTime(2026, 11, 17), entry: e, onChanged: () async {}),
      ),
    );
    await tester.pump();
  }

  Finder kg(String v) => find.bySemanticsLabel('Paino: $v kg');
  Finder reps(String v) => find.bySemanticsLabel('Toistot: $v');

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
  }

  Future<void> plus(WidgetTester tester, String label, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byTooltip('Lisää: $label'));
      await tester.pump();
    }
  }

  testWidgets('muutettu paino ja toistot säilyvät liikkeestä poistuttaessa, tallennus tyhjentää', (tester) async {
    final e = ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 6, rir: 2)]);
    await open(tester, e);
    expect(kg('60'), findsOneWidget);
    await plus(tester, 'Paino', 4); // 2,5 kg askel → 70
    await tester.tap(find.byTooltip('Vähennä: Toistot'));
    await tester.pump();
    expect(kg('70'), findsOneWidget);
    expect(reps('5'), findsOneWidget);

    await leave(tester);
    await open(tester, e);
    expect(kg('70'), findsOneWidget, reason: 'tallentamaton paino säilyi');
    expect(reps('5'), findsOneWidget, reason: 'tallentamattomat toistot säilyivät');

    // Tallennus: seuraava avaus lähtee tallennetusta sarjasta, ei vanhasta luonnoksesta.
    await tester.tap(find.widgetWithText(FilledButton, 'Muutama'));
    await tester.pump(const Duration(seconds: 1));
    rest.stop();
    expect(e.sets.last.kg, 70);
    await leave(tester);
    await open(tester, e);
    expect(kg('70'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('luonnos ohitetaan, jos sarjoja muutettiin muualla', (tester) async {
    final e = ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 6, rir: 2)]);
    await open(tester, e);
    await plus(tester, 'Paino', 4);
    await leave(tester);
    e.sets.add(SetEntry(65, 6, rir: 2));
    await open(tester, e);
    expect(kg('65'), findsOneWidget);
    expect(kg('70'), findsNothing);
  });

  testWidgets(
    'ensimmäinen sarja: luonnos säilyy, vaikka treeninäkymä luo tyhjän liikerivin uudelleen (yötesti 26.11.)',
    (tester) async {
      store.workouts = [
        Workout(date: DateTime(2026, 11, 10), title: 'X')
          ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 6, rir: 2)])),
      ];
      await open(tester, ExerciseEntry('Takakyykky', []));
      final start = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Paino: \d'))).label;
      await plus(tester, 'Paino', 2);
      await plus(tester, 'Toistot', 1);
      final kgNow = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Paino: \d'))).label;
      final repsNow = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Toistot: \d'))).label;
      expect(kgNow, isNot(start));
      await leave(tester);
      // Uusi olio samalla nimellä, kuten workout.dart:n _log poistaa tyhjän rivin ja lisää uuden.
      await open(tester, ExerciseEntry('Takakyykky', []));
      expect(find.bySemanticsLabel(kgNow), findsOneWidget, reason: 'tallentamaton paino säilyi');
      expect(find.bySemanticsLabel(repsNow), findsOneWidget, reason: 'tallentamattomat toistot säilyivät');
      // Palautettu luonnos tallentuu taas poistuttaessa (arvot yhä muutettuja).
      await leave(tester);
      await open(tester, ExerciseEntry('Takakyykky', []));
      expect(find.bySemanticsLabel(kgNow), findsOneWidget, reason: 'luonnos tallennettiin uudelleen poistuttaessa');
      // Toinen liike samana päivänä ei saa tätä luonnosta.
      await leave(tester);
      await open(tester, ExerciseEntry('Penkkipunnerrus', []));
      expect(find.bySemanticsLabel(kgNow), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('muuttamaton: ei luonnosta, avaus kuten ennen', (tester) async {
    final e = ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 6, rir: 2)]);
    await open(tester, e);
    await leave(tester);
    await open(tester, e);
    expect(kg('60'), findsOneWidget);
  });

  testWidgets('valmis-painike: pitkä nimi rivittyy samalla koolla eikä kutistu (käyttäjä 24.11.)', (tester) async {
    nameMode = 'both';
    addTearDown(() => nameMode = 'fi');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    const name = 'Rintatuettu kulmasoutu käsipainoilla';
    final e = ExerciseEntry(name, [
      for (final kg in [20.0, 24.0, 28.0]) SetEntry(kg, 10, rir: 2),
    ]);
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(411, 914), textScaler: TextScaler.linear(scale)),
            child: SetLoggerScreen(
              date: DateTime(2026, 11, 17),
              entry: e,
              target: Target(3, 6, 10, '1–2', 90, '3 × 6–10'),
              onChanged: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      final label = find.descendant(of: find.byKey(const ValueKey('exerciseDone')), matching: find.byType(Text));
      expect((tester.widget<Text>(label).data), '$name valmis', reason: 'ei englanninkielistä nimeä suluissa');
      expect(find.ancestor(of: label, matching: find.byType(FittedBox)), findsNothing);
      expect(tester.takeException(), isNull, reason: 'tekstikoko $scale');
    }
  });

  String row(WidgetTester tester, String key) => tester
      .widget<Text>(find.byKey(ValueKey(key)))
      .textSpan!
      .toPlainText()
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u2060', '');

  testWidgets('kahden käsipainon ehdotus kättä kohden otsikossa, Käytä täyttää yhteispainon (käyttäjä 24.–25.11.)', (
    tester,
  ) async {
    const name = 'Rintatuettu kulmasoutu käsipainoilla';
    store.workouts = [
      Workout(date: DateTime(2026, 11, 12), title: 'Yläkroppa')
        ..exercises.add(
          ExerciseEntry(name, [SetEntry(36, 8, rir: 3), SetEntry(44, 8, rir: 2), SetEntry(44, 8, rir: 2)]),
        ),
    ];
    final e = ExerciseEntry(name, []);
    await tester.pumpWidget(
      MaterialApp(
        home: SetLoggerScreen(
          date: DateTime(2026, 11, 17),
          entry: e,
          target: Target(3, 6, 10, '1–2', 90, '3 × 6–10'),
          onChanged: () async {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Toistot'), findsOneWidget);
    expect(row(tester, 'targetRow'), startsWith('3 × 6–10'));
    // Väli ja varaus eivät katkea viivan jälkeen eikä varaus lukunsa edestä (saame 1,3: "fápmu 2–⏎3", yötesti 27.11.).
    final rawTarget = tester.widget<Text>(find.byKey(const ValueKey('targetRow'))).textSpan!.toPlainText();
    expect(rawTarget, contains('6–\u206010'));
    expect(rawTarget, contains('varaa\u00A01–\u20602'));
    expect(find.text('Työsarjat'), findsOneWidget);
    expect(find.text('per käsi'), findsOneWidget);
    final sugg = row(tester, 'suggRow');
    final m = RegExp(r'^([\d,]+) kg × (\d+)$').firstMatch(sugg);
    expect(m, isNotNull, reason: sugg);
    // Edellinen: vain paras sarja (käyttäjä 25.11.), kättä kohden.
    expect(find.text('Edellinen paras'), findsOneWidget);
    expect(row(tester, 'lastRow'), '22 kg × 8');
    // Sitova sarja pienenee kapeassa sarakkeessa eikä katkea keskeltä ("17,5 kg ×⏎9", yötesti 26.11.).
    for (final k in ['suggRow', 'lastRow']) {
      final fitted = find.ancestor(of: find.byKey(ValueKey(k)), matching: find.byType(FittedBox));
      expect(fitted, findsOneWidget, reason: k);
    }
    expect(find.ancestor(of: find.byKey(const ValueKey('targetRow')), matching: find.byType(FittedBox)), findsNothing);
    await tester.tap(find.text('Käytä'));
    await tester.pump();
    final hand = double.parse(m![1]!.replaceAll(',', '.'));
    expect(
      find.textContaining('${fmtNum(hand)} kg kummassakin kädessä'),
      findsOneWidget,
      reason: 'Käytä täyttää yhteispainon, kättä kohden sama kuin ehdotuksessa',
    );
  });

  testWidgets('rivit: kuula, kehonpaino (Tänään), aika ja edestakaiset (yksikkö kerran) (käyttäjä 25.11.)', (
    tester,
  ) async {
    Future<void> show(String name, List<SetEntry> prev, Target target) async {
      store.workouts = [Workout(date: DateTime(2026, 11, 12), title: 'X')..exercises.add(ExerciseEntry(name, prev))];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: SetLoggerScreen(
            date: DateTime(2026, 11, 17),
            entry: ExerciseEntry(name, []),
            target: target,
            onChanged: () async {},
          ),
        ),
      );
      await tester.pump();
    }

    await show('Tuplakahvakuulaheilautus', [
      for (var i = 0; i < 3; i++) SetEntry(24, 10, rir: 2),
    ], Target(3, 8, 12, '1–2', 90, '3 × 8–12'));
    expect(row(tester, 'suggRow'), startsWith('24 kg × '));
    expect(find.text('per kuula'), findsOneWidget);
    expect(row(tester, 'lastRow'), '24 kg × 10');

    await show('Leuanveto', [
      SetEntry(0, 8, rir: 2),
      SetEntry(0, 8, rir: 2),
      SetEntry(0, 7, rir: 2),
    ], Target(3, 6, 10, '2–3', 150, '3 × 6–10'));
    expect(find.text('Tänään'), findsOneWidget);
    expect(row(tester, 'suggRow'), matches(RegExp(r'^\d+ toistoa$')));
    expect(row(tester, 'lastRow'), '8 toistoa');

    await show('Lankku', [SetEntry(0, 30, rir: 2), SetEntry(0, 30, rir: 2)], Target(3, 20, 40, '1–2', 60, '3 × 20–40'));
    expect(find.text('Kesto'), findsOneWidget);
    expect(row(tester, 'targetRow'), startsWith('3 × 20–40 s'));
    expect(row(tester, 'suggRow'), matches(RegExp(r'^\d+ s$')));
    expect(row(tester, 'lastRow'), '30 s');

    await show('Farmer walk', [
      SetEntry(40, 2, rir: 2),
      SetEntry(42.5, 2, rir: 2),
    ], Target(3, 2, 4, '1–2', 120, '3 × 2–4'));
    expect(find.text('Matka'), findsOneWidget);
    expect(row(tester, 'targetRow'), startsWith('3 × 2–4 edestakaisin'));
    expect(row(tester, 'lastRow'), '21,25 kg × 2 edestakaisin');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tallennusilmoitus ruudunlukijalle kättä kohden kuten sarjaluettelossa (yötesti 25.11.)', (tester) async {
    final e = ExerciseEntry('Vasarakääntö', [SetEntry(20, 8, rir: 1)]);
    await open(tester, e);
    tester.takeAnnouncements();
    await tester.tap(find.widgetWithText(FilledButton, 'Muutama'));
    await tester.pump();
    final said = tester.takeAnnouncements().map((a) => a.message).toList();
    expect(said, contains('Sarja tallennettu: 10 kg/käsi × 8'), reason: '$said');
  });

  testWidgets('Painoehdotus: Paras 6 vk näyttää 6 viikon parhaan sarjan, Pois ei korttia (käyttäjä 25.11.)', (
    tester,
  ) async {
    addTearDown(() => settings.suggestMode = 'suggest');
    Workout w(DateTime d, List<SetEntry> sets) =>
        Workout(date: d, title: 'X')..exercises.add(ExerciseEntry('Penkkipunnerrus', sets));
    store.workouts = [
      w(DateTime(2026, 9, 20), [SetEntry(100, 3, rir: 1)]), // yli 6 viikkoa sitten: ei mukana
      w(DateTime(2026, 10, 20), [SetEntry(40, 10, warmup: true), SetEntry(85, 5, rir: 1), SetEntry(80, 6, rir: 2)]),
      w(DateTime(2026, 11, 12), [SetEntry(60, 10, rir: 3), SetEntry(60, 10, rir: 3)]), // kevyt viimeisin kerta
    ];
    Future<void> show() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: SetLoggerScreen(
            date: DateTime(2026, 11, 17),
            entry: ExerciseEntry('Penkkipunnerrus', []),
            target: Target(3, 6, 10, '2–3', 150, '3 × 6–10'),
            onChanged: () async {},
          ),
        ),
      );
      await tester.pump();
    }

    settings.suggestMode = 'best';
    await show();
    expect(find.text('Paras 6 vk'), findsOneWidget);
    expect(row(tester, 'bestRow'), '85 kg × 5', reason: 'kevyt viimeisin kerta ei ratkaise, yli 6 vk vanha ei mukana');
    expect(find.textContaining('20.10.'), findsOneWidget);
    // Ohjelman tavoite ja laskuri pienempänä toisella rivillä (yötesti 26.11.).
    expect(row(tester, 'targetRow'), startsWith('3 × 6–10'));
    expect(find.byKey(const ValueKey('targetCount')), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    expect(find.byKey(const ValueKey('suggRow')), findsNothing);
    expect(kg('85'), findsOneWidget, reason: 'paino alkaa 6 viikon parhaasta sarjasta');
    expect(reps('5'), findsOneWidget);

    // Ei 6 viikon parasta (vain yli 6 vk vanhoja tai ei yhtään): tavoite näkyy silti.
    store.workouts = [];
    await show();
    expect(find.text('Paras 6 vk'), findsNothing);
    expect(find.text('0/3'), findsOneWidget);

    settings.suggestMode = 'off';
    store.workouts = [
      w(DateTime(2026, 10, 20), [SetEntry(85, 5, rir: 1)]),
      w(DateTime(2026, 11, 12), [SetEntry(60, 10, rir: 3)]),
    ];
    await show();
    expect(find.text('Paras 6 vk'), findsNothing);
    expect(find.byKey(const ValueKey('targetRow')), findsNothing);
    expect(find.byKey(const ValueKey('lastRow')), findsNothing);
    expect(find.text('Käytä'), findsNothing);
    expect(kg('60'), findsOneWidget, reason: 'Pois: paino alkaa edellisen kerran parhaasta sarjasta');
    expect(tester.takeException(), isNull);
  });
}
