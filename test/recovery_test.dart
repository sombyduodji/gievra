import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/home_extras.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/recovery.dart';
import 'package:treenipaivakirja/sleep.dart';

// Palautuminen-kortin värit ja kuormitus (käyttäjä 18.11.). Keksityt arvot.
void main() {
  final today = DateTime(2026, 11, 18);

  test('yösyke: +3 keltainen, +5 punainen, liian vähän öitä harmaa', () {
    expect(nightHrState(NightHr(today, 50, 50, 49)), TileState.green);
    expect(nightHrState(NightHr(today, 53, 52, 49)), TileState.yellow);
    expect(nightHrState(NightHr(today, 56, 54, 49)), TileState.red);
    expect(nightHrState(NightHr(today, 56, 54, null)), TileState.none);
  });

  test('yöarvot: lievä poikkeama keltainen, tutkimusraja punainen', () {
    Map<DateTime, NightMetrics> m(NightMetrics Function(int i) f) => {
      for (var i = 0; i < 30; i++) addDays(today, -i): f(i),
    };
    final base = m((i) => const NightMetrics(rr: 14, temp: 0, spo2: 97));
    final rr2 = {...base, today: const NightMetrics(rr: 15.8, temp: 0.35, spo2: 96)};
    expect(metricState('rr', metricStat(rr2, 'rr', today)!, rr2, today), TileState.yellow);
    expect(metricState('temp', metricStat(rr2, 'temp', today)!, rr2, today), TileState.yellow);
    expect(metricState('spo2', metricStat(rr2, 'spo2', today)!, rr2, today), TileState.yellow);
    final ill = {...base, today: const NightMetrics(rr: 17.5, temp: 0.6, spo2: 97)};
    expect(metricState('rr', metricStat(ill, 'rr', today)!, ill, today), TileState.red);
    expect(metricState('temp', metricStat(ill, 'temp', today)!, ill, today), TileState.red);
    expect(metricState('spo2', metricStat(ill, 'spo2', today)!, ill, today), TileState.green);
  });

  test('uni: 6 h tai alle punainen, 45 min alle tavallisen keltainen', () {
    SleepNight n(int day, int min) => SleepNight(
      addDays(today, -day),
      DateTime(today.year, today.month, today.day - day - 1, 23),
      DateTime(today.year, today.month, today.day - day, 7),
      Duration(minutes: min),
    );
    final base = {for (var i = 1; i < 30; i++) addDays(today, -i): n(i, 450)};
    expect(sleepTileState(sleepStats({...base, today: n(0, 440)}, today)), TileState.green);
    expect(sleepTileState(sleepStats({...base, today: n(0, 400)}, today)), TileState.yellow);
    expect(sleepTileState(sleepStats({...base, today: n(0, 355)}, today)), TileState.red);
  });

  test('kuormitus: viikko vs. 4 viikon keskiarvo; alle 3 viikkoa historiaa ei arviota', () {
    Workout run(int d, int min, {String intensity = 'reipas'}) => Workout(date: addDays(today, -d), title: 'Juoksu')
      ..activity = 'Juoksu'
      ..intensity = intensity
      ..seconds = min * 60;
    final steady = [for (var d = 0; d < 28; d += 3) run(d, 40)];
    expect(trainingLoad(steady, today)!.$1, TrainLoad.normal);
    final spike = [...steady, for (var d = 0; d < 6; d++) run(d, 60, intensity: 'kova')];
    expect(trainingLoad(spike, today)!.$1, TrainLoad.hard);
    expect(loadTileState(TrainLoad.hard), TileState.yellow, reason: 'ei koskaan punainen');
    final rest = [for (var d = 9; d < 28; d += 3) run(d, 40)];
    expect(trainingLoad(rest, today)!.$1, TrainLoad.light);
    expect(trainingLoad([run(2, 40), run(10, 40)], today), isNull);
  });
}
