import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/anim/figure.dart';
import 'package:treenipaivakirja/anim/motions.dart';

// Punnerruksissa tanko kulkee suoraan (penkki: hartioiden yläpuolelta rintalastan alaosaan, pystypunnerrus
// solisluilta pään yli), ei kaarra sivulle kesken toiston.

Offset wristFromShoulder(Motion m, double t) {
  final j = solve(m.at(t), m.anchor);
  return j.wrist - j.shoulder;
}

void main() {
  for (final name in ['Penkkipunnerrus', 'Kapea penkki', 'Lattiapunnerrus', 'Vinopenkki', 'Pystypunnerrus']) {
    test('$name: tanko kulkee suoraa linjaa', () {
      final m = exerciseMotions[name]!;
      final a = wristFromShoulder(m, 0), b = wristFromShoulder(m, 1);
      final dir = (b - a) / (b - a).distance;
      var maxOff = 0.0;
      for (var i = 0; i <= 40; i++) {
        final p = wristFromShoulder(m, i / 40) - a;
        maxOff = math.max(maxOff, (p.dx * dir.dy - p.dy * dir.dx).abs());
      }
      // Kuvan korkeus = 1; olkavarsi 0,16. Sallitaan alle 1 % poikkeama (pyöristys, kulmien rajat).
      expect(maxOff, lessThan(.01), reason: 'suurin sivupoikkeama $maxOff');
      // Alku- ja loppuasento eivät muutu.
      expect((wristFromShoulder(m, 0) - (_raw(m.start))).distance, lessThan(1e-3));
      expect((wristFromShoulder(m, 1) - (_raw(m.end))).distance, lessThan(1e-3));
    });
  }

  test('Penkki: ylhäällä tanko hartioiden yläpuolella, alhaalla rinnan päällä hieman jalkojen suuntaan', () {
    final m = exerciseMotions['Penkkipunnerrus']!;
    final top = wristFromShoulder(m, 0), bottom = wristFromShoulder(m, 1);
    expect(top.dx.abs(), lessThan(.02)); // suoraan olkapään yläpuolella
    expect(bottom.dx, greaterThan(0)); // alhaalla jalkojen suuntaan (rintalasta)
    expect(bottom.dx, lessThan(.1));
  });
}

Offset _raw(Pose p) {
  Offset dir(double deg) => Offset(math.sin(deg * math.pi / 180), math.cos(deg * math.pi / 180));
  return dir(p.arm) * .16 + dir(p.fore) * .15;
}
