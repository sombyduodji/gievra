import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/ongoing.dart';
import 'package:treenipaivakirja/ui/health_import.dart' show withoutRunning;

// Kesken Gievran liikunnan Health Connectiin tallentunut harjoitus ei näy uutena (käyttäjä 17.11.). Keksityt ajat.
void main() {
  final now = DateTime(2026, 11, 17, 11, 0);
  final pad = HealthCandidate(
    session: true,
    start: DateTime(2026, 11, 17, 10, 30),
    end: DateTime(2026, 11, 17, 10, 58),
    type: 79,
    app: 'UREVO',
  );
  final morning = HealthCandidate(
    session: true,
    start: DateTime(2026, 11, 17, 7, 0),
    end: DateTime(2026, 11, 17, 7, 40),
    type: 79,
    app: 'UREVO',
  );
  final gym = HealthCandidate(
    session: true,
    start: DateTime(2026, 11, 17, 10, 20),
    end: DateTime(2026, 11, 17, 10, 55),
    type: 70,
    app: 'Watch',
  );
  tearDown(() => Ongoing.activity = null);

  test('ei käynnissä: kaikki näkyvät', () {
    expect(withoutRunning([pad, morning, gym], now), [pad, morning, gym]);
  });

  test('kävely käynnissä 35 min: sen aikainen kävelymaton harjoitus piiloon, aamun ja salin näkyvät', () {
    Ongoing.activity = OngoingActivity(
      'Kävely',
      since: now.subtract(const Duration(minutes: 35)),
      elapsed: const Duration(minutes: 35),
    );
    expect(withoutRunning([pad, morning, gym], now), [morning, gym]);
  });

  test('tauolla: alku arvioidaan kuluneesta ajasta', () {
    Ongoing.activity = const OngoingActivity('Kävely', elapsed: Duration(minutes: 20));
    expect(withoutRunning([pad, morning], now), [morning]);
  });
}
