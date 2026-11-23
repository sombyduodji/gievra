import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/ui/sleep_stages_ui.dart';

// Univaiheet (käyttäjä 23.11.): näytetään unen paneelissa, unen määrä lasketaan kuten ennenkin. Keksitty yö.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const min = 60 * 1000;
  final bed = DateTime(2026, 3, 1, 22, 0), wake = DateTime(2026, 3, 2, 6, 30); // 8 h 30 min
  SleepSession session({String app = 'Sormus', DateTime? s, DateTime? e}) => SleepSession(
    s ?? bed,
    e ?? wake,
    awake: const Duration(minutes: 90),
    app: app,
    // kevyt 4 h 40 min, syvä 1 h, REM 1 h 20 min, hereillä 80 min + sängyssä hereillä 10 min (yht. 8 h 30 min)
    stageMs: {4: 280 * min, 5: 60 * min, 6: 80 * min, 1: 80 * min, 7: 10 * min},
  );
  final night = SleepNight(DateTime(2026, 3, 2), bed, wake, const Duration(hours: 7), app: 'Sormus');

  test('vaiheet yhteen: kevyt, syvä, REM; hereillä = hereillä + hereillä sängyssä', () {
    final s = SleepStages.of([session()]);
    expect(s.light, const Duration(minutes: 280));
    expect(s.deep, const Duration(hours: 1));
    expect(s.rem, const Duration(minutes: 80));
    expect(s.asleep, const Duration(minutes: 420));
    expect(s.awake, const Duration(minutes: 90));
    expect(s.span, const Duration(minutes: 510));
    expect(s.uncovered, Duration.zero);
  });

  test('vaiheeton aika näkyy erikseen; ilman vaiheita tyhjä', () {
    final s = SleepStages.of([
      SleepSession(bed, wake, stageMs: {4: 400 * min}),
    ]);
    expect(s.uncovered, const Duration(minutes: 110));
    expect(SleepStages.of([SleepSession(bed, wake)]).isEmpty, isTrue);
  });

  test('vain yön oma sovellus ja yön aika', () async {
    final s = await nightStages(
      night,
      source: (_, _) async => [
        session(),
        session(app: 'Kello'), // toinen lähde samalta yöltä
        session(s: wake.add(const Duration(hours: 5)), e: wake.add(const Duration(hours: 6))), // päiväunet
      ],
    );
    expect(s!.asleep, const Duration(minutes: 420));
    expect(await nightStages(night, source: (_, _) async => []), isNull);
  });

  testWidgets('paneelissa vaiheet osuuksineen ja Gievran laskutapa', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SleepStagesBox(night: night, source: (_, _) async => [session()]),
          ),
        ),
      ),
    );
    expect(find.text('Haetaan univaiheita…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Kevyt uni'), findsOneWidget);
    expect(find.text('4 h 40 min · 67 %'), findsOneWidget);
    expect(find.text('1 h 20 min · 19 %'), findsOneWidget); // REM
    expect(find.text('Univaiheet yhteensä'), findsOneWidget);
    expect(find.text('7 h 00 min'), findsOneWidget);
    expect(find.text('Hereillä'), findsOneWidget);
    expect(find.text('Sängyssä'), findsOneWidget);
    expect(find.text('Ei vaihetta'), findsNothing);
    expect(find.textContaining('Gievran uni'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ei vaiheita: ilmoitus', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SleepStagesBox(night: night, source: (_, _) async => []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tälle yölle ei ole univaiheita Health Connectissa.'), findsOneWidget);
  });

  testWidgets('kapea näyttö ja tekstikoko 2,0: ei ylivuotoa (testi 23.11.)', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SleepStagesBox(night: night, source: (_, _) async => [session()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sleepStages')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
