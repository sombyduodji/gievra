import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/running.dart';

// Juoksun matkaryhmät etusivun Kehitys-kortissa (käyttäjä 17.11.): alle 5, 5–10 ja yli 10 km. Keksityt lenkit.
void main() {
  final today = DateTime(2026, 11, 17);
  Workout run(int daysAgo, double km, int sec, [int? hr]) =>
      Workout(
          date: today.subtract(Duration(days: daysAgo)),
          title: 'Juoksu',
          activity: 'Juoksu',
        )
        ..distanceKm = km
        ..seconds = sec
        ..hrAvg = hr;

  test('ryhmä vain, kun molemmilla jaksoilla vähintään 2 juoksua; lyhyet ja pitkät erikseen', () {
    final ws = [
      run(3, 4, 1320, 150), run(10, 4.5, 1485, 152), // < 5 km nyt: 5:30 /km
      run(35, 4, 1400, 155), run(60, 4, 1400, 155), // < 5 km ennen: 5:50 /km
      run(5, 12, 4200), run(70, 12, 4500), // > 10 km: vain yksi kummallakin jaksolla
      run(90, 7, 2500), // yli 12 viikon takaa: ei mukana
    ];
    final g = runGroups(ws, today);
    expect(g.map((x) => x.label), ['< 5 km']);
    expect(g.single.pace.round(), 330);
    expect(g.single.paceDelta, -20);
    expect((g.single.hr, g.single.prevHr), (151, 155));
  });

  test('syke puuttuu: ryhmä silti, ilman sykettä', () {
    final ws = [run(1, 6, 2100), run(8, 6, 2100), run(40, 6, 2160), run(50, 6, 2160)];
    final g = runGroups(ws, today).single;
    expect(g.label, '5–10 km');
    expect(g.hr, isNull);
    expect(g.paceDelta, -10);
  });

  test('omat ryhmät (käyttäjä 17.11.): 1–3 ryhmää, oma matkaväli, päällekkäin saa mennä', () {
    final ws = [run(1, 10, 3000), run(8, 10.5, 3150), run(40, 9.5, 3000), run(50, 10, 3100), run(2, 21.1, 7600)];
    final g = runGroups(ws, today, bands: [(9, 11)]);
    expect(g.map((x) => x.label), ['9–11 km']);
    expect(g.single.runs, 2);
    expect(runGroups(ws, today, bands: [(0, null)]).single.label, 'kaikki matkat');
  });

  test('ryhmät tiedostoon ja takaisin; virheelliset ohitetaan', () {
    const b = <RunBand>[(0, 5), (7.5, 12.5), (21.1, null)];
    expect(runBandsToFile(b), '0-5; 7,5-12,5; 21,1-');
    expect(runBandsFromFile(runBandsToFile(b)), b);
    expect(runBandsFromFile('10-5; x; 3-8'), [(3.0, 8.0)]);
    expect(runBandsFromFile('roskaa'), defaultRunBands);
    expect(runBandsFromFile('0-1; 1-2; 2-3; 3-4').length, 3);
    expect(defaultRunBands.map(runBandLabel), ['< 5 km', '5–10 km', '> 10 km']);
  });
}
