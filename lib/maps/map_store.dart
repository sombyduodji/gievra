import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'pmtiles.dart';

// Offline-kartat: kuntakohtaiset OpenStreetMap-paketit (tools/map_extract.py, tools/map_catalog.py) ladataan
// GitHubin karttajulkaisusta sovelluksen omaan kansioon (ei treenikansioon: gigatavuja ei synkata eikä
// varmuuskopioida, ja ne voi aina ladata uudelleen). Sijaintia ei lähetetä minnekään: kunta ja etäisyydet
// lasketaan laitteella luettelon rajoista.

/// Luettelon osoite (karttajulkaisun liite; uusi karttaversio = uusi tagi). Testeissä ja emulaattorilla: --dart-define=MAP_CATALOG=http://10.0.2.2:8095/kartat.json
const mapCatalogUrl = String.fromEnvironment(
  'MAP_CATALOG',
  defaultValue: 'https://github.com/sombyduodji/gievra/releases/download/kartat-2026-11/kartat.json',
);

class MapPack {
  final String id, name, file, region, sha256;
  final String? se, sv;
  final int size;
  final List<double> bbox; // w, s, e, n
  final List<List<(double, double)>> shape; // (lon, lat) -renkaat
  const MapPack({
    required this.id,
    required this.name,
    required this.file,
    required this.region,
    required this.sha256,
    required this.size,
    required this.bbox,
    required this.shape,
    this.se,
    this.sv,
  });

  factory MapPack.fromJson(Map<String, dynamic> j) => MapPack(
    id: j['id'] as String? ?? p.basenameWithoutExtension(j['file'] as String),
    name: j['name'] as String? ?? j['file'] as String,
    file: j['file'] as String,
    region: j['region'] as String? ?? '',
    sha256: j['sha256'] as String,
    size: j['size'] as int,
    bbox: [
      for (final v in (j['bbox'] as List? ?? const [-180, -90, 180, 90])) (v as num).toDouble(),
    ],
    shape: _shape(j['shape'] as List?),
    se: j['se'] as String?,
    sv: j['sv'] as String?,
  );

  /// Onko piste kunnan alueella (rajan sisällä).
  bool contains(double lat, double lon) {
    if (lon < bbox[0] || lon > bbox[2] || lat < bbox[1] || lat > bbox[3]) return false;
    var c = false;
    for (final r in shape) {
      for (var i = 0, j = r.length - 1; i < r.length; j = i++) {
        final (x1, y1) = r[i];
        final (x2, y2) = r[j];
        if ((y1 > lat) != (y2 > lat) && lon < (x2 - x1) * (lat - y1) / (y2 - y1) + x1) c = !c;
      }
    }
    return c;
  }

  /// Lyhin etäisyys kunnan alueeseen kilometreinä (0, jos piste on sisällä).
  double distanceKm(double lat, double lon) {
    if (contains(lat, lon)) return 0;
    final kx = 111.32 * math.cos(lat * math.pi / 180), ky = 110.574;
    var best = double.infinity;
    for (final r in shape) {
      for (var i = 1; i < r.length; i++) {
        final ax = (r[i - 1].$1 - lon) * kx, ay = (r[i - 1].$2 - lat) * ky;
        final bx = (r[i].$1 - lon) * kx, by = (r[i].$2 - lat) * ky;
        final dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
        final t = l2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / l2).clamp(0.0, 1.0);
        best = math.min(best, math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)));
      }
    }
    return best;
  }

  /// Nimi käyttöliittymän kielellä: saameksi saamenkielinen nimi, jos sellainen on.
  String label(String lang) => lang == 'se' && se != null ? '$se ($name)' : name;
}

/// Luettelossa renkaat ovat listoja [lon, lat]; muunnetaan tietueiksi.
List<List<(double, double)>> _shape(List? raw) => [
  for (final r in (raw ?? const []))
    [for (final pt in r as List) (((pt as List)[0] as num).toDouble(), (pt[1] as num).toDouble())],
];

