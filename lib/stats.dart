import 'dart:math' as math;

import 'exercises.dart';
import 'insights.dart';
import 'models.dart';
import 'session_compare.dart';
import 'l10n.dart' as l10n;

// Edistyminen ja tilastot: viikko- ja kuukausikoosteet, fiiliksen kehitys (viikoittain, viikonpäivittäin,
// treenipäivittäin ja liikkeittäin), voimakehitys ja ehdotukset, kun fiilis laskee.

/// Lajin osuus jaksossa: kerrat, minuutit ja kilometrit.
class SportShare {
  int count = 0, minutes = 0;
  double km = 0;
}

class Recap {
  final DateTime from, to; // to = seuraavan jakson alku
  int gym = 0, activities = 0, sets = 0, prs = 0, minutes = 0, kcal = 0;
  int gymMinutes = 0, cardioMinutes = 0;
  double volume = 0, km = 0;
  final List<int> feelings = [];
  final List<int> hr = [];
  final Map<String, SportShare> sports = {}; // laji (tiedoston nimi, suomeksi) -> osuus
  Recap(this.from, this.to);
  int get sessions => gym + activities;
  double? get feeling => feelings.isEmpty ? null : feelings.reduce((a, b) => a + b) / feelings.length;
  int? get hrAvg => hr.isEmpty ? null : (hr.reduce((a, b) => a + b) / hr.length).round();
}

/// FitNotesista tuodut kardiorivit muistiinpanoissa: "- Juoksumatto: matka 5, aika 30:00".
final _cardioNote = RegExp(r'^- [^:\n]+: (?:matka [\d.,]+)?(?:, )?(?:aika (\d+):(\d\d))?\s*$', multiLine: true);

/// Tuotu kestävyystreeni ilman lajia: ei sarjoja, mutta muistiinpanoissa FitNotesin kardiorivejä.
bool isNoteCardio(Workout w) =>
    w.activity == null && !w.exercises.any((e) => e.sets.isNotEmpty) && _cardioNote.hasMatch(w.notes);

/// Salitreeni (sarjoja) vai kestävyys (laji tai tuotu kardio). null = tyhjä treeni.
String? workoutKind(Workout w) => w.activity != null || isNoteCardio(w)
    ? 'cardio'
    : w.exercises.any((e) => e.sets.isNotEmpty)
    ? 'gym'
    : null;

/// FitNotesin kardiorivien yhteisaika minuutteina (muistiinpanoista).
int noteCardioMinutes(Workout w) {
  var s = 0;
  for (final m in _cardioNote.allMatches(w.notes)) {
    if (m[1] != null) s += int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }
  return (s / 60).round();
}

/// Treenin kesto minuutteina: kirjattu kesto, kestävyyslajin tarkka aika tai tuodun kardion aika.
/// Salitreenin kestoa ei arvioida, jos sitä ei ole kirjattu.
int workoutMinutes(Workout w) {
  if (w.minutes != null) return w.minutes!;
  if (w.seconds != null) return (w.seconds! / 60).round();
  return isNoteCardio(w) ? noteCardioMinutes(w) : 0;
}

/// Treenin osat koosteeseen: ('gym' | 'cardio', minuutit). FitNotesin päivä, jossa on sekä sarjoja että
/// kardiorivejä, on kaksi osaa: salitreeni ja kestävyys (muistiinpanojen aika).
List<(String, int)> workoutParts(Workout w) {
  final k = workoutKind(w);
  if (k == null) return const [];
  if (k == 'gym' && _cardioNote.hasMatch(w.notes)) return [('gym', w.minutes ?? 0), ('cardio', noteCardioMinutes(w))];
  return [(k, workoutMinutes(w))];
}

