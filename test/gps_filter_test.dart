import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/gps_filter.dart';

// Keksityt reitit (ei kenenkään oikeita lenkkejä): tasokoordinaatisto metreinä keksityn origon ympärillä,
// 1 paikannus sekunnissa, Gaussin kohina siemenellä (toistettava).

const lat0 = 62.0, lon0 = 25.0;
final kx = 111320 * math.cos(lat0 * math.pi / 180);
const ky = 110574.0;
final t0 = DateTime.utc(2026, 1, 1, 12);

(double, double) toLatLon(double x, double y) => (lat0 + y / ky, lon0 + x / kx);
(double, double) toXY(double lat, double lon) => ((lon - lon0) * kx, (lat - lat0) * ky);

/// Totuus: piste reitillä [wps] matkan [s] kohdalla.
(double, double) along(List<(double, double)> wps, double s) {
  for (var i = 1; i < wps.length; i++) {
    final (ax, ay) = wps[i - 1];
    final (bx, by) = wps[i];
    final l = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
    if (s <= l) return (ax + (bx - ax) * s / l, ay + (by - ay) * s / l);
    s -= l;
  }
  return wps.last;
}

double pathLength(List<(double, double)> wps) {
  var d = 0.0;
  for (var i = 1; i < wps.length; i++) {
    d += math.sqrt(math.pow(wps[i].$1 - wps[i - 1].$1, 2) + math.pow(wps[i].$2 - wps[i - 1].$2, 2));
  }
  return d;
}