class MapCatalog {
  final String tag, osmDate, base;
  final MapPack overview, all;
  final List<MapPack> packs;
  final List<String> regions;
  const MapCatalog({
    required this.tag,
    required this.osmDate,
    required this.base,
    required this.overview,
    required this.all,
    required this.packs,
    required this.regions,
  });

  factory MapCatalog.fromJson(Map<String, dynamic> j) {
    MapPack pack(Map<String, dynamic> e) => MapPack.fromJson(e);
    return MapCatalog(
      tag: j['tag'] as String,
      osmDate: j['osmDate'] as String? ?? '',
      base: j['base'] as String,
      overview: pack({...(j['overview'] as Map<String, dynamic>), 'id': 'yleiskartta', 'name': 'Yleiskartta'}),
      all: pack({...(j['all'] as Map<String, dynamic>), 'id': 'suomi', 'name': 'Suomi'}),
      packs: [for (final e in j['packs'] as List) pack(e as Map<String, dynamic>)],
      regions: [for (final r in (j['regions'] as List? ?? const [])) r as String],
    );
  }

  /// Kunta, jossa piste on (null = Suomen ulkopuolella tai merellä).
  MapPack? packAt(double lat, double lon) => packs.where((x) => x.contains(lat, lon)).firstOrNull;

  /// Kunnat, joiden alue on enintään [km] päässä pisteestä (lähin ensin).
  List<MapPack> packsWithin(double lat, double lon, double km) {
    final list = [
      for (final x in packs)
        if (_roughKm(x, lat, lon) <= km + 50) (x, x.distanceKm(lat, lon)),
    ].where((e) => e.$2 <= km).toList()..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in list) e.$1];
  }

  static double _roughKm(MapPack x, double lat, double lon) {
    final b = x.bbox;
    final dlat = lat < b[1] ? b[1] - lat : (lat > b[3] ? lat - b[3] : 0.0);
    final dlon = lon < b[0] ? b[0] - lon : (lon > b[2] ? lon - b[2] : 0.0);
    return math.sqrt(math.pow(dlat * 110.574, 2) + math.pow(dlon * 111.32 * math.cos(lat * math.pi / 180), 2));
  }
}

/// Latauksen tila yhdelle tiedostolle.
class MapDownload {
  final MapPack pack;
  int received = 0;
  bool done = false;
  String? error;
  MapDownload(this.pack);
}

class MapStore extends ChangeNotifier {
  MapStore._();
  static final instance = MapStore._();

  /// Testejä varten: oma kansio ja HTTP-asiakas.
  @visibleForTesting
  Directory? dirOverride;
  @visibleForTesting
  http.Client? clientOverride;

  MapCatalog? catalog;
  final installed = <String>{}; // tiedostonimet
  final downloads = <String, MapDownload>{};
  bool _cancel = false;
  final _open = <String, PmTilesFile>{};

