import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/widgets.dart';

// Painon ja toistojen syöttö: miinusmerkkiä ei voi kirjoittaa, pilkku ja piste käyvät.
void main() {
  Future<double?> ask(WidgetTester t, String typed, {bool decimals = true}) async {
    double? result;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await askNumber(context, 'kg', 60, decimals: decimals),
            child: const Text('avaa'),
          ),
        ),
      ),
    );
    await t.tap(find.text('avaa'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), typed);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    return result;
  }

  testWidgets('miinus suodattuu, desimaalit pilkulla ja pisteellä', (t) async {
    expect(await ask(t, '-20'), 20);
    expect(await ask(t, '−20'), 20);
    expect(await ask(t, '82,5'), 82.5);
    expect(await ask(t, '82.5'), 82.5);
    expect(await ask(t, '-5', decimals: false), 5);
    expect(await ask(t, '5,5', decimals: false), 55);
    expect(await ask(t, '-'), isNull);
  });
}
