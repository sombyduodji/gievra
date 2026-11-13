// Viikon liikunta WHO:n suositusta vasten (WHO 2020, aikuiset): vähintään 150 min kohtuullisesti kuormittavaa
// liikuntaa viikossa (rasittava minuutti = 2 kohtuullista) ja lihaskuntoa vähintään 2 päivänä.
//
// Rasitus liikunnasta:
// - käyttäjän valitsema rasitus: Kevyt = kevyt, Reipas = kohtuullinen, Kova = rasittava;
// - ilman valintaa kävelylajit vauhdista (≥ 4 km/h) tai askeltiheydestä (≥ 100 askelta/min, Tudor-Locke ym. 2018),
//   liikkuvuus, jooga ja pilates kevyenä, muut lajit kohtuullisena.
// Lihaskuntopäivä: salitreeni, jossa on vähintään yksi työsarja.

import 'insights.dart' show weekStart;
import 'models.dart';

const whoMinutes = 150;
const whoStrengthDays = 2;

/// Lajit, jotka ilman rasitusvalintaa lasketaan kevyeksi (MET alle 3).
const _lightSports = {'Liikkuvuus ja venyttely', 'Jooga', 'Pilates'};

enum Effort { light, moderate, vigorous }

class WeekActivity {
  /// Kohtuullisiksi muunnetut minuutit (rasittava × 2).
  final int moderateEq;
  final int vigorous, moderate, light;
  final int strengthDays;
  const WeekActivity({
    required this.moderateEq,
    required this.vigorous,
    required this.moderate,
    required this.light,
    required this.strengthDays,
  });
  bool get minutesMet => moderateEq >= whoMinutes;
  bool get strengthMet => strengthDays >= whoStrengthDays;
}

int? _minutesOf(Workout w) => w.seconds != null ? (w.seconds! / 60).round() : w.minutes;

Effort effortOf(Workout w) {
  switch (w.intensity) {
    case 'kevyt':
      return Effort.light;
    case 'reipas':
      return Effort.moderate;
    case 'kova':
      return Effort.vigorous;
  }
  final name = w.activity ?? '';
  if (_lightSports.contains(name)) return Effort.light;
  if (name == 'Kävely' || name == 'Sauvakävely' || name == 'Retkeily') {
    final min = _minutesOf(w);
    if (w.distanceKm != null && min != null && min > 0) {
      return w.distanceKm! / (min / 60) >= 4 ? Effort.moderate : Effort.light;
    }
    if (w.steps != null && min != null && min > 0) return w.steps! / min >= 100 ? Effort.moderate : Effort.light;
    // Retkeily maastossa on kohtuullista ilman mittauksiakin; tavallinen kävely ilman tietoja kevyttä.
    return name == 'Retkeily' ? Effort.moderate : Effort.light;
  }
  return Effort.moderate;
}

/// Viikko maanantaista sunnuntaihin, jolle [day] osuu.
WeekActivity weekActivity(Iterable<Workout> workouts, DateTime day) {
  final mon = weekStart(DateTime(day.year, day.month, day.day));
  final next = addDays(mon, 7); // kalenteripäivinä (kesäaika)
  var vig = 0, mod = 0, light = 0;
  final strength = <DateTime>{};
  for (final w in workouts) {
    if (w.date.isBefore(mon) || !w.date.isBefore(next)) continue;
    if (w.activity == null) {
      if (w.exercises.any((e) => e.sets.any((s) => !s.warmup))) strength.add(w.date);
      continue;
    }
    final m = _minutesOf(w);
    if (m == null || m <= 0) continue;
    switch (effortOf(w)) {
      case Effort.light:
        light += m;
      case Effort.moderate:
        mod += m;
      case Effort.vigorous:
        vig += m;
    }
  }
  return WeekActivity(
    moderateEq: mod + 2 * vig,
    vigorous: vig,
    moderate: mod,
    light: light,
    strengthDays: strength.length,
  );
}
