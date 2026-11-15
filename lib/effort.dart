import 'hr_calc.dart';
import 'models.dart';
import 'sports.dart';

// Rasituksen arvio treenin lopun kyselyyn (Kevyt / Reipas / Kova esivalittuna, käyttäjä voi vaihtaa).
//
// Sykkeestä (vyön lukemat vähintään puolelta kestosta): keskisyke prosentteina maksimista. Rajat ACSM:n
// (Garber ym. 2011, Med Sci Sports Exerc 43(7):1334–1359) kohtuullisen ja raskaan rasituksen sykealueista:
// kohtuullinen 64–76 %, raskas 77–95 % maksimisykkeestä; alle 64 % = kevyt.
// Vauhdista (ei sykettä): kävelylajit alle 4 km/h kevyt (sama raja kuin viikon liikunnassa, weekly_activity.dart),
// alle 6,5 km/h reipas, nopeammin kova; juoksu alle 8 km/h reipas, nopeammin kova (Compendium: juoksu 8 km/h
// noin 8 MET = raskas). Muut lajit: ei arviota.

enum EffortSource { heartRate, pace }

/// Arvio: (rasitus 'kevyt' / 'reipas' / 'kova', mistä arvioitu) tai null.
(String, EffortSource)? estimateEffort(Workout w, {HrSeries? series, int? maxHr, int? durationSec}) {
  final dur = durationSec ?? w.durationSec;
  if (series != null && maxHr != null && maxHr > 0 && dur != null && dur > 0 && series.coverage(dur) >= .5) {
    final avg = series.avg;
    if (avg != null) {
      final pct = avg / maxHr;
      return (pct < .64 ? 'kevyt' : (pct < .77 ? 'reipas' : 'kova'), EffortSource.heartRate);
    }
  }
  final km = w.distanceKm;
  final sport = sportOf(w.activity);
  if (km == null || km <= 0 || dur == null || dur < 60 || !(sport?.steps ?? false)) return null;
  final kmh = km / (dur / 3600);
  if (isRun(w.activity)) return (kmh < 8 ? 'reipas' : 'kova', EffortSource.pace);
  return (kmh < 4 ? 'kevyt' : (kmh < 6.5 ? 'reipas' : 'kova'), EffortSource.pace);
}

/// Salitreenin nostot yhteenvetoon: ennätysten määrä ja suurin painonnousu edelliseen samaan liikkeeseen
/// (liike, kg). [history]: aiemmat treenit (ei tätä).
(int, (String, double)?) gymHighlights(Workout w, List<Workout> history) {
  final prs = w.exercises.expand((e) => e.sets).where((s) => s.pr).length;
  (String, double)? best;
  for (final e in w.exercises) {
    final work = e.workSets;
    if (work.isEmpty) continue;
    final top = work.map((s) => s.kg).reduce((a, b) => a > b ? a : b);
    if (top <= 0) continue;
    final prev = history
        .where((o) => o.date.isBefore(w.date) || (o.date == w.date && o.session < w.session))
        .where((o) => o.exercises.any((x) => x.name == e.name && x.workSets.isNotEmpty))
        .fold<Workout?>(null, (a, o) => a == null || o.date.isAfter(a.date) ? o : a);
    if (prev == null) continue;
    final prevTop = prev.exercises
        .firstWhere((x) => x.name == e.name)
        .workSets
        .map((s) => s.kg)
        .reduce((a, b) => a > b ? a : b);
    final up = top - prevTop;
    if (up > 0 && (best == null || up > best.$2)) best = (e.name, up);
  }
  return (prs, best);
}
