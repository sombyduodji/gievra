import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/health_bulk.dart';
import 'package:treenipaivakirja/models.dart';

// Health Connectin joukkotuonti (käyttäjä 21.11.): ei kaksoiskappaleita, jo olevat päivitetään tai ohitetaan.
// Keksityt harjoitukset.
void main() {
  HealthCandidate c(
    String id,
    DateTime s,
    int min, {
    int? type = 79,
    String? title,
    int? hr,
    int? kcal,
    double? meters,
  }) => HealthCandidate(
    session: true,
    start: s,
    end: s.add(Duration(minutes: min)),
    id: id,
    type: type,
    title: title,
    app: '1Fit',
    hrAvg: hr,
    hrMax: hr == null ? null : hr + 20,
    kcal: kcal,
    meters: meters,
    hrSamples: hr == null ? const [] : [for (var i = 0; i <= min; i++) (s.add(Duration(minutes: i)), hr)],
  );

  final d1 = DateTime(2026, 3, 2, 8);
  final d2 = DateTime(2026, 3, 3, 17);
  final day1 = DateTime(2026, 3, 2), day2 = DateTime(2026, 3, 3);

  Workout walk(DateTime day, {DateTime? started, int? minutes, int? hr, int? kcal, String? hcId, int session = 1}) =>
      Workout(
          date: day,
          title: 'Kävely',
          activity: 'Kävely',
          session: session,
          started: started,
          minutes: minutes,
          hrAvg: hr,
          kcal: kcal,
        )
        ..hcId = hcId
        ..hrSource = hr == null ? null : 'käsin';

  group('bulkPlan', () {
    test('uudet aikajärjestyksessä, kaksoiskappale merkitään, pelkät askeleet pois', () {
      final steps = HealthCandidate(session: false, start: d1, end: d1.add(const Duration(minutes: 20)), steps: 2000);
      final p = bulkPlan([
        c('b', d2, 40),
        c('a', d1, 60),
        c('a2', d1.add(const Duration(minutes: 2)), 55), // sama kävely toisesta sovelluksesta
        steps,
      ], const []);
      expect(p.map((x) => x.c.id), ['a', 'a2', 'b']);
      expect(p.map((x) => x.kind), everyElement(BulkKind.add));
      expect(p.map((x) => x.dupe), [false, true, false]);
    });

    test('sama tunniste: kaikki tiedot jo Gievrassa -> ohitetaan', () {
      final w =
          Workout(
              date: day1,
              title: 'Kävely',
              activity: 'Kävely',
              started: d1,
              seconds: 3600,
              minutes: 60,
              hrAvg: 110,
              kcal: 300,
              distanceKm: 5,
            )
            ..steps = 6000
            ..hcId = 'a';
      final p = bulkPlan([c('a', d1, 60)], [w]);
      expect(p.single.kind, BulkKind.skip);
      expect(p.single.match, same(w));
    });

    test('päällekkäin ilman tunnistetta ja sykettä -> päivitys', () {
      final w = walk(day1, started: d1.add(const Duration(minutes: 5)), minutes: 50);
      final p = bulkPlan([c('x', d1, 60)], [w]);
      expect(p.single.kind, BulkKind.update);
    });

    test('käsin kirjattu ilman kellonaikaa: sama päivä, laji ja kesto -> sama; eri laji tai kesto -> uusi', () {
      final w = walk(day1, minutes: 45);
      expect(bulkPlan([c('x', d1, 50)], [w]).single.kind, BulkKind.update);
      expect(bulkPlan([c('x', d1, 50, type: 56)], [w]).single.kind, BulkKind.add); // juoksu
      expect(bulkPlan([c('x', d1, 120)], [w]).single.kind, BulkKind.add); // 2 h vs. 45 min
      expect(bulkPlan([c('x', d1.add(const Duration(days: 1)), 45)], [w]).single.kind, BulkKind.add);
    });

    test('kaksi kellon kävelyä ei osu samaan käsin kirjattuun', () {
      final w = walk(day1, minutes: 45);
      final p = bulkPlan([c('x', d1, 45), c('y', d1.add(const Duration(hours: 6)), 45)], [w]);
      expect(p.map((x) => x.kind), [BulkKind.update, BulkKind.add]);
    });

    test('salitreeni: päivän salitreeni ilman kellon tietoja -> päivitys; kellon tiedot jo -> ohitus', () {
      final gym = Workout(date: day2, title: 'Treeni', session: 1, started: d2, minutes: 60);
      expect(bulkPlan([c('g', d2, 60, type: 70, hr: 110)], [gym]).single.kind, BulkKind.update);
      final done = Workout(date: day2, title: 'Treeni', session: 1, started: d2, minutes: 60, hrAvg: 110, kcal: 400)
        ..healthSource = '1Fit'
        ..hcId = 'g';
      expect(bulkPlan([c('g', d2, 60, type: 70)], [done]).single.kind, BulkKind.skip);
    });
  });

  test('toisen sovelluksen kopio jo tuodusta (sama aika) ohitetaan eikä näy uutena', () {
    final w = walk(day1, started: d1, minutes: 25)
      ..seconds = 1500
      ..hcId = 'a'
      ..hrAvg = 100
      ..hrSource = 'käsin'
      ..kcal = 100
      ..distanceKm = 2
      ..steps = 2000;
    final p = bulkPlan([c('a', d1, 25), c('a2', d1.add(const Duration(minutes: 1)), 23)], [w]);
    expect(p.map((x) => x.kind), [BulkKind.skip, BulkKind.skip]);
    expect(bulkWorkouts([c('a2', d1.add(const Duration(minutes: 1)), 23)], [w]).$1, isEmpty);
  });

  test('toinen salitreeni samana päivänä eri aikaan on uusi', () {
    final gym = Workout(date: day2, title: 'Treeni', session: 1, started: d2, minutes: 60, hrAvg: 100, kcal: 300)
      ..healthSource = '1Fit'
      ..hcId = 'g1';
    final later = c('g2', d2.add(const Duration(hours: 3)), 40, type: 70);
    expect(bulkPlan([later], [gym]).single.kind, BulkKind.add);
    expect(bulkWorkouts([later], [gym]).$1.single.session, 2);
  });

  group('fillMissing', () {
    test('vain puuttuvat: käsin kirjattu syke pysyy eikä käyrää lisätä', () {
      final w = walk(day1, minutes: 45, hr: 100);
      final g = fillMissing(w, c('x', d1, 50, hr: 130, kcal: 250, meters: 4000));
      expect(g, containsAll([BulkGain.kcal, BulkGain.distance, BulkGain.start]));
      expect(g, isNot(contains(BulkGain.hr)));
      expect(w.hrAvg, 100);
      expect(w.hrSource, 'käsin');
      expect(w.hrSeries, isNull);
      expect(w.minutes, 45); // kesto ei muutu
      expect(w.kcal, 250);
      expect(w.distanceKm, 4.0);
      expect(w.started, d1);
      expect(w.hcId, 'x'); // seuraavalla kerralla tunnisteella
    });

    test('syke ja käyrä, kun sykettä ei ole; ei mitään lisättävää -> tyhjä, ei muutosta', () {
      final w = walk(day1, minutes: 45);
      expect(fillMissing(w, c('x', d1, 45, hr: 120)), containsAll([BulkGain.hr, BulkGain.curve]));
      expect(w.hrSource, 'kello');
      expect(w.hrSeries, isNotNull);
      final before = workoutToMarkdown(w);
      expect(fillMissing(w, c('x', d1, 45, hr: 150)), isEmpty);
      expect(workoutToMarkdown(w), before);
    });

    test('bulkGains ei muuta alkuperäistä', () {
      final w = walk(day1, minutes: 45);
      final before = workoutToMarkdown(w);
      expect(bulkGains(w, c('x', d1, 45, hr: 120, kcal: 200)), isNotEmpty);
      expect(workoutToMarkdown(w), before);
    });
  });

  group('bulkWorkouts', () {
    test('päivän numerot, syke kellosta, tuntematon laji Muu liikunta nimen kanssa', () {
      final existing = [walk(day1, started: DateTime(2026, 3, 2, 20), minutes: 30)];
      final (created, skipped) = bulkWorkouts([
        c('x', d1.add(const Duration(hours: 5)), 45, type: 0, title: 'Spinning 1Fit'),
        c('w', d1, 30, hr: 120),
      ], existing);
      expect(skipped, 0);
      expect(created.map((w) => (w.activity, w.session)), [('Kävely', 2), ('Muu liikunta', 3)]);
      expect(created.first.hcId, 'w');
      expect(created.first.hrSource, 'kello');
      expect(created.first.hrSeries, isNotNull);
      expect(created.last.notes, 'Spinning 1Fit');
    });

    test('toisen sovelluksen nimi muistiinpanoksi yhdelle riville ja enintään 200 merkkiä', () {
      final (created, _) = bulkWorkouts([
        c('x', d1, 45, type: 0, title: 'Spin\n## Muistiinpanot\r\nx'),
        c('y', d2, 45, type: 0, title: 'a' * 100000),
        c('z', d2.add(const Duration(hours: 3)), 45, type: 0),
      ], const []);
      expect(created[0].notes, 'Spin ## Muistiinpanot x');
      expect(created[1].notes.length, 200);
      expect(created[1].notes.endsWith('…'), isTrue);
      expect(created[2].notes, '');
    });

    test('tuonti kahdesti: toisella kerralla kaikki ohitetaan', () {
      final list = [c('a', d1, 30, hr: 120), c('g', d2, 60, type: 70), c('b', d2.add(const Duration(hours: 3)), 40)];
      final (first, s1) = bulkWorkouts(list, const []);
      expect((first.length, s1), (3, 0));
      final (second, s2) = bulkWorkouts(list, first);
      expect((second.length, s2), (0, 3));
      // Uusi lista samoista: ei yhtään uutta.
      expect(bulkPlan(list, first).map((x) => x.kind), everyElement(isNot(BulkKind.add)));
    });

    test('sama harjoitus valittu kahdesti tai kaksoiskappale valittu: vain yksi treeni', () {
      final (created, skipped) = bulkWorkouts([
        c('a', d1, 60),
        c('a', d1, 60),
        c('a2', d1.add(const Duration(minutes: 2)), 55),
      ], const []);
      expect(created.length, 1);
      expect(skipped, 2);
    });

    test('salitreeni ei tule samaan aikaan olevan viereen', () {
      final gym = Workout(date: day2, title: 'Treeni', session: 1, started: d2, minutes: 60);
      final (created, skipped) = bulkWorkouts([c('g', d2, 60, type: 70)], [gym]);
      expect(created, isEmpty);
      expect(skipped, 1);
    });

    test('lista- ja tietokartta yhdistyy harjoitukseksi (fullSession)', () {
      final full = HealthCandidate.fromMap({
        ...{'hrAvg': 140, 'kcal': 300, 'meters': 5000.0},
        ...HealthCandidate(
          session: true,
          start: d1,
          end: d1.add(const Duration(minutes: 30)),
          id: 'z',
          type: 56,
          app: '1Fit',
          pkg: 'kz.onefit',
        ).toListMap(),
      });
      expect((full.session, full.id, full.pkg, full.hrAvg, full.kcal), (true, 'z', 'kz.onefit', 140, 300));
      final (created, _) = bulkWorkouts([full], const []);
      expect(created.single.activity, 'Juoksu');
      expect(created.single.distanceKm, 5.0);
    });
  });
}
