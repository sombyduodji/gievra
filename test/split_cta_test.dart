import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/home.dart';

import 'test_fonts.dart';

// Etusivun jaettu aloituspainike ja paneelit (ui-test 17.11.) ja päivänäkymän Sali/Liikunta-pari: teksti ei katkea millään
// kielellä, puhelimen leveydellä tai tekstikoolla. Oikea fontti (Roboto), koska testifontti on leveämpi kuin puhelimen.
void main() {
  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('gievra-split').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp,
    );
    await loadRoboto();
  });
  tearDown(() {
    debugSetCatalog('fi', const {});
    store.workouts = [];
  });

  final today = dateOnly(DateTime.now());
  Workout gym(int daysAgo) =>
      Workout(date: addDays(today, -daysAgo), title: 'Treeni')
        ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 5)]));
  Workout walk(int daysAgo) => Workout(date: addDays(today, -daysAgo), title: 'Kävely', activity: 'Kävely')
    ..distanceKm = 3
    ..seconds = 2400
    ..minutes = 40;

  final states = <String, List<Workout> Function()>{
    'sali käytetympi': () => [gym(2), gym(3), walk(4)],
    'liikunta käytetympi': () => [gym(2), walk(3), walk(4)],
    'salitreeni kesken': () => [gym(3), Workout(date: today, title: 'Koko keho B')],
  };

  for (final lang in ['fi', 'en', 'se']) {
    for (final (w, scale) in [(360.0, 1.0), (360.0, 1.3), (412.0, 1.0), (412.0, 1.3), (360.0, 2.0), (412.0, 2.0)]) {
      for (final st in states.entries) {
        // Ulkoasun kohennus 16.11.: etusivulla Sali | Liikunta -valitsin ja yksi kortti isolla aloituspainikkeella.
        testWidgets('$lang ${w.round()} dp ${(scale * 100).round()} %: ${st.key}', (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = Size(w * 3, 2400 * 3);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          debugSetCatalog(lang, lang == 'fi' ? const {} : po[lang]!);
          settings
            ..started = true
            ..introDone = true
            ..program = null
            ..trainMode = 'both';
          store.workouts = st.value();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(fontFamily: 'Roboto'),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const HomeScreen(),
            ),
          );
          await tester.pump();
          // Jaettu aloituspainike (ui-test 17.11.): Sali ja Liikunta vierekkäin, teksti ei katkea.
          expect(find.byKey(const ValueKey('homeStartGym')), findsOneWidget);
          expect(find.byKey(const ValueKey('homeStartActivity')), findsOneWidget);
          noCutText(tester);
          // Sali avaa paneelin: vapaa treeni ja kesken oleva treeni (Jatka).
          await tester.tap(find.byKey(const ValueKey('homeStartGym')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('panelFreeWorkout')), findsOneWidget);
          if (st.key == 'salitreeni kesken') {
            expect(find.textContaining(lang == 'en' ? 'Continue' : (lang == 'se' ? 'Joatkke' : 'Jatka')), findsWidgets);
          }
          noCutText(tester);
          Navigator.of(tester.element(find.byKey(const ValueKey('panelFreeWorkout')))).pop();
          await tester.pumpAndSettle();
          // Liikunta avaa paneelin: viimeksi käytetty laji ja kaikki lajit.
          await tester.tap(find.byKey(const ValueKey('homeStartActivity')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('panelAllSports')), findsOneWidget);
          expect(find.byKey(const ValueKey('panelSport_Kävely')), findsOneWidget);
          noCutText(tester);
          // Lajin valinta kysyy kirjaustavan.
          await tester.tap(find.byKey(const ValueKey('panelSport_Kävely')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('panelMode_watch')), findsOneWidget);
          expect(find.byKey(const ValueKey('panelMode_manual')), findsOneWidget);
          noCutText(tester);
          await tester.pumpWidget(const SizedBox());
        });
      }
      testWidgets('$lang ${w.round()} dp ${(scale * 100).round()} %: päivänäkymä 50/50', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(w * 3, 2400 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        debugSetCatalog(lang, lang == 'fi' ? const {} : po[lang]!);
        settings
          ..started = true
          ..introDone = true
          ..program = null
          ..trainMode = 'both';
        store.workouts = [gym(2), gym(3), walk(0)];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const HomeScreen(),
          ),
        );
        await tester.pump();
        showDay(tester.element(find.byType(HomeScreen)), today);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Päivänäkymän painikkeet (etusivu jää reitin alle, joten viimeiset löydöt ovat päivänäkymän).
        final g = tester.getSize(find.byKey(const ValueKey('splitGym')).last).width;
        final a = tester.getSize(find.byKey(const ValueKey('splitActivity')).last).width;
        expect((g - 14 - a).abs(), lessThan(1.5), reason: 'tasan 50/50 (vasemmassa palassa kärki 14 px)');
        checkPieces(tester, last: true);
        if (lang != 'se' && scale == 1.0) expectIcons(tester, emoji: '🚶', last: true);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final lang in ['fi', 'se']) {
    testWidgets('$lang fontti 2,0: ehdotuskortti ohjelman päivällä, teksti ei katkea', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      debugSetCatalog(lang, lang == 'fi' ? const {} : po[lang]!);
      settings
        ..started = true
        ..introDone = true
        ..trainMode = 'both'
        ..program = generateProgram(goal: 'lihaskasvu', experience: 'keski', days: 3, minutes: 60, injuries: const []);
      addTearDown(() => settings.program = null);
      store.workouts = [
        for (var d = 2; d < 9; d++) gym(d),
        for (var i = 0; i < 5; i++)
          Workout(date: today, title: 'Kävely', activity: 'Kävely', session: i + 1)
            ..minutes = 17
            ..feeling = 4,
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      );
      await tester.pump();
      // Ehdotettu päivä näkyy Sali-puolen vihjeenä ja paneelin ehdotuskortissa (ui-test 17.11.).
      final names = settings.program!.plan.map((d) => d.uiName).toSet();
      expect(find.byWidgetPredicate((w) => w is Text && names.contains(w.data)), findsWidgets);
      expect(find.byKey(const ValueKey('homeStartGym')), findsOneWidget);
      noCutText(tester);
      await tester.tap(find.byKey(const ValueKey('homeStartGym')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('panelStartSuggested')), findsOneWidget);
      noCutText(tester);
      debugSetCatalog('fi', const {});
    });
  }
}

