import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/ui/home.dart' show showDay;
import 'package:treenipaivakirja/ui/home_extras_ui.dart';

// Unen lähde (käyttäjä 19.11.): Uni-kortti kysyy kerran, kun kaksi sovellusta kirjasi saman yön; kalenterin päivästä
// yksittäisen yön lähteen voi vaihtaa. Keksityt yöt.
void main() {
  final t0 = dateOnly(DateTime.now());
  late Directory dir;
  SleepSession s(String app, int h) => SleepSession(
    DateTime(t0.year, t0.month, t0.day - 1, 23),
    DateTime(t0.year, t0.month, t0.day - 1, 23 + h),
    app: app,
  );
  SleepNight n(String app, int h) => SleepNight(
    t0,
    DateTime(t0.year, t0.month, t0.day - 1, 23),
    DateTime(t0.year, t0.month, t0.day - 1, 23 + h),
    Duration(hours: h),
    app: app,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugSetCatalog('fi', const {});
    dir = Directory.systemTemp.createTempSync('gievra-sleepsrc');
    settings
      ..folder = dir.path
      ..homeHidden = {}
      ..sleepApp = null
      ..sleepSourceAsked = false;
    store.workouts = [];
    sleepData.debugSource = (a, b) async => [s('Kello', 6), s('Oura', 7)];
  });
  tearDown(() {
    sleepData
      ..debugSource = null
      ..conflict = null
      ..loading = false;
    sleepData.nights.clear();
    settings
      ..folder = null
      ..sleepApp = null
      ..sleepSourceAsked = false;
    dir.deleteSync(recursive: true);
  });

  testWidgets('Uni-kortti: kysymys molemmin arvoin, valinta on oletus eikä kysytä uudelleen', (tester) async {
    sleepData.nights[t0] = n('Kello', 6);
    sleepData.conflict = [n('Kello', 6), n('Oura', 7)];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SleepCard())),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('sleepSourceQuestion')), findsOneWidget);
    expect(find.text('6 h 00 min'), findsWidgets);
    expect(find.text('7 h 00 min'), findsWidgets);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('sleepSourcePick_Oura')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect((settings.sleepApp, settings.sleepSourceAsked), ('Oura', true));
    expect(find.byKey(const ValueKey('sleepSourceQuestion')), findsNothing);
  });

  testWidgets('kalenterin päivä: uni ja Vaihda lähde vain tälle yölle', (tester) async {
    sleepData.nights[t0] = n('Kello', 6);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showDay(context, t0), child: const Text('avaa')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('Uni 6 h 00 min'), findsOneWidget);
    expect(find.byKey(const ValueKey('daySleepChange')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daySleepChange')));
    await tester.pumpAndSettle();
    expect(find.text('Yön lähde'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('nightSource_Oura')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(sleepData.nights[t0]!.app, 'Oura');
    expect(sleepData.nights[t0]!.picked, isTrue);
    expect(settings.sleepApp, isNull, reason: 'oletus ei muutu');
    expect(find.text('Uni 7 h 00 min'), findsOneWidget);
    expect(find.textContaining('Oura (valittu)'), findsOneWidget);
  });
}
