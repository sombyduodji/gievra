import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/drafts.dart';
import 'package:treenipaivakirja/gps_recorder.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ongoing.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/ui/running_bar.dart';

// Takaisin kesken liikunnan (käyttäjä 17.11.): ajanotto jatkuu taustalla ilman kysymystä, alapalkin palkki palauttaa,
// eikä toinen avattu liikunta sotke käynnissä olevaa. Keksityt treenit.
void main() {
  late Directory tmp;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    AwayActivity.debugReset();
    Ongoing.activity = null;
    tmp = Directory.systemTemp.createTempSync('gievra-tausta');
    ActivityDraft.dirOverride = tmp;
    GpsRecorder.stateDirOverride = tmp;
  });
  tearDown(() {
    ActivityDraft.dirOverride = null;
    GpsRecorder.stateDirOverride = null;
    tmp.deleteSync(recursive: true);
    AwayActivity.debugReset();
    Ongoing.activity = null;
  });

  Workout today(String sport, int session) {
    final now = DateTime.now();
    return Workout(date: DateTime(now.year, now.month, now.day), title: sport, activity: sport, session: session);
  }

  Future<void> app(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: today('Koripallo', 9)))),
              child: const Text('avaa'),
            ),
            bottomNavigationBar: const RunningBar(),
          ),
        ),
      ),
    );
  }

  Future<void> io(WidgetTester tester) => tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));

  testWidgets('Takaisin kesken ajanoton: ei kysymystä, ajanotto ja luonnos jatkuvat, palkki palauttaa', (tester) async {
    await app(tester);
    expect(find.byKey(const ValueKey('runningBar')), findsNothing);
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aloita'));
    await tester.pump(const Duration(seconds: 2));
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 5; i++) {
      await io(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('Tallennetaanko liikunta?'), findsNothing, reason: 'ei Hylkää-kysymystä kesken ajanoton');
    expect(find.byType(ActivityScreen), findsNothing);
    expect(AwayActivity.away, isTrue);
    expect(Ongoing.activity?.paused, isFalse, reason: 'ilmoitus ja kello jatkavat');
    final d = await tester.runAsync(ActivityDraft.load);
    expect(d?.$2['swStart'], isNotNull, reason: 'ajanotto luonnoksessa');
    expect(find.byKey(const ValueKey('runningBar')), findsOneWidget);
    expect(find.text('Koripallo'), findsOneWidget, reason: 'palkissa lajin nimi');

    // Ilmoituksen Tauko näkymän ollessa kiinni: luonnos tauolle.
    await tester.runAsync(AwayActivity.togglePause);
    await tester.pump();
    expect(Ongoing.activity?.paused, isTrue);
    expect(find.textContaining('tauolla'), findsOneWidget);
    await tester.runAsync(AwayActivity.togglePause);
    await tester.pump();
    expect(Ongoing.activity?.paused, isFalse);

    // Palkista takaisin: sama ajanotto jatkuu.
    // Napautus todellisessa ajassa: palautus lukee luonnos- ja GPS-tiedostot.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('runningBar')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 5; i++) {
      await io(tester);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(AwayActivity.away, isFalse);
    expect(find.byKey(const ValueKey('swPause')), findsOneWidget, reason: 'kello käy');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Toinen liikunta kesken taustalla olevan: ei ajanottoa, ei luonnoksen poistoa sulkiessa', (tester) async {
    await app(tester);
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aloita'));
    await tester.pump(const Duration(seconds: 2));
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 5; i++) {
      await io(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(AwayActivity.away, isTrue);
    // Uusi liikunta toisella lajilla (esim. kalenterista): ajanotto ei ole tarjolla, vain ajan syöttö.
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: today('Jooga', 10))));
    await tester.pumpAndSettle();
    expect(find.text('Aloita'), findsNothing);
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 5; i++) {
      await io(tester);
      await tester.pump(const Duration(milliseconds: 300));
    }
    final d = await tester.runAsync(ActivityDraft.load);
    expect(d?.$1.activity, 'Koripallo', reason: 'käynnissä olevan luonnos säilyi');
    expect(Ongoing.activity?.sport, 'Koripallo');
    expect(find.byKey(const ValueKey('runningBar')), findsOneWidget);
    // Taustalla oleva liikunta päättyy testin lopussa: ilmoituksen päivitysajastin pois.
    Ongoing.activity = null;
    AwayActivity.debugReset();
    Ongoing.refresh(); // peruu ajastimen heti; kanavan vastausta ei odoteta testissä
    await tester.pumpWidget(const SizedBox());
  });
}
