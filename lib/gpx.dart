import 'gps_filter.dart';

// Reitti GPX 1.1 -tiedostona treenin .md-tiedoston vieressä (sama nimi, pääte .gpx). Avautuu myös Garminin,
// Stravan, OsmAndin ym. ohjelmissa. Vain suodatetut pisteet ja ajat; ei laitetunnisteita.
//
// Polulle korjatussa reitissä pääraita (trkseg) on korjattu reitti, jonka muut ohjelmat näyttävät. Alkuperäiset
// GPS-pisteet ja GPS:n mittaama matka ovat raidan <extensions>-osassa (gievra:raw), jota muut ohjelmat eivät lue:
// korjauksen voi muuttaa tai poistaa myöhemmin. Vanhat Gievran versiot lukevat vain pääraidan.

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _iso(DateTime t) => '${t.toUtc().toIso8601String().split('.').first}Z';

const gievraGpxNs = 'https://sombyduodji.github.io/gievra/gpx/1';

String routeToGpx(
  List<List<TrackPoint>> segments, {
  required String name,
  String? type,
  String? desc,
  List<List<TrackPoint>>? raw,
  double? rawDistance,
}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<gpx version="1.1" creator="Gievra" xmlns="http://www.topografix.com/GPX/1/1" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      '${raw != null ? 'xmlns:gievra="$gievraGpxNs" ' : ''}'
      'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">',
    )
    ..writeln('  <trk>')
    ..writeln('    <name>${_esc(name)}</name>');
  if (desc != null) b.writeln('    <desc>${_esc(desc)}</desc>');
  if (type != null) b.writeln('    <type>${_esc(type)}</type>');
  if (raw != null) {
    // GPX 1.1: extensions ennen trkseg-osia.
    b
      ..writeln('    <extensions>')
      ..writeln('      <gievra:raw${rawDistance == null ? '' : ' distance="${rawDistance.toStringAsFixed(1)}"'}>');
    for (final seg in raw) {
      if (seg.isEmpty) continue;
      b.writeln('        <gievra:seg>');
      for (final p in seg) {
        b.writeln(
          '          <gievra:pt lat="${p.lat.toStringAsFixed(6)}" lon="${p.lon.toStringAsFixed(6)}" time="${_iso(p.time)}"/>',
        );
      }
      b.writeln('        </gievra:seg>');
    }
    b
      ..writeln('      </gievra:raw>')
      ..writeln('    </extensions>');
  }
  for (final seg in segments) {
    if (seg.isEmpty) continue;
    b.writeln('    <trkseg>');
    for (final p in seg) {
      b.writeln(
        '      <trkpt lat="${p.lat.toStringAsFixed(6)}" lon="${p.lon.toStringAsFixed(6)}"><time>${_iso(p.time)}</time></trkpt>',
      );
    }
    b.writeln('    </trkseg>');
  }
  b
    ..writeln('  </trk>')
    ..writeln('</gpx>');
  return b.toString();
}

final _seg = RegExp(r'<trkseg>(.*?)</trkseg>', dotAll: true);
final _pt = RegExp(r'<trkpt\s+([^>]*?)/?>(.*?)(?:</trkpt>|(?=<trkpt)|$)', dotAll: true);
final _lat = RegExp(r'''lat\s*=\s*["']([-\d.]+)["']''');
final _lon = RegExp(r'''lon\s*=\s*["']([-\d.]+)["']''');
final _time = RegExp(r'<time>\s*([^<]+?)\s*</time>');

/// Lukee GPX-reitin osuuksina (myös muiden ohjelmien tekemät). Pisteet ilman aikaa saavat ajan null-arvon sijaan
/// edellisen pisteen ajan; rikkinäiset pisteet ohitetaan.
List<List<TrackPoint>> parseGpx(String text) {
  final out = <List<TrackPoint>>[];
  for (final s in _seg.allMatches(text)) {
    final seg = <TrackPoint>[];
    DateTime? last;
    for (final m in _pt.allMatches(s[1]!)) {
      final lat = double.tryParse(_lat.firstMatch(m[1]!)?[1] ?? '');
      final lon = double.tryParse(_lon.firstMatch(m[1]!)?[1] ?? '');
      if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) continue;
      final t = DateTime.tryParse(_time.firstMatch(m[2] ?? '')?[1] ?? '') ?? last;
      if (t == null) continue;
      last = t;
      seg.add(TrackPoint(t, lat, lon));
    }
    if (seg.isNotEmpty) out.add(seg);
  }
  return out;
}

final _raw = RegExp(r'<gievra:raw\b([^>]*)>(.*?)</gievra:raw>', dotAll: true);
final _rawSeg = RegExp(r'<gievra:seg>(.*?)</gievra:seg>', dotAll: true);
final _rawPt = RegExp(r'<gievra:pt\s+([^>]*?)/?>');
final _rawTime = RegExp(r'''time\s*=\s*["']([^"']+)["']''');
final _rawDist = RegExp(r'''distance\s*=\s*["']([\d.]+)["']''');

/// Alkuperäiset GPS-pisteet ja GPS:n mittaama matka (m) polulle korjatusta reitistä; null = ei mukana.
(List<List<TrackPoint>>, double?)? parseRawGpx(String text) {
  final m = _raw.firstMatch(text);
  if (m == null) return null;
  final out = <List<TrackPoint>>[];
  for (final s in _rawSeg.allMatches(m[2]!)) {
    final seg = <TrackPoint>[];
    for (final p in _rawPt.allMatches(s[1]!)) {
      final lat = double.tryParse(_lat.firstMatch(p[1]!)?[1] ?? '');
      final lon = double.tryParse(_lon.firstMatch(p[1]!)?[1] ?? '');
      final t = DateTime.tryParse(_rawTime.firstMatch(p[1]!)?[1] ?? '');
      if (lat == null || lon == null || t == null || lat.abs() > 90 || lon.abs() > 180) continue;
      seg.add(TrackPoint(t, lat, lon));
    }
    if (seg.isNotEmpty) out.add(seg);
  }
  return (out, double.tryParse(_rawDist.firstMatch(m[1]!)?[1] ?? ''));
}

/// Reitin pituus metreinä (osuuksien sisällä; katkoja ei lasketa).
double routeLength(List<List<TrackPoint>> segments) {
  var d = 0.0;
  for (final s in segments) {
    for (var i = 1; i < s.length; i++) {
      d += geoDistance(s[i - 1].lat, s[i - 1].lon, s[i].lat, s[i].lon);
    }
  }
  return d;
}
