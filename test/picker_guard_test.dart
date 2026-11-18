import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/picker_guard.dart';

// Yötesti 18.11.: tiedostovalitsimen ja jakamisen tuplanapautus ("already_active").
void main() {
  test('toinen kutsu ensimmäisen ollessa auki palauttaa null; vapautuu virheenkin jälkeen', () async {
    final open = Completer<String>();
    var calls = 0;
    final first = pickOnce(() {
      calls++;
      return open.future;
    });
    expect(pickerBusy, isTrue);
    expect(await pickOnce(() async => 'toinen'), isNull);
    open.complete('eka');
    expect(await first, 'eka');
    expect(calls, 1);
    expect(pickerBusy, isFalse);
    await expectLater(pickOnce<String>(() async => throw StateError('x')), throwsStateError);
    expect(pickerBusy, isFalse);
    expect(await pickOnce(() async => 'taas'), 'taas');
  });
}