/// Jakson kooste. [kind]: 'all' = kaikki, 'gym' = salitreenit, 'cardio' = liikunta ja lajit.
Recap recap(List<Workout> ws, DateTime from, DateTime to, {String kind = 'all'}) {
  final r = Recap(from, to);
  for (final w in ws) {
    if (w.date.isBefore(from) || !w.date.isBefore(to)) continue;
    var counted = false;
    for (final (k, mins) in workoutParts(w)) {
      if (kind != 'all' && kind != k) continue;
      counted = true;
      r.minutes += mins;
      if (k == 'cardio') {
        r.activities++;
        r.cardioMinutes += mins;
        final s = r.sports.putIfAbsent(w.activity ?? 'Muu liikunta', SportShare.new);
        s.count++;
        s.minutes += mins;
        if (w.activity != null) {
          r.km += w.distanceKm ?? 0;
          s.km += w.distanceKm ?? 0;
          if (w.hrAvg != null) r.hr.add(w.hrAvg!);
        }
      } else {
        r.gym++;
        r.gymMinutes += mins;
        r.sets += w.exercises.fold(0, (a, e) => a + e.workSets.length);
        r.prs += w.exercises.expand((e) => e.sets).where((s) => s.pr).length;
        r.volume += workVolume(w);
      }
    }
    if (!counted) continue;
    r.kcal += w.kcal ?? 0;
    if (w.feeling != null) r.feelings.add(w.feeling!);
  }
  return r;
}

/// Treenit viikoittain [weeks] viikolta, viimeisenä [today]:n viikko: (viikon alku, salitreenit, kestävyys).
List<(DateTime, int, int)> weeklyCounts(List<Workout> ws, DateTime today, {int weeks = 12}) {
  final first = addDays(weekStart(today), -7 * (weeks - 1));
  final out = [for (var i = 0; i < weeks; i++) (addDays(first, 7 * i), 0, 0)];
  for (final w in ws) {
    final k = workoutKind(w);
    if (k == null || w.date.isBefore(first)) continue;
    final i =
        DateTime.utc(
          w.date.year,
          w.date.month,
          w.date.day,
        ).difference(DateTime.utc(first.year, first.month, first.day)).inDays ~/
        7;
    if (i < 0 || i >= weeks) continue;
    final parts = workoutParts(w).map((p) => p.$1);
    final (d, g, c) = out[i];
    out[i] = (d, g + (parts.contains('gym') ? 1 : 0), c + (parts.contains('cardio') ? 1 : 0));
  }
  return out;
}

/// Treenit kuukausittain [months] kuukaudelta, viimeisenä [last]:n kuukausi: (kuun alku, salitreenit, kestävyys).
List<(DateTime, int, int)> monthlyCounts(List<Workout> ws, DateTime last, {int months = 12}) {
  final first = DateTime(last.year, last.month - (months - 1));
  final out = [for (var i = 0; i < months; i++) (DateTime(first.year, first.month + i), 0, 0)];
  for (final w in ws) {
    final k = workoutKind(w);
    if (k == null) continue;
    final i = (w.date.year - first.year) * 12 + w.date.month - first.month;
    if (i < 0 || i >= months) continue;
    final parts = workoutParts(w).map((p) => p.$1);
    final (d, g, c) = out[i];
    out[i] = (d, g + (parts.contains('gym') ? 1 : 0), c + (parts.contains('cardio') ? 1 : 0));
  }
  return out;
}

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime nextMonth(DateTime d) => DateTime(d.year, d.month + 1);

/// Fiiliksen keskiarvo ryhmittäin (vähintään [minN] treeniä).
class FeelingGroup {
  final String label;
  final double avg;
  final int n;
  FeelingGroup(this.label, this.avg, this.n);
}

List<FeelingGroup> _group(Iterable<(String, int)> pairs, {int minN = 1}) {
  final sum = <String, int>{}, cnt = <String, int>{};
  for (final (k, v) in pairs) {
    sum[k] = (sum[k] ?? 0) + v;
    cnt[k] = (cnt[k] ?? 0) + 1;
  }
  return [
    for (final k in sum.keys)
      if (cnt[k]! >= minN) FeelingGroup(k, sum[k]! / cnt[k]!, cnt[k]!),
  ];
}

const weekdayNames = ['ma', 'ti', 'ke', 'to', 'pe', 'la', 'su'];

