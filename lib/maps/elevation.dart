import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../gps_filter.dart';
import '../l10n.dart' as l10n;

// Korkeustiedot (.elev, tools/elev_build.py): Maanmittauslaitoksen korkeusmalli 10 m (2019) noin 25 m:n
// ruudukkona kunnittain. Korkeus maanpinnasta (ei puista eikä rakennuksista), puolen metrin tarkkuudella.
// Aineisto: © Maanmittauslaitos, Korkeusmalli 10 m (2019), CC BY 4.0.

const elevMagic = 'GVELEV1\u0000';
const elevMagic2 = 'GVELEV2\u0000';
const elevAttribution = 'Korkeusmalli 10 m © Maanmittauslaitos 2019, CC BY 4.0';

/// Copernicus DEM GLO-30:n lisenssin vaatima ilmoitus muokatusta aineistosta (ei käännetä).
const copernicusAttribution =
    'produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 '
    'provided under COPERNICUS by the European Union and ESA; all rights reserved';

/// Otsake ilman korkeuksia (nopea tarkistus tuonnissa: onko tiedosto kokonainen).
/// Versio 1: koko ruudukko yhtenä zlib-pakettina. Versio 2: lohkot (B × B) ja hakemisto, joten luetaan vain
/// tarvittavat lohkot (tools/elev_build.py).
class ElevHeader {
  final int version, width, height, bodyLength, block;
  final double west, north, dLon, dLat;
  const ElevHeader(
    this.width,
    this.height,
    this.west,
    this.north,
    this.dLon,
    this.dLat,
    this.bodyLength, {
    this.version = 1,
    this.block = 0,
  });

  /// Näin monta tavua riittää otsakkeen lukuun (versio 2: 56).
  static const readLength = 56;
  int get headLength => version == 2 ? 56 : 52;
  int get requiredLength => headLength + bodyLength;
  double get east => west + width * dLon;
  double get south => north - height * dLat;
  int get blocksX => (width + block - 1) ~/ block;
  int get blocksY => (height + block - 1) ~/ block;

  bool containsPoint(double lat, double lon) => lon >= west && lon <= east && lat >= south && lat <= north;

  /// Heittää FormatExceptionin, jos tavut eivät ole .elev-otsake.
  static ElevHeader parse(Uint8List b) {
    if (b.length < 52) throw FormatException(l10n.fi('ei korkeustiedosto'));
    final magic = String.fromCharCodes(b.sublist(0, 8));
    final v2 = magic == elevMagic2;
    if (!v2 && magic != elevMagic) throw FormatException(l10n.fi('ei korkeustiedosto'));
    if (v2 && b.length < 56) throw FormatException(l10n.fi('ei korkeustiedosto'));
    final d = ByteData.sublistView(b, 0, v2 ? 56 : 52);
    final h = ElevHeader(
      d.getUint32(8, Endian.little),
      d.getUint32(12, Endian.little),
      d.getFloat64(16, Endian.little),
      d.getFloat64(24, Endian.little),
      d.getFloat64(32, Endian.little),
      d.getFloat64(40, Endian.little),
      d.getUint32(v2 ? 52 : 48, Endian.little),
      version: v2 ? 2 : 1,
      block: v2 ? d.getUint32(48, Endian.little) : 0,
    );
    // Versio 1 puretaan kokonaan muistiin: koko rajoitettu. Versio 2: vain lohkot, koko vapaa.
    final okSize = h.width > 0 && h.height > 0 && (v2 || h.width * h.height <= 60000000);
    final okBlock = !v2 || (h.block >= 16 && h.block <= 4096 && h.blocksX * h.blocksY <= 4000000);
    final okGeo = h.dLon > 0 && h.dLat > 0 && h.west >= -180 && h.east <= 180.01 && h.north <= 90 && h.south >= -90;
    if (!okSize || !okBlock || !okGeo || h.bodyLength <= 0) {
      throw FormatException(l10n.fi('korkeustiedoston otsake ei kelpaa'));
    }
    return h;
  }
}

