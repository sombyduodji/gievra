import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/models.dart';

// Tehdyn liikunnan lisäys Health Connectista. Keksityt harjoitukset ja arvot.
HealthCandidate session(String id, int type, DateTime start, Duration dur, {double? meters, int? steps}) =>
    HealthCandidate(
      session: true,
      id: id,
      type: type,
      start: start,
      end: start.add(dur),
      app: 'Testisovellus',
      hrAvg: 104,
      hrMax: 131,
      kcal: 410,
      steps: steps,
      meters: meters,
    );

void main() {
  final day = DateTime(2026, 11, 9);

  test('Health Connectin lajit Gievran lajeiksi; salitreeni ei ole liikuntaa', () {
    expect(sportForHealthType(79), 'Kävely');
    expect(sportForHealthType(57), 'Juoksu'); // juoksumatto
    expect(sportForHealthType(9), 'Pyöräily'); // kuntopyörä
    expect(sportForHealthType(74), 'Uinti');
    expect(sportForHealthType(25), isNull); // crosstrainer: käyttäjä valitsee
    expect(isStrengthType(70), isTrue);
  });

  test('Jo lisätyt piilotetaan: sama tunniste tai sama aika Gievran liikunnassa', () {
    final walk = session('a', 79, day.add(const Duration(hours: 8)), const Duration(minutes: 161));
    final run = session('b', 56, day.add(const Duration(hours: 18)), const Duration(minutes: 31));
    final bike = session('c', 8, day.add(const Duration(hours: 12)), const Duration(minutes: 40));
    final gym = session('d', 70, day.add(const Duration(hours: 16)), const Duration(minutes: 60));
    final existing = [
      Workout(date: day, title: 'Kävely', activity: 'Kävely')..hcId = 'a',
      // Juoksu kirjattu itse Gievraan samaan aikaan (alkoi 2 min myöhemmin).
      Workout(
        date: day,
        title: 'Juoksu',
        activity: 'Juoksu',
        started: day.add(const Duration(hours: 18, minutes: 2)),
        seconds: 30 * 60,
      ),
      // Eri aikaan: ei vaikuta pyöräilyyn.
      Workout(
        date: day,
        title: 'Juoksu',
        activity: 'Juoksu',
        started: day.add(const Duration(hours: 6)),
        seconds: 30 * 60,
      ),
    ];
    final (fresh, done) = newHealthSessions([walk, run, bike, gym], existing);
    expect(fresh.map((c) => c.id), ['c']);
    expect(done, 2);
  });

  test('Valmiiksi täytetty liikunta: aika, matka, syke, kalorit, askeleet, lähde ja tunniste', () {
    final c = session(
      'hc-123',
      79,
      day.add(const Duration(hours: 8, minutes: 2)),
      const Duration(hours: 2, minutes: 41),
      meters: 9412,
      steps: 13870,
    );
    final w = workoutFromHealth(c, 'Kävely', session: 2);
    expect(w.date, day);
    expect(w.session, 2);
    expect(w.started, day.add(const Duration(hours: 8, minutes: 2)));
    expect(w.seconds, 9660);
    expect(w.distanceKm, 9.41);
    expect(w.steps, 13870);
    expect((w.hrAvg, w.hrMax, w.kcal), (104, 131, 410));
    expect(w.healthSource, 'Testisovellus');
    expect(w.watchTime, isTrue);
    final back = parseWorkout(workoutToMarkdown(w));
    expect(back.hcId, 'hc-123');
    expect(back.distanceKm, 9.41);
    // Lajissa ilman matkaa tai askelia niitä ei kirjata.
    final yoga = workoutFromHealth(c, 'Jooga', session: 1);
    expect(yoga.distanceKm, isNull);
    expect(yoga.steps, isNull);
  });

  test('Asetus: oletus pois, tallentuu asetuksiin', () {
    expect(Settings().hcImport, isFalse);
    final s = Settings()..hcImport = true;
    expect((Settings()..applyMarkdown(s.settingsToMarkdown())).hcImport, isTrue);
  });

  test('Lisätyn liikunnan tiedot haetaan uudelleen: askeleet ja matka korjautuvat', () {
    final first = session(
      'hc-1',
      79,
      day.add(const Duration(hours: 7, minutes: 51)),
      const Duration(minutes: 190),
      meters: 6250,
      steps: 111,
    );
    final w = workoutFromHealth(first, 'Kävely', session: 1);
    final fixed = session('hc-1', 79, first.start, first.duration, meters: 6300, steps: 12058);
    applyCandidate(w, fixed, steps: true);
    expect((w.steps, w.distanceKm), (12058, 6.3));
    // Toinen harjoitus tai käsin kirjoitettu matka: matka ei muutu.
    final other = session('hc-2', 79, first.start, first.duration, meters: 9000);
    applyCandidate(w, other, steps: true);
    expect(w.distanceKm, 6.3);
  });
}