class FeelingStats {
  final List<(DateTime, double, int)> weekly; // viikon alku, keskiarvo (0 = ei merkintöjä), määrä
  final List<FeelingGroup> byWeekday, byDay, byExercise;
  final double? overall;
  final int count;
  FeelingStats(this.weekly, this.byWeekday, this.byDay, this.byExercise, this.overall, this.count);
}

FeelingStats feelingStats(List<Workout> ws, DateTime today, {int weeks = 12}) {
  final rated = ws.where((w) => w.feeling != null).toList();
  final weekly = <(DateTime, double, int)>[];
  final start = weekStart(addDays(today, -7 * (weeks - 1)));
  for (var i = 0; i < weeks; i++) {
    final a = addDays(start, 7 * i), b = addDays(a, 7);
    final f = [
      for (final w in rated)
        if (!w.date.isBefore(a) && w.date.isBefore(b)) w.feeling!,
    ];
    weekly.add((a, f.isEmpty ? 0 : f.reduce((x, y) => x + y) / f.length, f.length));
  }
  final byWeekday = _group([for (final w in rated) (weekdayNames[w.date.weekday - 1], w.feeling!)])
    ..sort((a, b) => weekdayNames.indexOf(a.label).compareTo(weekdayNames.indexOf(b.label)));
  final byDay = _group([for (final w in rated) (w.activity ?? w.title, w.feeling!)], minN: 2)
    ..sort((a, b) => a.avg.compareTo(b.avg));
  final byExercise = _group([
    for (final w in rated)
      for (final e in w.exercises.where((e) => e.sets.isNotEmpty)) (e.name, w.feeling!),
  ], minN: 3)..sort((a, b) => a.avg.compareTo(b.avg));
  final overall = rated.isEmpty ? null : rated.fold(0, (a, w) => a + w.feeling!) / rated.length;
  return FeelingStats(weekly, byWeekday, byDay, byExercise, overall, rated.length);
}

/// Ehdotukset fiiliksen ja treenimäärän perusteella. Tyhjä = ei huomautettavaa.
List<String> feelingSuggestions(List<Workout> ws, DateTime today) {
  final out = <String>[];
  final rated = ws.where((w) => w.feeling != null).toList();
  if (rated.length < 4) return out;
  double? avg(DateTime a, DateTime b) {
    final f = [
      for (final w in rated)
        if (!w.date.isBefore(a) && w.date.isBefore(b)) w.feeling!,
    ];
    return f.length < 2 ? null : f.reduce((x, y) => x + y) / f.length;
  }

  final t = addDays(dateOnly(today), 1);
  final recent = avg(addDays(t, -21), t), before = avg(addDays(t, -49), addDays(t, -21));
  if (recent != null && before != null && before - recent >= .6) {
    out.add(
      l10n.t(
        'Fiilis on laskenut viimeisen 3 viikon aikana ({0} → {1}). Pidä kevennysviikko: puolet '
        'sarjoista ja painot −10 %. Tarkista myös uni, syöminen ja stressi.',
        [_f(before), _f(recent)],
      ),
    );
  }
  final last3 = (rated..sort((a, b) => b.date.compareTo(a.date))).take(3).toList();
  if (last3.length == 3 && last3.every((w) => w.feeling! <= 2)) {
    out.add(
      l10n.t(
        'Kolme viimeisintä treeniä ovat tuntuneet raskailta. Lepopäivä tai kevyempi treeni auttaa '
        'palautumaan.',
      ),
    );
  }
  final s = feelingStats(ws, today);
  final overall = s.overall!;
  for (final g in s.byWeekday.where((g) => g.n >= 3 && overall - g.avg >= .7)) {
    out.add(
      l10n.t(
        '{0} treenit tuntuvat muita raskaammilta ({1} vs. {2}). Siirrä raskain treeni toiselle '
        'päivälle tai pidä edellinen ilta rauhallisena.',
        [_weekdayLong(g.label), _f(g.avg), _f(overall)],
      ),
    );
  }
  for (final g in s.byDay.where((g) => g.n >= 3 && overall - g.avg >= .7).take(2)) {
    out.add(
      l10n.t(
        '{0} tuntuu raskaimmalta ({1}). Vähennä sarja tai kaksi tai vaihda jokin liike (☰ → '
        'Ohjelma ja tavoitteet).',
        [l10n.trName(g.label), _f(g.avg)],
      ),
    );
  }
  final ex = s.byExercise.where((g) => g.n >= 4 && overall - g.avg >= .8).take(2).toList();
  if (ex.isNotEmpty) {
    out.add(
      l10n.t(
        'Treenit, joissa on {0}, tuntuvat raskaimmilta. Kokeile kevyempää painoa, vähemmän sarjoja tai saman liikemallin toista liikettä.',
        [ex.map((g) => l10n.trName(g.label)).join(l10n.t(' tai '))],
      ),
    );
  }
  // Treenitiheys: viimeiset 4 viikkoa vs. sitä edeltävät 8.
  double perWeek(DateTime a, DateTime b, int weeks) =>
      ws.where((w) => !w.date.isBefore(a) && w.date.isBefore(b)).length / weeks;
  final now4 = perWeek(addDays(t, -28), t, 4), prev8 = perWeek(addDays(t, -84), addDays(t, -28), 8);
  if (prev8 >= 2 && now4 <= prev8 * .5) {
    out.add(
      l10n.t(
        'Treenejä on ollut vähemmän ({0} viikossa, aiemmin {1}). Lyhyempikin treeni pitää kunnon '
        'yllä; ohjelman voi muuttaa kahdelle päivälle.',
        [_f(now4), _f(prev8)],
      ),
    );
  }
  return out;
}

