import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/main.dart';

/// Androidin 14+ kaltainen epälineaarinen skaalain: pienet koot 2×, isot vähemmän.
class _NonLinear extends TextScaler {
  const _NonLinear();
  @override
  double scale(double s) => s <= 20 ? s * 2 : s + 20;
  @override
  double get textScaleFactor => 2;
}

// Päivätesti 14.11.: järjestelmän suuri fontti katosi, kun sovelluksen tekstikoko ei ollut Pieni.
void main() {
  test('Sovelluksen kerroin puhelimen skaalaimen päälle koko kerrallaan; enintään 200 % tai puhelimen oma', () {
    const phone = _NonLinear();
    final s = AppTextScaler(phone, 1.15);
    expect(s.scale(14), 28, reason: 'puhelin jo 200 %: sovellus ei pienennä eikä ylitä');
    expect(s.scale(100), closeTo(120 * 1.15, 0.001), reason: 'iso koko: puhelin 120, sovellus päälle');
    final none = AppTextScaler(TextScaler.noScaling, 1.15);
    expect(none.scale(14), closeTo(16.1, 0.001));
    expect(AppTextScaler(TextScaler.noScaling, 3).scale(10), 20, reason: 'katto 200 %');
  });
}
