// Etusivun lisäkortit (käyttäjä 17.11.): viikkoputki, seuraava ohjelman päivä ja yön alin syke. Tässä vain laskenta,
// jotta sen voi testata ilman käyttöliittymää; kortit ovat tiedostossa ui/home_extras_ui.dart.

import 'app_state.dart' show Pause;
import 'insights.dart' show weekStart;
import 'models.dart';
import 'weekly_activity.dart';

/// Viikon tila putkessa: molemmat WHO:n suositukset (lihaskunto 2 päivänä ja 150 min reipasta liikuntaa),
/// toinen niistä, ei kumpaakaan, tauko (sairas, loma tai vamma vähintään 4 päivää: ei katkaise putkea) tai
/// kesken (kuluva viikko, jolla suositukset eivät vielä täyty).
enum WeekMark { both, one, none, pause, open }

class Streak {
  final int current, best;

  /// Viimeiset viikot vanhimmasta uusimpaan (kuluva viimeisenä): viikon maanantai ja tila.
  final List<(DateTime, WeekMark)> weeks;
  const Streak(this.current, this.best, this.weeks);
}

bool _paused(DateTime mon, List<Pause> pauses) {
  var n = 0;
  for (var d = mon; d.isBefore(addDays(mon, 7)); d = addDays(d, 1)) {
    if (pauses.any((p) => !d.isBefore(p.start) && (p.end == null || !d.isAfter(p.end!)))) n++;
  }
  return n >= 4;
}

/// Viikkoputki [today]-päivään asti. Kuluva viikko lasketaan mukaan vasta, kun suositukset täyttyvät; muuten se
/// on kesken eikä katkaise putkea. Taukoviikot ohitetaan. [show] = montako viikkoa palautetaan näytettäväksi.
Streak whoStreak(List<Workout> workouts, DateTime today, {List<Pause> pauses = const [], int show = 8}) {
  final thisMon = weekStart(dateOnly(today));
  if (workouts.isEmpty) return Streak(0, 0, [(thisMon, WeekMark.open)]);
  final first = weekStart(workouts.map((w) => w.date).reduce((a, b) => a.isBefore(b) ? a : b));
  final marks = <(DateTime, WeekMark)>[];
  for (var mon = first; !mon.isAfter(thisMon); mon = addDays(mon, 7)) {
    final a = periodActivity(workouts, mon, addDays(mon, 7));
    final met = (a.strengthMet ? 1 : 0) + (a.minutesMet ? 1 : 0);
    final mark = met == 2
        ? WeekMark.both
        : mon == thisMon
        ? WeekMark.open
        : _paused(mon, pauses)
        ? WeekMark.pause
        : met == 1
        ? WeekMark.one
        : WeekMark.none;
    marks.add((mon, mark));
  }
  var run = 0, best = 0;
  for (final (_, m) in marks) {
    if (m == WeekMark.both) {
      run++;
      if (run > best) best = run;
    } else if (m == WeekMark.one || m == WeekMark.none) {
      run = 0;
    }
  }
  final shown = marks.length > show ? marks.sublist(marks.length - show) : marks;
  return Streak(run, best, shown);
}

/// Yön alin syke: viimeisin yö, kolmen viimeisen yön keskiarvo ja tavallinen taso (mediaani 28 yöstä ennen niitä).
class NightHr {
  final DateTime lastDay;
  final int last;
  final double recent;
  final double? base;
  const NightHr(this.lastDay, this.last, this.recent, this.base);

  /// Ero tavalliseen (lyöntiä minuutissa); null = liian vähän öitä vertailuun (alle 7).
  double? get delta => base == null ? null : recent - base!;
}

/// [nights] = päivä (aamu, jona yö päättyi) → alin syke. Null, jos viimeisestä yöstä on yli 3 päivää.
NightHr? nightHr(Map<DateTime, int> nights, DateTime today) {
  if (nights.isEmpty) return null;
  final days = nights.keys.toList()..sort();
  final lastDay = days.last;
  if (dateOnly(today).difference(lastDay).inDays > 3) return null;
  final recentDays = days.where((d) => !d.isBefore(addDays(lastDay, -2))).toList();
  final recent = recentDays.map((d) => nights[d]!).reduce((a, b) => a + b) / recentDays.length;
  final from = addDays(recentDays.first, -28);
  final older = [
    for (final d in days)
      if (!d.isBefore(from) && d.isBefore(recentDays.first)) nights[d]!,
  ]..sort();
  double? base;
  if (older.length >= 7) {
    final m = older.length ~/ 2;
    base = older.length.isOdd ? older[m].toDouble() : (older[m - 1] + older[m]) / 2;
  }
  return NightHr(lastDay, nights[lastDay]!, recent, base);
}
