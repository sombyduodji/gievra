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
    expect(fresh.map((c) => c.id), ['c', 'd'], reason: 'salitreeni näkyy myös');
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

  test('Salitreeni: kellon tiedot päivän salitreeniin, muuten uusi; lisätty ei näy uudelleen', () {
    final c = session('g1', 70, day.add(const Duration(hours: 17, minutes: 5)), const Duration(minutes: 64));
    final morning = Workout(date: day, title: 'Koko keho A', started: day.add(const Duration(hours: 7)))
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)]));
    final evening = Workout(date: day, title: 'Koko keho B', session: 2, started: day.add(const Duration(hours: 17)))
      ..exercises.add(ExerciseEntry('Penkkipunnerrus', [SetEntry(80, 5)]));
    final walk = Workout(date: day, title: 'Kävely', activity: 'Kävely', session: 3);
    final (w, isNew) = gymFromHealth(c, [morning, walk, evening], nextSession: 4);
    expect(isNew, isFalse);
    expect(w.title, 'Koko keho B', reason: 'lähimpänä samaa aikaa');
    expect(w.exercises.single.name, 'Penkkipunnerrus');
    expect((w.started, w.minutes, w.watchTime), (c.start, 64, true));
    expect((w.hrAvg, w.hrMax, w.kcal, w.hcId, w.healthSource), (104, 131, 410, 'g1', 'Testisovellus'));
    expect(evening.hcId, isNull, reason: 'alkuperäistä ei muuteta ennen tallennusta');

    // Ei salitreeniä sinä päivänä: uusi, joka tallentuu ilman liikkeitäkin.
    final (n, nNew) = gymFromHealth(c, [walk], nextSession: 2);
    expect((nNew, n.session, n.activity, n.isEmpty), (true, 2, null, false));
    expect(parseWorkout(workoutToMarkdown(n)).hcId, 'g1');

    // Lisätty: ei enää listalla (tunniste tai samaan aikaan haetut kellon tiedot).
    expect(newHealthSessions([c], [w]).$1, isEmpty);
    final fetched = Workout(date: day, title: 'Koko keho B', started: day.add(const Duration(hours: 17)), minutes: 60)
      ..healthSource = 'Kello';
    expect(newHealthSessions([c], [fetched]).$1, isEmpty);
    expect(newHealthSessions([c], [evening]).$1.single.id, 'g1');
  });

  group('Askeleet ilman harjoitusta', () {
    DateTime at(int h, int m) => day.add(Duration(hours: h, minutes: m));
    // Minuutin tietueet tahdilla [spm] välille [h0:m0, h1:m1).
    List<StepRecord> walk(int h0, int m0, int h1, int m1, int spm, {String pkg = 'mat', String app = 'Matto'}) => [
      for (var t = at(h0, m0); t.isBefore(at(h1, m1)); t = t.add(const Duration(minutes: 1)))
        StepRecord(t, t.add(const Duration(minutes: 1)), spm, pkg: pkg, app: app),
    ];

    test('yhtenäinen kävely löytyy; lyhyt, hidas ja päivän summa eivät', () {
      final recs = [
        ...walk(7, 51, 11, 1, 63), // 190 min
        ...walk(12, 0, 12, 8, 100), // vain 8 min
        ...walk(13, 0, 13, 30, 20), // tallustelua
        StepRecord(day, day.add(const Duration(days: 1)), 15000, pkg: 'mat'), // päivän summa
      ];
      final r = stepStretches(recs);
      expect(r, hasLength(1));
      expect((r.single.start, r.single.end, r.single.steps), (at(7, 51), at(11, 1), 190 * 63));
      expect((r.single.stepsOnly, r.single.app, r.single.pkg), (true, 'Matto', 'mat'));
    });

    test('alle 2 min katko ei katkaise; päällekkäiset tietueet lasketaan kerran', () {
      final recs = [
        ...walk(9, 0, 9, 6, 100),
        ...walk(9, 7, 9, 15, 100), // 1 min tauko
        StepRecord(at(9, 0), at(9, 15), 1400, pkg: 'mat'), // sama kävely myös yhtenä tietueena
      ];
      final r = stepStretches(recs).single;
      expect((r.start, r.end), (at(9, 0), at(9, 15)));
      expect(r.steps, 1400, reason: 'ei tuplaannu');
    });

    test('kahden sovelluksen sama kävely: enemmän askelia voittaa; harjoituksen aikaiset pois', () {
      final recs = [
        ...walk(8, 0, 9, 0, 100),
        ...walk(8, 2, 8, 58, 30, pkg: 'phone'),
        ...walk(8, 5, 8, 40, 70, pkg: 'phone'),
      ];
      final r = stepStretches(recs).single;
      expect(r.pkg, 'mat');
      final run = session('s', 56, at(8, 0), const Duration(minutes: 55));
      expect(stepStretches(recs, sessions: [run]), isEmpty);
    });

    test('lisätty kävely ei näy uudelleen; tiedot liikuntaan', () {
      final c = stepStretches(walk(7, 51, 11, 1, 63)).single.withStats({'hrAvg': 98, 'kcal': 512, 'meters': 9300.0});
      final w = workoutFromHealth(c, 'Kävely', session: 1);
      expect((w.steps, w.distanceKm, w.hrAvg, w.kcal, w.seconds), (190 * 63, 9.3, 98, 512, 190 * 60));
      expect(newHealthSessions([c], [w]).$1, isEmpty);
      expect(newHealthSessions([c], const []).$1, [c]);
    });
  });
}
