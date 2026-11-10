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
import 'package:vector_tile/vector_tile.dart';

import '../gps_filter.dart';
import '../l10n.dart' as l10n;
import 'elevation.dart';
import 'file_hash.dart';
import 'path_snap.dart';
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

/// Kotisivulta ladattavan tarkistetaulukon tunniste (tools/site_maps.py → site/kartat-tarkisteet.json).
const checksumTableFormat = 'gievra-kartat-tarkisteet';

/// GitHubin julkaisujen API: jokaisen julkaisutiedoston SHA-256 (GitHub laskee sen itse, kenttä `digest`).
/// "Tarkista verkosta" tunnistaa näin minkä tahansa koskaan julkaistun karttaversion.
const mapReleasesApi = String.fromEnvironment(
  'MAP_RELEASES_API',
  defaultValue: 'https://api.github.com/repos/sombyduodji/gievra/releases?per_page=100',
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
  if (!RegExp(r'^[a-z0-9-]+\.(pmtiles|elev)$').hasMatch(name)) {
    throw FormatException('karttatiedoston nimi ei kelpaa: $name');
  }
  return name;
}

/// Korkeustiedosto (.elev, lib/maps/elevation.dart), ei kartta.
bool isElevFile(String name) => name.endsWith('.elev');

class MapPack {
  final String id, name, file, region, sha256;

  /// Maa (ISO 3166-1 -koodi pienillä kirjaimilla), jonka luettelossa paketti on.
  final String country;
  final String? se, sv;
  final int size;
  final List<double> bbox; // w, s, e, n
  final List<List<(double, double)>> shape; // (lon, lat) -renkaat

  /// Saman kartan aiempien julkaisujen tarkisteet: vanhempi tiedosto tunnistetaan tuonnissa (päivitys tarjolla).
  final List<String> oldSha256;

