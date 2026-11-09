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
  MapStore.instance.retryDelay = Duration.zero;

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
        ..clientOverride = null
        ..catalog = null
        ..installed.clear()
        ..unverified.clear()
        ..forgetKnown();
      tmp.deleteSync(recursive: true);
    });

    Map<String, Object> catalogFor(List<int> pmtiles, {String? sha, List<String>? old}) {
      final c = catalogJson(
        packs: [
          square(
            'testi',
            27.0,
            68.9,
            27.03,
            68.91,
            size: pmtiles.length,
            sha: sha ?? sha256.convert(pmtiles).toString(),
          ),
        ],
      );
      if (old != null) ((c['packs'] as List).single as Map)['sha256Old'] = old;
      return c;
    }

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
      final r = await store.importFiles([zip]);
      expect(r.imported, ['testi.pmtiles']);
      expect(r.skipped, isEmpty);
      expect(store.installed, {'testi.pmtiles'});
      expect(store.catalog!.packs.single.id, 'testi');
      expect(store.covers(68.905, 27.015), isTrue);
      expect(Directory('${maps.path}/tuonti').existsSync(), isFalse);
    });

    test('Kartta tunnistetaan sisällöstä: selaimen muuttama nimi tallentuu luettelon nimellä', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final store = MapStore.instance..dirOverride = maps;
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      store.catalog = MapCatalog.fromJson(catalogFor(pm));
      final renamed = '${tmp.path}/Testi (1).PMTILES';
      File(renamed).writeAsBytesSync(pm);
      final other = '${tmp.path}/jotain-muuta.pmtiles';
      File(other).writeAsBytesSync(pm);
      final r = await store.importFiles([renamed, other]);
      expect(r.imported, ['testi.pmtiles']);
      expect(r.skipped, isEmpty);
      expect(
        maps.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).where((n) => n.endsWith('.pmtiles')),
        ['testi.pmtiles'],
      );
    });

    test('Väärä tarkiste, vajaa tiedosto tai muu kuin kartta: ohitetaan syyn kanssa', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final store = MapStore.instance..dirOverride = maps;
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final bad = zipOf({'kartat.json': utf8.encode(jsonEncode(catalogFor(pm, sha: 'f' * 64))), 'testi.pmtiles': pm});
      var r = await store.importFiles([bad]);
      expect(r.imported, isEmpty);
      expect(r.skipped, [('testi.pmtiles', MapSkip.otherVersion)]);
      final changed = '${tmp.path}/testi(2).pmtiles';
      File(changed).writeAsBytesSync([...pm.sublist(0, pm.length - 1), pm.last ^ 1]);
      final cut = '${tmp.path}/vajaa.pmtiles';
      File(cut).writeAsBytesSync(pm.sublist(0, pm.length - 10));
      final notMap = '${tmp.path}/roska.pmtiles';
      File(notMap).writeAsStringSync('ei kartta');
      final text = '${tmp.path}/muistiinpano.txt';
      File(text).writeAsStringSync('hei');
      r = await store.importFiles([changed, cut, notMap, text]);
      expect(r.imported, isEmpty);
      expect(r.skipped, [
        ('muistiinpano.txt', MapSkip.notMap),
        ('vajaa.pmtiles', MapSkip.truncated),
        ('roska.pmtiles', MapSkip.notMap),
        ('testi(2).pmtiles', MapSkip.otherVersion),
      ]);
      expect(store.installed, isEmpty);
      expect(maps.listSync().whereType<File>().where((f) => f.path.endsWith('.pmtiles')), isEmpty);
    });

    test('Ilman luetteloa ja ilman kysyjää karttaa ei tuoda', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final store = MapStore.instance..dirOverride = maps;
      final file = '${tmp.path}/testi.pmtiles';
      File(file).writeAsBytesSync(pm);
      final r = await store.importFiles([file]);
      expect(r.skipped, [('testi.pmtiles', MapSkip.noCatalog)]);
      expect(File(file).existsSync(), isTrue, reason: 'käyttäjän tiedostoa ei siirretä');
    });

    test('Tarkista verkosta: uudempi luettelo tunnistaa kartan', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final store = MapStore.instance
        ..dirOverride = maps
        ..catalog = MapCatalog.fromJson(catalogFor(pm, sha: 'e' * 64))
        ..clientOverride = MockClient((req) async {
          if (req.url.pathSegments.last == 'maat.json') return http.Response('', 404);
          return http.Response(jsonEncode(catalogFor(pm)), 200);
        });
      final file = '${tmp.path}/testi (1).pmtiles';
      File(file).writeAsBytesSync(pm);
      final asked = <bool>[];
      final r = await store.importFiles(
        [file],
        onUnverified: (names, {required checkedOnline}) async {
          asked.add(checkedOnline);
          return UnverifiedChoice.checkOnline;
        },
      );
      expect(asked, [false]);
      expect(r.imported, ['testi.pmtiles']);
      expect(r.unverified, isEmpty);
      expect(File(file).existsSync(), isTrue);
    });

    test('Vanhempi versio tunnistetaan: luettelon aiemmat tarkisteet ja laitteen muistamat', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final real = sha256.convert(pm).toString();
      final file = '${tmp.path}/testi.pmtiles';
      File(file).writeAsBytesSync(pm);
      // 1) Luettelossa uusi versio, vanha tarkiste sha256Old-listassa: tunnistetaan, päivitys tarjolla.
      var store = MapStore.instance
        ..dirOverride = maps
        ..catalog = MapCatalog.fromJson(catalogFor(pm, sha: 'a' * 64, old: [real]));
      var r = await store.importFiles([file]);
      expect(r.imported, ['testi.pmtiles']);
      expect((await store.outdated()).map((x) => x.file), ['testi.pmtiles']);
      await store.deleteFile('testi.pmtiles');
      // 2) Laite on nähnyt tarkisteen aiemmin; nykyisessä luettelossa sitä ei enää ole.
      store
        ..catalog = null
        ..forgetKnown()
        ..catalog = MapCatalog.fromJson(catalogFor(pm));
      store = MapStore.instance..catalog = MapCatalog.fromJson(catalogFor(pm, sha: 'b' * 64));
      r = await store.importFiles([file]);
      expect(r.imported, ['testi.pmtiles']);
      // Muisti säilyy tiedostossa: uusi käynnistys (tyhjä muisti) lukee sen.
      store
        ..forgetKnown()
        ..catalog = null;
      await store.load(network: false);
      await store.deleteFile('testi.pmtiles');
      store.catalog = MapCatalog.fromJson(catalogFor(pm, sha: 'c' * 64));
      r = await store.importFiles([file]);
      expect(r.imported, ['testi.pmtiles']);
    });

    test('Tuo tarkistamatta: merkitään eikä korvaa tarkistettua; vajaa ei kelpaa', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final store = MapStore.instance..dirOverride = maps;
      final file = '${tmp.path}/Oma Kartta (2).pmtiles';
      File(file).writeAsBytesSync(pm);
      Future<UnverifiedChoice> anyway(List<String> n, {required bool checkedOnline}) async =>
          UnverifiedChoice.importAnyway;
      var r = await store.importFiles([file], onUnverified: anyway);
      expect(r.imported, ['oma-kartta.pmtiles']);
      expect(r.unverified, ['oma-kartta.pmtiles']);
      expect(store.unverified, {'oma-kartta.pmtiles'});

      // Tarkistettu testi.pmtiles asennettu; samanniminen tarkistamaton ei korvaa sitä.
      store.catalog = MapCatalog.fromJson(catalogFor(pm));
      final good = '${tmp.path}/testi.pmtiles';
      File(good).writeAsBytesSync(pm);
      expect((await store.importFiles([good])).imported, ['testi.pmtiles']);
      final changed = '${tmp.path}/testi(1).pmtiles';
      File(changed).writeAsBytesSync([...pm.sublist(0, pm.length - 1), pm.last ^ 1]);
      r = await store.importFiles([changed], onUnverified: anyway);
      expect(r.skipped, [('testi(1).pmtiles', MapSkip.verifiedExists)]);
      expect(File('${maps.path}/testi.pmtiles').readAsBytesSync(), pm);

      // Vajaa tiedosto ei kelpaa edes tarkistamatta.
      final cut = '${tmp.path}/vajaa.pmtiles';
      File(cut).writeAsBytesSync(pm.sublist(0, pm.length - 10));
      r = await store.importFiles([cut], onUnverified: anyway);
      expect(r.skipped, [('vajaa.pmtiles', MapSkip.truncated)]);
    });

    test('Edistyminen: tarkistetut tavut kasvavat loppuun asti', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final store = MapStore.instance
        ..dirOverride = maps
        ..catalog = MapCatalog.fromJson(catalogFor(pm));
      final file = '${tmp.path}/testi.pmtiles';
      File(file).writeAsBytesSync(pm);
      final seen = <MapImportProgress>[];
      await store.importFiles([file], onProgress: seen.add);
      final v = seen.where((x) => x.phase == MapImportPhase.verifying).toList();
      expect(v.first.done, 0);
      expect(v.last.done, pm.length);
      expect(v.last.total, pm.length);
      expect(seen.last.phase, MapImportPhase.installing);
    });

    test('Turvallinen nimi tarkistamattomalle', () {
      expect(MapStore.safeImportName('Oma Kartta (2).pmtiles'), 'oma-kartta.pmtiles');
      expect(MapStore.safeImportName('Ähtäri_ö.PMTILES'), 'ahtari-o.pmtiles');
      expect(MapStore.safeImportName('../../x.pmtiles'), 'x.pmtiles');
      expect(MapStore.safeImportName('kartta.txt'), isNull);
    });

    test('Tarkista verkosta: GitHubin omat tarkisteet tunnistavat vanhan julkaisun kartan', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final real = sha256.convert(pm).toString();
      final store = MapStore.instance
        ..dirOverride = maps
        ..clientOverride = MockClient((req) async {
          if (req.url.host == 'api.github.com') {
            expect(req.headers['User-Agent'], 'Gievra');
            return http.Response(
              jsonEncode([
                {
                  'tag_name': 'v0.3.2',
                  'assets': [
                    {'name': 'muu.pmtiles', 'digest': 'sha256:$real'},
                  ],
                },
                {
                  'tag_name': 'kartat-2025-01',
                  'assets': [
                    {'name': '../pois.pmtiles', 'digest': 'sha256:${'d' * 64}'},
                    {'name': 'testi.pmtiles', 'digest': 'sha256:$real'},
                    {'name': 'kartat.json', 'digest': 'sha256:${'c' * 64}'},
                  ],
                },
              ]),
              200,
            );
          }
          if (req.url.pathSegments.last == 'maat.json') return http.Response('', 404);
          return http.Response(jsonEncode(catalogFor(pm, sha: 'e' * 64)), 200); // nykyinen luettelo: uudempi
        });
      final file = '${tmp.path}/testi(3).pmtiles';
      File(file).writeAsBytesSync(pm);
      final r = await store.importFiles([
        file,
      ], onUnverified: (n, {required checkedOnline}) async => UnverifiedChoice.checkOnline);
      expect(r.imported, ['testi.pmtiles']);
      expect(r.unverified, isEmpty);
      expect(store.knownShas()[real], 'testi.pmtiles');
      expect(store.knownShas().containsValue('../pois.pmtiles'), isFalse);
      expect((await store.outdated()).map((x) => x.file), ['testi.pmtiles'], reason: 'vanha versio: päivitys tarjolla');
    });

    test('Ilman verkkoa: kotisivun tarkistetaulukko samalla kertaa tarkistaa kartan', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      final real = sha256.convert(pm).toString();
      final store = MapStore.instance..dirOverride = maps; // ei luetteloita, ei verkkoa
      final table = '${tmp.path}/kartat-tarkisteet(1).json';
      File(table).writeAsStringSync(
        jsonEncode({
          'format': checksumTableFormat,
          'version': 1,
          'files': [
            ['testi.pmtiles', real, pm.length, 'kartat-2025-01'],
            ['../pois.pmtiles', 'a' * 64, 1, 'kartat-2025-01'],
            ['rikki.pmtiles', 'ei-heksaa', 1, 'kartat-2025-01'],
          ],
        }),
      );
      final file = '${tmp.path}/Testi (2).pmtiles';
      File(file).writeAsBytesSync(pm);
      var r = await store.importFiles([table, file]);
      expect(r.checksums, 1);
      expect(r.imported, ['testi.pmtiles']);
      expect(r.unverified, isEmpty);
      // Taulukko muistetaan: myöhempi tuonti ilman taulukkoa tarkistuu myös.
      await store.deleteFile('testi.pmtiles');
      store.forgetKnown();
      await store.load(network: false);
      r = await store.importFiles([file]);
      expect(r.imported, ['testi.pmtiles']);
      // Pelkkä taulukko: ei karttoja, ei ohitettuja.
      r = await store.importFiles([table]);
      expect(r.imported, isEmpty);
      expect(r.skipped, isEmpty);
      expect(r.checksums, 1);
    });

    test('GitHubin satunnainen 504: luettelo haetaan uudelleen', () async {
      final maps = Directory('${tmp.path}/kartat')..createSync();
      final pm = File('test/fixtures/kartta-testi.pmtiles').readAsBytesSync();
      var calls = 0;
      final store = MapStore.instance
        ..dirOverride = maps
        ..clientOverride = MockClient((req) async {
          if (req.url.pathSegments.last == 'maat.json') return http.Response('', 404);
          return ++calls < 3 ? http.Response('', 504) : http.Response(jsonEncode(catalogFor(pm)), 200);
        });
      expect(await store.load(refresh: true), isNull);
      expect(calls, 3);
      expect(store.catalogs.keys, ['fi']);
    });

    test('Nimen siistiminen', () {
      expect(MapStore.normalizedMapName('es-yleiskartta(1).pmtiles'), 'es-yleiskartta.pmtiles');
      expect(MapStore.normalizedMapName('Es-Yleiskartta (12).pmtiles'), 'es-yleiskartta.pmtiles');
      expect(MapStore.normalizedMapName('no-tromso.pmtiles'), 'no-tromso.pmtiles');
    });
  });
}
