// Renderöi jokaisen liikkeen alku- ja loppuasennon kuvaksi tarkistusta varten:
//   RENDER=1 flutter test --update-goldens test/anim/render_test.dart  ->  test/anim/out/*.png
// Ei aja tavallisessa testiajossa (kuvat muuttuvat aina, kun asentoja hiotaan).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/anim/figure.dart';
import 'package:treenipaivakirja/anim/motions.dart';

void main() {
  final names = exerciseMotions.keys.toList();
  for (var i = 0; i < names.length; i++) {
    final n = names[i];
    testWidgets('anim $n', (tester) async {
      tester.view.physicalSize = const Size(440, 220);
      tester.view.devicePixelRatio = 1;
      final m = exerciseMotions[n]!;
      Widget fig(double t) => SizedBox(
        width: 220,
        height: 220,
        child: CustomPaint(
          painter: FigurePainter(m, t, body: Colors.white, faint: Colors.grey, floor: Colors.blueGrey),
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: const Color(0xFF0F1420),
            child: Row(children: [fig(0), fig(1)]),
          ),
        ),
      );
      await expectLater(find.byType(Row), matchesGoldenFile('out/${i.toString().padLeft(2, '0')}.png'));
    }, skip: Platform.environment['RENDER'] != '1');
  }
}
