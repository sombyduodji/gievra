import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/widgets.dart';

// Lukuikkunassa arvo on valittuna, joten kirjoitus korvaa sen (testikierros 15.11.: "5" + "30" = 530 km).
void main() {
  testWidgets('askNumber: nykyinen arvo valittuna', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => askNumber(context, 'Matka (km)', 12.5, min: 0, max: 1000),
            child: const Text('avaa'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    final c = tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(c.text, '12,5');
    expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 4));
  });

  test('selectedText valitsee koko tekstin', () {
    final c = selectedText('45:00');
    expect(c.selection.start, 0);
    expect(c.selection.end, 5);
  });
}
