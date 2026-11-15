import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/gps_filter.dart' show TrackPoint;
import 'package:treenipaivakirja/gpx.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/ui/finish_sheet.dart' show EffortFeelingCard;
import 'package:treenipaivakirja/ui/widgets.dart' show ValueStepper, fmtClock;

import 'test_fonts.dart';

// Tallennetun liikunnan lukunäkymä (mockup 10): yhteenvetokortti kaikissa lajeissa, muokkaus avaa säätimet
// ryhmiteltyinä. Keksityt treenit.
void main() {
  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };
  final day = DateTime(2026, 11, 12);

  setUpAll(() async {
    await loadRoboto();
  });
  tearDown(() {
    store.workouts = [];
    debugSetCatalog('fi', const {});
  });

  Workout hcWalk() => Workout(date: day, title: 'Kävely', activity: 'Kävely', distanceKm: 6.5)
    ..seconds = 3 * 3600 + 15 * 60 + 4
    ..minutes = 195
    ..started = DateTime(2026, 11, 12, 7, 51)
    ..steps = 12909
    ..kcal = 454
    ..healthSource = 'UREVO';
  Workout ball() => Workout(date: day, title: 'Koripallo', activity: 'Koripallo', session: 2)
    ..minutes = 53
    ..kcal = 380;
  Workout ride() => Workout(date: day, title: 'Pyöräily', activity: 'Pyöräily', distanceKm: 21, session: 3)
    ..seconds = 3600
    ..minutes = 60;

  Future<void> open(WidgetTester tester, Workout w, {double width = 412, double scale = 1}) async {
    tester.view.physicalSize = Size(width * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    store.workouts = [w];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ActivityScreen(workout: w),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder inSummary(String text) => find.descendant(
    of: find.byKey(const ValueKey('readSummary')),
    matching: find.textContaining(text, findRichText: true),
  );

  testWidgets('Health Connect -kävely: yhteenveto ilman säätimiä, rasitus ja fiilis kortissa', (tester) async {
    await open(tester, hcWalk());
    expect(find.byKey(const ValueKey('readSummary')), findsOneWidget);
    expect(find.byType(ValueStepper), findsNothing, reason: 'ei säätimiä lukunäkymässä');
    expect(find.text('Vaihda laji'), findsNothing);
    for (final s in ['3:15:04', '6,5', '30:01', '12', '454', 'Health Connect · UREVO']) {
      expect(inSummary(s), findsWidgets, reason: s);
    }
    expect(find.byType(EffortFeelingCard), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Laji ilman matkaa (koripallo): vain aika ja kalorit; pyöräily: nopeus vauhdin sijaan', (tester) async {
    await open(tester, ball());
    expect(inSummary('53 min'), findsWidgets);
    expect(inSummary('380'), findsWidgets);
    expect(inSummary('km'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester, ride());
    expect(inSummary('21'), findsWidgets);
    expect(inSummary('km/h'), findsWidgets);
    expect(inSummary('/km'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('GPS-kävely: reittikortti lukunäkymässä yhteenvedon alla', (tester) async {
    final t0 = DateTime.utc(2026, 11, 12, 8);
    final segs = [
      [for (var i = 0; i <= 60; i++) TrackPoint(t0.add(Duration(seconds: i * 30)), 62 + i * .0003, 25.0)],
    ];
    final w = Workout(date: day, title: 'Kävely', activity: 'Kävely', distanceKm: 2)
      ..seconds = 1800
      ..minutes = 30
      ..routeGpx = routeToGpx(segs, name: 'Kävely', type: 'Kävely', raw: segs, rawDistance: 2000);
    await open(tester, w);
    expect(find.byKey(const ValueKey('readSummary')), findsOneWidget);
    expect(find.byKey(const ValueKey('route')), findsOneWidget);
    expect(inSummary('GPS'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('GPS-kävely tauolla: loppuaika reitin viimeisestä pisteestä, ei alku + kesto (testikierros 15.11.)', (
    tester,
  ) async {
    final t0 = DateTime.utc(2026, 11, 12, 8);
    final segs = [
      [for (var i = 0; i <= 60; i++) TrackPoint(t0.add(Duration(seconds: i * 30)), 62 + i * .0003, 25.0)],
    ];
    final w = Workout(date: day, title: 'Kävely', activity: 'Kävely', distanceKm: 2)
      ..started = t0.toLocal()
      ..seconds = 1500 // 5 min taukoa
      ..minutes = 25
      ..routeGpx = routeToGpx(segs, name: 'Kävely', type: 'Kävely', raw: segs, rawDistance: 2000);
    await open(tester, w);
    final end = fmtClock(TimeOfDay.fromDateTime(t0.add(const Duration(minutes: 30)).toLocal()));
    final wrong = fmtClock(TimeOfDay.fromDateTime(t0.add(const Duration(minutes: 25)).toLocal()));
    expect(inSummary(end), findsWidgets);
    expect(inSummary(wrong), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Muokkaa: vahvistuksen jälkeen säätimet ryhmiteltyinä korteiksi', (tester) async {
    await open(tester, hcWalk());
    await tester.tap(find.byKey(const ValueKey('readEdit')));
    await tester.pumpAndSettle();
    expect(find.text('Muokataanko tallennettua treeniä?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Muokkaa'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('readSummary')), findsNothing);
    expect(find.byType(ValueStepper), findsWidgets);
    expect(find.text('Vaihda laji'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // Teksti ei katkea yhteenvedossa: kielet, kapea ja leveä puhelin, tavallinen ja iso teksti.
  for (final lang in ['fi', 'en', 'se']) {
    for (final (width, scale) in [(360.0, 1.0), (360.0, 1.3), (412.0, 1.0), (412.0, 1.3)]) {
      testWidgets('$lang ${width.round()} dp ${(scale * 100).round()} %: yhteenveto', (tester) async {
        debugSetCatalog(lang, lang == 'fi' ? const {} : po[lang]!);
        final w = hcWalk()..hrAvg = 112;
        await open(tester, w, width: width, scale: scale);
        final card = tester.renderObject<RenderBox>(find.byKey(const ValueKey('readSummary')));
        void walk(RenderObject o) {
          if (o is RenderParagraph) expect(o.didExceedMaxLines, isFalse, reason: o.text.toPlainText());
          if (o is RenderFittedBox && o.child != null && o.child!.hasSize && o.hasSize) {
            final c = o.child!.size;
            final f = [o.size.width / c.width, o.size.height / c.height, 1.0].reduce((a, b) => a < b ? a : b);
            expect(f, greaterThanOrEqualTo(.75));
          }
          o.visitChildren(walk);
        }

        walk(card);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
