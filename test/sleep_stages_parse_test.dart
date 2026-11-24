import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/health.dart';

// Yötesti 24.11.: Health Connectin univaiheista otetaan vain järkevät kestot (keksityt arvot).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('univaiheiden lukeminen ohittaa puuttuvat, negatiiviset ja yli vuorokauden arvot', () async {
    const ch = MethodChannel('fi.somby.gievra/health');
    final start = DateTime(2026, 11, 20, 23).millisecondsSinceEpoch;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
      expect(c.method, 'sleepSessions');
      return [
        {
          'start': start,
          'end': start + 7 * 3600000,
          'awakeMs': 600000,
          'stageMs': {'4': 3 * 3600000, '5': -5, '6': null, '1': 48 * 3600000, 'x': 60000},
          'app': 'Testi',
        },
      ];
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null),
    );
    final got = await HealthConnect.sleepSessions(DateTime(2026, 11, 20), DateTime(2026, 11, 21, 12));
    expect(got.single.stageMs, {4: 3 * 3600000, 0: 60000});
  });
}
