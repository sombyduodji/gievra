import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/drawer.dart';
import 'package:treenipaivakirja/ui/onboarding.dart';

// Aloitus (käyttäjä 18.11.): uusi käyttäjä näkee vain perusasiat. Terveys erillisellä valinnalla, tietosuoja
// näkyvästi, Kartat vain liikunnalle.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugSetCatalog('fi', const {});
    settings
      ..trainMode = 'gym'
      ..bodyTracker = false
      ..dailySteps = false;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pump();
  }

  testWidgets('terveys oletuksena pois: ei askel- eikä painokysymystä; tietosuoja näkyy', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('onbPrivacy')), findsOneWidget);
    expect(find.textContaining('ei lähetä eikä synkronoi'), findsOneWidget);
    expect(find.byKey(const ValueKey('onbHealth')), findsOneWidget);
    expect(find.byKey(const ValueKey('onbBody')), findsNothing);
    expect(find.byKey(const ValueKey('onbSteps')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('onbHealth')));
    await tester.pump();
    expect(find.byKey(const ValueKey('onbBody')), findsOneWidget);
    // Paino päälle ja terveys takaisin pois: painoa ei oteta käyttöön.
    await tester.tap(find.byKey(const ValueKey('onbBody')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onbHealth')));
    await tester.pump();
    expect(find.byKey(const ValueKey('onbBody')), findsNothing);
    await tester.tap(find.text('Aloitetaan'));
    await tester.pump();
    expect(settings.bodyTracker, isFalse);
    expect(settings.dailySteps, isFalse);
  });

  test('Kartat-valikko vain, kun liikunta on käytössä', () {
    expect(mapsInMenu('gym'), isFalse);
    expect(mapsInMenu('cardio'), isTrue);
    expect(mapsInMenu('both'), isTrue);
  });
}
