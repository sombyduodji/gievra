import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/home_settings.dart';

// Palautuminen-kortin kytkin kysyy Health Connectin sykkeen lukuluvan (yötesti 18.–19.11.: ei kysynyt lainkaan, ja
// kortti jäi tyhjäksi, ellei Health Connect -tuonti ollut jo päällä).
const _ch = MethodChannel('fi.somby.gievra/health');

void main() {
  final calls = <MethodCall>[];
  var allow = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugSetCatalog('fi', const {});
    calls.clear();
    settings
      ..hcImport = false
      ..setHomeCard('recovery', false)
      ..setHomeCard('night', false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_ch, (call) async {
      calls.add(call);
      return switch (call.method) {
        'status' => 'available',
        'request' || 'granted' => allow,
        _ => null,
      };
    });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_ch, null),
  );

  Future<void> tapSwitch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      // Asetussivu rakennetaan uudelleen asetusten muuttuessa (drawer.dart); sama tässä.
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(listenable: settings, builder: (_, _) => HomeLayoutSettings()),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('homeCardSwitch_recovery')));
    await tester.pumpAndSettle();
  }

  testWidgets('Lupa kielletty: kortti jää pois ja ilmoitus kertoo syyn', (tester) async {
    allow = false;
    await tapSwitch(tester);
    final req = calls.where((c) => c.method == 'request').toList();
    expect(req, hasLength(1));
    expect((req.single.arguments as Map)['heartRate'], isTrue, reason: 'vain sykkeen lukulupa');
    expect(settings.homeCardOn('recovery'), isFalse);
    expect(find.text('Palautuminen-kortti tarvitsee Health Connectin sykkeen lukuluvan.'), findsOneWidget);
    // Kerran kiellettyä lupaa Android ei kysy uudelleen: painike Health Connectin asetuksiin.
    await tester.tap(find.text('Avaa Health Connect'));
    await tester.pump();
    expect(calls.where((c) => c.method == 'settings'), hasLength(1));
  });

  testWidgets('Lupa annettu: kortti päälle ilman Health Connect -tuontia', (tester) async {
    allow = true;
    await tapSwitch(tester);
    expect(settings.homeCardOn('recovery'), isTrue);
    expect(settings.hcImport, isFalse, reason: 'tuonnin painiketta ei lisätä etusivulle');
    // Pois päältä: ei lupakyselyä, yöarvot pois samalla.
    calls.clear();
    await tester.tap(find.byKey(const ValueKey('homeCardSwitch_recovery')));
    await tester.pumpAndSettle();
    expect(settings.homeCardOn('recovery'), isFalse);
    expect(settings.homeCardOn('night'), isFalse);
    expect(calls.where((c) => c.method == 'request'), isEmpty);
  });
}
