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

// Offline-kartat: kuntakohtaiset (muissa maissa kommuner, council areas, provinciat …) OpenStreetMap-paketit (tools/map_extract.py, tools/map_catalog.py) ladataan
// GitHubin karttajulkaisusta sovelluksen omaan kansioon (ei treenikansioon: gigatavuja ei synkata eikä
// varmuuskopioida, ja ne voi aina ladata uudelleen). Sijaintia ei lähetetä minnekään: kunta ja etäisyydet
// lasketaan laitteella luettelon rajoista.

/// Suomen luettelon osoite (karttajulkaisun liite; uusi karttaversio = uusi tagi). Käytetään, jos maaluetteloa ei
/// saada. Testeissä ja emulaattorilla: --dart-define=MAP_CATALOG=http://10.0.2.2:8095/kartat.json
const mapCatalogUrl = String.fromEnvironment(
  'MAP_CATALOG',
  defaultValue: 'https://github.com/sombyduodji/gievra/releases/download/kartat-2026-11/kartat.json',
);

/// Maaluettelo: maat ja niiden luetteloiden osoitteet (Suomi, Ruotsi, Norja, Tanska, Islanti, Iso-Britannia, Espanja).
const mapIndexUrl = String.fromEnvironment(
  'MAP_INDEX',
  defaultValue: 'https://github.com/sombyduodji/gievra/releases/download/kartat-2026-11/maat.json',
);

/// Verkko-osoite vain https:llä (kehitysversiossa myös http, esim. paikallinen testipalvelin).
String safeMapUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !(u.isScheme('https') || (kDebugMode && u.isScheme('http'))) || u.host.isEmpty) {
    throw FormatException('karttojen osoite ei kelpaa: $url');
  }
  return url;
}

/// Karttatiedoston nimi luettelosta: vain pelkkä nimi (a–z, 0–9, -) ja .pmtiles, ettei luettelo voi ohjata
/// tiedostoa muualle (esim. ../ tai absoluuttinen polku).
String safeMapFile(String name) {
  if (!RegExp(r'^[a-z0-9-]+\.pmtiles$').hasMatch(name)) throw FormatException('karttatiedoston nimi ei kelpaa: $name');
  return name;
}

class MapPack {
  final String id, name, file, region, sha256;

