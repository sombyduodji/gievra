import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/hr_calc.dart';
import 'package:treenipaivakirja/models.dart';

// Health Connectin syke käyräksi (käyttäjä 15.11.: Oura näyttää Health Syncin 5 s:n käyrän, Gievra vain keskisykkeen).
// Keksityt lukemat.
void main() {
  final t0 = DateTime(2026, 3, 5, 17, 45, 12, 400);
  List<(DateTime, int)> every(int sec, int n, {int base = 110}) => [
    for (var i = 0; i < n; i++) (t0.add(Duration(seconds: sec * i)), base + i % 20),
  ];

  test('Health Sync 5 s: käyrä 5 s välein, alku sekunnin tarkkuudella', () {
    final s = hrSeriesFromHealth(every(5, 720))!;
    expect(s.interval, 5);
    expect(s.start, DateTime(2026, 3, 5, 17, 45, 12));
    expect(s.readingCount, 720);
    expect(s.coverage(3600), closeTo(1, .01));
    expect(s.max, 129);
  });

  test('harva kello (1 / min): väli 60 s, ei näytä katkoilta', () {
    final s = hrSeriesFromHealth(every(60, 60))!;
    expect(s.interval, 60);
    expect(s.missingSec, 0);
  });

  test('alle kaksi lukemaa tai nollat: ei käyrää', () {
    expect(hrSeriesFromHealth(const []), isNull);
    expect(hrSeriesFromHealth([(t0, 120)]), isNull);
    expect(hrSeriesFromHealth([(t0, 0), (t0.add(const Duration(seconds: 5)), 0)]), isNull);
  });

  test('järjestämättömät lukemat järjestetään', () {
    final xs = every(5, 30).reversed.toList();
    expect(hrSeriesFromHealth(xs)!.values.first, 110);
  });

  HealthCandidate cand(List<(DateTime, int)> xs) => HealthCandidate(
    session: true,
    start: t0,
    end: t0.add(const Duration(hours: 1)),
    app: 'Health Sync',
    hrAvg: 115,
    hrMax: 138,
    kcal: 552,
    hrSamples: xs,
  );

  test('kellon tiedot: keskisyke, maksimi ja käyrä treeniin; tallentuu tiedostoon', () {
    final w = Workout(date: DateTime(2026, 3, 5), title: 'Treeni')
      ..started = DateTime(2026, 3, 5, 17, 46)
      ..minutes = 72;
    applyCandidate(w, cand(every(5, 864)));
    expect(w.hrAvg, 115);
    expect(w.hrSource, 'kello');
    expect(w.hrSeries!.interval, 5);
    final back = parseWorkout(workoutToMarkdown(w));
    expect(back.hrSeries!.readingCount, 864);
  });

  test('vyön käyrä korvautuu kellon käyrällä (käyttäjä vahvisti); ilman lukemia käyrä pois', () {
    final w = Workout(date: DateTime(2026, 3, 5), title: 'Treeni')
      ..hrSource = 'sykevyö'
      ..hrSeries = HrSeries(t0, 1, [100, 101, 102]);
    applyCandidate(w, cand(every(5, 100)), replace: true);
    expect(w.hrSeries!.interval, 5);
    final w2 = Workout(date: DateTime(2026, 3, 5), title: 'Treeni')
      ..hrSource = 'sykevyö'
      ..hrSeries = HrSeries(t0, 1, [100, 101, 102]);
    applyCandidate(w2, cand(const []), replace: true);
    expect(w2.hrSeries, isNull);
  });

  test('vyön syke säilyy, jos korvausta ei vahvistettu', () {
    final vyo = HrSeries(t0, 1, [100, 101, 102]);
    final w = Workout(date: DateTime(2026, 3, 5), title: 'Treeni')
      ..hrSource = 'sykevyö'
      ..hrSeries = vyo;
    applyCandidate(w, cand(every(5, 100)));
    expect(w.hrSeries, same(vyo));
  });

  test('kanavan viesti: hrT ja hrV lukemiksi', () {
    final c = HealthCandidate.fromMap({
      'kind': 'session',
      'start': t0.millisecondsSinceEpoch,
      'end': t0.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      'hrAvg': 115,
      'hrT': [t0.millisecondsSinceEpoch, t0.millisecondsSinceEpoch + 5000],
      'hrV': [110, 112],
    });
    expect(c.hrSamples, hasLength(2));
    expect(c.hrSamples.last.$2, 112);
  });
}