/// Ennustevirheistä korkeudet (tools/elev_build.py encode): vasen + yläpuolinen − vasen yläkulma, int16 kiertäen.
Int16List _unpredict(List<int> raw, int w, int h) {
  final n = w * h;
  if (raw.length != n * 2) throw FormatException(l10n.fi('korkeustiedoston koko ei täsmää'));
  final r = ByteData.sublistView(Uint8List.fromList(raw));
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    final row = i ~/ w, col = i - row * w;
    final int pred;
    if (row == 0) {
      pred = col == 0 ? 0 : out[i - 1];
    } else if (col == 0) {
      pred = out[i - w];
    } else {
      pred = out[i - 1] + out[i - w] - out[i - w - 1];
    }
    out[i] = (pred + r.getInt16(i * 2, Endian.little)).toSigned(16);
  }
  return out;
}

/// Lukee tavuja tiedostosta (tai muistista testeissä): (alku, pituus).
typedef ElevReader = Future<Uint8List> Function(int start, int length);

class ElevationGrid {
  final ElevHeader header;

  /// Versio 1: koko ruudukko (puolen metrin yksikköinä riveittäin pohjoisesta etelään; -32768 = ei tietoa).
  final Int16List? dm;

  /// Versio 2: luetut lohkot (tunniste = rivi · lohkoja vaakaan + sarake) ja hakemisto.
  final _blocks = <int, Int16List>{};
  final Uint32List? _index;
  final ElevReader? _read;
  ElevationGrid(this.header, this.dm) : _index = null, _read = null;
  ElevationGrid._lazy(this.header, this._index, this._read) : dm = null;

  static const noData = -32768;

  /// Koko tiedosto muistista (testit, pienet tiedostot): versio 1 tai 2 (kaikki lohkot).
  static Future<ElevationGrid> fromBytes(Uint8List bytes) async {
    final h = ElevHeader.parse(bytes);
    if (bytes.length < h.requiredLength) throw FormatException(l10n.fi('korkeustiedosto on vajaa'));
    if (h.version == 1) {
      final raw = ZLibDecoder().decodeBytes(bytes.sublist(h.headLength, h.requiredLength));
      return ElevationGrid(h, _unpredict(raw, h.width, h.height));
    }
    final g = await open(h, (s, n) async => Uint8List.sublistView(bytes, s, s + n));
    await g.loadAll();
    return g;
  }

  /// Versio 2 tiedostosta: luetaan otsake ja hakemisto; lohkot vasta [loadAround]-kutsulla.
  static Future<ElevationGrid> open(ElevHeader h, ElevReader read) async {
    if (h.version != 2) throw FormatException(l10n.fi('vain versio 2 luetaan lohkoittain'));
    final nb = h.blocksX * h.blocksY;
    final idx = await read(h.headLength, (nb + 1) * 4);
    if (idx.length != (nb + 1) * 4) throw FormatException(l10n.fi('korkeustiedosto on vajaa'));
    final index = Uint32List(nb + 1);
    final bd = ByteData.sublistView(idx);
    for (var i = 0; i <= nb; i++) {
      index[i] = bd.getUint32(i * 4, Endian.little);
    }
    for (var i = 1; i <= nb; i++) {
      if (index[i] < index[i - 1]) throw FormatException(l10n.fi('korkeustiedoston hakemisto ei kelpaa'));
    }
    if (h.headLength + (nb + 1) * 4 + index[nb] > h.requiredLength) {
      throw FormatException(l10n.fi('korkeustiedoston hakemisto ei kelpaa'));
    }
    return ElevationGrid._lazy(h, index, read);
  }

  /// Enintään näin monta lohkoa muistissa yhtä tiedostoa kohden (lohko 128 kt → noin 4 Mt). Vanhimmat käyttämättömät
  /// poistetaan; nykyisen reitin lohkot jäävät aina, joten pitkäkin lenkki saa kaikki korkeutensa.
  static const maxBlocks = 32;

  Future<void> _load(int id) async {
    final have = _blocks.remove(id);
    if (have != null) {
      _blocks[id] = have; // viimeksi käytetty loppuun (LinkedHashMap: järjestys = käyttöjärjestys)
      return;
    }
    final h = header, index = _index!;
    final dataStart = h.headLength + index.length * 4;
    final bytes = await _read!(dataStart + index[id], index[id + 1] - index[id]);
    final bx = id % h.blocksX, by = id ~/ h.blocksX;
    final w = math.min(h.block, h.width - bx * h.block), hh = math.min(h.block, h.height - by * h.block);
    _blocks[id] = _unpredict(ZLibDecoder().decodeBytes(bytes), w, hh);
  }

  Future<void> loadAll() async {
    if (dm != null) return;
    for (var i = 0; i < header.blocksX * header.blocksY; i++) {
      await _load(i);
    }
  }

