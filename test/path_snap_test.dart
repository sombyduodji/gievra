import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/gps_filter.dart';
import 'package:treenipaivakirja/maps/path_snap.dart';

// Keksitty paikka ja reitit (metreinä paikallisessa tasossa); ei oikeita reittejä.
const lat0 = 61.5, lon0 = 23.8;
final kx = 111320 * math.cos(lat0 * math.pi / 180);
const ky = 110574.0;
(double, double) ll(double x, double y) => (lat0 + y / ky, lon0 + x / kx);
(double, double) xy(TrackPoint p) => ((p.lon - lon0) * kx, (p.lat - lat0) * ky);

SnapWay way(String kind, String detail, List<(double, double)> pts, {String name = ''}) =>
    SnapWay(kind, detail, [for (final (x, y) in pts) ll(x, y)], name: name);

/// Reitti x-akselia pitkin 5 m välein, sivuttaisheitto [jitter] (vuorotellen ±), y-siirtymä [y].
List<TrackPoint> track({double from = 0, double to = 200, double y = 0, double jitter = 0, double step = 5}) {
  final t0 = DateTime.utc(2026, 1, 1, 12);
  return [
    for (var i = 0; from + i * step <= to; i++)
      () {
        final (la, lo) = ll(from + i * step, y + (i.isEven ? jitter : -jitter));
        return TrackPoint(t0.add(Duration(seconds: i * 2)), la, lo);
      }(),
  ];
}

double maxAbsY(List<TrackPoint> pts, double target) => pts.map((p) => (xy(p).$2 - target).abs()).reduce(math.max);

void main() {
  final footway = way('path', 'footway', [(-50, 0), (300, 0)]);

  test('2–3 m:n heitto kävelytien vieressä korjataan tielle', () {
    final r = snapRoute([track(jitter: 3)], [footway], 'Kävely');
    expect(r.snapped, r.total);
    expect(maxAbsY(r.segments.single, 0), lessThan(0.05));
    // Ajat säilyvät ja järjestys pysyy.
    final pts = r.segments.single;
    for (var i = 1; i < pts.length; i++) {
      expect(pts[i].time.isBefore(pts[i - 1].time), isFalse);
    }
  });

  test('Metsässä (lähin väylä 25 m päässä) GPS-reitti pysyy ennallaan', () {
    final pts = track(y: 25, jitter: 2);
    final r = snapRoute([pts], [footway], 'Juoksu');
    expect(r.snapped, 0);
    expect(r.segments.single, same(r.segments.single));
    expect(maxAbsY(r.segments.single, 25), closeTo(2, 1e-6));
  });

  test('Jalan kävelytie voittaa autotien, pyörällä autotie', () {
    final road = way('major_road', 'secondary', [(-50, 0), (300, 0)], name: 'Keksitie');
    final sidewalk = way('path', 'sidewalk', [(-50, 6), (300, 6)]);
    final pts = track(y: 1.5, jitter: 1);
    final walk = snapRoute([pts], [road, sidewalk], 'Juoksu');
    expect(maxAbsY(walk.segments.single, 6), lessThan(0.05));
    final bike = snapRoute([pts], [road, sidewalk], 'Pyöräily');
    expect(maxAbsY(bike.segments.single, 0), lessThan(0.05));
  });

  test('Lyhyt osuma poikittaiseen polkuun ei riitä: pisteet pysyvät GPS:n mukaisina', () {
    final cross = way('path', 'path', [(100, -100), (100, 100)]);
    final pts = track(y: 0, jitter: 0);
    final r = snapRoute([pts], [cross], 'Kävely');
    expect(r.snapped, 0);
    expect(maxAbsY(r.segments.single, 0), lessThan(1e-6));
  });

  test('Mutka: väylän kulmapiste lisätään, jotta reitti ei oikaise', () {
    final bend = way('path', 'footway', [(0, 0), (100, 0), (100, 100)]);
    final t0 = DateTime.utc(2026, 1, 1, 12);
    final raw = [
      for (final (i, (x, y)) in [
        (0, 0.0),
        (20, 2.0),
        (40, -2.0),
        (60, 2.0),
        (80, -1.0),
        (98, 12.0),
        (101, 30.0),
        (99, 50.0),
        (102, 70.0),
        (100, 90.0),
      ].indexed)
        () {
          final (la, lo) = ll(x.toDouble(), y);
          return TrackPoint(t0.add(Duration(seconds: i * 8)), la, lo);
        }(),
    ];
    final r = snapRoute([raw], [bend], 'Kävely');
    final out = r.segments.single.map(xy).toList();
    expect(out.any((p) => (p.$1 - 100).abs() < 0.01 && p.$2.abs() < 0.01), isTrue, reason: 'kulma (100, 0) mukana');
    for (final (x, y) in out) {
      expect(math.min(y.abs(), (x - 100).abs()), lessThan(0.05)); // kaikki pisteet väylällä
    }
  });

  test('Hiihtoa, melontaa ja tuntematonta lajia ei korjata; moottoritietä ja rautatietä ei käytetä', () {
    final pts = track(jitter: 3);
    for (final s in ['Hiihto', 'Melonta', 'Uinti', 'Lumikenkäily', null]) {
      expect(snapRoute([pts], [footway], s).snapped, 0, reason: '$s');
    }
    final motorway = way('highway', 'motorway', [(-50, 0), (300, 0)]);
    final rail = way('rail', 'rail', [(-50, 0), (300, 0)]);
    expect(snapRoute([pts], [motorway, rail], 'Juoksu').snapped, 0);
  });

  test('Tienpätkät laattojen rajalla: reitti jatkuu katkeamatta', () {
    final a = way('path', 'footway', [(-50, 0), (100, 0)], name: 'Puistopolku');
    final b = way('path', 'footway', [(100, 0), (300, 0)], name: 'Puistopolku');
    final r = snapRoute([track(jitter: 3)], [a, b], 'Kävely');
    expect(r.snapped, r.total);
    expect(maxAbsY(r.segments.single, 0), lessThan(0.05));
  });
}
