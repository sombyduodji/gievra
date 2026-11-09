import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treenipaivakirja/gps_filter.dart';
import 'package:treenipaivakirja/maps/elevation.dart';
import 'package:treenipaivakirja/maps/map_store.dart';

import 'maps_test.dart' show catalogJson, square;

// Korkeustiedostot (.elev): muoto kuten tools/elev_build.py, keksityt korkeudet.

/// .elev-tiedosto korkeuksista (metreinä, null = ei tietoa) samalla tavalla kuin tools/elev_build.py.
Uint8List elevBytes(List<List<double?>> m, {double west = 25.0, double north = 60.3, double step = 0.001}) {
  final h = m.length, w = m.first.length;
  final q = [
    for (final row in m)
      for (final v in row) v == null ? -32768 : (v * 2).round(),
  ];
  int at(int r, int c) => q[r * w + c];
  final res = ByteData(w * h * 2);
  for (var r = 0; r < h; r++) {
    for (var c = 0; c < w; c++) {
      final pred = r == 0
          ? (c == 0 ? 0 : at(r, c - 1))
          : (c == 0 ? at(r - 1, c) : at(r, c - 1) + at(r - 1, c) - at(r - 1, c - 1));
      res.setInt16((r * w + c) * 2, (at(r, c) - pred).toSigned(16), Endian.little);
    }
  }
  final body = ZLibEncoder().encodeBytes(res.buffer.asUint8List());
  final head = ByteData(52);
  final magic = ascii.encode(elevMagic);
  for (var i = 0; i < 8; i++) {
    head.setUint8(i, magic[i]);
  }
  head
    ..setUint32(8, w, Endian.little)
    ..setUint32(12, h, Endian.little)
    ..setFloat64(16, west, Endian.little)
    ..setFloat64(24, north, Endian.little)
    ..setFloat64(32, step, Endian.little)
    ..setFloat64(40, step, Endian.little)
    ..setUint32(48, body.length, Endian.little);
  return Uint8List.fromList([...head.buffer.asUint8List(), ...body]);
}

/// Versio 2 (lohkot) kuten tools/elev_build.py encode_blocks.
Uint8List elevBytesV2(
  List<List<double?>> m, {
  double west = 25.0,
  double north = 60.3,
  double step = 0.001,
  int block = 16,
}) {
  final h = m.length, w = m.first.length;
  final q = [
    for (final row in m)
      for (final v in row) v == null ? -32768 : (v * 2).round(),
  ];
  final parts = <List<int>>[];
  for (var by = 0; by < h; by += block) {
    for (var bx = 0; bx < w; bx += block) {
      final bw = math.min(block, w - bx), bh = math.min(block, h - by);
      int at(int r, int c) => q[(by + r) * w + bx + c];
      final res = ByteData(bw * bh * 2);
      for (var r = 0; r < bh; r++) {
        for (var c = 0; c < bw; c++) {
          final pred = r == 0
              ? (c == 0 ? 0 : at(r, c - 1))
              : (c == 0 ? at(r - 1, c) : at(r, c - 1) + at(r - 1, c) - at(r - 1, c - 1));
          res.setInt16((r * bw + c) * 2, (at(r, c) - pred).toSigned(16), Endian.little);
        }
      }
      parts.add(ZLibEncoder().encodeBytes(res.buffer.asUint8List()));
    }
  }
  final index = ByteData((parts.length + 1) * 4);
  var off = 0;
  for (var i = 0; i < parts.length; i++) {
    index.setUint32(i * 4, off, Endian.little);
    off += parts[i].length;
  }
  index.setUint32(parts.length * 4, off, Endian.little);
  final body = [...index.buffer.asUint8List(), for (final p in parts) ...p];
  final head = ByteData(56);
  final magic = ascii.encode(elevMagic2);
  for (var i = 0; i < 8; i++) {
    head.setUint8(i, magic[i]);
  }
  head
    ..setUint32(8, w, Endian.little)
    ..setUint32(12, h, Endian.little)
    ..setFloat64(16, west, Endian.little)
    ..setFloat64(24, north, Endian.little)
    ..setFloat64(32, step, Endian.little)
    ..setFloat64(40, step, Endian.little)
    ..setUint32(48, block, Endian.little)
    ..setUint32(52, body.length, Endian.little);
  return Uint8List.fromList([...head.buffer.asUint8List(), ...body]);
}

