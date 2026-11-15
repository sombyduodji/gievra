import 'gps_filter.dart';
import 'maps/path_snap.dart' show measureRoute;

// Kyydin (auto, bussi, juna) tunnistus kävely- ja juoksureitiltä jälkikäteen: jos tallennus jäi päälle kyytiin
// noustessa, reitille kertyy matkaa, jota ei kävelty (Espanjan kävely 14.11.: viimeiset 3 min autossa).
// Vain kävely- ja juoksulajeissa: pyörä, hiihto ym. voivat oikeasti kulkea kovaa.

/// Lajit, joissa kyytiä etsitään, ja nopeus (km/h), jota nopeampi jatkuva eteneminen on kyytiä.
const _rideKmh = {
  'Kävely': 15.0,
  'Sauvakävely': 15.0,
  'Retkeily': 15.0,
  'Lumikenkäily': 15.0,
  'Juoksu': 27.0,
  'Hölkkä': 27.0,
};

bool vehicleCheckSport(String? sport) => _rideKmh.containsKey(sport);

/// Löydetty kyyti: aika [start]–[end] (viimeinen kävelty piste ennen kyytiä ja ensimmäinen sen jälkeen),
/// matka ja keskinopeus. [atStart]/[atEnd]: ennen/jälkeen ei juuri liikuttu (reitti alkoi tai päättyi kyytiin).
class VehicleRide {
  final DateTime start, end;
  final double meters;
  final bool atStart, atEnd;
  const VehicleRide(this.start, this.end, this.meters, {this.atStart = false, this.atEnd = false});

  Duration get duration => end.difference(start);
  double get kmh => duration.inMilliseconds <= 0 ? 0 : meters / 1000 / (duration.inMilliseconds / 3.6e6);
}

/// Kyydit reitiltä. Ikkunat vähintään [window] s; ikkuna on kyytiä, kun sen matka (myös osuuksien välisen katkon
/// yli) ylittää lajin rajan. Lähekkäiset (alle 90 s väli, esim. liikennevalot) yhdistetään. Kyyti hyväksytään, kun
/// sitä on vähintään 300 m.
List<VehicleRide> findVehicleRides(List<List<TrackPoint>> segments, String? sport, {double window = 15}) {
  final kmh = _rideKmh[sport];
  if (kmh == null) return const [];
  final limit = kmh / 3.6;
  final pts = [for (final s in segments) ...s];
  if (pts.length < 2) return const [];
  // Kumulatiivinen matka pisteittäin (katkon yli suoraan).
  final cum = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length; i++) {
    cum[i] = cum[i - 1] + geoDistance(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
  }
  double secs(int a, int b) => pts[b].time.difference(pts[a].time).inMilliseconds / 1000;
  // Nopeat välit [i, j] pisteindekseinä.
  final fast = <(int, int)>[];
  var j = 0;
  for (var i = 0; i < pts.length - 1; i++) {
    if (j <= i) j = i + 1;
    while (j < pts.length - 1 && secs(i, j) < window) {
      j++;
    }
    final dt = secs(i, j);
    if (dt <= 0) continue;
    if ((cum[j] - cum[i]) / dt > limit) fast.add((i, j));
  }
  if (fast.isEmpty) return const [];
  // Yhdistetään päällekkäiset ja lähekkäiset.
  final merged = <(int, int)>[];
  for (final f in fast) {
    if (merged.isNotEmpty) {
      final (a, b) = merged.last;
      if (f.$1 <= b || secs(b, f.$1) <= 90) {
        merged[merged.length - 1] = (a, f.$2 > b ? f.$2 : b);
        continue;
      }
    }
    merged.add(f);
  }
  final total = cum.last;
  final out = <VehicleRide>[];
  for (final (a, b) in merged) {
    final m = cum[b] - cum[a];
    if (m < 300) continue;
    // Koko reitti nopea: väärä laji (esim. juoksu kävelynä), ei kyyti.
    if (cum[a] < 100 && total - cum[b] < 100) continue;
    out.add(
      VehicleRide(
        pts[a].time,
        pts[b].time,
        m,
        // Alle 100 m ennen tai jälkeen: reitti alkoi tai päättyi kyytiin (ei kävelyä, jota säilyttää).
        atStart: cum[a] < 100,
        atEnd: total - cum[b] < 100,
      ),
    );
  }
  return out;
}

/// Reitti ilman kyytiä: väli (start, end) pois; alussa/lopussa olevasta kyydistä myös sitä edeltävät/seuraavat
/// pisteet. Kyydin kohdalla alkaa uusi osuus.
List<List<TrackPoint>> removeRide(List<List<TrackPoint>> segments, VehicleRide r) {
  bool keep(TrackPoint p) {
    if (r.atEnd && p.time.isAfter(r.start)) return false;
    if (r.atStart && p.time.isBefore(r.end)) return false;
    return !(p.time.isAfter(r.start) && p.time.isBefore(r.end));
  }

  final out = <List<TrackPoint>>[];
  for (final s in segments) {
    var cur = <TrackPoint>[];
    for (final p in s) {
      if (keep(p)) {
        // Kyydin yli ei piirretä viivaa: uusi osuus, kun edellinen säilytetty oli ennen kyytiä ja tämä sen jälkeen.
        if (cur.isNotEmpty && !cur.last.time.isAfter(r.start) && !p.time.isBefore(r.end)) {
          out.add(cur);
          cur = <TrackPoint>[];
        }
        cur.add(p);
      }
    }
    if (cur.isNotEmpty) out.add(cur);
  }
  return out.where((s) => s.isNotEmpty).toList();
}

/// GPS:n mittaama matka kyydin poiston jälkeen: jäljelle jäävä reitti mitattuna samoin kuin suodin mittaa
/// ([measureRoute]), enintään alkuperäinen. Ei "alkuperäinen − kyyti": suodin oli jo hylännyt osan kyydistä
/// (Espanjan kävely: 1 580 m, josta kyytiä vain n. 215 m, vaikka kyydin pisteiden väli oli 1,8 km).
double distanceWithoutRide(List<List<TrackPoint>> after, double rawDistance) {
  final d = measureRoute(after);
  return d > rawDistance ? rawDistance : d;
}

/// Kesto (s) kyydin poiston jälkeen: kyydin aika pois; reitin lopussa olevasta myös kyydin jälkeinen aika
/// reitin loppuun, alussa olevasta reitin alusta kyydin loppuun.
int secondsWithoutRide(int seconds, List<List<TrackPoint>> segments, VehicleRide r) {
  final pts = [for (final s in segments) ...s];
  if (pts.isEmpty) return seconds;
  var cut = r.duration;
  if (r.atEnd) cut = pts.last.time.difference(r.start);
  if (r.atStart) cut = r.end.difference(pts.first.time);
  if (r.atStart && r.atEnd) cut = pts.last.time.difference(pts.first.time);
  final s = seconds - cut.inSeconds;
  return s < 60 ? 60 : s;
}
