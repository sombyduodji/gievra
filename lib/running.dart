import 'insights.dart' show weekStart;
import 'models.dart';
import 'sports.dart';

/// Juoksun kehitys omana kokonaisuutenaan (ei sekoitu salin tai kahvakuulan edistymiseen).

/// Juoksut (Juoksu, Hölkkä), joissa on matka ja kesto; uusin ensin.
List<Workout> runsOf(List<Workout> ws) => [
  for (final w in ws)
    if (isRun(w.activity) && (w.distanceKm ?? 0) > 0 && (w.durationSec ?? 0) > 0) w,
]..sort((a, b) => b.date.compareTo(a.date));

class RunWeek {
  final DateTime start;
  double km = 0;
  int sec = 0, runs = 0;
  RunWeek(this.start);

  /// Viikon keskivauhti (s/km), matkalla painotettu.
  double? get pace => km > 0 ? sec / km : null;
}

/// Viimeiset [n] viikkoa vanhimmasta uusimpaan (myös tyhjät viikot).
List<RunWeek> runWeeks(List<Workout> runs, DateTime today, {int n = 12}) {
  final first = addDays(weekStart(dateOnly(today)), -7 * (n - 1));
  final weeks = [for (var i = 0; i < n; i++) RunWeek(addDays(first, 7 * i))];
  for (final r in runs) {
    final i = r.date.difference(first).inDays ~/ 7;
    if (r.date.isBefore(first) || i >= n) continue;
    weeks[i]
      ..km += r.distanceKm!
      ..sec += r.durationSec!
      ..runs += 1;
  }
  return weeks;
}

/// Paras suoritus vähintään [km] pitkästä juoksusta: nopein keskivauhti, aika laskettuna [km]:lle.
class RunBest {
  final double km;
  final Workout run;
  RunBest(this.km, this.run);
  int get sec => (run.paceSecPerKm! * km).round();
}

/// Ennätykset vakiomatkoille (5 km, 10 km, puolimaraton, maraton): nopein keskivauhti juoksuista, joiden
/// matka on vähintään vakiomatka (pidemmän juoksun keskivauhti on aina saavutettu koko matkalla).
List<RunBest> runBests(List<Workout> runs) {
  final out = <RunBest>[];
  for (final km in [5.0, 10.0, 21.0975, 42.195]) {
    final c = runs.where((r) => r.distanceKm! >= km - .05);
    if (c.isEmpty) continue;
    out.add(RunBest(km, c.reduce((a, b) => a.paceSecPerKm! <= b.paceSecPerKm! ? a : b)));
  }
  return out;
}

class RunTypeStats {
  final String type; // runTypes-avain tai '' (ei tyyppiä)
  int runs = 0, sec = 0, hrN = 0, hrSum = 0;
  double km = 0;
  RunTypeStats(this.type);
  double? get pace => km > 0 ? sec / km : null;
  int? get hrAvg => hrN > 0 ? (hrSum / hrN).round() : null;
}

/// Tyypeittäin: määrä, km, keskivauhti ja keskisyke (jos kellon tiedot).
List<RunTypeStats> runTypeStats(List<Workout> runs) {
  final m = <String, RunTypeStats>{};
  for (final r in runs) {
    final s = m.putIfAbsent(r.runType ?? '', () => RunTypeStats(r.runType ?? ''))
      ..runs += 1
      ..km += r.distanceKm!
      ..sec += r.durationSec!;
    if (r.hrAvg != null) {
      s
        ..hrN += 1
        ..hrSum += r.hrAvg!;
    }
  }
  final order = [for (final t in runTypes) t.$1, ''];
  return m.values.toList()..sort((a, b) => order.indexOf(a.type).compareTo(order.indexOf(b.type)));
}

/// Kehitys: kevyiden lenkkien (kevyt, palauttava, pitkä tai ei tyyppiä) keskivauhti ja -syke viimeisten
/// 4 viikon ajalta verrattuna sitä edeltäviin 4 viikkoon. Sama vauhti matalammalla sykkeellä tai nopeampi
/// vauhti samalla sykkeellä = peruskunto paranee.
class RunTrend {
  final double? paceNow, pacePrev;
  final int? hrNow, hrPrev;
  final int nNow, nPrev;
  RunTrend(this.paceNow, this.pacePrev, this.hrNow, this.hrPrev, this.nNow, this.nPrev);
}

RunTrend easyRunTrend(List<Workout> runs, DateTime today) {
  bool easy(Workout r) => r.runType == null || const {'kevyt', 'palauttava', 'pitka'}.contains(r.runType);
  final t = dateOnly(today);
  (double?, int?, int) agg(DateTime from, DateTime to) {
    var km = 0.0, sec = 0, hrN = 0, hr = 0, n = 0;
    for (final r in runs) {
      if (!easy(r) || r.date.isBefore(from) || !r.date.isBefore(to)) continue;
      n++;
      km += r.distanceKm!;
      sec += r.durationSec!;
      if (r.hrAvg != null) {
        hrN++;
        hr += r.hrAvg!;
      }
    }
    return (km > 0 ? sec / km : null, hrN > 0 ? (hr / hrN).round() : null, n);
  }

  final now = agg(addDays(t, -27), addDays(t, 1));
  final prev = agg(addDays(t, -55), addDays(t, -27));
  return RunTrend(now.$1, prev.$1, now.$2, prev.$2, now.$3, prev.$3);
}

/// Edellinen samantyyppinen juoksu (vertailuun tallennuksen jälkeen).
Workout? previousRun(List<Workout> ws, Workout run) {
  for (final r in runsOf(ws)) {
    if (identical(r, run) || (r.date == run.date && r.session == run.session)) continue;
    if (r.date.isAfter(run.date)) continue;
    if (r.runType == run.runType) return r;
  }
  return null;
}
