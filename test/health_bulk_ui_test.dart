import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/health_bulk_ui.dart';

// Health Connectin joukkotuonnin sivu (yötesti 22.11.): kielletyn luvan jälkeen tarjotaan Health Connectin asetukset
// (Android ei kysy uudelleen), tuonnin painikkeen kaksoisnapautus ei tuo kahdesti, ja kesken erän tullut
// lukuvirhe ei hukkaa jo haettuja. Keksityt harjoitukset, ei oikeita terveystietoja.
const _ch = MethodChannel('fi.somby.gievra/health');

void main() {
  final calls = <MethodCall>[];
  var allow = false;
  var failAfter = -1; // rangeStats heittää tämän monennen kutsun jälkeen (-1 = ei koskaan)
  final now = DateTime.now();
  List<Map<String, Object?>> sessions(int n) => [
    for (var i = 0; i < n; i++)
      {
        'kind': 'session',
        'id': 'test-$i',
        'start': DateTime(now.year, now.month, now.day - 1 - i, 7).millisecondsSinceEpoch,
        'end': DateTime(now.year, now.month, now.day - 1 - i, 7, 40).millisecondsSinceEpoch,
        'title': null,
        'type': 79, // kävely
        'app': 'Testisovellus',
        'pkg': 'com.example.test',
      },
  ];
  var list = sessions(3);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugSetCatalog('fi', const {});
    calls.clear();
    allow = false;
    failAfter = -1;
    list = sessions(3);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_ch, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'status':
          return 'available';
        case 'request' || 'granted':
          return allow;
        case 'historyAvailable':
          return false;
        case 'sessionList':
          return list;
        case 'rangeStats':
          final n = calls.where((c) => c.method == 'rangeStats').length;
          if (failAfter >= 0 && n > failAfter) throw PlatformException(code: 'health', message: 'rate limited');
          return {'hrAvg': 110, 'hrMax': 130, 'kcal': 150};
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_ch, null));

  // Tallennus kirjoittaa oikeisiin tiedostoihin: annetaan oikean ajan kulua välillä.
  Future<void> settle(WidgetTester tester) async {
    for (var k = 0; k < 200; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
      if (k > 10 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync('gievra-bulk');
    settings.folder = dir.path;
    store.workouts = [];
    addTearDown(() {
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HealthBulkImportScreen()));
    await settle(tester);
  }

  testWidgets('Lupa kielletty: Anna lupa, sitten Avaa Health Connect', (tester) async {
    await open(tester);
    expect(find.text('Anna lupa'), findsOneWidget);
    expect(find.text('Avaa Health Connect'), findsNothing);
    await tester.tap(find.text('Anna lupa'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'request'), hasLength(1));
    // Kerran kiellettyä lupaa Android ei kysy uudelleen: painike Health Connectin asetuksiin.
    await tester.tap(find.text('Avaa Health Connect'));
    await tester.pump();
    expect(calls.where((c) => c.method == 'settings'), hasLength(1));
    // Asetuksista palattaessa luvat tarkistetaan uudelleen.
    allow = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('3 uutta harjoitusta'), findsOneWidget);
  });

  testWidgets('Tuo-painikkeen kaksoisnapautus tuo kerran', (tester) async {
    allow = true;
    await open(tester);
    final b = find.byKey(const ValueKey('bulkImport'));
    await tester.tap(b);
    await tester.tap(b, warnIfMissed: false);
    await settle(tester);
    expect(find.text('Tuotiin 3 harjoitusta.'), findsOneWidget);
    expect(store.workouts.where((w) => w.hcId?.startsWith('test-') ?? false), hasLength(3));
    // Uudelleen: kaikki jo Gievrassa.
    await tester.tap(find.text('Näytä lista uudelleen'));
    await settle(tester);
    expect(find.text('0 uutta harjoitusta'), findsOneWidget);
  });

  testWidgets('Lukuvirhe kesken erän: jo haetut tallentuvat', (tester) async {
    allow = true;
    list = sessions(5);
    failAfter = 3;
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('bulkImport')));
    await settle(tester);
    expect(find.text('Tuotiin 3 harjoitusta.'), findsOneWidget);
    expect(find.textContaining('Health Connect keskeytti haun'), findsOneWidget);
    expect(store.workouts.where((w) => w.hcId?.startsWith('test-') ?? false), hasLength(3));
  });
}
