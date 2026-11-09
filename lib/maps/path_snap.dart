import 'dart:math' as math;

import '../gps_filter.dart';

// Reitin korjaus poluille (karttasovitus). Suodatettu GPS-reitti sovitetaan offline-kartan teihin ja polkuihin,
// mutta vain siellä, missä reitti selvästi kulkee väylää pitkin:
//  - piste, joka on muutaman metrin sivussa polusta, siirretään polulle (GPS heittää helposti 2–5 m),
//  - jalan (kävely, juoksu) suositaan kävely- ja pyöräteitä, polkuja ja jalkakäytäviä autoteiden sijaan,
//  - metsässä ja muualla, missä väylää ei ole lähellä, GPS-reittiin luotetaan sellaisenaan,
//  - lyhyt osuma väylään (alle [minRun] m) ei riitä: silloin pidetään GPS-pisteet.
//
// Menetelmä: piilo-Markov-malli ja Viterbi (Newson & Krumm 2009) ilman reititystä. Jokaisen pisteen tilat ovat
// lähimmät väylät ja "ei väylällä"; hinta = etäisyys väylästä (normaalijakauma) + väylätyypin hinta lajille +
// siirtymä (väylää pitkin kuljettu matka vs. GPS-matka). Väylän vaihto ja väylältä poistuminen maksavat.

/// Väylä offline-kartasta (Protomaps-pohjakartan roads-kerros): tyyppi ja pisteet (lat, lon).
class SnapWay {
  final String kind, detail, name;
  final List<(double, double)> points;
  const SnapWay(this.kind, this.detail, this.points, {this.name = ''});
}

/// Kenelle korjaus tehdään: jalan vai pyörällä. null = lajia ei korjata (hiihto, melonta, uinti, lumikenkäily…).
enum SnapMode { foot, bike }

SnapMode? snapModeFor(String? sport) => switch (sport) {
  'Juoksu' || 'Hölkkä' || 'Kävely' || 'Sauvakävely' || 'Retkeily' => SnapMode.foot,
  'Pyöräily' => SnapMode.bike,
  _ => null,
};

/// Väylätyypin hinta (luonnollisina logaritmeina; 0 = paras). null = väylää ei käytetä lainkaan.
double? wayCost(SnapWay w, SnapMode mode) {
  if (w.kind == 'path') {
    if (w.detail == 'corridor' || w.detail == 'platform') return null; // sisätilat ja laiturit
    if (mode == SnapMode.bike) return w.detail == 'cycleway' ? 0 : (w.detail == 'steps' ? null : 0.4);
    return w.detail == 'cycleway' ? 0.2 : 0;
  }
  if (w.kind == 'minor_road') return mode == SnapMode.bike ? 0.2 : 0.8;
  if (w.kind == 'major_road') return mode == SnapMode.bike ? 0.6 : 2.5;
  return null; // moottoritiet, rautatiet, lautat, muut
}

/// Säädöt (metrejä ja hintoja). Oletukset: polku korjataan noin 8 m:n päähän asti (pikkutie noin 6 m, jalan
/// pääteille ei koskaan), joten 2–5 m:n heitto korjautuu mutta kauempana kulkenut reitti ei hyppää polulle.
class SnapParams {
  /// GPS-virheen keskihajonta (m) väylän ympärillä.
  final double sigma;

  /// Kauempana olevaa väylää ei harkita (m).
  final double radius;

  /// "Ei väylällä" -tilan hinta: väylä voittaa, kun se on lähempänä kuin noin sqrt(2·offCost)·sigma.
  final double offCost;

  /// Siirtymän hinta: |väylää pitkin − GPS-matka| / beta.
  final double beta;

  /// Väylän vaihto (eri tyyppi tai nimi) ja väylälle tulo tai sieltä lähtö.
  final double switchCost, enterCost;

  /// Väyläosuus korjataan vain, jos se on vähintään näin pitkä (m) ja siinä on vähintään [minPoints] pistettä.
  final double minRun;
  final int minPoints;

  const SnapParams({
    this.sigma = 4,
    this.radius = 10,
    this.offCost = 2.0,
    this.beta = 6,
    this.switchCost = 1.5,
    this.enterCost = 2,
    this.minRun = 30,
    this.minPoints = 4,
  });
}

