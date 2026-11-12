import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/plates.dart';

// Levylaskuri: levyt puolta kohden omista levyistä.
void main() {
  test('102,5 kg 20 kg:n tangolla', () {
    final (ps, rest) = platesPerSide(102.5, 20, defaultPlates);
    expect(ps, [25, 15, 1.25]);
    expect(rest, 0);
  });

  test('Ei ahne: 15 ja 10 kg levyillä 60 kg = 10 + 10 puolelle', () {
    final (ps, rest) = platesPerSide(60, 20, [15, 10]);
    expect(ps, [10, 10]);
    expect(rest, 0);
  });

  test('Ei tarkalleen: jäännös ja lähin paino', () {
    final (ps, rest) = platesPerSide(101, 20, defaultPlates);
    expect(rest, closeTo(0.5, 1e-9));
    expect(loadableTotal(101, 20, defaultPlates), closeTo(100, 1e-9));
    expect(ps.fold<double>(0, (a, b) => a + b), closeTo(40, 1e-9));
  });

  test('Pelkkä tanko tai kevyempi', () {
    expect(platesPerSide(20, 20, defaultPlates).$1, isEmpty);
    expect(platesPerSide(15, 20, defaultPlates).$1, isEmpty);
  });

  test('Tankoliike tunnistetaan välineestä', () {
    expect(isBarbell('Takakyykky'), isTrue);
    expect(isBarbell('Lankku'), isFalse);
  });
}