/// Mäki: korkeus nousee itään 0,5 m/ruutu (noin 55 m), keskellä 20 m kumpare.
List<List<double?>> hill({int w = 40, int h = 30}) => [
  for (var r = 0; r < h; r++)
    [for (var c = 0; c < w; c++) 30 + c * 0.5 + 20 * math.exp(-(math.pow(c - 20, 2) + math.pow(r - 15, 2)) / 30)],
];

void main() {
  test('Vanha muoto (v1) puretaan samoin kuin se tehtiin; ei tietoa = null', () async {
    final m = hill();
    m[3][4] = null;
    final g = await ElevationGrid.fromBytes(elevBytes(m));
    expect(g.header.width, 40);
    expect(g.header.height, 30);
    // Ruudun keskipiste: (west + (c + 0,5)·step, north − (r + 0,5)·step).
    double lon(int c) => 25.0 + (c + 0.5) * 0.001;
    double lat(int r) => 60.3 - (r + 0.5) * 0.001;
    expect(g.at(lat(15), lon(20)), closeTo(m[15][20]!, 0.25));
    expect(g.at(lat(0), lon(39)), closeTo(m[0][39]!, 0.25));
    expect(g.at(lat(3), lon(4)), isNot(closeTo(0, 1)), reason: 'naapurit korvaavat puuttuvan');
    expect(g.at(61, 25.01), isNull);
    expect(() => ElevHeader.parse(Uint8List.fromList(utf8.encode('PMTiles' * 10))), throwsFormatException);
    final cut = elevBytes(m);
    expect(ElevationGrid.fromBytes(cut.sublist(0, cut.length - 5)), throwsFormatException);
  });

  test('Nousu ja lasku: mäen yli ja takaisin; tasainen reitti ei kerrytä nousua', () async {
    final g = await ElevationGrid.fromBytes(elevBytes(hill()));
    final t0 = DateTime(2026, 11, 9, 8);
    TrackPoint pt(int i, double lon) => TrackPoint(t0.add(Duration(seconds: i)), 60.285, lon);
    // Länsireunalta itäreunalle ja takaisin (noin 2 × 2 km).
    final route = [
      [for (var i = 0; i <= 40; i++) pt(i, 25.0005 + i * 0.000975)],
      [for (var i = 0; i <= 40; i++) pt(100 + i, 25.0395 - i * 0.000975)],
    ];
    final pr = elevationProfile(route, g.at)!;
    expect(pr.coverage, 1);
    expect(pr.climb, closeTo(pr.descent, 3), reason: "hystereesi jättää lopussa alle 2 m");
    expect(pr.climb, inInclusiveRange(38, 48), reason: 'laskettuna noin 45 m: kumpareelle 30, takaisin 13, loppu 2');
    expect(pr.points.last.$1, closeTo(4200, 200));
    // Tasainen: sama korkeus kaikkialla.
    final flat = await ElevationGrid.fromBytes(
      elevBytes([for (var r = 0; r < 30; r++) List<double?>.filled(40, 81.5)]),
    );
    final fp = elevationProfile(route, flat.at)!;
    expect((fp.climb, fp.descent), (0, 0));
    // Alueen ulkopuolella: ei profiilia.
    expect(
      elevationProfile([
        [pt(0, 26.0), pt(1, 26.01)],
      ], g.at),
      isNull,
    );
  });

  group('Karttaluettelo ja tuonti', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gievra-korkeus'));
    tearDown(() {
      MapStore.instance
        ..dirOverride = null
        ..catalog = null
        ..installed.clear()
        ..unverified.clear()
        ..forgetKnown();
      tmp.deleteSync(recursive: true);
    });

    Map<String, Object> withElev(Uint8List elev) {
      final pack = square('etela', 25.0, 60.27, 25.04, 60.3)
        ..['elev'] = {'file': 'etela.elev', 'size': elev.length, 'sha256': sha256.convert(elev).toString()};
      return catalogJson(packs: [pack]);
    }

    test('Korkeustiedosto luettelossa: oma tiedosto, ei yleiskarttaa mukaan', () {
      final elev = elevBytes(hill());
      final c = MapCatalog.fromJson(withElev(elev));
      final e = c.packs.single.elev!;
      expect((e.file, e.isElevation, e.size, e.id), ('etela.elev', true, elev.length, 'etela-korkeus'));
      expect(c.packs.single.isElevation, isFalse);
      final bad = withElev(elev);
      (((bad['packs'] as List).single as Map)['elev'] as Map)['file'] = '../x.elev';
      expect(() => MapCatalog.fromJson(bad), throwsFormatException);
    });

    test('Tuonti tunnistaa korkeustiedoston sisällöstä; profiili ladatuista tiedoista', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final store = MapStore.instance..dirOverride = maps;
      final elev = elevBytes(hill());
      store.catalog = MapCatalog.fromJson(withElev(elev));
      final renamed = '${tmp.path}/etela (2).elev';
      File(renamed).writeAsBytesSync(elev);
      final notElev = '${tmp.path}/x.elev';
      File(notElev).writeAsStringSync('ei korkeuksia');
      final r = await store.importFiles([renamed, notElev]);
      expect(r.imported, ['etela.elev']);
      expect(r.skipped.single.$2, MapSkip.notMap);
      expect(store.hasElevation, isTrue);
      expect(store.covers(60.285, 25.02), isFalse, reason: 'korkeustiedosto ei ole kartta');
      expect(await store.openFiles(), isEmpty);
      final t0 = DateTime(2026, 11, 9, 8);
      final pr = await store.profileFor([
        [for (var i = 0; i <= 40; i++) TrackPoint(t0.add(Duration(seconds: i)), 60.285, 25.0005 + i * 0.000975)],
      ]);
      expect(pr!.climb, greaterThan(20));
      // Kansion luku samaan aikaan kuin kartta ja profiili luetaan (sovelluksen avaus): ei virhettä.
      final both = await Future.wait([
        store.load(network: false).then((_) => null),
        store.profileFor([
          [TrackPoint(t0, 60.285, 25.001), TrackPoint(t0.add(const Duration(minutes: 5)), 60.285, 25.039)],
        ]),
        store.openFiles().then((_) => null),
      ]);
      expect(both[1], isNotNull);
      await store.delete(store.catalog!.packs.single.elev!);
      expect(store.hasElevation, isFalse);
    });
  });

  test('Kilometrien vauhti: tauko ei kuulu aikaan; vajaa viimeinen kilometri mukaan', () {
    // 2,5 km itään 5:00/km (1 m/0,3 s), puolivälissä 10 min tauko osuuksien välissä.
    final t0 = DateTime(2026, 11, 9, 8);
    const mPerDeg = 111320 * 0.4955; // pituusaste leveydellä 60,3 (cos 60,3° ≈ 0,4955)
    TrackPoint pt(double m, double extraSec) =>
        TrackPoint(t0.add(Duration(milliseconds: ((m * 0.3 + extraSec) * 1000).round())), 60.3, 25.0 + m / mPerDeg);
    final route = [
      [for (var m = 0.0; m <= 1200; m += 50) pt(m, 0)],
      [for (var m = 1200.0; m <= 2500; m += 50) pt(m, 600)],
    ];
    final sp = elevationProfile(route, (lat, lon) => 10.0)!.splits;
    expect(sp, hasLength(3));
    expect(sp[0].$3, closeTo(300, 3));
    expect(sp[1].$3, closeTo(300, 3), reason: 'tauko ei näy');
    expect(sp[2].$2, closeTo(500, 10));
    expect(sp[2].$3, closeTo(150, 3));
  });

  test('Kilometrit ilman korkeustietoja: sama vauhti kuin profiilissa', () {
    final t0 = DateTime(2026, 11, 9, 8);
    const mPerDeg = 111320 * 0.4955;
    final route = [
      [
        for (var m = 0.0; m <= 2300; m += 50)
          TrackPoint(t0.add(Duration(milliseconds: (m * 360).round())), 60.3, 25.0 + m / mPerDeg),
      ],
    ];
    final sp = routeKmSplits(route);
    expect(sp, hasLength(3));
    expect(sp[0].$3, closeTo(360, 4)); // 6:00/km
    expect(sp[2].$2, closeTo(300, 10));
    expect(
      routeKmSplits([
        [TrackPoint(t0, 60.3, 25.0)],
      ]),
      isEmpty,
    );
  });

  group('Ei korkeustietoja', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gievra-eikorkeus'));
    tearDown(() {
      MapStore.instance
        ..dirOverride = null
        ..catalog = null
        ..installed.clear()
        ..forgetKnown();
      tmp.deleteSync(recursive: true);
    });

    test('Kartat ilman korkeustiedostoja: ei profiilia, ei virhettä; rikkinäinen tiedosto ohitetaan', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      File('test/fixtures/kartta-testi.pmtiles').copySync('${maps.path}/testi.pmtiles');
      final store = MapStore.instance..dirOverride = maps;
      store.catalog = MapCatalog.fromJson(catalogJson());
      await store.load(network: false);
      final t0 = DateTime(2026, 11, 9, 8);
      final route = [
        [TrackPoint(t0, 68.905, 27.01), TrackPoint(t0.add(const Duration(minutes: 9)), 68.91, 27.03)],
      ];
      expect(store.hasElevation, isFalse);
      expect(await store.profileFor(route), isNull);
      expect(await store.openFiles(), hasLength(1), reason: 'kartta toimii');
      File('${maps.path}/rikki.elev').writeAsStringSync('ei korkeuksia');
      await store.load(network: false);
      expect(store.hasElevation, isTrue);
      expect(await store.profileFor(route), isNull);
    });

    test('Lähde luettelosta: Suomi Maanmittauslaitos, muut Copernicus tai luettelon oma', () {
      expect(MapCatalog.fromJson(catalogJson()).elevSource, elevAttribution);
      final se = {...catalogJson(), 'country': 'se'};
      expect(MapCatalog.fromJson(se).elevSource, copernicusAttribution);
      expect(MapCatalog.fromJson({...se, 'elevAttribution': 'X'}).elevSource, 'X');
      expect(copernicusAttribution, contains('produced using Copernicus WorldDEM-30'));
    });
  });

  test('Lohkomuoto (v2): samat korkeudet; reitti lataa vain tarvitsemansa lohkot', () async {
    final m = hill();
    m[20][30] = null;
    final bytes = elevBytesV2(m);
    final full = await ElevationGrid.fromBytes(bytes);
    final v1 = await ElevationGrid.fromBytes(elevBytes(m));
    for (final (lat, lon) in [(60.285, 25.02), (60.2755, 25.0305), (60.299, 25.001), (60.2795, 25.0305)]) {
      expect(full.at(lat, lon), v1.at(lat, lon));
    }
    final head = ElevHeader.parse(bytes);
    expect((head.version, head.block, head.blocksX, head.blocksY), (2, 16, 3, 2));
    final lazy = await ElevationGrid.open(head, (s, n) async => Uint8List.sublistView(bytes, s, s + n));
    expect(lazy.loadedBlocks, 0);
    await lazy.loadAround([(60.299, 25.001)]); // vasen yläkulma
    expect(lazy.loadedBlocks, 1);
    expect(lazy.at(60.299, 25.001), v1.at(60.299, 25.001));
    expect(lazy.at(60.275, 25.035), isNull, reason: 'lohkoa ei ladattu');
    // Vajaa tiedosto tai rikki hakemisto: virhe, ei kaatumista.
    expect(ElevationGrid.fromBytes(bytes.sublist(0, bytes.length - 10)), throwsFormatException);
  });

  test('Korkeustiedot omasta julkaisusta (elevBase), kartat luettelon osoitteesta; SHA tarkistetaan', () async {
    final tmp = Directory.systemTemp.createTempSync('gievra-elevbase');
    final store = MapStore.instance..dirOverride = Directory('${tmp.path}/k');
    final elev = elevBytesV2(hill());
    final pack = square('etela', 25.0, 60.27, 25.04, 60.3)
      ..['elev'] = {'file': 'etela.elev', 'size': elev.length, 'sha256': sha256.convert(elev).toString()};
    store.catalog = MapCatalog.fromJson({
      ...catalogJson(packs: [pack]),
      'elevBase': 'https://example.invalid/korkeus/',
    });
    final urls = <String>[];
    var body = elev;
    store.clientOverride = MockClient((req) async {
      urls.add('${req.url}');
      return http.Response.bytes(body, 200);
    });
    try {
      final e = store.catalog!.packs.single.elev!;
      expect(await store.download([e]), isEmpty);
      expect(urls, ['https://example.invalid/korkeus/etela.elev']);
      expect(store.isInstalled(e), isTrue);
      // Väärä sisältö: tarkiste ei täsmää, tiedostoa ei asenneta.
      await store.delete(e);
      body = Uint8List.fromList([...elev]..[100] ^= 1);
      expect(await store.download([e]), hasLength(1));
      expect(store.isInstalled(e), isFalse);
      // Vanhan muodon tiedosto tunnistetaan päivitettäväksi.
      File('${tmp.path}/k/vanha.elev').writeAsBytesSync(elevBytes(hill()));
      await store.load(network: false);
      expect(await store.oldFormatElevation(), ['vanha.elev']);
    } finally {
      store
        ..clientOverride = null
        ..dirOverride = null
        ..catalog = null
        ..installed.clear();
      tmp.deleteSync(recursive: true);
    }
  });
}
