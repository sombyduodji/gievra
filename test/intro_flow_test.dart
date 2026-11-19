import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/intro.dart';

import 'test_fonts.dart';

// Ohjelmakyselyn järjestys (päätös 14.11): vammat heti tavoitteen jälkeen, ennätykset vain voimanostolle,
// pikaohjelma = oletukset + vammakysymys + yhteenveto.
void main() {
  setUp(() {
    debugSetCatalog('fi', const {});
    store.workouts = [];
    settings
      ..program = null
      ..style = null
      ..injuries = [];
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox()); // uusi kysely (ei edellisen tilaa)
    await tester.pumpWidget(const MaterialApp(home: IntroScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String s) async {
    await tester.tap(find.text(s).hitTestable().first);
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) => tapText(tester, 'Seuraava');

  /// Sivujen otsikot alusta loppuun valitulla tavoitteella.
  Future<List<String>> walk(WidgetTester tester, String goal) async {
    await open(tester);
    await tapText(tester, 'Aloitan alusta');
    final titles = <String>[];
    for (var i = 0; i < 12; i++) {
      final bar = tester.widget<Text>(find.textContaining(RegExp(r'^Ohjelma \d+/\d+$')).first).data!;
      titles.add(bar);
      if (find.text('Mikä on tavoitteesi?').hitTestable().evaluate().isNotEmpty) {
        await tapText(tester, goal);
        titles.add('tavoite');
      }
      if (find.text('Onko sinulla vammoja tai kipuja?').hitTestable().evaluate().isNotEmpty) titles.add('vammat');
      if (find.text('Ennätykset (valinnainen)').hitTestable().evaluate().isNotEmpty) titles.add('ennätykset');
      if (find.text('Seuraava').hitTestable().evaluate().isEmpty) break;
      await next(tester);
    }
    return titles;
  }

  testWidgets('Täysi kysely: vammat heti tavoitteen jälkeen; ennätykset vain voimanostossa', (tester) async {
    final hyp = await walk(tester, 'Lihaskasvu');
    expect(hyp.indexOf('vammat'), hyp.indexOf('tavoite') + 2, reason: 'tavoite-sivu, sitten vammat: $hyp');
    expect(hyp, isNot(contains('ennätykset')));
    expect(hyp.last, 'Ohjelma 8/8');
    expect(find.text('Aloita ohjelma'), findsOneWidget);

    final pl = await walk(tester, 'Voimanosto');
    expect(pl, contains('ennätykset'));
    expect(pl.last, 'Ohjelma 9/9');
  });

  testWidgets('Saame, kapea näyttö, suuri teksti: Takaisin ja Seuraava eivät katkea kesken sanan (yötesti 19.11.)', (
    tester,
  ) async {
    await loadRoboto();
    final se = parsePo(File('assets/l10n/se.po').readAsStringSync());
    debugSetCatalog('se', se);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: const IntroScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(se['Pikaohjelma'] ?? 'Pikaohjelma').hitTestable().first);
    await tester.pumpAndSettle();
    for (final w in ['Takaisin', 'Seuraava']) {
      final label = se[w]!;
      final p = tester.renderObject<RenderParagraph>(find.text(label));
      final lines = {
        for (final b in p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length))) b.top.round(),
      }.length;
      expect(lines, 1, reason: '$label: $lines riviä');
    }
  });

  testWidgets('Pikaohjelma: vammakysymys ja sitten yhteenveto; Aloita ohjelma tallentaa ohjelman', (tester) async {
    await open(tester);
    await tapText(tester, 'Pikaohjelma');
    expect(find.text('Onko sinulla vammoja tai kipuja?'), findsOneWidget);
    expect(find.text('Ohjelma 2/3'), findsOneWidget);
    await next(tester);
    expect(find.text('Ohjelma 3/3'), findsOneWidget);
    await tapText(tester, 'Aloita ohjelma');
    await tester.pumpAndSettle();
    expect(settings.program, isNotNull);
    expect(settings.program!.days, 3);
    // Pikaohjelma ei huomauta omasta viikon sarjamäärästään (yötesti 18.–19.11.): uudelle käyttäjälle aloittelijan
    // taso, 3 × 60 min, ja suositus täyttyy.
    expect((settings.program!.experience, settings.program!.minutes), ('aloittelija', 60));
    expect(meetsWeeklyTargets(settings.program!), isTrue);
    expect(settings.program!.notes.where((n) => n.startsWith('Viikon sarjamäärä')), isEmpty);
  });

  testWidgets('Pikaohjelma tallennetulla keskitasolla 3 × 60 min: treeni pitenee, jotta viikon suositus täyttyy',
      (tester) async {
    settings.style = TrainingStyle(goal: 'lihaskasvu', experience: 'keski', days: 3, minutes: 60);
    await open(tester);
    await tapText(tester, 'Pikaohjelma');
    await next(tester);
    await tapText(tester, 'Aloita ohjelma');
    await tester.pumpAndSettle();
    expect((settings.program!.experience, settings.program!.minutes), ('keski', 75));
    expect(meetsWeeklyTargets(settings.program!), isTrue);
    expect(settings.program!.notes.where((n) => n.startsWith('Viikon sarjamäärä')), isEmpty);
  });

  testWidgets('Pikaohjelmasta takaisin ja Aloitan alusta: täysi kysely', (tester) async {
    await open(tester);
    await tapText(tester, 'Pikaohjelma');
    await tapText(tester, 'Takaisin');
    await tapText(tester, 'Aloitan alusta');
    expect(find.text('Mikä on tavoitteesi?'), findsOneWidget);
    expect(find.text('Ohjelma 2/8'), findsOneWidget);
  });

  testWidgets('Järjestelmän Takaisin palaa edelliselle sivulle, ei poistu kyselystä (päivätesti 14.11.)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Text('pohja')));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const IntroScreen()));
    await tester.pumpAndSettle();
    await tapText(tester, 'Aloitan alusta');
    expect(find.text('Ohjelma 2/8'), findsOneWidget);
    await next(tester);
    expect(find.text('Ohjelma 3/8'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ohjelma 2/8'), findsOneWidget, reason: 'yksi sivu taaksepäin');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ohjelma 1/8'), findsOneWidget);
    expect(find.byType(IntroScreen), findsOneWidget, reason: 'vielä kyselyssä');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsNothing, reason: 'ensimmäiseltä sivulta poistutaan');
  });

  testWidgets('Nopeat Takaisin-painallukset kesken siirtymän: jokainen vie sivun taaksepäin, ei poistu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Text('pohja')));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const IntroScreen()));
    await tester.pumpAndSettle();
    await tapText(tester, 'Aloitan alusta');
    await next(tester);
    expect(find.text('Ohjelma 3/8'), findsOneWidget);
    // Kolme painallusta 50 ms välein (siirtymä kestää 250 ms): puhelimella vain yksi sivu taaksepäin ennen korjausta.
    for (var k = 0; k < 3; k++) {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('Ohjelma 1/8'), findsOneWidget);
    expect(find.byType(IntroScreen), findsOneWidget, reason: 'ylimääräinen painallus ei poistu kyselystä');
  });

  testWidgets('Ohjelmasivulta avattu kysely: Peruuta ja Aloita ohjelma sulkevat sen (Takaisin-muutoksen jälkeen)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    // Ohjelma tallentuu tiedostoon: oikea väliaikainen kansio (ilman sitä tallennus ei etene testissä).
    final dir = Directory.systemTemp.createTempSync('gievra-kysely');
    settings.folder = dir.path;
    addTearDown(() {
      settings.folder = null;
      dir.deleteSync(recursive: true);
    });
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Text('pohja')));
    // Peruuta kesken kyselyn (sivu 2): kysely sulkeutuu, ohjelmaa ei tehdä.
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const IntroScreen()));
    await tester.pumpAndSettle();
    await tapText(tester, 'Aloitan alusta');
    expect(find.text('Ohjelma 2/8'), findsOneWidget);
    await tapText(tester, 'Peruuta');
    expect(find.byType(IntroScreen), findsNothing, reason: 'Peruuta sulkee kyselyn myös sivulla 2');
    expect(settings.program, isNull);
    // Pikaohjelma loppuun: Aloita ohjelma tallentaa ja sulkee kyselyn.
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const IntroScreen()));
    await tester.pumpAndSettle();
    await tapText(tester, 'Pikaohjelma');
    await next(tester);
    await tapText(tester, 'Aloita ohjelma');
    // Ohjelman tallennus kirjoittaa tiedoston (oikea levy-IO ei etene testin keinokellolla): annetaan aikaa.
    for (var i = 0; i < 20 && find.byType(IntroScreen).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsNothing, reason: 'Aloita ohjelma sulkee kyselyn (PopScope ei estä)');
    expect(settings.program, isNotNull);
    expect(find.text('pohja'), findsOneWidget);
  });
}
