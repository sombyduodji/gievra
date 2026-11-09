import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/garmin_import.dart';
import 'package:treenipaivakirja/gps_filter.dart';
import 'package:treenipaivakirja/gpx.dart';
import 'package:treenipaivakirja/maps/path_snap.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sports.dart';

// Polulle korjaus juoksun jälkeen (0.4.1): alkuperäinen reitti .gpx:n laajennuksessa, matka korjatun reitin
// mukaan, säädettävä raja 3–10 m, lajikohtainen oletus. Keksityt paikat ja reitit.
const lat0 = 61.5, lon0 = 23.8;
final kx = 111320 * math.cos(lat0 * math.pi / 180);
const ky = 110574.0;
(double, double) ll(double x, double y) => (lat0 + y / ky, lon0 + x / kx);

List<TrackPoint> zigzag({double to = 1000, double jitter = 3, double step = 5, double y = 0}) {
  final t0 = DateTime.utc(2026, 1, 1, 12);
  return [
    for (var i = 0; i * step <= to; i++)
      () {
        final (la, lo) = ll(i * step, y + (i.isEven ? jitter : -jitter));
        return TrackPoint(t0.add(Duration(seconds: i * 2)), la, lo);
      }(),
  ];
}

SnapWay path(double y) => SnapWay('path', 'footway', [ll(-50, y), ll(1100, y)]);

