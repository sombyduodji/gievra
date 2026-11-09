import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/running.dart';

Workout run(DateTime d, double km, int sec, {String? type, int? hr}) =>
    Workout(date: d, title: 'Juoksu', activity: 'Juoksu', distanceKm: km, seconds: sec, runType: type, hrAvg: hr);

void main() {
  test('Aika, vauhti ja nopeus', () {
    expect(parseDurationSec('25:31'), 25 * 60 + 31);
    expect(parseDurationSec('1:05:09'), 3909);
    expect(parseDurationSec('45'), 2700);
    expect(parseDurationSec('5:75'), isNull);
    expect(fmtDurationSec(3909), '1:05:09');
    expect(fmtDurationSec(1531), '25:31');
    final r = run(DateTime(2026, 11, 3), 5, 1531);
    expect(r.pace, '5:06 min/km');
    expect(r.speedKmh!.toStringAsFixed(1), '11.8');
  });

  test('Juoksu tiedostoon ja takaisin: tarkka aika ja lenkin tyyppi säilyvät', () {
    final r = run(DateTime(2026, 11, 3), 10.2, 3735, type: 'pitka', hr: 142)..minutes = 62;
    final md = workoutToMarkdown(r);
    expect(md, contains('time: 1:02:15'));
    expect(md, contains('run_type: pitka'));
    final back = parseWorkout(md);
    expect(back.seconds, 3735);
    expect(back.runType, 'pitka');
    expect(back.pace, r.pace);
    // Vanha tiedosto ilman tarkkaa aikaa: vauhti minuuteista.
    final old = parseWorkout(md.replaceAll('time: 1:02:15\n', ''));
    expect(old.seconds, isNull);
    expect(old.durationSec, 62 * 60);
  });

  test('Viikot, ennätykset ja kevyiden lenkkien kehitys', () {
    final today = DateTime(2026, 11, 7); // la
    final runs = runsOf([
      run(DateTime(2026, 11, 3), 6, 6 * 360, type: 'kevyt', hr: 140), // 6:00
      run(DateTime(2026, 11, 5), 5, 5 * 290, type: 'kilpailu', hr: 170), // 4:50
      run(DateTime(2026, 10, 1), 6, 6 * 380, type: 'kevyt', hr: 146), // 6:20, edellinen jakso
      run(DateTime(2026, 8, 20), 21.1, (21.1 * 330).round(), type: 'pitka'),
      Workout(date: DateTime(2026, 11, 4), title: 'Sali'), // ei juoksu
    ]);
    expect(runs.length, 4);
    final weeks = runWeeks(runs, today);
    expect(weeks.last.km, 11);
    expect(weeks.last.runs, 2);
    final bests = runBests(runs);
    expect(bests.first.km, 5);
    expect(fmtDurationSec(bests.first.sec), '24:10'); // 5 km kilpailu 4:50/km
    expect(bests.map((b) => b.km), contains(10.0)); // puolimaratonilta laskettu
    final trend = easyRunTrend(runs, today);
    expect(fmtPace(trend.paceNow!), '6:00');
    expect(fmtPace(trend.pacePrev!), '6:20');
    expect(trend.hrNow, 140);
    expect(previousRun(runs, runs[1])!.date, DateTime(2026, 10, 1)); // 6 km 3.11. -> edellinen 6 km
    expect(previousRun(runs, runs.first)!.date, DateTime(2026, 11, 3)); // 5 km: 6 km mahtuu ±20 %:iin
    expect(previousRun(runs, runs[3]), isNull); // puolimaraton: ei aiempaa yhtä pitkää
  });

  test('Kevyet lenkit rasituksesta: Kevyt tai merkitsemättä; vanha lenkin tyyppi huomioidaan', () {
    final today = DateTime(2026, 11, 7);
    Workout r(int d, String? inten, {String? type}) =>
        run(DateTime(2026, 11, d), 5, 5 * 300, type: type)..intensity = inten;
    final runs = runsOf([
      r(6, 'kevyt'), // 6:00 kevyt
      r(5, null), // merkitsemättä: kevyt
      r(4, 'kova'), // ei
      r(3, null, type: 'intervallit'), // vanha tiedosto: tyyppi intervallit, ei kevyt
    ]);
    expect(easyRunTrend(runs, today).nNow, 2);
  });
}
