// Palautuminen-kortin ruutujen tila (käyttäjä 18.11.): vihreä = omalla tasolla, keltainen = hieman poikkeava
// (seuraa), punainen = selvästi poikkeava (tutkimuksen raja), harmaa = liian vähän öitä vertailuun. Punaiset
// raja-arvot ovat samat kuin ennen (lib/sleep.dart metricFlag, home_extras.dart nightHr); keltainen on lievempi
// askel ennen niitä. Vain fysiologiset arvot (yösyke, HRV, hengitys, lämpö) lasketaan yhteiseen "kevyt päivä"
// -neuvoon; happi, uni ja kuormitus ovat omia huomioitaan.

import 'home_extras.dart' show NightHr;
import 'models.dart';
import 'sleep.dart';

enum TileState { none, green, yellow, red }

/// Palautuminen-kortin valittavat ruudut järjestyksessä (käyttäjä 18.11.: kaikki valittavissa, myös yösyke).
const recoveryTileKeys = ['nighthr', 'hrv', 'rest', 'rr', 'spo2', 'temp', 'sleep', 'load'];

/// Järjestettävät ruudut oletusjärjestyksessä (leposyke ei näy Palautuminen-kortissa: yösyke kattaa sen).
const recoveryOrderDefault = ['nighthr', 'hrv', 'rr', 'spo2', 'temp', 'sleep', 'load'];

/// Yösyke: kolmen yön keskiarvo vs. tavallinen (+3 keltainen, +5 punainen; Mishra 2020, Quer 2020).
TileState nightHrState(NightHr n) {
  final d = n.delta;
  if (d == null) return TileState.none;
  return d >= 5
      ? TileState.red
      : d >= 3
      ? TileState.yellow
      : TileState.green;
}

/// Yöarvo: punainen = tutkimuksen raja (HRV kahtena päivänä peräkkäin), keltainen = lievempi poikkeama.
TileState metricState(String key, MetricStat s, Map<DateTime, NightMetrics> all, DateTime today) {
  final f = metricFlag(key, s);
  if (f == -1) return TileState.none;
  final u = s.usual!;
  switch (key) {
    case 'hrv':
      if (f == 1) return hrvLowSustained(all, today) ? TileState.red : TileState.yellow;
      return TileState.green;
    case 'rr':
      if (f == 1) return TileState.red;
      return s.last - u >= 1.5 ? TileState.yellow : TileState.green;
    case 'temp':
      if (f == 1) return TileState.red;
      return s.last - u >= 0.3 ? TileState.yellow : TileState.green;
    case 'spo2':
      if (f == 1) return TileState.red;
      return s.last <= u - 1 ? TileState.yellow : TileState.green;
    case 'rest':
      if (f == 1) return TileState.red;
      return s.recent - u >= 3 ? TileState.yellow : TileState.green;
  }
  return TileState.green;
}

/// Viime yön uni vs. tavallinen: punainen 6 h tai alle (Craven 2022), keltainen vähintään 45 min alle oman
/// tavallisen. Ilman tavallista tasoa vain 6 tunnin raja.
TileState sleepTileState(SleepStats s) {
  final last = s.last;
  if (last == null || !s.fresh) return TileState.none;
  if (last.asleep <= const Duration(hours: 6)) return TileState.red;
  final usual = s.usual;
  if (usual != null && last.asleep <= usual - sleepShortMargin) return TileState.yellow;
  return TileState.green;
}

enum TrainLoad { light, normal, hard }

/// Kuormitus: viimeisen 7 päivän kuorma verrattuna 4 viikon viikkokeskiarvoon (minuutit × rasitus: kevyt 1,
/// reipas 2, kova 3; salitreeni 2 tai kova sali 3). Alle 0,8 kevyt, yli 1,3 kova (Gabbett 2016:n "makea kohta";
/// suhteen käyttö vammojen ennustamiseen on kiistelty, Impellizzeri 2020, joten tämä on vain taustatietoa eikä
/// koskaan punainen). Null = alle 3 viikkoa historiaa tai ei treenejä 4 viikkoon.
(TrainLoad, double)? trainingLoad(List<Workout> ws, DateTime today, {int? maxHr}) {
  final t = dateOnly(today);
  final from28 = addDays(t, -27), from7 = addDays(t, -6);
  var sum7 = 0.0, sum28 = 0.0;
  DateTime? oldest;
  for (final w in ws) {
    if (w.date.isAfter(t)) continue;
    if (oldest == null || w.date.isBefore(oldest)) oldest = w.date;
    if (w.date.isBefore(from28)) continue;
    final load = workoutLoad(w, maxHr: maxHr);
    if (load <= 0) continue;
    sum28 += load;
    if (!w.date.isBefore(from7)) sum7 += load;
  }
  if (oldest == null || daysBetween(oldest, t) < 21 || sum28 <= 0) return null;
  final ratio = sum7 / (sum28 / 4);
  final level = ratio < .8
      ? TrainLoad.light
      : ratio > 1.3
      ? TrainLoad.hard
      : TrainLoad.normal;
  return (level, ratio);
}

/// Yhden treenin kuorma: minuutit × rasitus (kevyt 1, tavallinen 2, kova 3; sali kovana, jos syke tai tuntuma
/// kertoo niin).
double workoutLoad(Workout w, {int? maxHr}) {
  final min = (w.durationSec ?? 0) / 60;
  if (min <= 0) return 0;
  final factor = w.activity == null
      ? (hardWorkout(w, maxHr: maxHr) ? 3 : 2)
      : switch (w.intensity) {
          'kova' => 3,
          'kevyt' => 1,
          _ => 2,
        };
  return min * factor;
}

TileState loadTileState(TrainLoad l) => l == TrainLoad.hard ? TileState.yellow : TileState.green;