  /// Lataa lohkot, joita pisteiden korkeudet tarvitsevat (pisteen ruutu ja sen naapurit).
  Future<void> loadAround(Iterable<(double, double)> latLons) async {
    if (dm != null) return;
    final h = header, need = <int>{};
    for (final (lat, lon) in latLons) {
      final x = ((lon - h.west) / h.dLon - 0.5).floor(), y = ((h.north - lat) / h.dLat - 0.5).floor();
      for (final cy in [y, y + 1]) {
        for (final cx in [x, x + 1]) {
          if (cx < 0 || cy < 0 || cx >= h.width || cy >= h.height) continue;
          need.add((cy ~/ h.block) * h.blocksX + cx ~/ h.block);
        }
      }
    }
    for (final id in need) {
      await _load(id);
    }
    // Muistin raja: vanhimmat lohkot pois, ei kuitenkaan tämän reitin tarvitsemia.
    if (_blocks.length > maxBlocks) {
      for (final id in [..._blocks.keys]) {
        if (_blocks.length <= maxBlocks) break;
        if (!need.contains(id)) _blocks.remove(id);
      }
    }
  }

  /// Ladattuja lohkoja (muistin käyttö: lohko 256 × 256 = 128 kt).
  int get loadedBlocks => _blocks.length;

  int _val(int cx, int cy) {
    final d = dm;
    if (d != null) return d[cy * header.width + cx];
    final h = header, b = h.block;
    final blk = _blocks[(cy ~/ b) * h.blocksX + cx ~/ b];
    if (blk == null) return noData; // ei ladattu: kuin ei tietoa
    final bw = math.min(b, h.width - (cx ~/ b) * b);
    return blk[(cy % b) * bw + cx % b];
  }

  /// Korkeus metreinä (bilineaarinen; null = alueen ulkopuolella tai ei tietoa).
  double? at(double lat, double lon) {
    final h = header;
    // Ruutujen keskipisteet: sarake c kattaa [west + c·dLon, west + (c+1)·dLon).
    final x = (lon - h.west) / h.dLon - 0.5, y = (h.north - lat) / h.dLat - 0.5;
    if (x < -0.5 || y < -0.5 || x > h.width - 0.5 || y > h.height - 0.5) return null;
    final x0 = x.floor().clamp(0, h.width - 1), y0 = y.floor().clamp(0, h.height - 1);
    final x1 = math.min(x0 + 1, h.width - 1), y1 = math.min(y0 + 1, h.height - 1);
    final fx = (x - x0).clamp(0.0, 1.0), fy = (y - y0).clamp(0.0, 1.0);
    var sum = 0.0, wsum = 0.0;
    void add(int cx, int cy, double w) {
      final v = _val(cx, cy);
      if (v == noData || w <= 0) return;
      sum += v * w;
      wsum += w;
    }

    add(x0, y0, (1 - fx) * (1 - fy));
    add(x1, y0, fx * (1 - fy));
    add(x0, y1, (1 - fx) * fy);
    add(x1, y1, fx * fy);
    if (wsum < 0.25) return null; // enimmäkseen ei tietoa
    return sum / wsum / 2;
  }
}

/// Reitin korkeusprofiili: (matka metreinä, korkeus metreinä) noin [step] metrin välein, nousu ja lasku.
class ElevationProfile {
  final List<(double, double)> points;
  final double climb, descent;

  /// Osuus reitistä, jolle korkeus löytyi (0–1).
  final double coverage;

  /// Kilometrit: (alku metreinä, pituus metreinä, aika sekunteina ilman taukoja); viimeinen voi olla vajaa.
  final List<(double, double, double)> splits;

  /// Korkeusaineiston lähde ja lisenssin vaatima ilmoitus (esim. Maanmittauslaitos tai Copernicus).
  final String attribution;
  const ElevationProfile(
    this.points,
    this.climb,
    this.descent,
    this.coverage, {
    this.splits = const [],
    this.attribution = elevAttribution,
  });

  ElevationProfile withAttribution(String a) =>
      ElevationProfile(points, climb, descent, coverage, splits: splits, attribution: a);

  double get minM => points.map((e) => e.$2).reduce(math.min);
  double get maxM => points.map((e) => e.$2).reduce(math.max);
}

double _distM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180, dLon = (lon2 - lon1) * math.pi / 180;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a.toDouble()));
}

