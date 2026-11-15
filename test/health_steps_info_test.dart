import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/l10n.dart';

// Askeleet lähteittäin (Health Connect -tuonti): natiivipuoli antaa luvut, sanat käyttöliittymän kielellä.
void main() {
  tearDown(() => debugSetCatalog('fi', const {}));

  test('englanniksi ei suomenkielisiä sanoja', () {
    debugSetCatalog('en', parsePo(File('assets/l10n/en.po').readAsStringSync()));
    final s = HealthCandidate.stepsInfoText({
      'stepsBySource': 'Oura: 5200',
      'stepsMinuteBest': 5300,
      'stepsHcTotal': 5400,
    });
    expect(s, 'Oura: 5200, best by minute: 5300, Health Connect total: 5400');
  });

  test('ilman lähteitä ei alkupilkkua; tyhjä = null', () {
    expect(HealthCandidate.stepsInfoText({'stepsBySource': '', 'stepsHcTotal': 10}), 'Health Connect yhteensä: 10');
    expect(HealthCandidate.stepsInfoText({'stepsBySource': ''}), isNull);
  });
}