/// Mikään teksti ei katkea ("…" tai rivit loppuvat).
void noCutText(WidgetTester tester) {
  for (final p in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
  }
}

void checkPieces(WidgetTester tester, {bool last = false}) {
  for (final key in ['splitGym', 'splitActivity']) {
    final all = find.byKey(ValueKey(key));
    final piece = last ? all.last : all;
    if (!last) expect(all, findsOneWidget, reason: key);
    final box = tester.renderObject<RenderBox>(piece);
    var titles = 0;
    void walkTree(RenderObject o) {
      if (o is RenderFittedBox && o.child != null && o.child!.hasSize && o.hasSize) {
        final c = o.child!.size;
        final f = [o.size.width / c.width, o.size.height / c.height, 1.0].reduce((a, b) => a < b ? a : b);
        // Enintään 130 %: vähintään 80 %. Isompi fontti (2,0): saa pienentää, kunhan teksti on vähintään normaalikokoinen.
        final ts = MediaQuery.textScalerOf(tester.element(piece)).scale(1);
        expect(
          f * (ts > 1.3 ? ts : 1),
          greaterThanOrEqualTo(ts > 1.3 ? 1.0 : .8),
          reason: '$key: otsikko pienenee liikaa',
        );
        titles++;
      }
      if (o is RenderParagraph) {
        expect(o.didExceedMaxLines, isFalse, reason: '$key: ${o.text.toPlainText()}');
        // Teksti näkyy kokonaan palan sisällä.
        // Näytöllä oleva koko (FittedBoxin pienennys mukana).
        final r = MatrixUtils.transformRect(o.getTransformTo(null), Offset.zero & o.size);
        final b = box.localToGlobal(Offset.zero) & box.size;
        expect(
          b.inflate(.5).contains(r.topLeft) && b.inflate(.5).contains(r.bottomRight),
          isTrue,
          reason: '$key: "${o.text.toPlainText()}" palan ulkopuolella',
        );
      }
      o.visitChildren(walkTree);
    }

    walkTree(box);
    expect(titles, greaterThanOrEqualTo(1), reason: '$key: otsikko puuttuu');
  }
  // Otsikot samalla korkeudella (käyttäjä 15.11.) ja kummallakin puolella yksi tekstirivi (ei alarivejä).
  double titleCenter(String key) {
    final all = find.byKey(ValueKey(key));
    final piece = last ? all.last : all;
    final ps = tester
        .renderObjectList<RenderParagraph>(find.descendant(of: piece, matching: find.byType(RichText)))
        .where((p) => RegExp(r'\p{L}', unicode: true).hasMatch(p.text.toPlainText())) // kuvakkeet ja emoji pois
        .toList();
    expect(ps, hasLength(1), reason: '$key: yksi otsikko, ei alariviä');
    final r = MatrixUtils.transformRect(ps.single.getTransformTo(null), Offset.zero & ps.single.size);
    return r.center.dy;
  }

  expect(
    (titleCenter('splitGym') - titleCenter('splitActivity')).abs(),
    lessThan(.5),
    reason: 'otsikot eri korkeudella',
  );
}

/// Kuvakkeet näkyvissä: Sali-puolella käsipaino tai ▶, Liikunta-puolella lajin emoji.
void expectIcons(WidgetTester tester, {required String emoji, bool open = false, bool last = false}) {
  Finder inPiece(String key, Finder f) {
    final all = find.byKey(ValueKey(key));
    return find.descendant(of: last ? all.last : all, matching: f);
  }

  expect(
    inPiece('splitGym', find.byIcon(open ? Icons.play_arrow_rounded : Icons.fitness_center_rounded)),
    findsOneWidget,
  );
  expect(inPiece('splitActivity', find.text(emoji)), findsOneWidget);
}
