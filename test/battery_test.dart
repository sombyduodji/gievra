import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/battery.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/battery_ui.dart';

// Akunsäästön ohje: kerran päivityksen jälkeen (vain jos rajoitettu), ei uudelle asennukselle (aloitus kertoo).
// Androidin vastaukset keksitään kanavalla.
void main() {
  const ch = MethodChannel('fi.somby.gievra/power');
  var exempt = false;
  final calls = <String>[];

  setUp(() {
    debugSetCatalog('fi', const {});
    calls.clear();
    battery.exempt = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
      calls.add(c.method);
      return c.method == 'status' ? {'exempt': exempt, 'samsung': true} : true;
    });
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => maybeShowBatteryHint(context), child: const Text('go')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('Päivitys: ohje kerran, Salli avaa Androidin kysymyksen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [Workout(date: DateTime(2026, 11, 1), title: 'Vanha')];
    exempt = false;
    await open(tester);
    expect(find.text('Salli Gievran toimia taustalla'), findsOneWidget);
    expect(find.textContaining('Samsung:'), findsOneWidget);
    expect(find.textContaining('Älä sulje treenin ilmoitusta'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('batteryAllow')));
    await tester.pump();
    expect(calls, contains('request'));
    await tester.tap(find.text('Valmis'));
    await tester.pumpAndSettle();
    await open(tester);
    expect(find.text('Salli Gievran toimia taustalla'), findsNothing, reason: 'vain kerran');
  });

  testWidgets('Jo sallittu tai uusi asennus: ei ohjetta', (tester) async {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [Workout(date: DateTime(2026, 11, 1), title: 'Vanha')];
    exempt = true;
    await open(tester);
    expect(find.text('Salli Gievran toimia taustalla'), findsNothing);
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    exempt = false;
    await open(tester);
    expect(find.text('Salli Gievran toimia taustalla'), findsNothing, reason: 'aloitus kertoi jo');
  });
}
