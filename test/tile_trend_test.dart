import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart';
import 'package:treenipaivakirja/ui/tile_trend.dart';

// Palautuminen-ruudun käyrä (käyttäjä 19.11., vaihtoehto C): jokainen ruutu avaa paneelin, jossa 30 päivää tai
// 12 viikkoa; poikkeavassa ruudussa neuvo käyrän alla. Keksityt yösykkeet.
void main() {
  final now = dateOnly(DateTime.now());
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugSetCatalog('fi', const {});
    store.workouts = [];
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: NightHrCard()))));
    await tester.pump();
  }

  testWidgets('vihreä yösyke: napautus avaa käyrän ilman neuvoa; 12 vk -valinta', (tester) async {
    NightHrData.debugNights = {for (var i = 0; i < 40; i++) addDays(now, -i): 50 + (i % 3)};
    await pump(tester);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nightTile_nighthr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tileTrend')), findsOneWidget);
    expect(find.text('Vihreä vyö: tavallinen vaihtelusi.'), findsOneWidget);
    expect(find.textContaining('Keskiarvo: 7 pv'), findsOneWidget);
    expect(find.text('Mitä se voi tarkoittaa'), findsNothing, reason: 'neuvo vain poikkeavassa ruudussa');
    await tester.tap(find.byKey(const ValueKey('trend12')));
    await tester.pumpAndSettle();
    expect(find.text('Viikkokeskiarvot 12 viikolta.'), findsOneWidget);
    expect(find.text('tämä viikko'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('punainen yösyke: käyrä ja neuvo samassa paneelissa', (tester) async {
    NightHrData.debugNights = {
      for (var i = 3; i < 30; i++) addDays(now, -i): 50,
      for (var i = 0; i < 3; i++) addDays(now, -i): 57,
    };
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('nightTile_nighthr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tileTrend')), findsOneWidget);
    expect(find.text('Yösyke selvästi koholla'), findsOneWidget);
    expect(find.text('Mitä se voi tarkoittaa'), findsOneWidget);
  });

  testWidgets('vähän öitä: ei käyrää vaan maininta', (tester) async {
    NightHrData.debugNights = {now: 52};
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('nightTile_nighthr')));
    await tester.pumpAndSettle();
    expect(find.text('Liian vähän tietoa käyrään.'), findsOneWidget);
  });

  test('kuormitus: viikkosummat, treenitön viikko nollana, ennen ensimmäistä tyhjä', () {
    final d = {addDays(now, -20): 100.0, addDays(now, -19): 50.0, now: 30.0};
    final w = tileWeeks('load', d, now);
    expect(w, hasLength(12));
    expect(w.first, isNull);
    expect(w.last, 30);
    expect(w.whereType<double>().fold(0.0, (a, b) => a + b), 180);
    final avg = tileWeeks('nighthr', {now: 50, addDays(now, -1): 52}, now);
    expect(avg.whereType<double>(), isNotEmpty);
  });
}
