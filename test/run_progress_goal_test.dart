import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/home_layout.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/running.dart';

// Juoksun kehitystavoitteet (käyttäjä 18.11.). Keksityt juoksut.
void main() {
  final mon = DateTime(2026, 11, 16);
  Workout run(int dayOffset, double km, int min, {int? hr}) => Workout(date: addDays(mon, dayOffset), title: 'Juoksu')
    ..activity = 'Juoksu'
    ..distanceKm = km
    ..seconds = min * 60
    ..hrAvg = hr;

  test('vauhdin kehitys vertaa samaan matkaryhmään; pieni parannus riittää', () {
    final ws = [
      run(-20, 5.5, 33), // 6:00/km, ryhmä 5–10
      run(-10, 3, 18), // 6:00/km, ryhmä < 5
      run(1, 5.5, 32), // ~5:49/km
      run(2, 12, 80), // ryhmä > 10 ilman vertailua: ei mukana
    ];
    final d = paceProgress(ws, mon, addDays(mon, 7), defaultRunBands)!;
    expect(d, lessThan(0));
    expect(d, closeTo(-10.9, 0.2));
    expect(paceProgress([run(1, 5, 30)], mon, addDays(mon, 7), defaultRunBands), isNull);
  });

  test('vauhti samalla sykkeellä prosentteina; vain juoksut, joissa syke', () {
    final ws = [run(-7, 5, 30, hr: 150), run(1, 5, 30, hr: 145), run(2, 5, 25)];
    expect(hrPaceProgress(ws, mon, addDays(mon, 7)), closeTo(3.45, 0.01));
    expect(hrPaceProgress([run(1, 5, 30)], mon, addDays(mon, 7)), isNull);
  });

  test('tiedostomuoto: kehitystavoitteet ilman lajia, ei määrää', () {
    final gs = goalsFromFile('pace:Juoksu:1; hrpace:*:1; km:Juoksu:20');
    expect(gs, [const Goal('pace', null, 1), const Goal('hrpace', null, 1), const Goal('km', 'Juoksu', 20)]);
    expect(gs.first.progress, isTrue);
    expect(goalsFromFile(goalsToFile(gs)), gs);
  });
}
