import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';

// Sarjatyypin valitsin ("Normaali / Pudotus / AMRAP") järjestelmän fontilla 2,0 puhelimella: sana ei katkea kesken
// ("Dábála/š", "AMRA/P"; havaittu Samsungilla 15.11.2026), teksti pienenee yhdelle riville.
void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('SetKindPicker ${scale}x: yksikään sana ei katkea', (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(412, 800), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SetKindPicker(value: null, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      void walk(RenderObject o) {
        if (o is RenderParagraph) {
          expect(o.text.toPlainText().contains(RegExp(r'\s')), isFalse);
          expect(o.size.width, greaterThan(0));
          expect(o.getFullHeightForCaret(const TextPosition(offset: 0)), isNotNull);
          // Yksi rivi: korkeus on enintään yhden rivin verran (leveyden mukaan ei rivity).
          final one = TextPainter(text: o.text, textDirection: TextDirection.ltr, textScaler: o.textScaler)..layout();
          expect(o.size.height, lessThanOrEqualTo(one.height + 1), reason: o.text.toPlainText());
        }
        o.visitChildren(walk);
      }

      walk(tester.renderObject(find.byType(SetKindPicker)));
      expect(tester.takeException(), isNull);
    });
  }
}
