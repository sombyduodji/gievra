import 'insights.dart' show weekStart;
import 'l10n.dart';
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

/// Kehitys: kevyiden lenkkien (rasitus Kevyt tai merkitsemättä; vanhoissa myös lenkin tyyppi) keskivauhti ja -syke viimeisten
/// 4 viikon ajalta verrattuna sitä edeltäviin 4 viikkoon. Sama vauhti matalammalla sykkeellä tai nopeampi
/// vauhti samalla sykkeellä = peruskunto paranee.
class RunTrend {
  final double? paceNow, pacePrev;
  final int? hrNow, hrPrev;
  final int nNow, nPrev;
  RunTrend(this.paceNow, this.pacePrev, this.hrNow, this.hrPrev, this.nNow, this.nPrev);
}

RunTrend easyRunTrend(List<Workout> runs, DateTime today) {
  bool easy(Workout r) =>
      r.intensity == 'kevyt' ||
      (r.intensity == null && (r.runType == null || const {'kevyt', 'palauttava', 'pitka'}.contains(r.runType)));
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

/// Edellinen suunnilleen yhtä pitkä juoksu (±20 %) vertailuun tallennuksen jälkeen.
Workout? previousRun(List<Workout> ws, Workout run) {
  for (final r in runsOf(ws)) {
    if (identical(r, run) || (r.date == run.date && r.session == run.session)) continue;
    if (r.date.isAfter(run.date)) continue;
    final a = r.distanceKm ?? 0, b = run.distanceKm ?? 0;
    if (b > 0 && (a - b).abs() <= b * 0.2) return r;
  }
  return null;
}

/// Juoksun matkaryhmä etusivun Kehitys-kortissa (käyttäjä 17.11.): alle 5 km, 5–10 km ja yli 10 km, jotta lyhyitä ja
/// pitkiä lenkkejä ei verrata keskenään.
class RunGroup {
  final String label; // '< 5 km', '5–10 km', '> 10 km'
  final double pace, prevPace; // s/km, matkalla painotettu
  final int? hr, prevHr; // keskisyke lenkeistä, joissa on syke
  final int runs, prevRuns;
  const RunGroup(this.label, this.pace, this.prevPace, this.hr, this.prevHr, this.runs, this.prevRuns);

  /// Vauhdin muutos sekunteina kilometrille (negatiivinen = nopeampi).
  int get paceDelta => (pace - prevPace).round();
}

/// Juoksun matkaryhmä etusivun Kehitys-kortissa: matka [lo, hi) km, hi null = ei ylärajaa.
typedef RunBand = (double, double?);

/// Oletus: alle 5, 5–10 ja yli 10 km. Käyttäjä voi valita 1–3 omaa ryhmää asetuksista (käyttäjä 17.11.).
const defaultRunBands = <RunBand>[(0, 5), (5, 10), (10, null)];

String runBandLabel(RunBand b) => switch (b) {
  (0, null) => t('kaikki matkat'),
  (0, final double hi) => '< ${fmtNum(hi)} km',
  (final lo, null) => '> ${fmtNum(lo)} km',
  (final lo, final double hi) => '${fmtNum(lo)}–${fmtNum(hi)} km',
};

/// Tiedostoon: "0-5; 5-10; 10-" (desimaalit pilkulla).
String runBandsToFile(List<RunBand> bands) =>
    bands.map((b) => '${fileNum(b.$1)}-${b.$2 == null ? '' : fileNum(b.$2!)}').join('; ');

/// Tiedostosta; virheelliset ryhmät ohitetaan, enintään 3. Tyhjä tulos = oletus.
List<RunBand> runBandsFromFile(String v) {
  final out = <RunBand>[];
  for (final part in v.split(';')) {
    final m = RegExp(r'^\s*([0-9]+(?:,[0-9]+)?)\s*-\s*([0-9]+(?:,[0-9]+)?)?\s*$').firstMatch(part);
    if (m == null) continue;
    final lo = parseNum(m.group(1)!)!;
    final hi = m.group(2) == null ? null : parseNum(m.group(2)!);
    if (hi != null && hi <= lo) continue;
    out.add((lo, hi));
    if (out.length == 3) break;
  }
  return out.isEmpty ? defaultRunBands : out;
}

/// Matkaryhmät, joissa on vähintään [minRuns] juoksua sekä viimeisten 4 viikon aikana että 8 viikkoa ennen sitä.
List<RunGroup> runGroups(List<Workout> ws, DateTime today, {int minRuns = 2, List<RunBand> bands = defaultRunBands}) {
  final t0 = addDays(today, -28);
  final t1 = addDays(today, -84);
  final out = <RunGroup>[];
  for (final b in bands) {
    final (lo, hi0) = b;
    final hi = hi0 ?? double.infinity;
    final label = runBandLabel(b);
    final now = <Workout>[], before = <Workout>[];
    for (final w in runsOf(ws)) {
      final km = w.distanceKm!;
      if (km < lo || km >= hi || w.date.isAfter(today)) continue;
      if (!w.date.isBefore(t0)) {
        now.add(w);
      } else if (!w.date.isBefore(t1)) {
        before.add(w);
      }
    }
    if (now.length < minRuns || before.length < minRuns) continue;
    double pace(List<Workout> l) =>
        l.fold<double>(0, (a, w) => a + w.durationSec!) / l.fold<double>(0, (a, w) => a + w.distanceKm!);
    int? hr(List<Workout> l) {
      final h = [
        for (final w in l)
          if (w.hrAvg != null) w.hrAvg!,
      ];
      return h.isEmpty ? null : (h.reduce((a, b) => a + b) / h.length).round();
    }

    out.add(RunGroup(label, pace(now), pace(before), hr(now), hr(before), now.length, before.length));
  }
  return out;
}

/// Oma tavoite "Juoksuvauhdin kehitys" (käyttäjä 18.11.): jakson juoksujen vauhti verrattuna 4 edelliseen viikkoon
/// samassa matkaryhmässä (lyhyttä lenkkiä ei verrata pitkään). Ryhmien erotukset painotetaan jakson kilometreillä.
/// Negatiivinen = nopeampi (s/km). Null = ei vertailtavaa (jaksolla tai sitä edeltävällä 4 viikolla ei juoksua
/// samassa ryhmässä).
double? paceProgress(List<Workout> ws, DateTime from, DateTime next, List<RunBand> bands) {
  final before = addDays(from, -28);
  final runs = runsOf(ws);
  var wsum = 0.0, dsum = 0.0;
  for (final (lo, hi0) in bands) {
    final hi = hi0 ?? double.infinity;
    var kmN = 0.0, secN = 0.0, kmB = 0.0, secB = 0.0;
    for (final r in runs) {
      final km = r.distanceKm!;
      if (km < lo || km >= hi) continue;
      if (!r.date.isBefore(from) && r.date.isBefore(next)) {
        kmN += km;
        secN += r.durationSec!;
      } else if (!r.date.isBefore(before) && r.date.isBefore(from)) {
        kmB += km;
        secB += r.durationSec!;
      }
    }
    if (kmN == 0 || kmB == 0) continue;
    dsum += (secN / kmN - secB / kmB) * kmN;
    wsum += kmN;
  }
  return wsum == 0 ? null : dsum / wsum;
}

/// Oma tavoite "Vauhti samalla sykkeellä": metrejä sydämenlyöntiä kohden (matka / (kesto × keskisyke)) jakson
/// juoksuista verrattuna 4 edelliseen viikkoon, prosentteina (positiivinen = nopeampi samalla sykkeellä, eli
/// peruskunto paranee). Vain juoksut, joissa on keskisyke. Null = ei vertailtavaa.
double? hrPaceProgress(List<Workout> ws, DateTime from, DateTime next) {
  final before = addDays(from, -28);
  var mN = 0.0, bN = 0.0, mB = 0.0, bB = 0.0;
  for (final r in runsOf(ws)) {
    final hr = r.hrAvg;
    if (hr == null || hr < 60) continue;
    final beats = r.durationSec! / 60 * hr;
    final m = r.distanceKm! * 1000;
    if (!r.date.isBefore(from) && r.date.isBefore(next)) {
      mN += m;
      bN += beats;
    } else if (!r.date.isBefore(before) && r.date.isBefore(from)) {
      mB += m;
      bB += beats;
    }
  }
  if (bN == 0 || bB == 0) return null;
  return (mN / bN) / (mB / bB) * 100 - 100;
}