String _f(double v) => fmtDec(v, 1);

String _weekdayLong(String short) => {
  'ma': l10n.t('Maanantain'),
  'ti': l10n.t('Tiistain'),
  'ke': l10n.t('Keskiviikon'),
  'to': l10n.t('Torstain'),
  'pe': l10n.t('Perjantain'),
  'la': l10n.t('Lauantain'),
  'su': l10n.t('Sunnuntain'),
}[short]!;

/// Voimakehitys: paras arvioitu maksimi kuukausittain useimmin tehdyille liikkeille.
class LiftTrend {
  final String exercise;
  final List<(DateTime, double)> monthly; // kuukausi, paras e1RM
  LiftTrend(this.exercise, this.monthly);
  double? get change => monthly.length < 2 ? null : (monthly.last.$2 - monthly.first.$2) / monthly.first.$2;

  /// Viimeisin arvio alle 70 % jakson parhaasta: todennäköisemmin kevyt jakso (tekniikka, kuntoutus, tauko)
  /// kuin voiman romahdus. Näytetään neutraalisti eikä punaisena prosenttina.
  bool get light {
    if (monthly.length < 2) return false;
    final best = monthly.map((m) => m.$2).reduce(math.max);
    return monthly.last.$2 < best * .7;
  }
}

List<LiftTrend> liftTrends(List<Workout> ws, DateTime today, {int months = 6, int top = 5}) {
  final from = DateTime(today.year, today.month - months + 1);
  final count = <String, int>{};
  for (final w in ws.where((w) => !w.date.isBefore(from))) {
    for (final e in w.exercises.where((e) => e.sets.isNotEmpty && measureOf(e.name) == Measure.reps)) {
      count[e.name] = (count[e.name] ?? 0) + 1;
    }
  }
  final names = (count.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(top).map((e) => e.key);
  // Jokainen piste = paras arvio kuluvalta ja edelliseltä kuukaudelta: yksi kevyt kuukausi (tekniikka, kevennys)
  // ei näytä romahdukselta.
  return [
    for (final n in names)
      LiftTrend(n, [
        for (var i = 0; i < months; i++)
          if (bestLift(
                ws,
                n,
                since: DateTime(from.year, from.month + i - 1),
                until: addDays(DateTime(from.year, from.month + i + 1), -1),
              )
              case final r?)
            (DateTime(from.year, from.month + i), r.e1rm),
      ]),
  ].where((t) => t.monthly.isNotEmpty).toList();
}

double clamp01(double v) => math.max(0, math.min(1, v));
