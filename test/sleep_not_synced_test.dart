import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/recovery.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart';

// Tämän yön uni ei vielä Health Connectissa (käyttäjä 24.11.: Ouraa ei ole avattu aamulla): edellinen yö näkyy
// harmaana omalla nimellään, ei vihjeitä eikä Palautumisen väriä siitä. Keksityt yöt.
void main() {
  final today = dateOnly(DateTime.now());
  SleepNight n(int daysAgo, int min) => SleepNight(
    addDays(today, -daysAgo),
    DateTime(today.year, today.month, today.day - daysAgo - 1, 23),
    DateTime(today.year, today.month, today.day - daysAgo, 7),
    Duration(minutes: min),
    app: 'Sormus',
  );
  final base = {for (var i = 2; i < 30; i++) addDays(today, -i): n(i, 450)};

  test('tämän yön uni: tuore; vain edellinen yö: ei tuore, ei vihjettä eikä väriä', () {
    final withToday = sleepStats({...base, addDays(today, -1): n(1, 450), today: n(0, 340)}, today);
    expect(withToday.fresh, isTrue);
    expect(sleepHint(withToday), SleepHint.short);
    expect(sleepTileState(withToday), TileState.red);

    // Eilinen lyhyt yö, tämän yön uni puuttuu: näytetään, mutta vanhana.
    final stale = sleepStats({...base, addDays(today, -1): n(1, 340)}, today);
    expect(stale.last!.day, addDays(today, -1));
    expect(stale.fresh, isFalse);
    expect(sleepHint(stale), SleepHint.ok);
    expect(sleepTileState(stale), TileState.none);
    expect(sleepStats({}, today).fresh, isFalse);
  });

  test('yön nimi: nukkumaanmenon ja heräämisen viikonpäivät', () {
    debugSetCatalog('fi', const {});
    expect(staleNightLabel(DateTime(2026, 11, 23)), 'su–ma');
    expect(staleNightLabel(DateTime(2026, 11, 23, 7, 30)), 'su–ma');
  });

  group('Uni-kortti', () {
    late Directory dir;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      debugSetCatalog('fi', const {});
      dir = Directory.systemTemp.createTempSync('gievra-sleepstale');
      settings
        ..folder = dir.path
        ..homeHidden = {}
        ..sleepApp = null
        ..sleepSourceAsked = false;
      store.workouts = [];
      sleepData.debugSource = (a, b) async => [];
    });
    tearDown(() {
      sleepData
        ..debugSource = null
        ..conflict = null
        ..loading = false;
      sleepData.nights.clear();
      settings.folder = null;
      dir.deleteSync(recursive: true);
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: SleepCard())),
        ),
      );
      await tester.pump();
    }

    testWidgets('vain edellinen yö: huomautus ja yön nimi, ei vihjettä', (tester) async {
      sleepData.nights.addAll({...base, addDays(today, -1): n(1, 340)});
      await pump(tester);
      expect(find.byKey(const ValueKey('sleepNotYet')), findsOneWidget);
      expect(find.text('viime yö'), findsNothing);
      expect(find.text('yö ${staleNightLabel(addDays(today, -1))}'), findsOneWidget);
      expect(find.byKey(const ValueKey('sleepTip')), findsNothing);
    });

    testWidgets('tämän yön uni: ei huomautusta', (tester) async {
      sleepData.nights.addAll({...base, addDays(today, -1): n(1, 450), today: n(0, 440)});
      await pump(tester);
      expect(find.byKey(const ValueKey('sleepNotYet')), findsNothing);
      expect(find.text('viime yö'), findsOneWidget);
    });
  });
}
