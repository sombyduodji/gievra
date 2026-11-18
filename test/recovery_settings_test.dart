import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/home_layout.dart';
import 'package:treenipaivakirja/recovery.dart';
import 'package:treenipaivakirja/ui/recovery_card.dart';

// Palautumisen ruudut (käyttäjä 18.11.): valinta ja järjestys asetuksissa; selitykset etusivun ohjeessa.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    settings
      ..recoveryOrder = [...recoveryOrderDefault]
      ..nightTiles = {...recoveryTileKeys}
      ..homeHidden = {...homeCardsOffByDefault};
  });

  test('järjestys tiedostoon ja takaisin; tuntemattomat pois, puuttuvat loppuun', () {
    settings.recoveryOrder = ['load', 'sleep', 'nighthr', 'hrv', 'rr', 'spo2', 'temp'];
    expect(settings.settingsToMarkdown(), contains('recovery_order: load, sleep, nighthr, hrv, rr, spo2, temp'));
    settings.recoveryOrder = [...recoveryOrderDefault];
    settings.applyMarkdown('---\nrecovery_order: sleep, roska, nighthr, sleep\n---\n');
    expect(settings.recoveryOrder, ['sleep', 'nighthr', 'hrv', 'rr', 'spo2', 'temp', 'load']);
    settings.recoveryOrder = [...recoveryOrderDefault];
    expect(settings.settingsToMarkdown(), isNot(contains('recovery_order')));
  });

  testWidgets('asetussivu: kytkin piilottaa ruudun; ohjeosio näyttää värit ja avaa sivun', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    settings.homeHidden = {'sleep'};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: RecoveryHelpSection())),
      ),
    );
    expect(find.text('Punainen: selvästi poikkeava'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recoveryChooseTiles')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recoveryTilesSettings')), findsOneWidget);
    expect(find.byKey(const ValueKey('recTileRow_load')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recTileSwitch_load')));
    await tester.pump();
    expect(settings.nightTiles.contains('load'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
