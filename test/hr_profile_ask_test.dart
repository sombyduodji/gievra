import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/hr_calc.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/drawer.dart';
import 'package:treenipaivakirja/ui/hr_ui.dart';
import 'package:treenipaivakirja/ui/watch.dart';

// Omat tiedot kellon sykkeelle (käyttäjä 15.11.): kortin Lisää tiedot -painike, syntymävuosi riittää alueisiin,
// valinnainen oma maksimisyke, kysymys kerran haun jälkeen. Keksityt tiedot.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings
      ..birthYear = null
      ..sex = null
      ..maxHr = null
      ..hrProfileAsked = false
      ..body = BodyLog();
  });
  tearDown(() {
    settings
      ..birthYear = null
      ..sex = null
      ..maxHr = null
      ..hrProfileAsked = false
      ..body = BodyLog();
  });

  Workout watchWorkout() => Workout(date: DateTime(2026, 3, 5), title: 'Treeni')
    ..minutes = 72
    ..hrSource = 'kello'
    ..healthSource = 'Health Sync'
    ..hrSeries = HrSeries.decode('5 17:46:00 110 112 115 118 120 138', DateTime(2026, 3, 5));

  Future<void> pump(WidgetTester tester, Workout w) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: HrDetails(w))),
      ),
    );
  }

  testWidgets('kortin Lisää tiedot: pelkkä syntymävuosi tallentuu, alueet näkyvät heti', (tester) async {
    await pump(tester, watchWorkout());
    expect(find.textContaining('Sykealueisiin tarvitaan syntymävuosi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hrProfileAdd')));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Tallenna');
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'ilman syntymävuotta ei tallenneta');
    await tester.enterText(find.byKey(const ValueKey('birthYear')), '1985');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull, reason: 'syntymävuosi riittää');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(settings.birthYear, 1985);
    expect(settings.sex, isNull);
    expect(find.textContaining('Sykealueisiin tarvitaan'), findsNothing);
    expect(find.textContaining('arvio iästä'), findsOneWidget);
  });

  testWidgets('oma maksimisyke: virheellinen estää tallennuksen, kelvollinen käytetään (oma mittaus)', (tester) async {
    await pump(tester, watchWorkout());
    await tester.tap(find.byKey(const ValueKey('hrProfileAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('birthYear')), '1985');
    await tester.enterText(find.byKey(const ValueKey('maxHrField')), '90');
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Tallenna');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.text('120–230'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('maxHrField')), '186');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(settings.maxHr, 186);
    expect(find.textContaining('oma mittaus'), findsOneWidget);
  });

  testWidgets('virheellinen pituus tai paino estää tallennuksen kuten maksimisyke (yötesti 25.11.)', (tester) async {
    await pump(tester, watchWorkout());
    await tester.tap(find.byKey(const ValueKey('hrProfileAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('birthYear')), '1985');
    await tester.enterText(find.byKey(const ValueKey('heightCm')), '5');
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Tallenna');
    expect(find.text('100–250'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('heightCm')), '178');
    await tester.enterText(find.byKey(const ValueKey('weightKg')), '0');
    await tester.pump();
    expect(find.text('20–400'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('weightKg')), '');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(settings.birthYear, 1985);
    expect(settings.body.heightCm, 178);
  });

  testWidgets('Ei nyt: mitään ei tallenneta, painike jää', (tester) async {
    await pump(tester, watchWorkout());
    await tester.tap(find.byKey(const ValueKey('hrProfileAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ei nyt'));
    await tester.pumpAndSettle();
    expect(settings.birthYear, isNull);
    expect(find.byKey(const ValueKey('hrProfileAdd')), findsOneWidget);
  });

  test('haun jälkeen kysytään kerran: vain käyrän kanssa, ilman omia tietoja, ei uudelleen', () {
    final w = watchWorkout();
    expect(shouldAskHrProfile(w), isTrue);
    expect(
      shouldAskHrProfile(Workout(date: DateTime(2026, 3, 5), title: 'Treeni')),
      isFalse,
      reason: 'ei käyrää',
    );
    settings.markHrProfileAsked();
    expect(shouldAskHrProfile(w), isFalse, reason: 'kysytty jo');
    settings.hrProfileAsked = false;
    settings.birthYear = 1985;
    expect(shouldAskHrProfile(w), isFalse, reason: 'tiedot on jo');
  });

  test('yhteenveto: puuttuvat kehotetaan, osittaiset näytetään, maksimi oma tai arvio iästä', () {
    expect(hrProfileSummary(), 'Lisää syntymävuosi, sukupuoli, pituus ja paino');
    final y = DateTime.now().year - 40;
    settings.birthYear = y;
    expect(hrProfileSummary(), '40 v · maksimisyke n. ${(208 - 0.7 * 40).round()}');
    settings.maxHr = 186;
    settings.sex = 'mies';
    expect(hrProfileSummary(), '40 v · mies · maksimisyke n. 186');
  });

  testWidgets('Asetukset → Keho ja laitteet: Sykealueet ja kalorit myös ilman sykevyötä; tallennus päivittää rivin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.text('Keho ja laitteet'));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('hrProfileSettings'));
    expect(
      find.descendant(of: tile, matching: find.text('Lisää syntymävuosi, sukupuoli, pituus ja paino')),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('birthYear')), '${DateTime.now().year - 40}');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Tallenna'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: tile, matching: find.textContaining('40 v')), findsOneWidget);
  });
}
