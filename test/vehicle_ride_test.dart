import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/gpx.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/gps_filter.dart';
import 'package:treenipaivakirja/vehicle_ride.dart';

// Keksitty reitti: pisteet sekunnin välein pohjoiseen annetuilla nopeuksilla (m/s) ja kestoilla (s).
List<TrackPoint> _route(List<(double, int)> legs, {DateTime? start}) {
  final t0 = start ?? DateTime.utc(2026, 11, 14, 12);
  var lat = 60.0, t = 0;
  final out = [TrackPoint(t0, lat, 25.0)];
  for (final (v, secs) in legs) {
    for (var i = 0; i < secs; i++) {
      lat += v / 111195.0;
      t++;
      out.add(TrackPoint(t0.add(Duration(seconds: t)), lat, 25.0));
    }
  }
  return out;
}

double _len(List<List<TrackPoint>> s) => [
  for (final seg in s)
    for (var i = 1; i < seg.length; i++) geoDistance(seg[i - 1].lat, seg[i - 1].lon, seg[i].lat, seg[i].lon),
].fold(0.0, (a, b) => a + b);

void main() {
  // 30 min kävelyä 1,3 m/s (n. 2,3 km), sitten 3 min autolla 12 m/s (43 km/h, n. 2,2 km).
  final walkThenCar = [
    _route([(1.3, 1800), (12, 180)]),
  ];

  test('kävely, lopussa auto: kyyti löytyy lopusta, poisto jättää kävelyn', () {
    final r = findVehicleRides(walkThenCar, 'Kävely');
    expect(r, hasLength(1));
    expect(r.single.atEnd, isTrue);
    expect(r.single.atStart, isFalse);
    expect(r.single.kmh, greaterThan(30));
    final after = removeRide(walkThenCar, r.single);
    expect(_len(after), closeTo(1800 * 1.3, 60));
    final d = distanceWithoutRide(after, _len(walkThenCar));
    expect(d, closeTo(1800 * 1.3, 60));
    expect(secondsWithoutRide(1980, walkThenCar, r.single), closeTo(1800, 20));
  });

  test('vain kävely- ja juoksulajit: pyöräilyssä ja hiihdossa ei kyytiä', () {
    expect(findVehicleRides(walkThenCar, 'Juoksu'), hasLength(1));
    expect(findVehicleRides(walkThenCar, 'Pyöräily'), isEmpty);
    expect(findVehicleRides(walkThenCar, 'Hiihto'), isEmpty);
    expect(findVehicleRides(walkThenCar, null), isEmpty);
    expect(vehicleCheckSport('Pyöräily'), isFalse);
    expect(vehicleCheckSport('Kävely'), isTrue);
  });

  test('reipas kävely (7 km/h) ja kova juoksu (20 km/h) eivät ole kyytiä', () {
    expect(
      findVehicleRides([
        _route([(7 / 3.6, 1800)]),
      ], 'Kävely'),
      isEmpty,
    );
    expect(
      findVehicleRides([
        _route([(2.5, 600), (20 / 3.6, 300), (2.5, 600)]),
      ], 'Juoksu'),
      isEmpty,
    );
  });

  test('koko reitti nopea: väärä laji, ei kyytiä', () {
    expect(
      findVehicleRides([
        _route([(3.5, 1800)]),
      ], 'Kävely'),
      isEmpty,
      reason: '12,6 km/h kävelynä',
    );
    expect(
      findVehicleRides([
        _route([(5, 1800)]),
      ], 'Kävely'),
      isEmpty,
      reason: '18 km/h koko matkan',
    );
  });

  test('bussi keskellä: väli pois, reitti jatkuu omana osuutena, kesto lyhenee bussin ajalla', () {
    final segs = [
      _route([(1.3, 900), (10, 240), (1.3, 900)]),
    ];
    final r = findVehicleRides(segs, 'Kävely');
    expect(r, hasLength(1));
    expect(r.single.atStart || r.single.atEnd, isFalse);
    final after = removeRide(segs, r.single);
    expect(after, hasLength(2));
    expect(_len(after), closeTo(1800 * 1.3, 80));
    expect(secondsWithoutRide(2040, segs, r.single), closeTo(1800, 30));
  });

  test('alussa autolla: alku pois', () {
    final segs = [
      _route([(14, 120), (1.3, 1800)]),
    ];
    final r = findVehicleRides(segs, 'Kävely').single;
    expect(r.atStart, isTrue);
    expect(_len(removeRide(segs, r)), closeTo(1800 * 1.3, 60));
  });

  test('kyyti katkon yli (GPS-hyppy osuuksien välissä, kuten Espanjan kävelyssä)', () {
    final a = _route([(1.3, 1200)]);
    final last = a.last;
    // 47 s myöhemmin 600 m pohjoisempana, sitten lyhyt osuus autolla.
    final b = _route(
      [(11, 60)],
      start: last.time.add(const Duration(seconds: 47)),
    ).map((p) => TrackPoint(p.time, p.lat + (last.lat - 60.0) + 600 / 111195.0, p.lon)).toList();
    final r = findVehicleRides([a, b], 'Kävely');
    expect(r, hasLength(1));
    expect(r.single.atEnd, isTrue);
    expect(math.max(0, _len(removeRide([a, b], r.single)) - 1200 * 1.3), lessThan(40));
  });

  Future<Workout> open(WidgetTester tester, String sport) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final len = _len(walkThenCar);
    final w = Workout(date: DateTime(2026, 11, 4), title: sport, activity: sport)
      ..seconds = 1980
      ..minutes = 33
      ..distanceKm = (len / 10).round() / 100
      ..routeGpx = routeToGpx(walkThenCar, name: sport, type: sport, raw: walkThenCar, rawDistance: len);
    await tester.pumpWidget(MaterialApp(home: ActivityScreen(workout: w)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return w;
  }

  testWidgets('Liikunnan näkymä: Nousitko kyytiin? Poista kyyti lyhentää matkan ja ajan', (tester) async {
    final w = await open(tester, 'Kävely');
    expect(find.byKey(const ValueKey('vehicleRide')), findsOneWidget);
    await tester.ensureVisible(find.text('Poista kyyti'));
    await tester.tap(find.text('Poista kyyti'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('vehicleRide')), findsNothing);
    expect(w.seconds, closeTo(1800, 20));
    expect(w.distanceKm, closeTo(2.34, 0.08));
    expect(w.routeGpx, contains('kyyti poistettu'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Liikunnan näkymä: Pidä reitti piilottaa kortin; pyöräilyssä korttia ei ole', (tester) async {
    await open(tester, 'Kävely');
    await tester.ensureVisible(find.text('Pidä reitti'));
    await tester.tap(find.text('Pidä reitti'));
    await tester.pump();
    expect(find.byKey(const ValueKey('vehicleRide')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester, 'Pyöräily');
    expect(find.byKey(const ValueKey('vehicleRide')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
