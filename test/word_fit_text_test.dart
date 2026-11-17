import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/widgets.dart';

// Liikuntanäkymän laatat saameksi fontilla 2,0: sana ei saa katketa kesken (yötesti 16.11.: "Áigemihti/deapmi").
void main() {
  testWidgets('pisin sana mahtuu riville; lyhyet tekstit ennallaan', (tester) async {
    Future<Text> pump(String s, double width) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: width,
                child: WordFitText(s, width: width, style: const TextStyle(fontSize: 15)),
              ),
            ),
          ),
        ),
      );
      return tester.widget<Text>(find.byType(Text));
    }

    final long = await pump('Áigemihtideapmi', 120);
    expect(long.style!.fontSize, lessThan(15));
    final tp = TextPainter(
      text: TextSpan(text: 'Áigemihtideapmi', style: long.style),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(2),
    )..layout();
    expect(tp.width, lessThanOrEqualTo(120));
    tp.dispose();

    final short = await pump('Čális ieš', 300);
    expect(short.style!.fontSize, 15);
  });
}
