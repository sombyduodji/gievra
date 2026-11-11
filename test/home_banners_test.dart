import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/injury_screen.dart';

// Vammatila ja tauko näkyvät etusivun yläreunassa vain, kun ne ovat päällä. Keksityt valinnat.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    settings.injuries = [];
    settings.pauses = [];
  });

  Future<void> home(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Ei tilarivejä, kun vammatila ja tauko ovat pois', (tester) async {
    await home(tester);
    expect(find.text('Vammatila'), findsNothing);
    expect(find.textContaining('Sairastat'), findsNothing);
    expect(find.textContaining('Lomalla'), findsNothing);
  });

  testWidgets('Vammatila ylhäällä: alueet näkyvät ja napautus avaa vammatilan', (tester) async {
    settings.injuries = ['polvi_etu'];
    await home(tester);
    expect(find.text('Vammatila'), findsOneWidget);
    await tester.tap(find.text('Vammatila'));
    await tester.pumpAndSettle();
    expect(find.byType(InjuryScreen), findsOneWidget);
  });

  testWidgets('Sairasloma ylhäällä: napautus näyttää tiedot ja tauon voi lopettaa', (tester) async {
    settings.startPause('sairas', DateTime(2026, 11, 7));
    await home(tester);
    expect(find.text('Sairastat – parane pian!'), findsOneWidget);
    expect(find.text('Alkoi 7.11.2026'), findsOneWidget);
    await tester.tap(find.text('Sairastat – parane pian!'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Älä treenaa kuumeisena'), findsOneWidget);
    await tester.tap(find.text('Lopeta tauko'));
    await tester.pumpAndSettle();
    expect(settings.activePause, isNull);
    expect(find.textContaining('Sairastat'), findsNothing);
  });

  testWidgets('Loma ylhäällä', (tester) async {
    settings.startPause('loma', DateTime(2026, 11, 9));
    await home(tester);
    expect(find.text('Lomalla – nauti!'), findsOneWidget);
  });

  testWidgets('Vammatilan rivillä lyhyet alueiden nimet kerran kukin', (tester) async {
    // "Polvi (kierukka / eturistiside), lyhyesti": "lyhyesti" näytti omalta alueeltaan.
    settings.injuries = ['polvi_kierukka_ristiside', 'olkapaa_kiertajakalvosin', 'olkapaa_epavakaus', 'ranne'];
    await home(tester);
    expect(find.text('Polvi, Olkapää, Ranne / käsi'), findsOneWidget);
  });

  test('Lyhyt nimi jokaiselle alueelle suomeksi ja englanniksi', () {
    final en = parsePo(File('assets/l10n/en.po').readAsStringSync());
    for (final cat in [const <String, String>{}, en]) {
      debugSetCatalog(cat.isEmpty ? 'fi' : 'en', cat);
      for (final r in injuryRegions) {
        final s = injuryShortName(t(r.name));
        expect(s, isNotEmpty, reason: r.id);
        expect(s.contains('(') || s.contains(','), isFalse, reason: s);
      }
    }
    debugSetCatalog('fi', const {});
    expect(injuryShortName('Knee (meniscus / ACL), in brief'), 'Knee');
  });

  testWidgets('Tuntematon alue: ei näytetä tunnusta; pelkkä tuntematon ei avaa vammatilaa', (tester) async {
    settings.injuries = ['vanha_alue', 'ranne'];
    await home(tester);
    expect(find.text('Ranne / käsi'), findsOneWidget);
    expect(find.textContaining('vanha_alue'), findsNothing);
    settings.setInjuries(['vanha_alue']);
    await tester.pump();
    expect(find.text('Vammatila'), findsNothing);
  });
}
