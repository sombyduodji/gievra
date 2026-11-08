import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treenipaivakirja/maps/map_store.dart';
import 'package:treenipaivakirja/maps/pmtiles.dart';

// test/fixtures/kartta-testi.pmtiles: pieni pala Inarin erämaata (zoom 11–13), tehty työkalulla
// tools/map_extract.py. Karttatiedot © OpenStreetMap contributors, ODbL 1.0.

/// Laatan koordinaatit pisteelle.
(int, int) tileXY(double lat, double lon, int z) {
  final n = 1 << z;
  final r = lat * math.pi / 180;
  return (((lon + 180) / 360 * n).floor(), ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor());
}

/// Keksitty kunta: neliö (lon, lat) -kulmista.
Map<String, Object> square(String id, double w, double s, double e, double n, {int size = 1000, String? sha}) => {
  'id': id,
  'name': id,
  'file': '$id.pmtiles',
  'region': 'Testimaakunta',
  'size': size,
  'sha256': sha ?? '0' * 64,
  'bbox': [w, s, e, n],
  'shape': [
    [
      [w, s],
      [e, s],
      [e, n],
      [w, n],
      [w, s],
    ],
  ],
};

Map<String, Object> catalogJson({List<Map<String, Object>>? packs, Map<String, Object>? overview}) => {
  'format': 1,
  'tag': 'kartat-testi',
  'osmDate': '2026-11-07',
  'base': 'https://example.invalid/kartat/',
  'overview': overview ?? {'file': 'yleiskartta.pmtiles', 'size': 10, 'sha256': '0' * 64},
  'all': {'file': 'suomi.pmtiles', 'size': 100, 'sha256': '0' * 64},
  'regions': ['Testimaakunta'],
  'packs': packs ?? [square('etela', 25.0, 60.0, 25.5, 60.3), square('pohjoinen', 25.0, 61.0, 25.5, 61.3)],
};