double distToPath(List<(double, double)> wps, double x, double y) {
  var best = double.infinity;
  for (var i = 1; i < wps.length; i++) {
    final (ax, ay) = wps[i - 1];
    final (bx, by) = wps[i];
    final dx = bx - ax, dy = by - ay;
    final t = (((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
    best = math.min(best, math.sqrt(math.pow(ax + t * dx - x, 2) + math.pow(ay + t * dy - y, 2)));
  }
  return best;
}

class Noise {
  final math.Random r;
  Noise(int seed) : r = math.Random(seed);
  double gauss(double sigma) {
    final u1 = 1 - r.nextDouble(), u2 = r.nextDouble();
    return sigma * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}

/// Simuloitu tallennus: [speed] m/s reittiä pitkin. [tweak] voi muuttaa tai poistaa paikannuksen (null = ei
/// paikannusta sillä sekunnilla).
List<GpsFix> simulate(
  List<(double, double)> wps,
  double speed, {
  double sigma = 3,
  double accuracy = 5,
  int seed = 1,
  int startSecond = 0,
  GpsFix? Function(int sec, double x, double y, GpsFix fix)? tweak,
}) {
  final n = Noise(seed);
  final total = pathLength(wps);
  final fixes = <GpsFix>[];
  for (var sec = 0; sec * speed <= total; sec++) {
    final (x, y) = along(wps, sec * speed);
    final (lat, lon) = toLatLon(x + n.gauss(sigma), y + n.gauss(sigma));
    final f = GpsFix(t0.add(Duration(seconds: startSecond + sec)), lat, lon, accuracy);
    final g = tweak == null ? f : tweak(sec, x, y, f);
    if (g != null) fixes.add(g);
  }
  return fixes;
}

GpsFilter run(List<GpsFix> fixes, GpsLimits limits) {
  final f = GpsFilter(limits);
  for (final x in fixes) {
    f.add(x);
  }
  f.finish();
  return f;
}

double maxDeviation(GpsFilter f, List<(double, double)> wps) {
  var m = 0.0;
  for (final p in f.points) {
    final (x, y) = toXY(p.lat, p.lon);
    m = math.max(m, distToPath(wps, x, y));
  }
  return m;
}

GpsFix offset(GpsFix f, double dx, double dy, {double? accuracy}) {
  final (x, y) = toXY(f.lat, f.lon);
  final (lat, lon) = toLatLon(x + dx, y + dy);
  return GpsFix(f.time, lat, lon, accuracy ?? f.accuracy);
}

// Kortteli: 2 km, mutkia molempiin suuntiin.
const block = <(double, double)>[
  (0, 0),
  (400, 0),
  (400, 300),
  (100, 300),
  (100, 600),
  (600, 600),
  (600, 0),
  (500, -100),
];

void main() {
  test('lajien rajat', () {
    expect(GpsLimits.forSport('Kävely'), GpsLimits.walk);
    expect(GpsLimits.forSport('Retkeily'), GpsLimits.walk);
    expect(GpsLimits.forSport('Juoksu'), GpsLimits.run);
    expect(GpsLimits.forSport('Pyöräily'), GpsLimits.cycle);
    expect(GpsLimits.forSport(null), GpsLimits.run);
  });

  test('tavallinen lenkki kohinalla: matka ja reitti oikein', () {
    final truth = pathLength(block);
    final f = run(simulate(block, 3.0), GpsLimits.run);
    expect(f.distance, closeTo(truth, truth * 0.03), reason: '${f.distance} vs $truth');
    expect(maxDeviation(f, block), lessThan(8));
    expect(f.segments.length, 1);
  });

  test('50 m sivuun ja takaisin -piikit poistetaan', () {
    final truth = pathLength(block);
    var spikes = 0;
    final fixes = simulate(
      block,
      3.0,
      seed: 2,
      tweak: (sec, x, y, fix) {
        if (sec % 45 == 20) {
          spikes++;
          return offset(fix, 50 * (sec.isEven ? 1 : -1), 35);
        }
        return fix;
      },
    );
    final f = run(fixes, GpsLimits.run);
    expect(spikes, greaterThan(10));
    expect(maxDeviation(f, block), lessThan(10), reason: '${f.rejected}');
    expect(f.distance, closeTo(truth, truth * 0.03), reason: '${f.distance} vs $truth ${f.rejected}');
  });

  test('äkkispurtti 50 km/h ei mene läpi', () {
    // Kolme peräkkäistä paikannusta hyppää 40 m eteenpäin ja palaa (näennäisesti yli 100 km/h).
    final truth = pathLength(block);
    final fixes = simulate(
      block,
      3.0,
      seed: 3,
      tweak: (sec, x, y, fix) {
        if (sec >= 200 && sec < 203) return offset(fix, 40, 0);
        return fix;
      },
    );
    final f = run(fixes, GpsLimits.run);
    expect(maxDeviation(f, block), lessThan(10), reason: '${f.rejected}');
    expect(f.distance, closeTo(truth, truth * 0.03));
  });

  test('tasaisen nopea pätkä kävelyssä (14 m/s) hylätään', () {
    final f = GpsFilter(GpsLimits.walk);
    final fixes = simulate([(0, 0), (300, 0)], 1.4, seed: 4);
    for (final x in fixes) {
      f.add(x);
    }
    final before = f.distance;
    // Seuraavat 3 s "liikutaan" 14 m/s (puhelin autossa / GPS-hyppy): ei kerry matkaa.
    final last = fixes.last;
    for (var i = 1; i <= 3; i++) {
      f.add(offset(GpsFix(last.time.add(Duration(seconds: i)), last.lat, last.lon, 5), 14.0 * i, 0));
    }
    expect(f.distance - before, lessThan(5));
  });

  test('liikennevalot: paikallaan 60 s ei kerrytä matkaa', () {
    final route = <(double, double)>[(0, 0), (500, 0)];
    final n = Noise(5);
    final fixes = <GpsFix>[];
    var sec = 0;
    void addAt(double x, double y, double sigma) {
      final (lat, lon) = toLatLon(x + n.gauss(sigma), y + n.gauss(sigma));
      fixes.add(GpsFix(t0.add(Duration(seconds: sec++)), lat, lon, 6));
    }

    for (var d = 0.0; d <= 250; d += 1.4) {
      addAt(d, 0, 3);
    }
    for (var i = 0; i < 60; i++) {
      addAt(250, 0, 4); // seistään, GPS ajelehtii
    }
    for (var d = 250.0; d <= 500; d += 1.4) {
      addAt(d, 0, 3);
    }
    final f = run(fixes, GpsLimits.walk);
    expect(f.distance, closeTo(pathLength(route), 15), reason: '${f.distance}');
  });

  test('tunneli: 30 s katko, uskottava matka lasketaan', () {
    final truth = pathLength(block);
    final fixes = simulate(block, 3.0, seed: 6, tweak: (sec, x, y, fix) => sec >= 300 && sec < 330 ? null : fix);
    final f = run(fixes, GpsLimits.run);
    expect(f.segments.length, 2);
    // Katkon yli suora viiva voi oikaista mutkan; muuten matka täsmää.
    expect(f.distance, closeTo(truth, truth * 0.04), reason: '${f.distance} vs $truth');
  });

  test('epäuskottava katko (500 m sivuun) ei kerrytä matkaa', () {
    final a = simulate([(0, 0), (300, 0)], 1.4, seed: 7);
    final b = simulate([(800, 0), (1100, 0)], 1.4, seed: 8, startSecond: a.length + 15);
    final f = run([...a, ...b], GpsLimits.walk);
    expect(f.distance, closeTo(600, 25), reason: '${f.distance} ${f.rejected}');
    expect(f.segments.length, 2);
  });

  test('epätarkat paikannukset ohitetaan', () {
    final truth = pathLength(block);
    final fixes = simulate(
      block,
      3.0,
      seed: 9,
      tweak: (sec, x, y, fix) {
        if (sec % 7 == 3) return offset(fix, 80, -60, accuracy: 60);
        return fix;
      },
    );
    final f = run(fixes, GpsLimits.run);
    expect(f.rejected['accuracy'], greaterThan(50));
    expect(maxDeviation(f, block), lessThan(8));
    expect(f.distance, closeTo(truth, truth * 0.03));
  });

  test('alku odottaa tarkkaa paikannusta', () {
    final fixes = simulate(
      block,
      3.0,
      seed: 10,
      tweak: (sec, x, y, fix) {
        if (sec < 8) return offset(fix, 120, 90, accuracy: 40);
        return fix;
      },
    );
    final f = run(fixes, GpsLimits.run);
    final (x, y) = toXY(f.points.first.lat, f.points.first.lon);
    expect(distToPath(block, x, y), lessThan(8));
    expect(maxDeviation(f, block), lessThan(8));
  });

  test('jyrkkä käännös polulla säilyy (ei ole piikki)', () {
    // Kävely 150 m, U-käännös 6 m leveänä, takaisin.
    const hairpin = <(double, double)>[(0, 0), (150, 0), (153, 3), (150, 6), (0, 6)];
    final truth = pathLength(hairpin);
    final f = run(simulate(hairpin, 1.4, sigma: 2.5, seed: 11), GpsLimits.walk);
    expect(f.distance, closeTo(truth, truth * 0.05), reason: '${f.distance} vs $truth ${f.rejected}');
    final reach = f.points.map((p) => toXY(p.lat, p.lon).$1).reduce(math.max);
    expect(reach, greaterThan(142), reason: 'käännöksen kärki: $reach');
    expect(f.rejected['spike'], 0);
  });

  test('pyöräily 30 km/h ei hylkää pisteitä', () {
    final truth = pathLength(block);
    final f = run(simulate(block, 30 / 3.6, seed: 12), GpsLimits.cycle);
    expect(f.distance, closeTo(truth, truth * 0.03), reason: '${f.distance} ${f.rejected}');
    expect(f.rejected['speed'], 0);
  });

  test('20 eri kohinaa: lenkki, piikit ja pysähdys pysyvät rajoissa', () {
    final truth = pathLength(block);
    for (var seed = 100; seed < 120; seed++) {
      final f = run(
        simulate(block, 3.0, seed: seed, tweak: (sec, x, y, fix) => sec % 60 == 30 ? offset(fix, 50, 0) : fix),
        GpsLimits.run,
      );
      expect(f.distance, closeTo(truth, truth * 0.03), reason: 'siemen $seed: ${f.distance} ${f.rejected}');
      expect(maxDeviation(f, block), lessThan(10), reason: 'siemen $seed');
    }
  });

  test('hidas kävely 0,6 m/s ei ole pysähdys', () {
    const route = <(double, double)>[(0, 0), (200, 0), (200, 100)];
    final truth = pathLength(route);
    for (var seed = 200; seed < 205; seed++) {
      final f = run(simulate(route, 0.6, sigma: 2.5, seed: seed), GpsLimits.walk);
      expect(f.distance, closeTo(truth, truth * 0.06), reason: 'siemen $seed: ${f.distance}');
    }
  });

  test('Lyhyt GPS-katko paikallaan (puhelin ei lähetä 48 s): viiva jatkuu yhtenä, matka oikein', () {
    // Kävely 200 m, seisahdus 48 s ilman paikannuksia (siirtymä 3 m), jatko 200 m. Keksitty reitti.
    final a = simulate([(0, 0), (200, 0)], 1.4, seed: 30);
    final b = simulate([(203, 0), (403, 0)], 1.4, seed: 31, startSecond: a.length + 48);
    final f = run([...a, ...b], GpsLimits.walk);
    expect(f.segments.length, 1, reason: f.diagnostics);
    expect(f.distance, closeTo(403, 20));
    expect(f.maxFixGapSec, closeTo(49, 1.5));
    expect(f.received, a.length + b.length);
    expect(f.diagnostics, contains('pisin väli'));
  });
}

