import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/onboarding.dart';

// Yötesti 24.11.: aloituksen pituus 999 ja paino 0 ohitettiin hiljaa. Nyt virhe kenttään eikä jatketa.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugSetCatalog('fi', const {});
    settings
      ..trainMode = 'gym'
      ..bodyTracker = false
      ..dailySteps = false;
  });

  testWidgets('rajojen ulkopuolinen pituus ja paino: virhe eikä aloitus jatku; korjattuna jatkuu', (tester) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onbHealth')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onbBody')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('onbHeight')), '999');
    await tester.enterText(find.byKey(const ValueKey('onbWeight')), '0');
    await tester.tap(find.text('Aloitetaan'));
    await tester.pump();
    expect(find.text('Anna pituus 100–250 cm.'), findsOneWidget);
    expect(find.text('Anna paino 20–400 kg.'), findsOneWidget);
    expect(settings.bodyTracker, isFalse, reason: 'ei jatkettu');
    await tester.enterText(find.byKey(const ValueKey('onbHeight')), '180');
    await tester.enterText(find.byKey(const ValueKey('onbWeight')), '');
    await tester.pump();
    expect(find.text('Anna pituus 100–250 cm.'), findsNothing);
    await tester.tap(find.text('Aloitetaan'));
    await tester.pump();
    expect(settings.bodyTracker, isTrue);
    expect(settings.body.heightCm, 180);
    expect(tester.takeException(), isNull);
  });
}