  /// Saman alueen korkeustiedot omana tiedostonaan (null = ei saatavilla, esim. muut maat kuin Suomi).
  final MapPack? elev;
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
    this.oldSha256 = const [],
    this.elev,
  });

  bool get isElevation => isElevFile(file);

  factory MapPack.fromJson(Map<String, dynamic> j, {String country = 'fi'}) {
    final pack = MapPack._fromJson(j, country: country);
    final e = j['elev'] as Map<String, dynamic>?;
    if (e == null) return pack;
    final elev = MapPack._fromJson({...j, ...e, 'id': '${pack.id}-korkeus'}, country: country);
    if (!elev.isElevation) throw FormatException('korkeustiedoston nimi ei kelpaa: ${elev.file}');
    return MapPack(
      id: pack.id,
      name: pack.name,
      file: pack.file,
      region: pack.region,
      sha256: pack.sha256,
      size: pack.size,
      bbox: pack.bbox,
      shape: pack.shape,
      se: pack.se,
      sv: pack.sv,
      country: pack.country,
      oldSha256: pack.oldSha256,
      elev: elev,
    );
  }

  factory MapPack._fromJson(Map<String, dynamic> j, {String country = 'fi'}) => MapPack(
    country: country,
    id: j['id'] as String? ?? p.basenameWithoutExtension(j['file'] as String),
    name: j['name'] as String? ?? j['file'] as String,
    file: safeMapFile(j['file'] as String),
    region: j['region'] as String? ?? '',
    sha256: j['sha256'] as String,
    oldSha256: [for (final h in (j['sha256Old'] as List? ?? const [])) h as String],
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

  /// Korkeustiedostojen lähde ja lisenssin vaatima ilmoitus (luettelon elevAttribution).
  final String elevSource;

  /// Korkeustiedostojen latausosoite, jos eri julkaisussa kuin kartat (GitHubissa enintään 1 000 tiedostoa
  /// julkaisua kohden); muuten [base].
  final String? elevBase;
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
    this.elevSource = elevAttribution,
    this.elevBase,
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
      elevSource: j['elevAttribution'] as String? ?? (fi ? elevAttribution : copernicusAttribution),
      elevBase: j['elevBase'] == null ? null : _safeBase(j['elevBase'] as String),
      tag: j['tag'] as String,
      osmDate: j['osmDate'] as String? ?? '',
      base: _safeBase(j['base'] as String),
      overview: pack({
        ...(j['overview'] as Map<String, dynamic>),
        'id': fi ? 'yleiskartta' : '$cc-yleiskartta',
        'name': l10n.fi('Yleiskartta'), // näytetään t():llä
      }),
      all: all == null ? null : pack({...all, 'id': fi ? 'suomi' : '$cc-koko', 'name': l10n.fi('Koko maa')}),
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

/// Miksi tiedosto jätettiin tuomatta.
enum MapSkip {
  /// Ei PMTiles-karttaa eikä karttaluetteloa (tai zip ei aukea).
  notMap,

  /// Karttaluettelo ei kelpaa.
  badCatalog,

  /// Tiedosto on lyhyempi kuin otsake lupaa: lataus jäi kesken.
  truncated,

  /// Nimi vastaa luettelon karttaa, mutta sisältö ei: toinen karttajulkaisu tai vioittunut tiedosto.
  otherVersion,

  /// Tarkiste ei vastaa yhtään tunnettua karttaa.
  unknown,

  /// Karttaluetteloa ei ole (sovellus ei ole vielä hakenut sitä), joten karttaa ei voi tarkistaa.
  noCatalog,

  /// Samanniminen tarkistettu kartta on jo asennettu: tarkistamaton ei korvaa sitä.
  verifiedExists,
}

/// Mitä tehdään kartoille, joiden tarkiste ei vastaa mitään tunnettua.
enum UnverifiedChoice { checkOnline, importAnyway, skip }

enum MapImportPhase { unpacking, verifying, checkingOnline, installing }

/// Tuonnin edistyminen: käsiteltävä tiedosto ja tarkistetut tavut kaikista tuotavista kartoista.
class MapImportProgress {
  final String name;
  final int done, total;
  final MapImportPhase phase;
  const MapImportProgress(this.name, this.done, this.total, this.phase);
  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

/// Tuonnin tulos: asennetut tiedostot (luettelon nimillä) ja ohitetut syineen.
class MapImportResult {
  final imported = <String>[];

  /// Tuotu ilman tarkistusta (myös [imported]-listassa).
  final unverified = <String>[];

  /// Tuodusta tarkistetaulukosta luetut tarkisteet.
  int checksums = 0;
  final skipped = <(String, MapSkip)>[];
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
    _remember(c);
    // Suomi ensin, muut aakkosjärjestyksessä maakoodin mukaan.
    final sorted = catalogs.values.toList()
      ..sort((a, b) => a.country == 'fi' ? -1 : (b.country == 'fi' ? 1 : a.country.compareTo(b.country)));
    catalogs
      ..clear()
      ..addEntries([for (final x in sorted) MapEntry(x.country, x)]);
  }

  /// Kaikkien maiden kaikki tiedostot (yleiskartat, koko maa, paketit).
  Iterable<MapPack> get allPacks =>
      catalogs.values.expand((c) => [c.overview, ?c.all, ...c.packs, for (final x in c.packs) ?x.elev]);

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

  /// Odotus ennen uutta yritystä, kun palvelin vastaa 5xx (testeissä lyhyempi).
  @visibleForTesting
  Duration retryDelay = const Duration(seconds: 2);

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
    if (_known.isEmpty) await _loadKnown();
    await _scan();
    await _loadUnverified();
    notifyListeners(); // tallennetut luettelot näkyvät heti, verkosta haku jatkuu taustalla
    String? err;
    if (network && (refresh || catalogs.isEmpty)) {
      final client = clientOverride ?? http.Client();
      // GitHubin tiedostopalvelin vastaa välillä 502/503/504 (tai aikakatkaisu): yritetään uudelleen.
      Future<String> get(String url) async {
        for (var attempt = 0; ; attempt++) {
          try {
            final r = await client.get(Uri.parse(safeMapUrl(url))).timeout(const Duration(seconds: 15));
            if (r.statusCode == 200) return utf8.decode(r.bodyBytes);
            if (r.statusCode < 500 || attempt >= 2) throw HttpException('HTTP ${r.statusCode}');
          } on TimeoutException {
            if (attempt >= 2) rethrow;
          }
          await Future<void>.delayed(retryDelay * (attempt + 1));
        }
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

  Future<void>? _scanning;

  /// Lukee ladatut tiedostot kansiosta. Samanaikaiset kutsut odottavat samaa lukua, ja lista vaihdetaan kerralla:
  /// muuten esim. kartta ja korkeusprofiili voisivat nähdä sen hetken tyhjänä.
  Future<void> _scan() => _scanning ??= _scanNow().whenComplete(() => _scanning = null);

  Future<void> _scanNow() async {
    final d = await dir();
    final found = <String>{};
    await for (final e in d.list()) {
      if (e is! File) continue;
      if (e.path.endsWith('.pmtiles') || isElevFile(e.path)) found.add(p.basename(e.path));
      // Keskeneräinen lataus (sovellus suljettiin kesken): poistetaan, ettei vie tilaa.
      if (e.path.endsWith('.part') && downloads.isEmpty) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
    installed
      ..clear()
      ..addAll(found);
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
      if (e is File && (e.path.endsWith('.pmtiles') || isElevFile(e.path))) n += await e.length();
    }
    return n;
  }

  /// Lataa paketit (yleiskartta mukaan, jos puuttuu). Tarkistaa SHA-256:n; keskeneräinen tiedosto ei jää.
  /// [replace]: ladataan myös jo asennetut (päivitys); vanha kartta pysyy käytössä, kunnes uusi on tarkistettu.
  /// Palauttaa epäonnistuneet lataukset (tyhjä = kaikki onnistui). Latauslista tyhjenee aina lopuksi.
  Future<List<MapDownload>> download(List<MapPack> packs, {bool replace = false}) async {
    if (catalogs.isEmpty || downloads.isNotEmpty) return const [];
    // Jokaisen maan yleiskartta mukaan, jos sitä (tai koko maata) ei vielä ole.
    // (Pelkät korkeustiedot eivät tuo yleiskarttaa.)
    final maps = packs.where((x) => !x.isElevation);
    final countries = packs.isEmpty ? {country} : {for (final x in maps) x.country};
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
          final c = catalogs[x.country]!;
          await _fetch(client, x.isElevation ? (c.elevBase ?? c.base) : c.base, x, dl);
          dl.done = true;
          installed.add(x.file);
          await _setVersion(x.file, x.sha256);
          unverified.remove(x.file);
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
    http.StreamedResponse res;
    for (var attempt = 0; ; attempt++) {
      res = await client.send(http.Request('GET', Uri.parse('$base${x.file}'))).timeout(_stall);
      if (res.statusCode == 200) break;
      await res.stream.drain<void>().catchError((_) {});
      // GitHubin tiedostopalvelimen satunnainen 5xx: uusi yritys.
      if (res.statusCode < 500 || attempt >= 2 || _cancel) throw HttpException('HTTP ${res.statusCode}');
      await Future<void>.delayed(retryDelay * (attempt + 1));
    }
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
      _grids.remove(x.file);
      await _open.remove(x.file)?.close(); // päivitys: vanha tiedosto suljetaan ennen korvaamista
      await part.rename(p.join(d.path, x.file));
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// Tuo kartat tiedostoista (ilman verkkoa, esim. Seafilesta, kotisivulta tai toiselta laitteelta): .zip, jossa
  /// karttoja (.pmtiles) ja luetteloita (kartat.json, `<maa>.json`), tai yksittäisiä .pmtiles- ja luettelotiedostoja.
  ///
  /// Kartta tunnistetaan sisällöstä, ei tiedostonimestä: SHA-256-tarkisteen pitää vastata jonkin luettelon kartan
  /// nykyistä tai aiempaa versiota (myös laitteen muistamia tarkisteita), ja kartta tallennetaan luettelon nimellä
  /// (esim. selaimen nimeämä `es-yleiskartta(1).pmtiles` → `es-yleiskartta.pmtiles`). Yksittäistä tiedostoa ei
  /// kopioida ennen tarkistusta: tarkiste lasketaan paikallaan ([onProgress] kertoo edistymisen).
  ///
  /// Tunnistamaton mutta ehjä kartta: [onUnverified] kysyy käyttäjältä (hae tarkisteet verkosta / tuo ilman
  /// tarkistusta / ohita). Ilman tarkistusta tuotu kartta merkitään tarkistamattomaksi ([unverified]), eikä se
  /// koskaan korvaa tarkistettua karttaa. Ei-kartta tai vajaa tiedosto ohitetaan aina.
  Future<MapImportResult> importFiles(
    List<String> paths, {
    void Function(MapImportProgress)? onProgress,
    Future<UnverifiedChoice> Function(List<String> names, {required bool checkedOnline})? onUnverified,
  }) async {
    final d = await dir();
    final tmp = Directory(p.join(d.path, 'tuonti'));
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create();
    final result = MapImportResult();
    final maps = <(String, File, bool)>[]; // (alkuperäinen nimi, tiedosto, saa siirtää)
    final catalogFiles = <(String, File)>[];
    final movable = await _movableRoots();
    var k = 0;
    bool isJson(String name) => name.toLowerCase().endsWith('.json');
    bool isMap(String name) => name.toLowerCase().endsWith('.pmtiles') || isElevFile(name.toLowerCase());
    bool wanted(String name) => isMap(name) || isJson(name);
    try {
      for (final path in paths) {
        final name = p.basename(path);
        final lower = name.toLowerCase();
        if (lower.endsWith('.zip')) {
          onProgress?.call(MapImportProgress(name, 0, 0, MapImportPhase.unpacking));
          final input = InputFileStream(path);
          try {
            final zip = ZipDecoder().decodeStream(input);
            for (final f in zip.files) {
              final n = p.basename(f.name);
              if (!f.isFile || !wanted(n)) continue;
              final ext = isMap(n) ? p.extension(n).toLowerCase() : '.json';
              final out = p.join(tmp.path, '${k++}$ext');
              final os = OutputFileStream(out);
              f.writeContent(os);
              await os.close();
              if (isMap(n)) {
                maps.add((n, File(out), true));
              } else {
                catalogFiles.add((n, File(out)));
              }
            }
          } catch (_) {
            result.skipped.add((name, MapSkip.notMap));
          } finally {
            await input.close();
          }
        } else if (isMap(lower)) {
          maps.add((name, File(path), movable.any((r) => p.isWithin(r, path))));
        } else if (isJson(name)) {
          catalogFiles.add((name, File(path)));
        } else {
          result.skipped.add((name, MapSkip.notMap));
        }
      }
      // Luettelot ensin: niillä kartat tunnistetaan.
      for (final (name, f) in catalogFiles) {
        try {
          final text = await f.readAsString();
          final j = jsonDecode(text) as Map<String, dynamic>;
          if (j['format'] == checksumTableFormat) {
            result.checksums += await _addChecksumTable(j);
            continue;
          }
          final c = MapCatalog.fromJson(j);
          _add(c);
          country = c.country;
          await File(p.join(d.path, c.cacheName)).writeAsString(text);
        } catch (_) {
          result.skipped.add((name, MapSkip.badCatalog));
        }
      }
      // Kartat: rakenne (nopea) ja tarkiste (koko tiedosto, edistyminen).
      final ok = <(String, File, bool, int)>[];
      for (final (name, f, mv) in maps) {
        try {
          final len = await f.length();
          final bool complete;
          if (isElevFile(f.path.toLowerCase())) {
            final raf = await f.open();
            final head = await raf.read(ElevHeader.readLength);
            await raf.close();
            complete = len >= ElevHeader.parse(head).requiredLength; // heittää, jos ei korkeustiedosto
          } else {
            final pm = await PmTilesFile.open(f.path); // heittää, jos ei PMTiles v3
            complete = len >= pm.requiredLength;
            await pm.close();
          }
          if (!complete) {
            result.skipped.add((name, MapSkip.truncated));
            continue;
          }
          ok.add((name, f, mv, len));
        } catch (_) {
          result.skipped.add((name, MapSkip.notMap));
        }
      }
      final total = ok.fold<int>(0, (a, e) => a + e.$4);
      var before = 0;
      final hashed = <(String, File, bool, String)>[];
      for (final (name, f, mv, len) in ok) {
        final base = before;
        onProgress?.call(MapImportProgress(name, base, total, MapImportPhase.verifying));
        final digest = await sha256OfFile(
          f.path,
          onProgress: (b) => onProgress?.call(MapImportProgress(name, base + b, total, MapImportPhase.verifying)),
        );
        before += len;
        hashed.add((name, f, mv, digest));
      }

      Future<void> install(String name, File f, bool mv, String file, String digest, {required bool verified}) async {
        onProgress?.call(MapImportProgress(name, total, total, MapImportPhase.installing));
        await _open.remove(file)?.close();
        _grids.remove(file);
        final dest = p.join(d.path, file);
        if (mv) {
          try {
            await f.rename(dest);
          } on FileSystemException {
            await _copyInto(f, dest);
          }
        } else {
          await _copyInto(f, dest);
        }
        installed.add(file);
        await _setVersion(file, verified ? digest : '?$digest');
        if (!result.imported.contains(file)) result.imported.add(file);
      }

      var pending = hashed;
      var checkedOnline = false;
      while (pending.isNotEmpty) {
        final bySha = knownShas();
        final unknown = <(String, File, bool, String)>[];
        for (final e in pending) {
          final file = bySha[e.$4];
          if (file == null) {
            unknown.add(e);
          } else {
            await install(e.$1, e.$2, e.$3, file, e.$4, verified: true);
          }
        }
        pending = unknown;
        if (pending.isEmpty) break;
        final choice = onUnverified == null
            ? UnverifiedChoice.skip
            : await onUnverified([for (final e in pending) e.$1], checkedOnline: checkedOnline);
        if (choice == UnverifiedChoice.checkOnline && !checkedOnline) {
          onProgress?.call(MapImportProgress('', total, total, MapImportPhase.checkingOnline));
          checkedOnline = true;
          await load(refresh: true); // virhe (ei verkkoa) ei haittaa: kysytään uudelleen
          await fetchGithubDigests(); // GitHubin omat tarkisteet kaikista karttajulkaisuista (myös vanhoista)
          continue;
        }
        final verifiedFiles = {
          for (final e in (await _versions()).entries)
            if (!e.value.startsWith('?')) e.key,
        };
        for (final (name, f, mv, digest) in pending) {
          final file = safeImportName(name);
          if (choice != UnverifiedChoice.importAnyway || file == null) {
            result.skipped.add((name, _whyUnknown(name)));
          } else if (verifiedFiles.contains(file) && installed.contains(file)) {
            result.skipped.add((name, MapSkip.verifiedExists));
          } else {
            await install(name, f, mv, file, digest, verified: false);
            result.unverified.add(file);
          }
        }
        break;
      }
      // Tiedostonvalitsimen välimuistiin jääneet kopiot (ohitetut tai jo asennetut) pois: ne vievät tilaa.
      for (final (_, f, mv) in maps) {
        if (mv && await f.exists()) await f.delete().catchError((_) => f);
      }
      await _loadUnverified();
      notifyListeners();
      return result;
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  MapSkip _whyUnknown(String name) {
    if (catalogs.isEmpty && _known.isEmpty) return MapSkip.noCatalog;
    final file = normalizedMapName(name);
    return allPacks.any((x) => x.file == file) || _known.containsValue(file) ? MapSkip.otherVersion : MapSkip.unknown;
  }

  /// Kopio ensin .part-tiedostoon ja sitten paikalleen: keskeytynyt kopio ei jää kartaksi.
  static Future<void> _copyInto(File src, String dest) async {
    final part = '$dest.part';
    await src.copy(part);
    await File(part).rename(dest);
  }

  /// Kansiot, joista tuotavan tiedoston saa siirtää (ei kopioida): tiedostonvalitsimen välimuisti ja tuontikansio.
  Future<List<String>> _movableRoots() async {
    final roots = [p.join((await dir()).path, 'tuonti')];
    try {
      roots.add((await getTemporaryDirectory()).path);
    } catch (_) {}
    return roots;
  }

  /// Tunnetut tarkisteet → tiedostonimi: luetteloiden nykyiset ja aiemmat versiot sekä laitteen muistamat
  /// (tunnetut.json: kaikki tarkisteet, jotka sovellus on joskus nähnyt luettelossa).
  Map<String, String> knownShas() => {
    ..._known,
    for (final x in allPacks) ...{for (final h in x.oldSha256) h: x.file},
    for (final x in allPacks) x.sha256: x.file,
  };

  final _known = <String, String>{};

  /// Testejä varten: unohda muistetut tarkisteet.
  @visibleForTesting
  void forgetKnown() => _known.clear();

  Future<File> _knownFile() async => File(p.join((await dir()).path, 'tunnetut.json'));

  Future<void> _loadKnown() async {
    try {
      final f = await _knownFile();
      if (await f.exists()) {
        _known.addAll(Map<String, String>.from(jsonDecode(await f.readAsString()) as Map));
      }
    } catch (_) {}
  }

  /// Muistaa luettelon kaikki tarkisteet: vanhempikin tiedosto tunnistetaan, vaikka luettelo päivittyy.
  Future<void> _remember(MapCatalog c) async {
    var changed = false;
    for (final x in [c.overview, ?c.all, ...c.packs]) {
      for (final h in [x.sha256, ...x.oldSha256]) {
        if (_known[h] != x.file) {
          _known[h] = x.file;
          changed = true;
        }
      }
    }
    if (!changed) return;
    try {
      await (await _knownFile()).writeAsString(jsonEncode(_known));
    } catch (_) {}
  }

  /// Hakee GitHubin API:sta kaikkien karttajulkaisujen (tagi alkaa `kartat`) .pmtiles-tiedostojen tarkisteet ja
  /// lisää ne muistettuihin ([knownShas]). Yksi pyyntö (100 julkaisua); ilman kirjautumista GitHub sallii 60 pyyntöä
  /// tunnissa, joten tätä kutsutaan vain käyttäjän pyynnöstä. Palauttaa löydettyjen tarkisteiden määrän (0 virheellä).
  Future<int> fetchGithubDigests({int maxPages = 5}) async {
    final client = clientOverride ?? http.Client();
    final name = RegExp(r'^[a-z0-9-]+\.(pmtiles|elev)$'), hex = RegExp(r'^sha256:([0-9a-f]{64})$');
    var n = 0, changed = false;
    try {
      // Sivu kerrallaan (100 julkaisua sivulla): vanhimmat karttajulkaisut ovat viimeisillä sivuilla.
      for (var page = 1; page <= maxPages; page++) {
        http.Response? r;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            r = await client
                .get(
                  Uri.parse(safeMapUrl('$mapReleasesApi&page=$page')),
                  headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Gievra'},
                )
                .timeout(const Duration(seconds: 20));
            if (r.statusCode < 500) break;
          } on TimeoutException {
            r = null;
          }
          await Future<void>.delayed(retryDelay * (attempt + 1));
        }
        if (r == null || r.statusCode != 200) break;
        final releases = jsonDecode(utf8.decode(r.bodyBytes)) as List;
        for (final rel in releases) {
          if (rel is! Map) continue;
          final tag = '${rel['tag_name']}';
          if (!tag.startsWith('kartat') && !tag.startsWith('korkeus')) continue;
          for (final a in (rel['assets'] as List? ?? const [])) {
            if (a is! Map) continue;
            final file = '${a['name']}';
            final m = hex.firstMatch('${a['digest']}');
            if (m == null || !name.hasMatch(file)) continue;
            n++;
            if (_known[m[1]!] != file) {
              _known[m[1]!] = file;
              changed = true;
            }
          }
        }
        if (releases.length < 100) break;
      }
    } catch (_) {
      // verkko- tai muotovirhe: käytetään sitä, mitä saatiin
    } finally {
      if (clientOverride == null) client.close();
    }
    if (changed) {
      try {
        await (await _knownFile()).writeAsString(jsonEncode(_known));
      } catch (_) {}
    }
    return n;
  }

  /// Kotisivun tarkistetaulukko (kartat-tarkisteet.json): kaikkien karttajulkaisujen tarkisteet. Tuotuna kartat
  /// tarkistetaan ilman verkkoa; tarkisteet muistetaan. Palauttaa hyväksyttyjen rivien määrän.
  Future<int> _addChecksumTable(Map<String, dynamic> j) async {
    final name = RegExp(r'^[a-z0-9-]+\.(pmtiles|elev)$'), hex = RegExp(r'^[0-9a-f]{64}$');
    var n = 0, changed = false;
    for (final e in (j['files'] as List? ?? const [])) {
      if (e is! List || e.length < 2) continue;
      final file = '${e[0]}', sha = '${e[1]}';
      if (!name.hasMatch(file) || !hex.hasMatch(sha)) continue;
      n++;
      if (_known[sha] != file) {
        _known[sha] = file;
        changed = true;
      }
    }
    if (changed) await (await _knownFile()).writeAsString(jsonEncode(_known));
    return n;
  }

  /// Ilman tarkistusta tuodut kartat (tiedostonimet).
  final unverified = <String>{};

  Future<void> _loadUnverified() async {
    unverified
      ..clear()
      ..addAll([
        for (final e in (await _versions()).entries)
          if (e.value.startsWith('?')) e.key,
      ]);
  }

  /// Tiedostonimi ilman tarkistusta tuodulle kartalle: luettelon muoto, vain a–z, 0–9 ja viiva. null = ei kelpaa.
  static String? safeImportName(String name) {
    var n = normalizedMapName(name);
    final ext = n.endsWith('.pmtiles') ? '.pmtiles' : (n.endsWith('.elev') ? '.elev' : null);
    if (ext == null) return null;
    var stem = n.substring(0, n.length - ext.length);
    stem = stem
        .replaceAll(RegExp('[åäá]'), 'a')
        .replaceAll(RegExp('[öøó]'), 'o')
        .replaceAll(RegExp('[^a-z0-9-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (stem.isEmpty || stem.length > 80) return null;
    return '$stem$ext';
  }

  /// Selaimen tai käyttäjän muuttama nimi luettelon muotoon: `Es-Yleiskartta (1).pmtiles` → `es-yleiskartta.pmtiles`.
  static String normalizedMapName(String name) =>
      name.toLowerCase().replaceFirst(RegExp(r'\s*[(\[]\d+[)\]](?=\.(pmtiles|elev)$)'), '');

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
    for (final f in [...installed]) {
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
    _grids.remove(file);
    final f = File(p.join((await dir()).path, file));
    if (await f.exists()) await f.delete();
    installed.remove(file);
    unverified.remove(file);
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

  /// Tiet ja polut reitin ympäriltä ladatuista kartoista (tarkin zoomitaso, roads-kerros) reitin korjaukseen
  /// poluille ([snapRoute]). Tyhjä, jos alueen karttoja ei ole ladattu.
  Future<List<SnapWay>> waysAround(List<List<TrackPoint>> segments, {double marginM = 30}) async {
    final files = [
      for (final f in await openFiles())
        if (f.maxZoom >= 14) f,
    ];
    if (files.isEmpty) return const [];
    final z = files.map((f) => f.maxZoom).reduce(math.max), n = 1 << z;
    final tiles = <(int, int)>{};
    for (final s in segments) {
      for (final pt in s) {
        final dLat = marginM / 110574, dLon = marginM / (111320 * math.cos(pt.lat * math.pi / 180));
        final (x0, y0) = _tileOf(pt.lat + dLat, pt.lon - dLon, n);
        final (x1, y1) = _tileOf(pt.lat - dLat, pt.lon + dLon, n);
        for (var x = x0; x <= x1; x++) {
          for (var y = y0; y <= y1; y++) {
            tiles.add((x, y));
          }
        }
      }
    }
    if (tiles.length > 400) return const []; // hyvin pitkä reitti: ei korjata (muisti ja aika)
    final ways = <SnapWay>[];
    for (final (x, y) in tiles) {
      for (final f in files) {
        if (f.maxZoom != z) continue;
        final bytes = await f.tile(z, x, y);
        if (bytes == null) continue;
        try {
          for (final layer in VectorTile.fromBytes(bytes: bytes).layers) {
            if (layer.name != 'roads') continue;
            final ext = layer.extent.toDouble();
            for (final ft in layer.features) {
              if (ft.type != VectorTileGeomType.LINESTRING) continue;
              final props = ft.decodeProperties();
              String str(String k) => props[k]?.dartStringValue ?? '';
              for (final line in ft.decodeLineString()) {
                ways.add(
                  SnapWay(str('kind'), str('kind_detail'), [
                    for (final c in line) _tileToLatLon(x + c[0] / ext, y + c[1] / ext, n),
                  ], name: str('name')),
                );
              }
            }
          }
        } catch (_) {}
        break; // sama laatta löytyy vain yhdestä tiedostosta (tai on sama naapurikunnan tiedostossa)
      }
    }
    return ways;
  }

  static (int, int) _tileOf(double lat, double lon, int n) {
    final r = lat * math.pi / 180;
    final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
    final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor().clamp(0, n - 1);
    return (x, y);
  }

  static (double, double) _tileToLatLon(double tx, double ty, int n) {
    final lon = tx / n * 360 - 180;
    final lat =
        math.atan((math.exp(math.pi * (1 - 2 * ty / n)) - math.exp(-math.pi * (1 - 2 * ty / n))) / 2) * 180 / math.pi;
    return (lat, lon);
  }

  /// Avatut karttatiedostot karttanäkymälle: koko Suomi tai kunnat + yleiskartta.
  // Puretut korkeustiedostot (muutama kerrallaan muistissa; kunta noin 0,1–5 Mt).
  final _grids = <String, ElevationGrid>{};

  /// Reitin pisteet ja niiden välit noin 100 m:n välein (lohkot, joiden yli reitti kulkee).
  static List<(double, double)> _densify(List<List<TrackPoint>> segments) {
    final out = <(double, double)>[];
    for (final s in segments) {
      for (var i = 0; i < s.length; i++) {
        out.add((s[i].lat, s[i].lon));
        if (i == 0) continue;
        final a = s[i - 1], b = s[i];
        final dy = (b.lat - a.lat) * 111320, dx = (b.lon - a.lon) * 111320 * math.cos(a.lat * math.pi / 180);
        final steps = (math.sqrt(dx * dx + dy * dy) / 100).floor();
        for (var k = 1; k <= steps; k++) {
          final f = k / (steps + 1);
          out.add((a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f));
        }
      }
    }
    return out;
  }

  /// Korkeustiedoston lähde sen luettelosta; tuntematon tiedosto: Suomen nimet Maanmittauslaitos, muut Copernicus.
  String elevSourceOf(String file) {
    for (final c in catalogs.values) {
      if (c.packs.any((x) => x.elev?.file == file)) return c.elevSource;
    }
    return RegExp(r'^[a-z]{2}-').hasMatch(file) ? copernicusAttribution : elevAttribution;
  }

  /// Ladatut korkeustiedostot vanhassa muodossa (versio 1, koko tiedosto muistiin): päivitys suositeltava.
  Future<List<String>> oldFormatElevation() async {
    final d = await dir();
    final out = <String>[];
    for (final f in [...installed.where(isElevFile)]) {
      try {
        final raf = await File(p.join(d.path, f)).open();
        final head = await raf.read(8);
        await raf.close();
        if (String.fromCharCodes(head) == elevMagic) out.add(f);
      } catch (_) {}
    }
    return out;
  }

  /// Muistissa olevat korkeustiedostot ja niiden lohkot (muistitestit).
  @visibleForTesting
  (int, int) get elevCache => (_grids.length, _grids.values.fold(0, (a, g) => a + g.loadedBlocks));

  /// Onko ladattuja korkeustiedostoja.
  bool get hasElevation => installed.any(isElevFile);

  /// Reitin korkeusprofiili ladatuista korkeustiedoista (null = ei korkeustietoja reitin alueelta).
  Future<ElevationProfile?> profileFor(List<List<TrackPoint>> segments) async {
    final pts = [for (final s in segments) ...s];
    if (pts.isEmpty) return null;
    if (installed.isEmpty && downloads.isEmpty) await _scan(); // sovellus juuri avattu: kansiota ei vielä luettu
    if (!hasElevation) return null;
    var w = 180.0, e = -180.0, so = 90.0, n = -90.0;
    for (final t in pts) {
      w = math.min(w, t.lon);
      e = math.max(e, t.lon);
      so = math.min(so, t.lat);
      n = math.max(n, t.lat);
    }
    final d = await dir();
    final grids = <ElevationGrid>[];
    for (final f in [...installed.where(isElevFile)]) {
      try {
        var g = _grids[f];
        if (g == null) {
          final file = File(p.join(d.path, f));
          final raf = await file.open();
          final head = ElevHeader.parse(await raf.read(ElevHeader.readLength));
          await raf.close();
          if (head.west > e || head.east < w || head.south > n || head.north < so) continue;
          if (head.version == 1) {
            g = await ElevationGrid.fromBytes(await file.readAsBytes()); // vanha muoto: koko tiedosto
          } else {
            // Uusi muoto: vain otsake ja hakemisto nyt, lohkot reitin kohdalta alla.
            g = await ElevationGrid.open(head, (start, length) async {
              final r = await file.open();
              try {
                await r.setPosition(start);
                return await r.read(length);
              } finally {
                await r.close();
              }
            });
          }
          if (_grids.length >= 6) _grids.remove(_grids.keys.first);
          _grids[f] = g;
        } else {
          final h = g.header;
          if (h.west > e || h.east < w || h.south > n || h.north < so) continue;
        }
        await g.loadAround(_densify(segments));
        grids.add(g);
      } catch (e) {
        debugPrint('korkeus $f: $e');
      }
    }
    if (grids.isEmpty) return null;
    final used = <ElevationGrid>{};
    double? at(double lat, double lon) {
      for (final g in grids) {
        if (!g.header.containsPoint(lat, lon)) continue;
        final v = g.at(lat, lon);
        if (v != null) {
          used.add(g);
          return v;
        }
      }
      return null;
    }

    final prof = elevationProfile(segments, at);
    if (prof == null) return null;
    // Lähteet niistä tiedostoista, joista korkeudet tulivat (rajan yli: esim. Maanmittauslaitos ja Copernicus).
    final sources = <String>{
      for (final e in _grids.entries)
        if (used.contains(e.value)) elevSourceOf(e.key),
    };
    return prof.withAttribution(sources.join(' · '));
  }

  Future<List<PmTilesFile>> openFiles() async {
    final d = await dir();
    final out = <PmTilesFile>[];
    for (final f in [...installed]) {
      if (isElevFile(f)) continue;
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
