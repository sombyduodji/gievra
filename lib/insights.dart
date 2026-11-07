import 'dart:math' as math;

import 'exercises.dart';
import 'models.dart';

// Edistymisen seuranta ja kevennysviikkovinkit.
//
// Perusta:
// - Rogerson ym. 2024, Sports Medicine – Open (kysely, 246 voima- ja fysiikkaurheilijaa): kevennys
//   tehtiin keskimäärin 5,6 ± 2,3 viikon välein ja se kesti 6,4 ± 1,7 päivää. Sarjoja ja toistoja
//   vähennettiin, kuormaa ja ponnistelua kevennettiin, treenitiheys pysyi samana.
// - Bell ym. 2023, Sports Medicine – Open (Delphi-konsensus): kevennys mesosyklin lopussa tai välissä,
//   volyymia vähennetään, lisäksi autoregulaatio eli kevennys väsymyksen tai suoritusdatan perusteella.

/// Arvioitu yhden toiston maksimi (Epley). Yli 12 toiston sarjoja ei käytetä, arvio epätarkka.
double? e1rm(double kg, int reps) {
  if (kg <= 0 || reps < 1 || reps > 12) return null;
  return reps == 1 ? kg : kg * (1 + reps / 30);
}

DateTime weekStart(DateTime d) => addDays(d, 1 - d.weekday);

class Progress {
  final String exercise;
  final double before;
  final double now;
  Progress(this.exercise, this.before, this.now);
  double get pct => (now - before) / before * 100;
}

class Insights {
  /// Viikot putkeen ilman kevennystä (nykyinen viikko mukaan lukien, jos siinä on treenejä).
  final int loadingWeeks;
  final bool suggestDeload;
  final bool autoregulated; // ehdotus tuli junnaavista nostoista, ei pelkästä viikkomäärästä
  final List<Progress> improving;
  final List<Progress> stalled;
  final int prs30d;
  Insights({
    required this.loadingWeeks,
    required this.suggestDeload,
    required this.autoregulated,
    required this.improving,
    required this.stalled,
    required this.prs30d,
  });

  bool get isEmpty => !suggestDeload && improving.isEmpty && stalled.isEmpty && prs30d == 0;
}

