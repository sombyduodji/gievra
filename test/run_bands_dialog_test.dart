import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/running.dart';
import 'package:treenipaivakirja/ui/run_bands.dart';

// Juoksun matkaryhmien muokkaus (käyttäjä 17.11.): poisto, lisäys, virheellinen väli ja oletus.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => settings.runBands = defaultRunBands);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(onPressed: () => editRunBands(c), child: const Text('auki')),
        ),
      ),
    );
    await tester.tap(find.text('auki'));
    await tester.pumpAndSettle();
  }

  testWidgets('yksi oma ryhmä: kaksi poistetaan, väli muutetaan', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('runBandAdd')), findsNothing, reason: 'jo 3');
    await tester.tap(find.byKey(const ValueKey('runBandRemove_2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('runBandRemove_1')));
    await tester.pump();
    final remove0 = tester.widget<IconButton>(find.byKey(const ValueKey('runBandRemove_0')));
    expect(remove0.onPressed, isNull, reason: 'vähintään yksi ryhmä');
    await tester.enterText(find.byKey(const ValueKey('runBandFrom_0')), '9');
    await tester.enterText(find.byKey(const ValueKey('runBandTo_0')), '11');
    await tester.tap(find.byKey(const ValueKey('runBandSave')));
    await tester.pumpAndSettle();
    expect(settings.runBands, [(9.0, 11.0)]);
    expect(settings.settingsToMarkdown(), contains('run_bands: 9-11'));
  });

  testWidgets('virheellinen väli ei tallennu; lisäys ja oletus', (tester) async {
    settings.runBands = [(5, 10)];
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('runBandAdd')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('runBandFrom_1')), '12');
    await tester.enterText(find.byKey(const ValueKey('runBandTo_1')), '8');
    await tester.tap(find.byKey(const ValueKey('runBandSave')));
    await tester.pump();
    expect(find.textContaining('Tarkista matkat'), findsOneWidget);
    expect(settings.runBands, [(5.0, 10.0)]);
    await tester.enterText(find.byKey(const ValueKey('runBandTo_1')), '');
    await tester.tap(find.byKey(const ValueKey('runBandSave')));
    await tester.pumpAndSettle();
    expect(settings.runBands, [(5.0, 10.0), (12.0, null)]);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('runBandDefault')));
    await tester.pumpAndSettle();
    expect(settings.runBands, defaultRunBands);
    expect(settings.settingsToMarkdown(), isNot(contains('run_bands')));
  });
}
