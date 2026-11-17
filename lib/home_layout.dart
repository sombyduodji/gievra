// Muokattava etusivu (käyttäjä 17.11.): aloituspainikkeet, WHO-renkaat (lihaskunto, reipas liikunta, askeleet) ja
// kalenteri ovat aina näkyvissä. Niiden alle omat tavoitteet (1–3) ja valittavat kortit omassa järjestyksessään.
// Yksi oma tavoite näkyy WHO-renkaiden rivissä, kaksi tai kolme omana korttinaan.

import 'models.dart';
import 'weekly_activity.dart' show periodActivity;

/// Oma tavoite viikossa: [kind] 'gym' (salipäivät), 'km' (matka), 'min' (liikunta-aika) tai 'times' (kerrat);
/// [sport] rajaa lajiin (null = kaikki liikunta; salipäivillä aina null). Kuukaudessa tavoite × päivät / 7.
class Goal {
  final String kind;
  final String? sport;
  final double perWeek;
  const Goal(this.kind, this.sport, this.perWeek);

  static const kinds = ['gym', 'km', 'min', 'times'];

  @override
  bool operator ==(Object other) =>
      other is Goal && other.kind == kind && other.sport == sport && other.perWeek == perWeek;
  @override
  int get hashCode => Object.hash(kind, sport, perWeek);
  @override
  String toString() => 'Goal($kind, $sport, $perWeek)';

  /// Tavoite jaksolle, jossa [days] päivää (viikko 7).
  double target(int days) => days == 7 ? perWeek : perWeek * days / 7;

  /// Toteutunut jaksolla [from, next). Salipäivät: päivät, joilla salitreeni (kuten WHO-lihaskuntorengas).
  double value(List<Workout> ws, DateTime from, DateTime next) {
    if (kind == 'gym') return periodActivity(ws, from, next).strengthDays.toDouble();
    var sum = 0.0;
    for (final w in ws) {
      final out = w.date.isBefore(from) || !w.date.isBefore(next) || w.activity == null;
      if (out || (sport != null && w.activity != sport)) continue;
      sum += switch (kind) {
        'km' => w.distanceKm ?? 0,
        'min' => (w.durationSec ?? 0) / 60,
        _ => 1,
      };
    }
    return sum;
  }
}

/// Tiedostoon: "gym:*:3; km:Juoksu:20" (desimaalit pilkulla, * = kaikki liikunta).
String goalsToFile(List<Goal> gs) => gs.map((g) => '${g.kind}:${g.sport ?? '*'}:${fileNum(g.perWeek)}').join('; ');

List<Goal> goalsFromFile(String v) {
  final out = <Goal>[];
  for (final part in v.split(';')) {
    final f = part.split(':');
    if (f.length != 3 || !Goal.kinds.contains(f[0].trim())) continue;
    final n = parseNum(f[2]);
    if (n == null || n <= 0 || n > 100000) continue;
    final kind = f[0].trim(), sport = f[1].trim();
    out.add(Goal(kind, kind == 'gym' || sport == '*' || sport.isEmpty ? null : sport, n));
    if (out.length == 3) break;
  }
  return out;
}

/// Valittavat kortit WHO-osion alla: seuraava ohjelman päivä, omat tavoitteet (kun niitä on 2–3), viikkoputki, yön
/// alin syke, viimeksi, voiman kehitys, juoksun kehitys (matkaryhmät) ja kehonpaino (näkyvyys asetuksesta weightOnHome, koska se vaatii painon seurannan).
const homeCardIds = ['next', 'goals', 'streak', 'recovery', 'recent', 'strength', 'running', 'weight'];

/// Järjestys ja piilotetut tiedostoon: "goals, recent, -strength, running, weight" (- = piilossa).
String homeCardsToFile(List<String> order, Set<String> hidden) =>
    order.map((id) => hidden.contains(id) ? '-$id' : id).join(', ');

(List<String>, Set<String>) homeCardsFromFile(String v) {
  final order = <String>[], hidden = <String>{};
  for (var id in v.split(',').map((s) => s.trim())) {
    final off = id.startsWith('-');
    if (off) id = id.substring(1);
    if (!homeCardIds.contains(id) || order.contains(id)) continue;
    order.add(id);
    if (off) hidden.add(id);
  }
  // Uudet kortit (tulevat versiot) loppuun näkyviin.
  for (final id in homeCardIds) {
    if (!order.contains(id)) order.add(id);
  }
  return (order, hidden);
}