/// Tulos: korjattu reitti ja kuinka suuri osa pisteistä siirrettiin väylälle.
class SnapResult {
  final List<List<TrackPoint>> segments;
  final int snapped, total;
  const SnapResult(this.segments, this.snapped, this.total);
}

class _Plane {
  final double lat0, lon0, kx, ky;
  _Plane(this.lat0, this.lon0) : kx = 111320 * math.cos(lat0 * math.pi / 180), ky = 110574;
  (double, double) xy(double lat, double lon) => ((lon - lon0) * kx, (lat - lat0) * ky);
  (double, double) latLon(double x, double y) => (lat0 + y / ky, lon0 + x / kx);
}

class _Line {
  final List<(double, double)> xy;
  final List<double> along; // kertymä alusta
  final double cost;
  final String key; // tyyppi + nimi: saman väylän palat laattojen rajoilla
  _Line(this.xy, this.cost, this.key) : along = [0] {
    for (var i = 1; i < xy.length; i++) {
      along.add(along.last + _d(xy[i - 1], xy[i]));
    }
  }
}

double _d((double, double) a, (double, double) b) => math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

class _Cand {
  final int line, seg;
  final double x, y, s, dist;
  const _Cand(this.line, this.seg, this.x, this.y, this.s, this.dist);
}