  /// Maa (ISO 3166-1 -koodi pienillä kirjaimilla), jonka luettelossa paketti on.
  final String country;
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
    this.country = 'fi',
  });

  factory MapPack.fromJson(Map<String, dynamic> j, {String country = 'fi'}) => MapPack(
    country: country,
    id: j['id'] as String? ?? p.basenameWithoutExtension(j['file'] as String),
    name: j['name'] as String? ?? j['file'] as String,
    file: safeMapFile(j['file'] as String),
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

  /// Maa (fi, se, no, dk, is, gb, es), sen nimet (fi, en, se, local) ja pakettien yksikkö (kommun, council …).
  final String country, unit;
  final Map<String, String> names;

  /// Aluerajojen lähde (esim. Tilastokeskus tai OpenStreetMap).
  final String boundaries;
  final MapPack overview;

  /// Koko maa yhtenä tiedostona (vain, jos se on alle GitHubin 2 GiB:n rajan).
  final MapPack? all;
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
    this.country = 'fi',
    this.unit = 'kunta',
    this.names = const {'fi': 'Suomi', 'en': 'Finland', 'se': 'Suopma', 'local': 'Suomi'},
    this.boundaries = 'Tilastokeskus, CC BY 4.0',
  });

  static String _safeBase(String base) {
    safeMapUrl(base);
    return base.endsWith('/') ? base : '$base/';
  }

  factory MapCatalog.fromJson(Map<String, dynamic> j) {
    final cc = j['country'] as String? ?? 'fi';
    if (!RegExp(r'^[a-z]{2}$').hasMatch(cc)) throw FormatException('maakoodi ei kelpaa: $cc');
    final fi = cc == 'fi';
    MapPack pack(Map<String, dynamic> e) => MapPack.fromJson(e, country: cc);
    final all = j['all'] as Map<String, dynamic>?;
    return MapCatalog(
      country: cc,
      unit: j['unit'] as String? ?? 'kunta',
      names: j['names'] == null
          ? const {'fi': 'Suomi', 'en': 'Finland', 'se': 'Suopma', 'local': 'Suomi'}
          : {for (final e in (j['names'] as Map).entries) '${e.key}': '${e.value}'},
      boundaries: j['boundaries'] as String? ?? 'Tilastokeskus, CC BY 4.0',
      tag: j['tag'] as String,
      osmDate: j['osmDate'] as String? ?? '',
      base: _safeBase(j['base'] as String),
      overview: pack({
        ...(j['overview'] as Map<String, dynamic>),
        'id': fi ? 'yleiskartta' : '$cc-yleiskartta',
        'name': 'Yleiskartta',
      }),
      all: all == null ? null : pack({...all, 'id': fi ? 'suomi' : '$cc-koko', 'name': 'Koko maa'}),
      packs: [for (final e in j['packs'] as List) pack(e as Map<String, dynamic>)],
      regions: [for (final r in (j['regions'] as List? ?? const [])) r as String],
    );
  }

  /// Maan nimi käyttöliittymän kielellä.
  String label(String lang) => names[lang] ?? names['en'] ?? country;

  /// Välimuistin tiedostonimi: Suomi kartat.json (vanhat versiot), muut `<maa>.json`.
  String get cacheName => country == 'fi' ? 'kartat.json' : '$country.json';

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

  /// Maiden luettelot (Suomi ensin) ja Kartat-näkymässä valittu maa.
  final catalogs = <String, MapCatalog>{};
  String country = 'fi';

  /// Valitun maan luettelo (null, kun yhtään luetteloa ei ole).
  MapCatalog? get catalog => catalogs[country] ?? catalogs.values.firstOrNull;
  set catalog(MapCatalog? c) {
    if (c == null) {
      catalogs.clear();
    } else {
      _add(c);
      country = c.country;
    }
  }

  void _add(MapCatalog c) {
    catalogs[c.country] = c;
    // Suomi ensin, muut aakkosjärjestyksessä maakoodin mukaan.
    final sorted = catalogs.values.toList()
      ..sort((a, b) => a.country == 'fi' ? -1 : (b.country == 'fi' ? 1 : a.country.compareTo(b.country)));
    catalogs
      ..clear()
      ..addEntries([for (final x in sorted) MapEntry(x.country, x)]);
  }

  /// Kaikkien maiden kaikki tiedostot (yleiskartat, koko maa, paketit).
  Iterable<MapPack> get allPacks => catalogs.values.expand((c) => [c.overview, ?c.all, ...c.packs]);

  /// Paketti, jonka alueella piste on (mikä tahansa maa).
  MapPack? packAt(double lat, double lon) {
    for (final c in catalogs.values) {
      final k = c.packAt(lat, lon);
      if (k != null) return k;
    }
    return null;
  }

  /// Paketit enintään [km] päässä pisteestä kaikista maista (lähin ensin): rajan yli ulottuu naapurimaahan.
  List<MapPack> packsWithin(double lat, double lon, double km) {
    final list = [
      for (final c in catalogs.values)
        for (final x in c.packsWithin(lat, lon, km)) (x, x.distanceKm(lat, lon)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in list) e.$1];
  }

  final installed = <String>{}; // tiedostonimet
  final downloads = <String, MapDownload>{};
  bool _cancel = false;
  final _open = <String, PmTilesFile>{};

  /// Lataus katkaistaan, jos dataa ei tule tähän aikaan.
  static const _stall = Duration(seconds: 30);

  Future<Directory> dir() async {
    final d = dirOverride ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'kartat'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Luettelot: ensin tallennetut kopiot, sitten verkosta (jos [refresh]): maaluettelo ja jokaisen maan luettelo.
  /// Jos maaluetteloa ei saada, haetaan pelkkä Suomen luettelo. Palauttaa virheen tekstinä tai null.
  /// [network] false: vain tallennetut luettelot ja ladatut tiedostot (nopea, ei verkkoa).
  Future<String?> load({bool refresh = false, bool network = true}) async {
    final d = await dir();
    if (catalogs.isEmpty) {
      await for (final e in d.list()) {
        final n = p.basename(e.path);
        if (e is! File || !_isCatalogName(n)) continue;
        try {
          _add(MapCatalog.fromJson(jsonDecode(await e.readAsString()) as Map<String, dynamic>));
        } catch (_) {}
      }
    }
    await _scan();
    notifyListeners(); // tallennetut luettelot näkyvät heti, verkosta haku jatkuu taustalla
    String? err;
    if (network && (refresh || catalogs.isEmpty)) {
      final client = clientOverride ?? http.Client();
      Future<String> get(String url) async {
        final r = await client.get(Uri.parse(safeMapUrl(url))).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}');
        return utf8.decode(r.bodyBytes);
      }

      Future<void> fetch(String url, {String? expect}) async {
        final text = await get(url);
        final c = MapCatalog.fromJson(jsonDecode(text) as Map<String, dynamic>);
        if (expect != null && c.country != expect) throw FormatException('luettelon maa ${c.country} ≠ $expect');
        _add(c);
        await File(p.join(d.path, c.cacheName)).writeAsString(text);
      }

      try {
        List<(String, String)> countries;
        try {
          final index = jsonDecode(await get(mapIndexUrl)) as Map<String, dynamic>;
          countries = [
            for (final e in index['countries'] as List) ((e as Map)['id'] as String, e['catalog'] as String),
          ];
        } catch (_) {
          countries = [('fi', mapCatalogUrl)]; // vanha julkaisu ilman maaluetteloa
        }
        final errors = <String>[];
        await Future.wait([
          for (final (cc, url) in countries) fetch(url, expect: cc).catchError((Object e) => errors.add('$cc: $e')),
        ]);
        if (errors.isNotEmpty && catalogs.isEmpty) err = errors.join('; ');
      } catch (e) {
        err = '$e';
      } finally {
        if (clientOverride == null) client.close();
      }
    }
    notifyListeners();
    return err;
  }

  static bool _isCatalogName(String n) => n == 'kartat.json' || RegExp(r'^[a-z]{2}\.json$').hasMatch(n);

  Future<void> _scan() async {
    final d = await dir();
    installed.clear();
    await for (final e in d.list()) {
      if (e is! File) continue;
      if (e.path.endsWith('.pmtiles')) installed.add(p.basename(e.path));
      // Keskeneräinen lataus (sovellus suljettiin kesken): poistetaan, ettei vie tilaa.
      if (e.path.endsWith('.part') && downloads.isEmpty) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  bool isInstalled(MapPack x) => installed.contains(x.file);

  /// Onko pisteen kohdalla tarkka kartta (alueen paketti tai koko maa ladattu).
  bool covers(double lat, double lon) {
    for (final c in catalogs.values) {
      // Suomi: koko maa kattaa myös merialueet (kuten ennenkin).
      if (c.country == 'fi' && c.all != null && isInstalled(c.all!)) return true;
      final k = c.packAt(lat, lon);
      if (k != null && (isInstalled(k) || (c.all != null && isInstalled(c.all!)))) return true;
    }
    return false;
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
  /// [replace]: ladataan myös jo asennetut (päivitys); vanha kartta pysyy käytössä, kunnes uusi on tarkistettu.
  /// Palauttaa epäonnistuneet lataukset (tyhjä = kaikki onnistui). Latauslista tyhjenee aina lopuksi.
  Future<List<MapDownload>> download(List<MapPack> packs, {bool replace = false}) async {
    if (catalogs.isEmpty || downloads.isNotEmpty) return const [];
    // Jokaisen maan yleiskartta mukaan, jos sitä (tai koko maata) ei vielä ole.
    final countries = packs.isEmpty ? {country} : {for (final x in packs) x.country};
    final todo = [
      for (final cc in countries)
        if (catalogs[cc] case final c? when !isInstalled(c.overview) && !(c.all != null && isInstalled(c.all!)))
          c.overview,
      ...packs.where((x) => replace || !isInstalled(x)),
    ];
    _cancel = false;
    for (final x in todo) {
      downloads[x.file] = MapDownload(x);
    }
    notifyListeners();
    final client = _client = clientOverride ?? http.Client();
    final failed = <MapDownload>[];
    try {
      for (final x in todo) {
        final dl = downloads[x.file]!;
        if (_cancel) {
          dl.error = 'peruttu';
          failed.add(dl);
          continue;
        }
        try {
          await _fetch(client, catalogs[x.country]!.base, x, dl);
          dl.done = true;
          installed.add(x.file);
          await _setVersion(x.file, x.sha256);
        } catch (e) {
          dl.error = _cancel ? 'peruttu' : '$e';
          failed.add(dl);
        }
        notifyListeners();
      }
    } finally {
      _client = null;
      if (clientOverride == null) client.close();
      downloads.clear();
      notifyListeners();
    }
    return failed;
  }

  http.Client? _client;

  /// Keskeyttää latauksen heti, myös jumittuneen (yhteys suljetaan).
  void cancel() {
    _cancel = true;
    if (clientOverride == null) _client?.close();
  }

  Future<void> _fetch(http.Client client, String base, MapPack x, MapDownload dl) async {
    final d = await dir();
    final part = File(p.join(d.path, '${x.file}.part'));
    final res = await client.send(http.Request('GET', Uri.parse('$base${x.file}'))).timeout(_stall);
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final sink = part.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    try {
      await for (final chunk in res.stream.timeout(_stall)) {
        if (_cancel) throw const HttpException('peruttu');
        sink.add(chunk);
        hasher.add(chunk);
        dl.received += chunk.length;
        notifyListeners();
      }
      await sink.close();
      hasher.close();
      if (digest.value.toString() != x.sha256) throw const FormatException('tarkiste ei täsmää');
      await _open.remove(x.file)?.close(); // päivitys: vanha tiedosto suljetaan ennen korvaamista
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
      // Luettelot ensin: niillä tarkistetaan kartat.
      for (final n in staged.keys.where(_isCatalogName).toList()) {
        final text = await staged.remove(n)!.readAsString();
        final c = MapCatalog.fromJson(jsonDecode(text) as Map<String, dynamic>);
        catalog = c;
        await File(p.join(d.path, c.cacheName)).writeAsString(text);
      }
      final known = {for (final x in allPacks) x.file: x};
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

  static bool _importable(String name) => _isCatalogName(name) || RegExp(r'^[a-z0-9-]+\.pmtiles$').hasMatch(name);

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
    final v = await _versions();
    final d = await dir();
    final out = <MapPack>[];
    for (final x in allPacks) {
      if (!installed.contains(x.file)) continue;
      final known = v[x.file];
      final size = await File(p.join(d.path, x.file)).length();
      if ((known != null && known != x.sha256) || size != x.size) out.add(x);
    }
    return out;
  }

  /// Päivittää vanhentuneet kartat (lataa uuden version vanhan tilalle; epäonnistuessa vanha jää käyttöön).
  Future<List<MapDownload>> update(List<MapPack> packs) => download(packs, replace: true);

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
    await _scan(); // myös keskeneräisten latausten jäänteet
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
