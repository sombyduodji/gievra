import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/widgets.dart';

// Numeron syöttö: sallittu väli näkyy, ja väärä arvo pitää ikkunan auki (ennen hylättiin hiljaa).
void main() {
  setUp(() => debugSetCatalog('fi', const {}));

  testWidgets('Painon syöttö: 99999 ja tyhjä eivät kelpaa, 120,5 kelpaa', (tester) async {
    double? got;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              got = await askNumber(context, 'Paino (kg)', 20, min: 0, max: 1000);
              done = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Sallittu 0–1000'), findsOneWidget, reason: 'väli näkyy heti');
    await tester.enterText(find.byType(TextField), '99999');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'ikkuna pysyy auki');
    expect(done, isFalse);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '120,5');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect((done, got), (true, 120.5));
  });

  testWidgets('Ilman väliä toimii kuten ennen', (tester) async {
    double? got = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              TextButton(onPressed: () async => got = await askNumber(context, 'Matka', 5), child: const Text('go')),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(got, 7);
  });
}