/// Korjaa reitin [ways]-väylille. Reitti palautetaan ennallaan, jos laji ei ole korjattava tai väyliä ei ole.
SnapResult snapRoute(
  List<List<TrackPoint>> segments,
  List<SnapWay> ways,
  String? sport, {
  SnapParams params = const SnapParams(),
}) {
  final total = segments.fold<int>(0, (a, s) => a + s.length);
  final mode = snapModeFor(sport);
  final first = segments.where((s) => s.isNotEmpty).firstOrNull?.first;
  if (mode == null || ways.isEmpty || first == null) return SnapResult(segments, 0, total);
  final plane = _Plane(first.lat, first.lon);
  final lines = <_Line>[];
  for (final w in ways) {
    final c = wayCost(w, mode);
    if (c == null || w.points.length < 2) continue;
    lines.add(_Line([for (final (la, lo) in w.points) plane.xy(la, lo)], c, '${w.kind}/${w.detail}/${w.name}'));
  }
  if (lines.isEmpty) return SnapResult(segments, 0, total);

  // Ruudukko: väylän osat ruuduittain nopeaa lähihakua varten.
  final cell = params.radius * 2;
  final grid = <(int, int), List<(int, int)>>{};
  for (var li = 0; li < lines.length; li++) {
    final xy = lines[li].xy;
    for (var si = 1; si < xy.length; si++) {
      final (ax, ay) = xy[si - 1];
      final (bx, by) = xy[si];
      final x0 = ((math.min(ax, bx) - params.radius) / cell).floor(),
          x1 = ((math.max(ax, bx) + params.radius) / cell).floor();
      final y0 = ((math.min(ay, by) - params.radius) / cell).floor(),
          y1 = ((math.max(ay, by) + params.radius) / cell).floor();
      if ((x1 - x0 + 1) * (y1 - y0 + 1) > 400) continue; // virheellisen pitkä osa
      for (var gx = x0; gx <= x1; gx++) {
        for (var gy = y0; gy <= y1; gy++) {
          (grid[(gx, gy)] ??= []).add((li, si));
        }
      }
    }
  }

  List<_Cand> candidates(double px, double py) {
    final best = <int, _Cand>{}; // väylä -> lähin kohta
    for (final (li, si) in grid[((px / cell).floor(), (py / cell).floor())] ?? const <(int, int)>[]) {
      final l = lines[li];
      final (ax, ay) = l.xy[si - 1];
      final (bx, by) = l.xy[si];
      final dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
      final t = l2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
      final x = ax + t * dx, y = ay + t * dy;
      final d = math.sqrt((px - x) * (px - x) + (py - y) * (py - y));
      if (d > params.radius) continue;
      final prev = best[li];
      if (prev == null || d < prev.dist) best[li] = _Cand(li, si, x, y, l.along[si - 1] + t * math.sqrt(l2), d);
    }
    final list = best.values.toList()..sort((a, b) => a.dist.compareTo(b.dist));
    return list.take(6).toList();
  }

  var snapped = 0;
  final out = <List<TrackPoint>>[];
  for (final seg in segments) {
    if (seg.length < 2) {
      out.add(seg);
      continue;
    }
    final pts = [for (final p in seg) plane.xy(p.lat, p.lon)];
    final cands = [for (final (x, y) in pts) candidates(x, y)];
    // Viterbi. Tila k: 0 = ei väylällä, 1.. = cands[i][k-1].
    double emit(int i, int k) {
      if (k == 0) return params.offCost;
      final c = cands[i][k - 1];
      return c.dist * c.dist / (2 * params.sigma * params.sigma) + lines[c.line].cost;
    }

    double trans(int i, int a, int b) {
      if (a == 0 && b == 0) return 0;
      if (a == 0 || b == 0) return params.enterCost;
      final ca = cands[i - 1][a - 1], cb = cands[i][b - 1];
      final g = _d(pts[i - 1], pts[i]);
      if (ca.line == cb.line) return ((cb.s - ca.s).abs() - g).abs() / params.beta;
      final e = math.sqrt(math.pow(ca.x - cb.x, 2) + math.pow(ca.y - cb.y, 2));
      final sw = lines[ca.line].key == lines[cb.line].key ? 0.3 : params.switchCost;
      return (e - g).abs() / params.beta + sw;
    }

    var cost = [for (var k = 0; k <= cands[0].length; k++) emit(0, k)];
    final back = <List<int>>[];
    for (var i = 1; i < pts.length; i++) {
      final n = cands[i].length + 1;
      final next = List.filled(n, double.infinity), from = List.filled(n, 0);
      for (var b = 0; b < n; b++) {
        final e = emit(i, b);
        for (var a = 0; a < cost.length; a++) {
          final v = cost[a] + trans(i, a, b) + e;
          if (v < next[b]) {
            next[b] = v;
            from[b] = a;
          }
        }
      }
      back.add(from);
      cost = next;
    }
    final states = List.filled(pts.length, 0);
    var k = 0;
    for (var j = 1; j < cost.length; j++) {
      if (cost[j] < cost[k]) k = j;
    }
    for (var i = pts.length - 1; i >= 0; i--) {
      states[i] = k;
      if (i > 0) k = back[i - 1][k];
    }

    // Lyhyet väyläosuudet takaisin GPS:lle: korjataan vain, kun reitti selvästi kulkee väylää pitkin.
    var i = 0;
    while (i < pts.length) {
      if (states[i] == 0) {
        i++;
        continue;
      }
      var j = i;
      var len = 0.0;
      while (j + 1 < pts.length && states[j + 1] != 0) {
        len += _d(pts[j], pts[j + 1]);
        j++;
      }
      if (j - i + 1 < params.minPoints || len < params.minRun) {
        for (var m = i; m <= j; m++) {
          states[m] = 0;
        }
      }
      i = j + 1;
    }

    // Uusi osuus: korjatut pisteet väylällä; saman väylän peräkkäisten pisteiden väliin väylän mutkat.
    final res = <TrackPoint>[];
    for (var m = 0; m < seg.length; m++) {
      final p = seg[m];
      if (states[m] == 0) {
        res.add(p);
        continue;
      }
      final c = cands[m][states[m] - 1];
      if (m > 0 && states[m - 1] != 0) {
        final pc = cands[m - 1][states[m - 1] - 1];
        if (pc.line == c.line && pc.seg != c.seg) {
          final l = lines[c.line];
          final ds = (c.s - pc.s).abs();
          // Vain, jos matka väylää pitkin on uskottava (ei kiertoa toiselle puolelle).
          if (ds <= _d(pts[m - 1], pts[m]) * 1.5 + 20) {
            final fwd = c.seg > pc.seg;
            final vs = fwd ? [for (var v = pc.seg; v < c.seg; v++) v] : [for (var v = pc.seg - 1; v >= c.seg; v--) v];
            final t0 = seg[m - 1].time, dt = p.time.difference(t0).inMilliseconds;
            for (final v in vs) {
              final frac = ds == 0 ? 0.0 : ((l.along[v] - pc.s).abs() / ds).clamp(0.0, 1.0);
              final (la, lo) = plane.latLon(l.xy[v].$1, l.xy[v].$2);
              res.add(TrackPoint(t0.add(Duration(milliseconds: (dt * frac).round())), la, lo));
            }
          }
        }
      }
      final (la, lo) = plane.latLon(c.x, c.y);
      res.add(TrackPoint(p.time, la, lo));
      snapped++;
    }
    out.add(res);
  }
  return SnapResult(out, snapped, total);
}
