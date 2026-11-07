import 'models.dart';

// Kehonpainon seuranta: kehonpaino.md treenikansiossa (pituus ja punnitukset). Mukana varmuuskopiossa,
// tuonnissa ja synkronoinnissa kuten muutkin .md-tiedostot.
//
// ---
// height: 180 cm
// tags: [kehonpaino]
// ---
//
// # Kehonpaino
//
// - 2026-11-07: 82,4 kg

const bodyFileName = 'kehonpaino.md';

class BodyLog {
  int? heightCm;
  final Map<DateTime, double> weights; // päivä -> kg
  BodyLog({this.heightCm, Map<DateTime, double>? weights}) : weights = weights ?? {};

  bool get isEmpty => heightCm == null && weights.isEmpty;

  /// Punnitukset vanhimmasta uusimpaan.
  List<(DateTime, double)> get sorted =>
      (weights.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$1.compareTo(b.$1)));

  BodyLog copy() => BodyLog(heightCm: heightCm, weights: {...weights});
}

/// Painon syöte: pilkku tai piste käy ("82,4", "82.4", "82"). Järkevä alue 20–400 kg, muuten null.
double? parseWeight(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s*kg$', caseSensitive: false), '');
  if (t.startsWith('-') || t.startsWith('−')) return null;
  final v = parseNum(t);
  if (v == null || v < 20 || v > 400) return null;
  return (v * 10).round() / 10;
}

/// Pituus senttimetreinä: 100–250 cm, muuten null.
int? parseHeight(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s*cm$', caseSensitive: false), '');
  if (t.startsWith('-') || t.startsWith('−')) return null;
  final v = parseNum(t);
  if (v == null || v < 100 || v > 250) return null;
  return v.round();
}

/// Painoindeksi (kg / m²), yksi desimaali.
double bmi(double kg, int heightCm) {
  final m = heightCm / 100;
  return (kg / (m * m) * 10).round() / 10;
}

final _entry = RegExp(r'^\s*[-*]\s*(\d{4}-\d{2}-\d{2})\s*:\s*([-−]?[\d.,]+)');

BodyLog parseBody(String text) {
  final b = BodyLog();
  final lines = text.split('\n');
  var i = 0;
  if (lines.isNotEmpty && lines[0].trim() == '---') {
    for (i = 1; i < lines.length && lines[i].trim() != '---'; i++) {
      final l = lines[i];
      final idx = l.indexOf(':');
      if (idx > 0 && l.substring(0, idx).trim() == 'height') b.heightCm = parseHeight(l.substring(idx + 1));
    }
  }
  for (final l in lines.skip(i)) {
    final m = _entry.firstMatch(l);
    if (m == null) continue;
    final d = DateTime.tryParse(m[1]!);
    final kg = parseWeight(m[2]!);
    if (d != null && kg != null) b.weights[dateOnly(d)] = kg;
  }
  return b;
}

String bodyToMarkdown(BodyLog b) {
  final s = StringBuffer('---\n');
  if (b.heightCm != null) s.writeln('height: ${b.heightCm} cm');
  s
    ..writeln('tags: [kehonpaino]')
    ..writeln('---')
    ..writeln()
    ..writeln('# Kehonpaino')
    ..writeln();
  for (final (d, kg) in b.sorted.reversed) {
    s.writeln('- ${isoDate(d)}: ${fileNum(kg)} kg');
  }
  return s.toString();
}

/// Yhdistää tuodun lokin nykyiseen: puuttuvat päivät ja pituus lisätään, olemassa olevia ei muuteta.
BodyLog mergeBody(BodyLog current, BodyLog imported) {
  final out = current.copy();
  out.heightCm ??= imported.heightCm;
  for (final e in imported.weights.entries) {
    out.weights.putIfAbsent(e.key, () => e.value);
  }
  return out;
}

/// Painosarja tilastoihin: punnitukset ja treeneihin kirjatut kehonpainot (esim. FitNotes-tuonti);
/// saman päivän punnitus voittaa. Vanhimmasta uusimpaan.
List<(DateTime, double)> weightSeries(BodyLog b, List<Workout> ws) {
  final m = <DateTime, double>{};
  for (final w in ws) {
    final bw = w.bodyweight;
    if (bw != null && bw >= 20 && bw <= 400) m[dateOnly(w.date)] = bw;
  }
  m.addAll(b.weights);
  return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
}