/// Korkeusprofiili reitille [segments]: pisteet [step] metrin välein (osuuksien väliset tauot ohitetaan), korkeus
/// [heightAt]-funktiosta, tasoitus noin 50 m liukuvalla keskiarvolla ja nousu/lasku hystereesillä [threshold] m
/// (ruudukon pieni kohina ei kerry nousuksi). null = korkeutta ei löytynyt riittävästi (alle 80 % reitistä).
ElevationProfile? elevationProfile(
  List<List<TrackPoint>> segments,
  double? Function(double lat, double lon) heightAt, {
  double step = 10,
  double threshold = 2,
}) {
  final raw = <(double, double?)>[];
  var dist = 0.0;
  for (final seg in segments) {
    if (seg.isEmpty) continue;
    raw.add((dist, heightAt(seg.first.lat, seg.first.lon)));
    var carry = 0.0;
    for (var i = 1; i < seg.length; i++) {
      final a = seg[i - 1], b = seg[i];
      final d = _distM(a.lat, a.lon, b.lat, b.lon);
      if (d <= 0) continue;
      var t = step - carry;
      while (t <= d) {
        final f = t / d;
        raw.add((dist + t, heightAt(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f)));
        t += step;
      }
      carry = d - (t - step);
      dist += d;
    }
  }
  if (raw.length < 2) return null;
  final known = raw.where((e) => e.$2 != null).length;
  final coverage = known / raw.length;
  if (coverage < 0.8) return null;
  final pts = [
    for (final (d, h) in raw)
      if (h != null) (d, h),
  ];
  // Tasoitus: ±2 näytettä (noin 50 m).
  final smooth = <(double, double)>[];
  for (var i = 0; i < pts.length; i++) {
    var s = 0.0, n = 0;
    for (var j = math.max(0, i - 2); j <= math.min(pts.length - 1, i + 2); j++) {
      s += pts[j].$2;
      n++;
    }
    smooth.add((pts[i].$1, s / n));
  }
  var climb = 0.0, descent = 0.0, anchor = smooth.first.$2;
  for (final (_, h) in smooth) {
    if (h - anchor >= threshold) {
      climb += h - anchor;
      anchor = h;
    } else if (anchor - h >= threshold) {
      descent += anchor - h;
      anchor = h;
    }
  }
  return ElevationProfile(smooth, climb, descent, coverage, splits: kmSplits(routeClock(segments)));
}

/// Reitin (matka, aika ilman taukoja) -parit jokaisessa reittipisteessä; osuuksien väliset tauot ohitetaan.
List<(double, double)> routeClock(List<List<TrackPoint>> segments) {
  final clock = <(double, double)>[];
  var dist = 0.0, moving = 0.0;
  for (final seg in segments) {
    if (seg.isEmpty) continue;
    clock.add((dist, moving));
    for (var i = 1; i < seg.length; i++) {
      final a = seg[i - 1], b = seg[i];
      final dt = b.time.difference(a.time).inMilliseconds / 1000;
      if (dt > 0) moving += dt;
      final d = _distM(a.lat, a.lon, b.lat, b.lon);
      if (d <= 0) continue;
      dist += d;
      clock.add((dist, moving));
    }
  }
  return clock;
}

/// Kilometrien vauhti suoraan reitistä (ilman korkeustietoja).
List<(double, double, double)> routeKmSplits(List<List<TrackPoint>> segments) => kmSplits(routeClock(segments));

/// Kilometrien ajat (matka, aika) -pareista: aika kilometrin rajalla lineaarisesti. Viimeinen vajaa kilometri
/// mukaan, jos se on vähintään 100 m.
List<(double, double, double)> kmSplits(List<(double, double)> clock) {
  if (clock.length < 2) return const [];
  final total = clock.last.$1;
  double timeAt(double d) {
    for (var i = 1; i < clock.length; i++) {
      final (d0, t0) = clock[i - 1];
      final (d1, t1) = clock[i];
      if (d <= d1) return d1 == d0 ? t1 : t0 + (t1 - t0) * (d - d0) / (d1 - d0);
    }
    return clock.last.$2;
  }

  final out = <(double, double, double)>[];
  for (var start = 0.0; start < total; start += 1000) {
    final end = math.min(start + 1000, total);
    if (end - start < 100) break;
    out.add((start, end - start, timeAt(end) - timeAt(start)));
  }
  return out;
}