void main() {
  test('Laattojen numerointi sama kuin PMTiles-määrittelyssä', () {
    expect([zxyToTileId(0, 0, 0), zxyToTileId(1, 0, 0), zxyToTileId(1, 0, 1), zxyToTileId(1, 1, 1)], [0, 1, 2, 3]);
    expect(zxyToTileId(1, 1, 0), 4);
    expect(zxyToTileId(2, 0, 0), 5);
  });

  test('Karttatiedoston luku: laatta löytyy alueelta, ei muualta', () async {
    final f = await PmTilesFile.open('test/fixtures/kartta-testi.pmtiles');
    expect((f.minZoom, f.maxZoom), (11, 13));
    expect(f.bounds.$1, closeTo(27.0, 0.01));
    final (x, y) = tileXY(68.905, 27.015, 13);
    final tile = await f.tile(13, x, y);
    expect(tile, isNotNull);
    expect(tile![0], 0x1a); // MVT: ensimmäinen kenttä on taso (layer)
    expect(await f.tile(13, x + 50, y), isNull);
    expect(await f.tile(5, 17, 7), isNull); // zoom ei tiedostossa
    await f.close();
  });

  test('Luettelo: kunta pisteessä ja kunnat säteen sisällä', () {
    final c = MapCatalog.fromJson(catalogJson());
    expect(c.packAt(60.1, 25.2)?.id, 'etela');
    expect(c.packAt(60.5, 25.2), isNull); // välissä "merta"
    // Pisteestä 60.1 N pohjoiseen kuntaan on ~78 km.
    expect(c.packsWithin(60.1, 25.2, 20).map((x) => x.id), ['etela']);
    expect(c.packsWithin(60.1, 25.2, 100).map((x) => x.id), ['etela', 'pohjoinen']);
    expect(c.packs.first.distanceKm(60.1, 25.2), 0);
    expect(c.packs.last.distanceKm(60.1, 25.2), closeTo(100.0, 25));
  });

  group('Lataus', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gievra-kartat'));
    tearDown(() {
      MapStore.instance
        ..dirOverride = null
        ..clientOverride = null
        ..catalog = null
        ..installed.clear()
        ..downloads.clear();
      tmp.deleteSync(recursive: true);
    });

    test('Tarkiste täsmää: tiedosto asennetaan; väärä tarkiste: ei jälkiä', () async {
      final good = utf8.encode('kunnan kartta');
      final over = utf8.encode('yleiskartta');
      final cat = catalogJson(
        packs: [
          square('hyva', 25, 60, 25.5, 60.3, size: good.length, sha: sha256.convert(good).toString()),
          square('rikki', 26, 60, 26.5, 60.3, size: 5, sha: 'f' * 64),
        ],
        overview: {'file': 'yleiskartta.pmtiles', 'size': over.length, 'sha256': sha256.convert(over).toString()},
      );
      final store = MapStore.instance
        ..dirOverride = tmp
        ..clientOverride = MockClient.streaming((req, _) async {
          final name = req.url.pathSegments.last;
          final body = switch (name) {
            'kartat.json' => utf8.encode(jsonEncode(cat)),
            'hyva.pmtiles' => good,
            'yleiskartta.pmtiles' => over,
            _ => utf8.encode('väärä sisältö'),
          };
          return http.StreamedResponse(Stream.value(body), 200);
        });
      expect(await store.load(refresh: true), isNull);
      expect(store.catalog!.packs.length, 2);
      await store.download(store.catalog!.packs);
      expect(store.installed, {'hyva.pmtiles', 'yleiskartta.pmtiles'});
      expect(File('${tmp.path}/hyva.pmtiles').readAsStringSync(), 'kunnan kartta');
      expect(tmp.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
      expect(File('${tmp.path}/rikki.pmtiles').existsSync(), isFalse);
      expect(store.covers(60.1, 25.2), isTrue);
      expect(store.covers(60.1, 26.2), isFalse);
      // Luettelo jää talteen: toimii ilman verkkoa.
      store.catalog = null;
      store.clientOverride = MockClient((_) async => http.Response('', 500));
      expect(await store.load(), isNull);
      expect(store.catalog, isNotNull);
      await store.delete(store.catalog!.packs.first);
      expect(store.covers(60.1, 25.2), isFalse);
    });
  });

  group('Ladatut kartat', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gievra-ladatut'));
    tearDown(() {
      MapStore.instance
        ..dirOverride = null
        ..clientOverride = null
        ..catalog = null
        ..installed.clear()
        ..downloads.clear();
      tmp.deleteSync(recursive: true);
    });

    test('Päivitys tunnistetaan ja ladataan; poisto vapauttaa tilan', () async {
      var a = utf8.encode('kartta A v1');
      final b = utf8.encode('kartta B');
      Map<String, Object> cat() => catalogJson(
        packs: [
          square('a', 25, 60, 25.5, 60.3, size: a.length, sha: sha256.convert(a).toString()),
          square('b', 26, 60, 26.5, 60.3, size: b.length, sha: sha256.convert(b).toString()),
        ],
      );
      final store = MapStore.instance
        ..dirOverride = tmp
        ..clientOverride = MockClient.streaming((req, _) async {
          final body = switch (req.url.pathSegments.last) {
            'kartat.json' => utf8.encode(jsonEncode(cat())),
            'a.pmtiles' => a,
            _ => b,
          };
          return http.StreamedResponse(Stream.value(body), 200);
        });
      await store.load(refresh: true);
      await store.download(store.catalog!.packs);
      expect((await store.installedFiles()).map((e) => e.$1).toSet(), {'a.pmtiles', 'b.pmtiles'});
      expect(await store.outdated(), isEmpty);

      // Uusi versio julkaistaan: vain A on vanhentunut.
      a = utf8.encode('kartta A versio 2');
      await store.load(refresh: true);
      expect((await store.outdated()).map((x) => x.id), ['a']);
      await store.update(await store.outdated());
      expect(File('${tmp.path}/a.pmtiles').readAsStringSync(), 'kartta A versio 2');
      expect(await store.outdated(), isEmpty);

      // Päivitys epäonnistuu (verkko katkeaa): vanha kartta jää käyttöön, latauslista tyhjenee.
      final good = a;
      a = utf8.encode('kartta A versio 3');
      final cat3 = cat();
      a = utf8.encode('rikki');
      store.catalog = MapCatalog.fromJson(cat3);
      final failed = await store.update(await store.outdated());
      expect(failed.map((d) => d.pack.id), contains('a'));
      expect(store.downloads, isEmpty);
      expect(store.installed, contains('a.pmtiles'));
      expect(File('${tmp.path}/a.pmtiles').readAsBytesSync(), good);
      expect(tmp.listSync().where((e) => e.path.endsWith('.part')), isEmpty);

      await store.deleteFile('b.pmtiles');
      expect(store.installed, {'a.pmtiles'});
      await store.deleteAll();
      expect(store.installed, isEmpty);
      expect(await store.installedFiles(), isEmpty);
      expect(await store.usedBytes(), 0);
    });
  });

  test('Luettelo: tiedostonimi ei voi osoittaa muualle, osoite vain https', () {
    Map<String, Object> withFile(String f) =>
        catalogJson(packs: [square('x', 25, 60, 25.5, 60.3, size: 1, sha: 'a' * 64)])
          ..['overview'] = {'file': f, 'size': 1, 'sha256': 'a' * 64};
    expect(() => MapCatalog.fromJson(withFile('../../shared_prefs/x.pmtiles')), throwsFormatException);
    expect(() => MapCatalog.fromJson(withFile('/data/x.pmtiles')), throwsFormatException);
    expect(() => MapCatalog.fromJson(withFile('Yleis.PMTILES')), throwsFormatException);
    expect(MapCatalog.fromJson(withFile('yleiskartta.pmtiles')).overview.file, 'yleiskartta.pmtiles');
    final ftp = catalogJson(packs: const [])..['base'] = 'ftp://example.invalid/';
    expect(() => MapCatalog.fromJson(ftp), throwsFormatException);
  });

  test('Keskeneräinen lataus (.part) poistetaan seuraavalla kerralla', () async {
    final tmp = Directory.systemTemp.createTempSync('gievra-part');
    final store = MapStore.instance..dirOverride = tmp;
    File('${tmp.path}/suomi.pmtiles.part').writeAsStringSync('puolikas');
    await store.load(network: false);
    expect(tmp.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    store.dirOverride = null;
    tmp.deleteSync(recursive: true);
  });

  group('Useampi maa', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gievra-maat'));
    tearDown(() {
      MapStore.instance
        ..dirOverride = null
        ..clientOverride = null
        ..catalog = null
        ..country = 'fi'
        ..installed.clear()
        ..downloads.clear();
      tmp.deleteSync(recursive: true);
    });

    // Keksitty raja-alue: Suomen kunta ja Ruotsin kommun vierekkäin (lon 24,0–24,2 ja 23,8–24,0).
    List<int> bytes(String s) => utf8.encode(s);
    final fiPack = bytes('fi kunta'), sePack = bytes('se kommun'), seOver = bytes('se yleiskartta');
    final fiOver = bytes('fi yleiskartta');
    Map<String, Object> fiCat() => catalogJson(
      packs: [square('rajakunta', 24.0, 65.8, 24.2, 66.0, size: fiPack.length, sha: sha256.convert(fiPack).toString())],
      overview: {'file': 'yleiskartta.pmtiles', 'size': fiOver.length, 'sha256': sha256.convert(fiOver).toString()},
    );
    Map<String, Object> seCat({String country = 'se'}) => {
      ...catalogJson(
        packs: [
          {
            ...square(
              'se-rajakommun',
              23.8,
              65.8,
              24.0,
              66.0,
              size: sePack.length,
              sha: sha256.convert(sePack).toString(),
            ),
            'region': 'Norrbottens län',
          },
        ],
        overview: {
          'file': 'se-yleiskartta.pmtiles',
          'size': seOver.length,
          'sha256': sha256.convert(seOver).toString(),
        },
      ),
      'format': 2,
      'country': country,
      'unit': 'kommun',
      'names': {'fi': 'Ruotsi', 'en': 'Sweden', 'se': 'Ruoŧŧa', 'local': 'Sverige'},
      'boundaries': '© OpenStreetMap contributors (ODbL)',
    }..remove('all');

    MockClient server({String seCountry = 'se'}) => MockClient.streaming((req, _) async {
      final body = switch (req.url.pathSegments.last) {
        'maat.json' => bytes(
          jsonEncode({
            'format': 2,
            'countries': [
              {'id': 'fi', 'catalog': 'https://example.invalid/kartat/kartat.json'},
              {'id': 'se', 'catalog': 'https://example.invalid/pohjola/se.json'},
            ],
          }),
        ),
        'kartat.json' => bytes(jsonEncode(fiCat())),
        'se.json' => bytes(jsonEncode(seCat(country: seCountry))),
        'rajakunta.pmtiles' => fiPack,
        'se-rajakommun.pmtiles' => sePack,
        'se-yleiskartta.pmtiles' => seOver,
        'yleiskartta.pmtiles' => fiOver,
        _ => bytes('?'),
      };
      return http.StreamedResponse(Stream.value(body), 200);
    });

    test('Maaluettelo: Suomi ja Ruotsi, säde rajan yli, Ruotsin paketin mukana Ruotsin yleiskartta', () async {
      final store = MapStore.instance
        ..dirOverride = tmp
        ..clientOverride = server();
      expect(await store.load(refresh: true), isNull);
      expect(store.catalogs.keys, ['fi', 'se']);
      expect(store.catalogs['se']!.label('fi'), 'Ruotsi');
      expect(store.catalogs['se']!.all, isNull);
      // Rajalla: 10 km säde ottaa molemmat maat, lähin ensin.
      final near = store.packsWithin(65.9, 24.05, 10);
      expect(near.map((x) => x.id), ['rajakunta', 'se-rajakommun']);
      expect(store.packAt(65.9, 23.9)!.country, 'se');

      expect(await store.download([store.catalogs['se']!.packs.single]), isEmpty);
      expect(store.installed, {'se-yleiskartta.pmtiles', 'se-rajakommun.pmtiles'});
      expect(store.covers(65.9, 23.9), isTrue);
      expect(store.covers(65.9, 24.1), isFalse);

      // Tallennetut luettelot riittävät ilman verkkoa.
      store
        ..catalog = null
        ..clientOverride = MockClient((_) async => http.Response('', 500));
      expect(await store.load(), isNull);
      expect(store.catalogs.keys, ['fi', 'se']);
      expect(File('${tmp.path}/se.json').existsSync(), isTrue);
    });

    test('Väärän maan luettelo hylätään; vanha julkaisu ilman maaluetteloa: vain Suomi', () async {
      final store = MapStore.instance
        ..dirOverride = tmp
        ..clientOverride = server(seCountry: 'no');
      await store.load(refresh: true);
      expect(store.catalogs.keys, ['fi']);

      store
        ..catalog = null
        ..clientOverride = MockClient.streaming((req, _) async {
          final last = req.url.pathSegments.last;
          if (last == 'maat.json') return http.StreamedResponse(Stream.value(bytes('')), 404);
          return http.StreamedResponse(Stream.value(bytes(jsonEncode(fiCat()))), 200);
        });
      expect(await store.load(refresh: true), isNull);
      expect(store.catalogs.keys, ['fi']);
    });
  });

  group('Tuonti tiedostosta', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gievra-karttatuonti'));
    tearDown(() {
      MapStore.instance
        ..dirOverride = null
        ..catalog = null
        ..installed.clear();
      tmp.deleteSync(recursive: true);
    });

    Map<String, Object> catalogFor(List<int> pmtiles, {String? sha}) => catalogJson(
      packs: [
        square('testi', 27.0, 68.9, 27.03, 68.91, size: pmtiles.length, sha: sha ?? sha256.convert(pmtiles).toString()),
      ],
    );

    String zipOf(Map<String, List<int>> files) {
      final a = Archive();
      for (final e in files.entries) {
        a.addFile(ArchiveFile.bytes(e.key, e.value));
      }
      final path = '${tmp.path}/paketti.zip';
      File(path).writeAsBytesSync(ZipEncoder().encodeBytes(a));
      return path;
    }

    test('Zip-paketti: luettelo ja kartta asennetaan, tarkiste tarkistetaan', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final store = MapStore.instance..dirOverride = maps;
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final zip = zipOf({'kartat.json': utf8.encode(jsonEncode(catalogFor(pm))), 'testi.pmtiles': pm});
      expect(await store.importFiles([zip]), 1);
      expect(store.installed, {'testi.pmtiles'});
      expect(store.catalog!.packs.single.id, 'testi');
      expect(store.covers(68.905, 27.015), isTrue);
      expect(Directory('${maps.path}/tuonti').existsSync(), isFalse);
    });

    test('Väärä tarkiste tai muu kuin kartta: ei asenneta', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final store = MapStore.instance..dirOverride = maps;
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final bad = zipOf({'kartat.json': utf8.encode(jsonEncode(catalogFor(pm, sha: 'f' * 64))), 'testi.pmtiles': pm});
      await expectLater(store.importFiles([bad]), throwsFormatException);
      expect(store.installed, isEmpty);
      final notMap = '${tmp.path}/roska.pmtiles';
      File(notMap).writeAsStringSync('ei kartta');
      await expectLater(store.importFiles([notMap]), throwsA(anything));
      expect(maps.listSync().whereType<File>().where((f) => f.path.endsWith('.pmtiles')), isEmpty);
    });
  });
}
