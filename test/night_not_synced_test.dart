import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/home_layout.dart' show homeCardsOffByDefault;
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/recovery.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart' show NightHrData, NightMetricsCard, staleNightLabel;
import 'package:treenipaivakirja/ui/recovery_card.dart';

// Tämän yön yösyke ja HRV eivät vielä Health Connectissa (yötesti 25.–26.11.): edellisen yön arvoa ei näytetä
// tämän päivän palautumisena eikä väritetä, kuten Uni-ruudussa. Keksityt arvot.
void main() {
  setUpAll(() {
    final tmp = Directory.systemTemp.createTempSync('gievra-night').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp,
    );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugSetCatalog('fi', const {});
    settings.homeHidden = {};
  });
  tearDown(() {
    NightHrData.debugNights = const {};
    sleepData.metrics.clear();
    settings.homeHidden = {...homeCardsOffByDefault};
  });

  // [lastAgo] = montako päivää sitten viimeisin yö; viimeisin yö poikkeaa selvästi (syke +8, HRV puolet).
  void data(DateTime now, int lastAgo) {
    NightHrData.debugNights = {for (var i = lastAgo; i < 30; i++) addDays(now, -i): i == lastAgo ? 60 : 50 + i % 2};
    sleepData.metrics.addAll({
      for (var i = lastAgo; i < 40; i++)
        addDays(now, -i): NightMetrics(hrv: i == lastAgo ? 25 : 50.0 + i % 3, rest: 50, rr: 14, spo2: 96, temp: 0),
    });
  }

  test('Palautuminen: vanha yö "ei vielä", harmaa; tämän yön arvo väritetään', () {
    final now = dateOnly(DateTime.now());
    data(now, 1);
    var tiles = {for (final x in recoveryTiles(now.add(const Duration(hours: 8)))) x.key: x};
    for (final k in ['nighthr', 'hrv']) {
      expect((tiles[k]!.value, tiles[k]!.sub, tiles[k]!.state), ('–', 'ei vielä', TileState.none), reason: k);
    }
    NightHrData.debugNights = const {};
    sleepData.metrics.clear();
    data(now, 0);
    tiles = {for (final x in recoveryTiles(now.add(const Duration(hours: 8)))) x.key: x};
    expect(tiles['nighthr']!.value, '60');
    expect(tiles['nighthr']!.state, isNot(TileState.none));
    expect(tiles['hrv']!.state, isNot(TileState.none));
  });

  testWidgets('Yöarvot-kortti: vanha yö harmaana omalla nimellään ja huomautus, ei poikkeamavihjettä', (tester) async {
    final now = dateOnly(DateTime.now());
    data(now, 1);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: NightMetricsCard()))));
    await tester.pump();
    expect(find.textContaining('Tämän yön arvoja ei vielä ole Health Connectissa'), findsOneWidget);
    expect(find.textContaining('poikkeaa tavallisesta'), findsNothing);
    expect(find.text('yö ${staleNightLabel(addDays(now, -1))}'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
