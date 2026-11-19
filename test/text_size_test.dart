import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/main.dart';

// Tekstin koko (Asetukset → Yleiset): Pieni = alkuperäinen koko (oletus), Normaali 115 %, Suuri 130 %;
// tallentuu asetustiedostoon ja kerrotaan puhelimen oman fonttikoon päälle.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    debugSetCatalog('fi', const {});
    settings
      ..started = true
      ..introDone = true
      ..program = null
      ..textSize = 'small';
  });

  test('Asetus tallentuu tiedostoon ja luetaan takaisin; tuntematon arvo ei muuta', () {
    expect(settings.textFactor, 1.0);
    settings.textSize = 'large';
    final md = settings.settingsToMarkdown();
    expect(md, contains('text_size: large'));
    settings.textSize = 'small';
    settings.applyMarkdown(md);
    expect(settings.textSize, 'large');
    expect(settings.textFactor, 1.3);
    settings.applyMarkdown(md.replaceFirst('text_size: large', 'text_size: jättimäinen'));
    expect(settings.textSize, 'large');
    settings.textSize = 'small';
  });

  testWidgets('Sovellus käyttää valittua kokoa puhelimen oman koon päällä', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Testifontti (Ahem) on leveä: ylivuodot tarkistetaan oikeilla fonteilla (GIEVRA_TEXT_SCALE, l10n_screens_test).
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    double scale() => MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first)).scale(100) / 100;
    await tester.pumpWidget(const TreeniApp());
    await tester.pump();
    expect(scale(), 1.0, reason: 'Pieni: ennallaan');
    settings.textSize = 'normal';
    settings.notifyListeners();
    await tester.pump();
    expect(scale(), closeTo(1.15, .001));
    // Puhelimen oma koko 120 % × Suuri 130 % = 156 %.
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    settings.textSize = 'large';
    settings.notifyListeners();
    await tester.pump();
    expect(scale(), closeTo(1.56, .001));
    // Yhteensä enintään 200 %.
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    await tester.pump();
    expect(scale(), closeTo(2.0, .001));
    settings.textSize = 'small';
    await tester.pumpWidget(const SizedBox());
  });
}