/// [workouts] missä tahansa järjestyksessä. [deloadEvery]: suositusväli viikkoina.
Insights analyze(List<Workout> workouts, {DateTime? now, int deloadEvery = 6}) {
  final today = dateOnly(now ?? DateTime.now());
  final ws = [...workouts]..sort((a, b) => a.date.compareTo(b.date));

  // --- Viikkovolyymi (sarjat) ja kevennysviikon tunnistus -----------------
  final setsPerWeek = <DateTime, int>{};
  for (final w in ws) {
    final k = weekStart(w.date);
    setsPerWeek[k] = (setsPerWeek[k] ?? 0) + w.exercises.fold(0, (a, e) => a + e.workSets.length);
  }
  // Kuljetaan viikkoja taaksepäin nykyisestä. Kevyt viikko = tauko tai alle 60 % edeltävän
  // neljän viikon keskiarvosta. Kuluva viikko ei katkaise putkea, jos se on vasta kesken.
  var loading = 0;
  final thisWeek = weekStart(today);
  for (var wk = thisWeek; ; wk = addDays(wk, -7)) {
    final n = setsPerWeek[wk] ?? 0;
    if (wk == thisWeek && n == 0) continue;
    final prev = [for (var i = 1; i <= 4; i++) setsPerWeek[addDays(wk, -7 * i)] ?? 0];
    final avg = prev.reduce((a, b) => a + b) / 4;
    final light = n == 0 || (avg > 0 && n < avg * .6);
    if (light && !(wk == thisWeek)) break;
    if (!light) loading++;
    if (loading > 52) break;
  }

  // --- Edistyminen liikkeittäin (paras arvioitu 1RM) ---------------------
  final recentFrom = addDays(today, -28);
  final baseFrom = addDays(today, -84);
  final stallFrom = addDays(today, -42);
  final best = <String, Map<String, double>>{}; // liike -> {recent, base, stallNow, stallBefore}
  final sessions = <String, int>{};
  final setsTotal = <String, int>{};
  for (final w in ws) {
    if (w.date.isBefore(addDays(today, -126))) continue;
    for (final e in w.exercises) {
      if (measureOf(e.name) != Measure.reps) continue;
      var top = 0.0;
      for (final s in e.sets) {
        top = math.max(top, e1rm(s.kg, s.reps) ?? 0);
      }
      if (top == 0) continue;
      final m = best[e.name] ??= {};
      void up(String k) => m[k] = math.max(m[k] ?? 0, top);
      if (!w.date.isBefore(recentFrom)) {
        up('recent');
      } else if (!w.date.isBefore(baseFrom)) {
        up('base');
      }
      if (!w.date.isBefore(stallFrom)) {
        up('stallNow');
        sessions[e.name] = (sessions[e.name] ?? 0) + 1;
        setsTotal[e.name] = (setsTotal[e.name] ?? 0) + e.workSets.length;
      } else {
        up('stallBefore');
      }
    }
  }
  final improving = <Progress>[];
  final stalled = <Progress>[];
  for (final MapEntry(key: name, value: m) in best.entries) {
    final r = m['recent'], b = m['base'];
    if (r != null && b != null && r > b * 1.01) improving.add(Progress(name, b, r));
    // Junnaa: vähintään 4 kertaa viimeisen 6 viikon aikana eikä parempi kuin sitä ennen.
    final sn = m['stallNow'], sb = m['stallBefore'];
    if (sn != null && sb != null && (sessions[name] ?? 0) >= 4 && sn <= sb) {
      stalled.add(Progress(name, sb, sn));
    }
  }
  improving.sort((a, b) => b.pct.compareTo(a.pct));
  stalled.sort((a, b) => (setsTotal[b.exercise] ?? 0).compareTo(setsTotal[a.exercise] ?? 0));

  final prs = ws
      .where((w) => !w.date.isBefore(addDays(today, -30)))
      .fold(0, (a, w) => a + w.exercises.fold(0, (b, e) => b + e.sets.where((s) => s.pr).length));

  // Ehdotus: suositusväli täynnä, tai jo 4+ viikkoa ja vähintään kaksi liikettä junnaa.
  final byWeeks = loading >= deloadEvery;
  final byStall = loading >= 4 && stalled.length >= 2;
  return Insights(
    loadingWeeks: loading,
    suggestDeload: byWeeks || byStall,
    autoregulated: !byWeeks && byStall,
    improving: improving.take(3).toList(),
    stalled: stalled.take(3).toList(),
    prs30d: prs,
  );
}

/// Liikkeen paras sarja arvioidun maksimin mukaan (Epley, enintään 12 toistoa).
class LiftRecord {
  final DateTime date;
  final double kg;
  final int reps;
  final double e1rm;
  const LiftRecord(this.date, this.kg, this.reps, this.e1rm);
}

LiftRecord? bestLift(List<Workout> ws, String exercise, {DateTime? since, DateTime? until}) {
  LiftRecord? best;
  for (final w in ws) {
    if (since != null && w.date.isBefore(since)) continue;
    if (until != null && w.date.isAfter(until)) continue;
    for (final e in w.exercises.where((e) => e.name == exercise)) {
      for (final s in e.sets) {
        final v = e1rm(s.kg, s.reps);
        if (v != null && (best == null || v > best.e1rm)) best = LiftRecord(w.date, s.kg, s.reps, v);
      }
    }
  }
  return best;
}

/// Maksimiehdotus aloituskyselyyn: paras arvio viimeiseltä 6 kuukaudelta. Jos liikettä ei ole tehty
/// puoleen vuoteen, käytetään 6 kuukautta ennen viimeistä kertaa (ja palautetaan sen päivä).
(LiftRecord?, DateTime? oldWindowEnd) suggestedMax(List<Workout> ws, String exercise, DateTime today) {
  final recent = bestLift(ws, exercise, since: addDays(today, -183));
  if (recent != null) return (recent, null);
  DateTime? last;
  for (final w in ws) {
    if (w.exercises.any((e) => e.name == exercise && e.sets.any((s) => e1rm(s.kg, s.reps) != null)) &&
        (last == null || w.date.isAfter(last))) {
      last = w.date;
    }
  }
  if (last == null) return (null, null);
  return (bestLift(ws, exercise, since: addDays(last, -183), until: last), last);
}
