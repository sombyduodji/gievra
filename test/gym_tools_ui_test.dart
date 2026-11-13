import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/plates.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/progression.dart';
import 'package:treenipaivakirja/ui/plate_sheet.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Uusien salityökalujen käyttöliittymä: levylaskuri, prosentit, pudotus/AMRAP, supersarjojen luonti, kielet.
// Keksityt treenit ja painot.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    settings
      ..program = null
      ..pauses = []
      ..plates = [...defaultPlates]
      ..barKg = defaultBarKg
      ..weightStep = 2.5
      ..restTimer = false;
    debugSetCatalog('fi', const {});
  });

  Future<void> tall(WidgetTester tester, {double width = 1080}) async {
    tester.view.physicalSize = Size(width, 7000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<ExerciseEntry> logger(WidgetTester tester, String name, {List<SetEntry>? sets}) async {
    final e = ExerciseEntry(name, sets);
    await tester.pumpWidget(
      MaterialApp(
        home: SetLoggerScreen(date: DateTime(2026, 11, 12), entry: e, onChanged: () async {}),
      ),
    );
    await tester.pump();
    return e;
  }

  test('Omat levyt ja tanko tallentuvat asetuksiin', () {
    settings.setPlates([20, 10, 5, 1.25], 15);
    final md = settings.settingsToMarkdown();
    expect(md, contains('plates: 20; 10; 5; 1,25'));
    expect(md, contains('bar: 15'));
    settings
      ..plates = [...defaultPlates]
      ..barKg = 20;
    settings.applyMarkdown(md);
    expect(settings.plates, [20, 10, 5, 1.25]);
    expect(settings.barKg, 15);
  });

  testWidgets(
    'Sarjan kirjaus tiiviisti: yksi tietokortti, paino ja toistot vierekkäin, ohje ja mittaustapa ?-painikkeesta',
    (tester) async {
      await tall(tester);
      store.workouts = [
        Workout(
          date: DateTime(2026, 11, 9),
          exercises: [
            ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 8), SetEntry(60, 8), SetEntry(62.5, 7)]),
          ],
        ),
      ];
      await logger(tester, 'Penkkipunnerrus');
      // Edellinen kerta ja ehdotus samassa kortissa; Näin teet ei vie tilaa ylhäällä.
      expect(find.textContaining('Edellinen kerta', findRichText: true), findsOneWidget);
      expect(find.textContaining('Ehdotus'), findsOneWidget);
      expect(find.text('Näin teet'), findsNothing);
      // Paino ja toistot samalla rivillä.
      final w = tester.getCenter(find.text('PAINO'));
      final r = tester.getCenter(find.text('TOISTOT'));
      expect((w.dy - r.dy).abs(), lessThan(1));
      expect(r.dx, greaterThan(w.dx));
      // Lisätiedot kortin napautuksella.
      await tester.tap(find.textContaining('Edellinen kerta', findRichText: true));
      await tester.pump();
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      // Ohje ja mittaustapa.
      await tester.tap(find.byTooltip('Ohje ja mittaustapa'));
      for (var k = 0; k < 6; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Näin teet'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Sekunnit'));
      for (var k = 0; k < 6; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(measureOf('Penkkipunnerrus'), Measure.seconds);
      Navigator.of(tester.element(find.byType(SetLoggerScreen))).pop();
      for (var k = 0; k < 6; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('SEKUNNIT'), findsOneWidget);
      settings.setMeasure('Penkkipunnerrus', Measure.reps);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ei Tallenna vastaamatta -painiketta; tallentamaton sarja: ilmoitus ennen liikkeen valmistumista', (
    tester,
  ) async {
    await tall(tester);
    final e = await logger(tester, 'Penkkipunnerrus');
    expect(find.text('Tallenna vastaamatta'), findsNothing);
    // Ei sarjoja: ilmoitus, OK palaa kirjaukseen.
    await tester.tap(find.text('Merkitse liike valmiiksi'));
    await tester.pumpAndSettle();
    expect(find.text('Viimeistä sarjaa ei ole tallennettu'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(SetLoggerScreen), findsOneWidget);
    // Tallennus vastaamalla, sitten painon muutos ilman tallennusta: taas ilmoitus.
    await tester.tap(find.text('Muutama'));
    await tester.pump();
    expect(e.sets, hasLength(1));
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    await tester.tap(find.text('Merkitse liike valmiiksi'));
    await tester.pumpAndSettle();
    expect(find.text('Viimeistä sarjaa ei ole tallennettu'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(e.sets, hasLength(1), reason: 'ei tallennettu ilman vastausta');
    // Umpikujaton: Merkitse silti sulkee kirjauksen ilman ylimääräistä sarjaa.
    await tester.tap(find.text('Merkitse liike valmiiksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merkitse silti'));
    await tester.pumpAndSettle();
    expect(find.byType(SetLoggerScreen), findsNothing);
    expect(e.sets, hasLength(1));
  });

  testWidgets('Levylaskuri: levyt näkyvät ja omien levyjen muutos päivittää', (tester) async {
    await tall(tester);
    store.workouts = [
      Workout(
        date: DateTime(2026, 11, 9),
        exercises: [
          ExerciseEntry('Takakyykky', [SetEntry(102.5, 5)]),
        ],
      ),
    ];
    await logger(tester, 'Takakyykky', sets: [SetEntry(102.5, 5)]);
    expect(find.text('Levyt / puoli: 25 + 15 + 1,25'), findsOneWidget);
    await tester.tap(find.text('Levyt / puoli: 25 + 15 + 1,25'));
    await tester.pumpAndSettle();
    expect(find.text('Levylaskuri'), findsOneWidget);
    // 15 pois käytöstä: 20 + 20 + 1,25 (vähiten levyjä).
    await tester.tap(find.widgetWithText(FilterChip, '15'));
    await tester.pumpAndSettle();
    expect(settings.plates.contains(15), isFalse);
    expect(find.text('Levyt / puoli: 20 + 20 + 1,25'), findsWidgets, reason: 'vähiten levyjä');
    // Ei tarkalleen: 1,25 pois → lähin paino ja Käytä-painike.
    await tester.tap(find.widgetWithText(FilterChip, '1,25'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lähin: 100 kg'), findsOneWidget);
    await tester.tap(find.text('Käytä 100 kg'));
    await tester.pumpAndSettle();
    expect(find.text('Levyt / puoli: 20 + 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Levyrivi vain tankoliikkeissä', (tester) async {
    await tall(tester);
    await logger(tester, 'Hauiskääntö', sets: [SetEntry(12, 10)]);
    expect(find.byType(PlateLine), findsNothing);
  });

  testWidgets('Prosenttilaskuri: rivin napautus asettaa painon', (tester) async {
    await tall(tester);
    store.workouts = [
      Workout(
        date: DateTime(2026, 11, 9),
        exercises: [
          ExerciseEntry('Penkkipunnerrus', [SetEntry(90, 4, rir: 0)]),
        ],
      ),
    ];
    await logger(tester, 'Penkkipunnerrus', sets: [SetEntry(60, 8)]);
    await tester.tap(find.byTooltip('Prosenttia maksimista'));
    await tester.pumpAndSettle();
    // e1RM 90 × (1 + 4/30) = 102 → pyöristettynä 102,5; 80 % = 82 → 82,5.
    expect(find.textContaining('Arvio kirjatuista sarjoista: 102 kg'), findsOneWidget);
    await tester.tap(find.text('80 %'));
    await tester.pumpAndSettle();
    expect(find.text('Levyt / puoli: 25 + 5 + 1,25'), findsOneWidget, reason: '82,5 kg valittu');
  });

  testWidgets('Pudotussarja: −20 % valmiiksi, AMRAP tallentuu ilman varaa ja palaa tavalliseen', (tester) async {
    await tall(tester);
    final e = await logger(tester, 'Penkkipunnerrus', sets: [SetEntry(100, 5, rir: 1)]);
    await tester.tap(find.text('Pudotus'));
    await tester.pump();
    expect(find.text('Levyt / puoli: 25 + 5'), findsOneWidget, reason: '80 kg');
    await tester.tap(find.text('Ei yhtään'));
    await tester.pump();
    expect(e.sets.last.kind, dropSet);
    expect(e.sets.last.kg, 80);
    await tester.tap(find.text('AMRAP'));
    await tester.pump();
    // Pudotuksista takaisin: työsarjan paino (100), ei pudotuksen jälkeistä 64 kg.
    expect(find.text('Levyt / puoli: 25 + 15'), findsOneWidget, reason: '100 kg');
    expect(find.text('Ei yhtään'), findsNothing);
    expect(find.text('Tallenna vastaamatta'), findsNothing, reason: 'AMRAP: vain yksi tallennuspainike');
    await tester.tap(find.text('Tallenna AMRAP-sarja'));
    await tester.pump();
    expect(e.sets.last.kind, amrapSet);
    expect(e.sets.last.rir, 0);
    expect(find.text('Ei yhtään'), findsOneWidget, reason: 'takaisin tavalliseen');
    expect(find.textContaining('AMRAP'), findsWidgets);
  });

  testWidgets('Supersarjan luonti treenissä ⋮-valikosta', (tester) async {
    await tall(tester);
    final w = Workout(
      date: DateTime(2026, 11, 12),
      title: 'Veto',
      exercises: [
        ExerciseEntry('Leuanveto', [SetEntry(0, 8)]),
        ExerciseEntry('Pystypunnerrus', [SetEntry(40, 8)]),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: w)));
    await tester.pump();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supersarjat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Pystypunnerrus'));
    await tester.pump();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Leuanveto'));
    await tester.pump();
    await tester.tap(find.text('Yhdistä (2)'));
    await tester.pump();
    await tester.tap(find.text('Valmis'));
    await tester.pumpAndSettle();
    expect(w.supersets, [
      ['Pystypunnerrus', 'Leuanveto'],
    ]);
    expect(find.text('Supersarja A'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final lang in ['en', 'se']) {
    testWidgets('Uudet näkymät kielellä $lang kapealla näytöllä ilman ylivuotoa', (tester) async {
      await tall(tester, width: 900); // 300 dp
      final en = parsePo(File('assets/l10n/en.po').readAsStringSync());
      debugSetCatalog(lang, lang == 'en' ? en : parsePo(File('assets/l10n/$lang.po').readAsStringSync()), english: en);
      addTearDown(() => debugSetCatalog('fi', const {}));
      store.workouts = [
        Workout(
          date: DateTime(2026, 11, 9),
          exercises: [
            ExerciseEntry('Takakyykky', [SetEntry(100, 5, rir: 1)]),
          ],
        ),
      ];
      await logger(tester, 'Takakyykky', sets: [SetEntry(101, 5, kind: dropSet)]);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Levyt'), findsNothing, reason: 'ei suomea');
      await tester.tap(find.byType(PlateLine));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'levylaskuri');
      expect(find.textContaining('Omat levyt'), findsNothing);
      Navigator.of(tester.element(find.byType(SetLoggerScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.percent));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'prosentit');
      expect(find.textContaining('Arvio kirjatuista'), findsNothing);
    });
  }

  test('Kahvakuulaohjelmat: vain kuula- tai kehonpainoliikkeitä, ehdotukset kuulakokoina', () {
    for (final kb in kbFocuses.keys) {
      for (final days in [2, 3, 4]) {
        final p = generateProgram(
          goal: 'kunto',
          experience: 'keski',
          days: days,
          minutes: 60,
          injuries: const [],
          equipment: {'kahvakuula'},
          kbFocus: kb,
        );
        expect(p.kbFocus, kb);
        expect(parseProgram(programToMarkdown(p))!.plan.length, p.plan.length, reason: '$kb tallentuu');
        for (final it in p.plan.expand((d) => d.items)) {
          final eq = exerciseEquipment[it.exercise] ?? const {};
          expect(eq.contains(Equip.kahvakuula) || eq.contains(Equip.kehonpaino), isTrue, reason: '$kb: ${it.exercise}');
          expect(isBarbell(it.exercise), isFalse);
          final tg = targetFor(p, it, DateTime(2026, 11, 12));
          expect(tg.sets, greaterThan(0));
        }
        // Veto vähintään puolet työnnöstä (kahvakuulalla ei pystyvetoa).
      }
    }
    // Ehdotus: 15 toistoa, varaa muutama → seuraava kuulakoko.
    store.workouts = [
      Workout(
        date: DateTime(2026, 11, 9),
        exercises: [
          ExerciseEntry('Kahvakuulapystypunnerrus', [SetEntry(16, 15, rir: 1), SetEntry(16, 15, rir: 1)]),
        ],
      ),
    ];
    final s = suggestNext('Kahvakuulapystypunnerrus', DateTime(2026, 11, 12))!;
    expect(kettlebellSizes.contains(s.kg), isTrue);
    expect(s.kg, greaterThan(16));
  });
}
