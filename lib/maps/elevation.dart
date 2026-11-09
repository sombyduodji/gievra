import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../gps_filter.dart';

// Korkeustiedot (.elev, tools/elev_build.py): Maanmittauslaitoksen korkeusmalli 10 m (2019) noin 25 m:n
// ruudukkona kunnittain. Korkeus maanpinnasta (ei puista eikä rakennuksista), puolen metrin tarkkuudella.
// Aineisto: © Maanmittauslaitos, Korkeusmalli 10 m (2019), CC BY 4.0.

const elevMagic = 'GVELEV1\u0000';
const elevAttribution = 'Korkeusmalli 10 m © Maanmittauslaitos 2019, CC BY 4.0';

/// Otsake ilman korkeuksia (nopea tarkistus tuonnissa: onko tiedosto kokonainen).
class ElevHeader {
  final int width, height, bodyLength;
  final double west, north, dLon, dLat;
  const ElevHeader(this.width, this.height, this.west, this.north, this.dLon, this.dLat, this.bodyLength);

  static const length = 52;
  int get requiredLength => length + bodyLength;
  double get east => west + width * dLon;
  double get south => north - height * dLat;

  bool containsPoint(double lat, double lon) => lon >= west && lon <= east && lat >= south && lat <= north;

  /// Heittää FormatExceptionin, jos tavut eivät ole .elev-otsake.
  static ElevHeader parse(Uint8List b) {
    if (b.length < length || String.fromCharCodes(b.sublist(0, 8)) != elevMagic) {
      throw const FormatException('ei korkeustiedosto');
    }
    final d = ByteData.sublistView(b, 0, length);
    final h = ElevHeader(
      d.getUint32(8, Endian.little),
      d.getUint32(12, Endian.little),
      d.getFloat64(16, Endian.little),
      d.getFloat64(24, Endian.little),
      d.getFloat64(32, Endian.little),
      d.getFloat64(40, Endian.little),
      d.getUint32(48, Endian.little),
    );
    final okSize = h.width > 0 && h.height > 0 && h.width * h.height <= 60000000;
    final okGeo = h.dLon > 0 && h.dLat > 0 && h.west >= -180 && h.east <= 180 && h.north <= 90 && h.south >= -90;
    if (!okSize || !okGeo || h.bodyLength <= 0) throw const FormatException('korkeustiedoston otsake ei kelpaa');
    return h;
  }
}

class ElevationGrid {
  final ElevHeader header;

  /// Korkeudet puolen metrin yksikköinä riveittäin pohjoisesta etelään; -32768 = ei tietoa.
  final Int16List dm;
  ElevationGrid(this.header, this.dm);

  static const noData = -32768;

  static ElevationGrid decode(Uint8List bytes) {
    final h = ElevHeader.parse(bytes);
    if (bytes.length < h.requiredLength) throw const FormatException('korkeustiedosto on vajaa');
    final raw = ZLibDecoder().decodeBytes(bytes.sublist(ElevHeader.length, h.requiredLength));
    final n = h.width * h.height;
    if (raw.length != n * 2) throw const FormatException('korkeustiedoston koko ei täsmää');
    final r = ByteData.sublistView(Uint8List.fromList(raw));
    final out = Int16List(n);
    final w = h.width;
    // Ennuste: vasen + yläpuolinen − vasen yläkulma (tools/elev_build.py encode), int16 kiertäen.
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
    return ElevationGrid(h, out);
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
      final v = dm[cy * h.width + cx];
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
  const ElevationProfile(this.points, this.climb, this.descent, this.coverage, {this.splits = const []});

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
  // Matka ja aika ilman taukoja jokaisessa reittipisteessä (kilometrien vauhti).
  final clock = <(double, double)>[];
  var dist = 0.0, moving = 0.0;
  for (final seg in segments) {
    if (seg.isEmpty) continue;
    raw.add((dist, heightAt(seg.first.lat, seg.first.lon)));
    clock.add((dist, moving));
    var carry = 0.0;
    for (var i = 1; i < seg.length; i++) {
      final a = seg[i - 1], b = seg[i];
      final d = _distM(a.lat, a.lon, b.lat, b.lon);
      final dt = b.time.difference(a.time).inMilliseconds / 1000;
      if (dt > 0) moving += dt;
      if (d <= 0) continue;
      clock.add((dist + d, moving));
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
  return ElevationProfile(smooth, climb, descent, coverage, splits: kmSplits(clock));
}

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