void main() {
  test('GPX: korjattu reitti pääraitana, alkuperäinen ja GPS-matka laajennuksessa; vanha lukija näkee pääraidan', () {
    final raw = [zigzag(to: 200)];
    final snapped = snapRoute(raw, [path(0)], 'Kävely').segments;
    final gpx = routeToGpx(snapped, name: 'Kävely', type: 'Kävely', desc: 'testi', raw: raw, rawDistance: 212.3);
    expect(gpx, contains('xmlns:gievra="$gievraGpxNs"'));
    // GPX 1.1: extensions ennen trkseg-osia.
    expect(gpx.indexOf('<extensions>'), lessThan(gpx.indexOf('<trkseg>')));
    final main = parseGpx(gpx); // sama lukija kuin 0.4:ssä ja aiemmin
    expect(main.single.length, snapped.single.length);
    expect(main.single.first.lat, closeTo(snapped.single.first.lat, 1e-6));
    final (r, d) = parseRawGpx(gpx)!;
    expect(r.single.length, raw.single.length);
    expect(r.single[3].lat, closeTo(raw.single[3].lat, 1e-6));
    expect(r.single[3].time, raw.single[3].time);
    expect(d, 212.3);
    expect(parseRawGpx(routeToGpx(raw, name: 'x')), isNull); // ilman korjausta ei laajennusta
  });

  test('.md: korjauksen raja ja käsin kirjoitettu matka säilyvät; vanha tiedosto ilman niitä', () {
    final w = Workout(date: DateTime(2026, 11, 9), title: 'Juoksu', activity: 'Juoksu', distanceKm: 5.03)
      ..snapM = 6
      ..distanceManual = true;
    final md = workoutToMarkdown(w);
    expect(md, contains('snap: 6 m'));
    expect(md, contains('distance_source: manual'));
    final back = parseWorkout(md);
    expect(back.snapM, 6);
    expect(back.distanceManual, isTrue);
    final off = parseWorkout(workoutToMarkdown(w..snapM = 0));
    expect(off.snapM, 0);
    final old = parseWorkout(
      md
          .replaceAll('snap: 0 m\n', '')
          .replaceAll(RegExp(r'snap: .*\n'), '')
          .replaceAll('distance_source: manual\n', ''),
    );
    expect(old.snapM, isNull);
    expect(old.distanceManual, isFalse);
  });

  test('Matka seuraa korjattua reittiä; ilman korjausta täsmälleen GPS:n matka', () {
    final raw = [zigzag(to: 1000, jitter: 3)];
    // Suodattimen matka = pisteiden polku (sama mittaus) + katkon uskottava matka 20 m.
    final gps = measureRoute(raw) + 20;
    expect(snappedDistance(raw, raw, gps), gps);
    final snapped = snapRoute(raw, [path(0)], 'Juoksu', params: SnapParams.forLimit(5)).segments;
    final d = snappedDistance(raw, snapped, gps);
    expect(d, lessThan(gps)); // siksak pois
    expect(d, closeTo(1000 + 20, 15)); // polun pituus + katko
  });

  test('Raja 3–10 m: 5 m sivussa kulkeva reitti korjataan 6 m:llä, ei 3 m:llä', () {
    final raw = [zigzag(to: 300, jitter: 0, y: 5)];
    expect(snapRoute(raw, [path(0)], 'Kävely', params: SnapParams.forLimit(3)).snapped, 0);
    final r = snapRoute(raw, [path(0)], 'Kävely', params: SnapParams.forLimit(6));
    expect(r.snapped, r.total);
  });

  test('Lajikohtainen oletus asetuksiin ja takaisin; puuttuva = 5 m', () {
    final s = Settings()..snapDefaults = {'Juoksu': 7, 'Kävely': 0};
    final back = Settings()..applyMarkdown(s.settingsToMarkdown());
    expect(back.snapFor('Juoksu'), 7);
    expect(back.snapFor('Kävely'), 0);
    expect(back.snapFor('Pyöräily'), 5);
  });

  test('Poistetut lajit: vanhat treenit tunnistetaan, uusia ei tarjota; muussa liikunnassa matka (GPS)', () {
    for (final n in ['Hölkkä', 'Futsal', 'Nyrkkeily', 'CrossFit']) {
      expect(sportOf(n)?.retired, isTrue, reason: n);
    }
    expect(sports.where((s) => !s.retired).map((s) => s.name), isNot(contains('Hölkkä')));
    expect(isRun('Hölkkä'), isTrue); // vanhat hölkät juoksutilastoissa
    expect(sportOf('Muu liikunta')!.distance, isTrue);
    expect(snapModeFor('Muu liikunta'), isNull);
  });

  test('Garmin: uudet lajinimet ja tunnistamattomat lajit käyttäjän valinnalla', () {
    expect(garminSport('Futsal'), 'Jalkapallo');
    expect(garminSport('Boxing'), 'Kamppailulajit');
    expect(garminSport('Table Tennis'), 'Pöytätennis');
    expect(garminSport('Resort Skiing'), 'Laskettelu');
    expect(garminSport('Cross Country Classic Skiing'), 'Hiihto');
    expect(garminSport('Jogging'), 'Juoksu');
    expect(garminSport('Disc Golf'), 'Golf'); // lähellä: ei kysytä
    const csv =
        'Suorituksen tyyppi,Päiväys,Etäisyys,Aika\n'
        'Purjehdus,2026-11-01 10:00:00,2.5,1:10:00\n'
        'purjehdus,2026-11-02 10:00:00,2.1,1:00:00\n'
        'Ratsastus,2026-11-03 10:00:00,15,0:50:00\n'
        'Juoksu,2026-11-04 10:00:00,5,0:30:00\n';
    expect(garminUnknownTypes(csv), [('Purjehdus', 2), ('Ratsastus', 1)]);
    // Ilman valintaa tunnistamaton = Muu liikunta; valinnalla pari tai ohitus.
    final (plain, _) = readGarminCsv(csv, const []);
    expect(plain.workouts.where((w) => w.activity == 'Muu liikunta').length, 3);
    final (chosen, skipped) = readGarminCsv(csv, const [], choices: {'purjehdus': 'Melonta', 'ratsastus': null});
    expect(chosen.workouts.map((w) => w.activity).toList()..sort(), ['Juoksu', 'Melonta', 'Melonta']);
    expect(skipped, 0); // käyttäjän ohittamat eivät ole voimaharjoittelua
  });
}