  Future<Directory> dir() async {
    final d = dirOverride ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'kartat'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Luettelo: ensin tallennettu kopio, sitten verkosta (jos [refresh]). Palauttaa virheen tekstinä tai null.
  /// [network] false: vain tallennettu luettelo ja ladatut tiedostot (nopea, ei verkkoa).
  Future<String?> load({bool refresh = false, bool network = true}) async {
    final d = await dir();
    final cached = File(p.join(d.path, 'kartat.json'));
    if (catalog == null && await cached.exists()) {
      try {
        catalog = MapCatalog.fromJson(jsonDecode(await cached.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
    }
    await _scan();
    notifyListeners(); // tallennettu luettelo näkyy heti, verkosta haku jatkuu taustalla
    String? err;
    if (network && (refresh || catalog == null)) {
      try {
        final r = await (clientOverride ?? http.Client())
            .get(Uri.parse(mapCatalogUrl))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}');
        final text = utf8.decode(r.bodyBytes);
        catalog = MapCatalog.fromJson(jsonDecode(text) as Map<String, dynamic>);
        await cached.writeAsString(text);
      } catch (e) {
        err = '$e';
      }
    }
    notifyListeners();
    return err;
  }

  Future<void> _scan() async {
    final d = await dir();
    installed
      ..clear()
      ..addAll([
        await for (final e in d.list())
          if (e is File && e.path.endsWith('.pmtiles')) p.basename(e.path),
      ]);
  }

  bool isInstalled(MapPack x) => installed.contains(x.file);

  /// Onko pisteen kohdalla tarkka kartta (kunta tai koko Suomi ladattu).
  bool covers(double lat, double lon) {
    final c = catalog;
    if (c == null) return false;
    if (isInstalled(c.all)) return true;
    final k = c.packAt(lat, lon);
    return k != null && isInstalled(k);
  }

  /// Ladattujen karttojen koko tavuina.
  Future<int> usedBytes() async {
    final d = await dir();
    var n = 0;
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.pmtiles')) n += await e.length();
    }
    return n;
  }

  /// Lataa paketit (yleiskartta mukaan, jos puuttuu). Tarkistaa SHA-256:n; keskeneräinen tiedosto ei jää.
  Future<void> download(List<MapPack> packs) async {
    final c = catalog;
    if (c == null) return;
    final todo = [
      if (!isInstalled(c.overview) && !isInstalled(c.all)) c.overview,
      ...packs.where((x) => !isInstalled(x)),
    ];
    _cancel = false;
    for (final x in todo) {
      downloads[x.file] = MapDownload(x);
    }
    notifyListeners();
    final client = clientOverride ?? http.Client();
    for (final x in todo) {
      if (_cancel) break;
      final dl = downloads[x.file]!;
      try {
        await _fetch(client, c.base, x, dl);
        dl.done = true;
        installed.add(x.file);
        await _setVersion(x.file, x.sha256);
      } catch (e) {
        dl.error = '$e';
      }
      notifyListeners();
    }
    downloads.removeWhere((_, v) => v.done);
    notifyListeners();
  }

  void cancel() => _cancel = true;

  Future<void> _fetch(http.Client client, String base, MapPack x, MapDownload dl) async {
    final d = await dir();
    final part = File(p.join(d.path, '${x.file}.part'));
    final res = await client.send(http.Request('GET', Uri.parse('$base${x.file}')));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final sink = part.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    try {
      await for (final chunk in res.stream) {
        if (_cancel) throw const HttpException('peruttu');
        sink.add(chunk);
        hasher.add(chunk);
        dl.received += chunk.length;
        notifyListeners();
      }
      await sink.close();
      hasher.close();
      if (digest.value.toString() != x.sha256) throw const FormatException('tarkiste ei täsmää');
      await part.rename(p.join(d.path, x.file));
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// Tuo karttapaketin tiedostosta (ilman verkkoa, esim. Seafilesta tai toiselta laitteelta): .zip, jossa
  /// karttoja (.pmtiles) ja luettelo (kartat.json), tai yksittäinen .pmtiles / kartat.json. Kartat tarkistetaan
  /// (PMTiles-otsake ja luettelon SHA-256, jos luettelossa on tiedosto). Palauttaa tuotujen karttojen määrän.
  Future<int> importFiles(List<String> paths) async {
    final d = await dir();
    final tmp = Directory(p.join(d.path, 'tuonti'));
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create();
    final staged = <String, File>{}; // nimi -> purettu tiedosto
    try {
      for (final path in paths) {
        final name = p.basename(path).toLowerCase();
        if (name.endsWith('.zip')) {
          final input = InputFileStream(path);
          try {
            final zip = ZipDecoder().decodeStream(input);
            for (final f in zip.files) {
              final n = p.basename(f.name);
              if (!f.isFile || !_importable(n)) continue;
              final out = File(p.join(tmp.path, n));
              final os = OutputFileStream(out.path);
              f.writeContent(os);
              await os.close();
              staged[n] = out;
            }
          } finally {
            await input.close();
          }
        } else if (_importable(p.basename(path))) {
          final n = p.basename(path);
          staged[n] = await File(path).copy(p.join(tmp.path, n));
        }
      }
      // Luettelo ensin: sillä tarkistetaan kartat.
      final cat = staged.remove('kartat.json');
      if (cat != null) {
        final text = await cat.readAsString();
        catalog = MapCatalog.fromJson(jsonDecode(text) as Map<String, dynamic>);
        await File(p.join(d.path, 'kartat.json')).writeAsString(text);
      }
      final known = {
        for (final x in [...?catalog?.packs, if (catalog != null) catalog!.overview, if (catalog != null) catalog!.all])
          x.file: x,
      };
      var n = 0;
      for (final e in staged.entries) {
        final f = await PmTilesFile.open(e.value.path); // heittää, jos ei PMTiles v3
        await f.close();
        final pack = known[e.key];
        final digest = (await sha256.bind(e.value.openRead()).first).toString();
        if (pack != null && digest != pack.sha256) throw FormatException('tarkiste ei täsmää: ${e.key}');
        await _open.remove(e.key)?.close();
        await e.value.rename(p.join(d.path, e.key));
        installed.add(e.key);
        await _setVersion(e.key, digest);
        n++;
      }
      notifyListeners();
      return n;
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  static bool _importable(String name) => name == 'kartat.json' || RegExp(r'^[a-z0-9-]+\.pmtiles$').hasMatch(name);

  // Asennettujen karttojen tarkisteet (asennetut.json): päivitys tunnistetaan, kun luettelon tarkiste muuttuu.
  Future<File> _versionsFile() async => File(p.join((await dir()).path, 'asennetut.json'));

  Future<Map<String, String>> _versions() async {
    try {
      final f = await _versionsFile();
      if (!await f.exists()) return {};
      return Map<String, String>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _setVersion(String file, String? sha) async {
    final v = await _versions();
    if (sha == null) {
      v.remove(file);
    } else {
      v[file] = sha;
    }
    await (await _versionsFile()).writeAsString(jsonEncode(v));
  }

  /// Ladatut kartat: tiedostonimi ja koko tavuina, suurin ensin.
  Future<List<(String, int)>> installedFiles() async {
    final d = await dir();
    final out = <(String, int)>[];
    for (final f in installed) {
      final file = File(p.join(d.path, f));
      if (await file.exists()) out.add((f, await file.length()));
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  /// Ladatut kartat, joista luettelossa on uudempi versio (tarkiste tai koko eroaa).
  Future<List<MapPack>> outdated() async {
    final c = catalog;
    if (c == null) return [];
    final v = await _versions();
    final d = await dir();
    final out = <MapPack>[];
    for (final x in [c.overview, c.all, ...c.packs]) {
      if (!installed.contains(x.file)) continue;
      final known = v[x.file];
      final size = await File(p.join(d.path, x.file)).length();
      if ((known != null && known != x.sha256) || size != x.size) out.add(x);
    }
    return out;
  }

  /// Päivittää vanhentuneet kartat (lataa uuden version vanhan tilalle).
  Future<void> update(List<MapPack> packs) async {
    for (final x in packs) {
      installed.remove(x.file);
    }
    await download(packs);
  }

  /// Poistaa yhden ladatun kartan tiedostonimellä (myös tuodut ja yleiskartta).
  Future<void> deleteFile(String file) async {
    await _open.remove(file)?.close();
    final f = File(p.join((await dir()).path, file));
    if (await f.exists()) await f.delete();
    installed.remove(file);
    await _setVersion(file, null);
    notifyListeners();
  }

  /// Poistaa kaikki ladatut kartat (luettelo jää, joten ne voi ladata uudelleen).
  Future<void> deleteAll() async {
    for (final f in [...installed]) {
      await deleteFile(f);
    }
  }

  Future<void> delete(MapPack x) => deleteFile(x.file);

  /// Sulkee avatut karttatiedostot (esim. kun kansio vaihtuu tai testi siivoaa).
  Future<void> closeAll() async {
    for (final f in _open.values) {
      await f.close();
    }
    _open.clear();
  }

  /// Avatut karttatiedostot karttanäkymälle: koko Suomi tai kunnat + yleiskartta.
  Future<List<PmTilesFile>> openFiles() async {
    final d = await dir();
    final out = <PmTilesFile>[];
    for (final f in installed) {
      try {
        out.add(_open[f] ??= await PmTilesFile.open(p.join(d.path, f)));
      } catch (_) {}
    }
    return out;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
