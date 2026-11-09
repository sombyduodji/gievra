import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'sports.dart';

// Health Connect (Android): treenin jälkeen syke, kalorit ja askeleet kellosta. Ei tuoda kaikkea historiaa: haetaan vain
// tämän treenin aikaväliä lähellä olevat harjoitukset, ja käyttäjä vahvistaa ("Onko tämä se?"). Tiedot luetaan
// laitteella (ks. android/.../HealthBridge.kt), eikä mitään lähetetä verkkoon.

/// Health Connectista löytynyt ehdokas: kellon harjoitus tai pelkkä sykedata treenin ajalta.
class HealthCandidate {
  final bool session; // false = sykedata ilman harjoitusta (treenin omalta ajalta)
  final DateTime start, end;
  final String? title;
  final int? type;
  final String app;
  final int? hrAvg, hrMax, kcal, steps;

  /// Health Connectin tunniste (tehdyn liikunnan lisäys) ja matka metreinä (jos luettu).
  final String? id;
  final double? meters;

  /// Askeleet ilman harjoitusta (yhtenäinen kävely, jota mikään sovellus ei tallentanut harjoitukseksi) ja sen
  /// tallentanut sovellus (paketti).
  final bool stepsOnly;
  final String? pkg;
  const HealthCandidate({
    required this.session,
    required this.start,
    required this.end,
    this.title,
    this.type,
    this.app = '',
    this.hrAvg,
    this.hrMax,
    this.kcal,
    this.steps,
    this.id,
    this.meters,
    this.stepsOnly = false,
    this.pkg,
  });

  /// Askelista tehty liikunta saman ajan sykkeellä, kaloreilla ja matkalla (rangeStats).
  HealthCandidate withStats(Map m) => HealthCandidate(
    session: session,
    start: start,
    end: end,
    title: title,
    type: type,
    app: app,
    hrAvg: (m['hrAvg'] as num?)?.toInt(),
    hrMax: (m['hrMax'] as num?)?.toInt(),
    kcal: (m['kcal'] as num?)?.toInt(),
    steps: steps,
    id: id,
    meters: (m['meters'] as num?)?.toDouble(),
    stepsOnly: stepsOnly,
    pkg: pkg,
  );

  factory HealthCandidate.fromMap(Map m) => HealthCandidate(
    session: m['kind'] == 'session',
    start: DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
    end: DateTime.fromMillisecondsSinceEpoch((m['end'] as num).toInt()),
    title: (m['title'] as String?)?.trim().isEmpty ?? true ? null : (m['title'] as String).trim(),
    type: (m['type'] as num?)?.toInt(),
    app: m['app'] as String? ?? '',
    hrAvg: (m['hrAvg'] as num?)?.toInt(),
    hrMax: (m['hrMax'] as num?)?.toInt(),
    kcal: (m['kcal'] as num?)?.toInt(),
    steps: (m['steps'] as num?)?.toInt(),
    id: m['id'] as String?,
    meters: (m['meters'] as num?)?.toDouble(),
  );

  Duration get duration => end.difference(start);
  bool get hasData => hrAvg != null || hrMax != null || kcal != null || (steps ?? 0) > 0;
}

/// Treenin aikaväli: alku ja kesto treenistä; ilman alkuaikaa koko päivä (kesto vain vertailuun).
(DateTime, DateTime, bool) workoutWindow(Workout w) {
  final secs = w.seconds ?? (w.minutes == null ? null : w.minutes! * 60);
  if (w.started != null) {
    return (w.started!, w.started!.add(Duration(seconds: secs ?? 3600)), true);
  }
  final day = DateTime(w.date.year, w.date.month, w.date.day);
  return (day, day.add(const Duration(days: 1)), false);
}

/// Ehdokkaat parhaasta huonoimpaan: päällekkäisyys treenin kanssa (osuus pidemmästä), muuten alkuaikojen ero.
/// Mukana vain "riittävän lähellä" olevat: aikavälit menevät päällekkäin tai alkavat enintään 45 min erossa.
/// Ilman alkuaikaa (koko päivä) verrataan kestoon. Pelkkä sykedata tulee kellon harjoitusten jälkeen.
List<HealthCandidate> rankCandidates(Workout w, List<HealthCandidate> all) {
  final (start, end, timed) = workoutWindow(w);
  final dur = timed ? end.difference(start) : Duration(seconds: w.seconds ?? (w.minutes ?? 60) * 60);
  double score(HealthCandidate c) {
    if (!c.hasData) return double.negativeInfinity;
    final bonus = c.session ? 0.0 : -0.5;
    if (!timed) {
      if (c.start.isBefore(start) || !c.start.isBefore(end)) return double.negativeInfinity;
      final diff = (c.duration - dur).inSeconds.abs();
      return 1 - diff / 7200 + bonus;
    }
    final overlap = (c.end.isBefore(end) ? c.end : end).difference(c.start.isAfter(start) ? c.start : start);
    if (overlap.inSeconds > 0) {
      final longer = c.duration > dur ? c.duration : dur;
      return 1 + overlap.inSeconds / (longer.inSeconds == 0 ? 1 : longer.inSeconds) + bonus;
    }
    final gap = c.start.difference(start).inSeconds.abs();
    return gap <= 45 * 60 ? 1 - gap / 2700 + bonus : double.negativeInfinity;
  }

  final scored = [for (final c in all) (c, score(c))].where((e) => e.$2 > double.negativeInfinity).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final e in scored) e.$1];
}

/// Täyttää treeniin syke- ja kaloritiedot ehdokkaasta (vain ne, jotka löytyivät); askeleet vain lajeihin, joissa
/// ne kirjataan (kävely, juoksu, retkeily …).
void applyCandidate(Workout w, HealthCandidate c, {bool steps = false}) {
  if (c.hrAvg != null) w.hrAvg = c.hrAvg;
  if (c.hrMax != null) w.hrMax = c.hrMax;
  if (c.kcal != null) w.kcal = c.kcal;
  if (steps && (c.steps ?? 0) > 0) w.steps = c.steps;
  // Health Connectista lisätty liikunta (sama harjoitus): myös matka päivittyy, ellei sitä ole kirjoitettu käsin.
  if (w.hcId != null && w.hcId == c.id && (c.meters ?? 0) > 0 && !w.distanceManual) {
    w.distanceKm = (c.meters! / 10).round() / 100;
  }
  w.healthSource = c.app;
}

/// Kanava Android-puolelle (HealthBridge.kt).
class HealthConnect {
  static const _ch = MethodChannel('fi.somby.gievra/health');

  /// available, update (Health Connect -sovellus asennettava tai päivitettävä) tai unavailable.
  static Future<String> status() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return 'unavailable';
    try {
      return await _ch.invokeMethod<String>('status') ?? 'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  /// [import]: tehdyn liikunnan lisäys tarvitsee lisäksi matkan lukuluvan.
  static Future<bool> granted({bool import = false}) async =>
      await _ch.invokeMethod<bool>('granted', {'import': import}) ?? false;

  /// Lupakysely; [write] vain kehitysversiossa (testitiedot emulaattorille).
  static Future<bool> request({bool write = false, bool import = false}) async =>
      await _ch.invokeMethod<bool>('request', {'write': write, 'import': import}) ?? false;

  /// Päivän [day] harjoitukset (alkavat sinä päivänä, laitteen aikavyöhykkeellä) tunnisteineen ja matkoineen.
  static Future<List<HealthCandidate>> sessions(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final r = await _ch.invokeMethod<List>('sessions', {
      'start': start.millisecondsSinceEpoch,
      'end': DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch,
    });
    return [for (final m in r ?? const []) HealthCandidate.fromMap(m as Map)];
  }

  /// Päivän askeltietueet (askelista tehty liikunta).
  static Future<List<StepRecord>> stepRecords(DateTime day) async {
    final r = await _ch.invokeMethod<List>('stepRecords', {
      'start': DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
      'end': DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch,
    });
    return [for (final m in r ?? const []) StepRecord.fromMap(m as Map)];
  }

  /// Aikavälin syke, kalorit ja matka sovellukselta [pkg].
  static Future<HealthCandidate> withRangeStats(HealthCandidate c) async {
    final m = await _ch.invokeMethod<Map>('rangeStats', {
      'start': c.start.millisecondsSinceEpoch,
      'end': c.end.millisecondsSinceEpoch,
      'pkg': c.pkg,
    });
    return m == null ? c : c.withStats(m);
  }

  static Future<List<HealthCandidate>> candidates(DateTime start, DateTime end) async {
    final r = await _ch.invokeMethod<List>('candidates', {
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    return [for (final m in r ?? const []) HealthCandidate.fromMap(m as Map)];
  }

  static Future<void> openSettings() => _ch.invokeMethod('settings');

  /// Kehitysversio: keksitty harjoitus sykkeineen emulaattorille.
  static Future<void> debugInsert(DateTime start, DateTime end, {int type = 56, int bpm = 145}) => _ch.invokeMethod(
    'debugInsert',
    {'start': start.millisecondsSinceEpoch, 'end': end.millisecondsSinceEpoch, 'type': type, 'bpm': bpm},
  );
}

// ---- Tehdyn liikunnan lisäys Health Connectista (asetus, oletus pois) ----

/// Health Connectin harjoitustyyppi (ExerciseSessionRecord.EXERCISE_TYPE_*) Gievran lajiksi; null = ei tunneta
/// (käyttäjä valitsee). Salitreenit eivät ole liikuntaa: ks. [isStrengthType].
String? sportForHealthType(int? type) => switch (type) {
  56 || 57 => 'Juoksu', // juoksu, juoksumatto
  79 => 'Kävely',
  37 => 'Retkeily',
  8 || 9 => 'Pyöräily', // myös kuntopyörä
  73 || 74 => 'Uinti',
  61 => 'Hiihto',
  62 => 'Laskettelu',
  53 || 54 => 'Soutu',
  46 => 'Melonta',
  39 || 60 => 'Luistelu',
  63 => 'Lumikenkäily',
  64 => 'Jalkapallo',
  5 => 'Koripallo',
  78 => 'Lentopallo',
  38 => 'Jääkiekko',
  66 => 'Squash',
  2 => 'Sulkapallo',
  76 => 'Tennis',
  75 => 'Pöytätennis',
  32 => 'Golf',
  26 => 'Ryhmäliikunta',
  83 => 'Jooga',
  48 => 'Pilates',
  16 => 'Tanssi',
  51 => 'Kiipeily',
  44 || 11 => 'Kamppailulajit',
  71 => 'Liikkuvuus ja venyttely',
  _ => null,
};

/// Voimaharjoittelu (Health Connect): kirjataan Gievran salitreeniin, ei liikunnaksi.
bool isStrengthType(int? type) => type == 70 || type == 81 || type == 13;

/// Päivän harjoitukset, joita ei vielä ole Gievrassa, ja jo lisättyjen määrä. Jo lisätty = sama Health Connectin
/// tunniste (hc_id) tai Gievran liikunta, joka on suurimmaksi osaksi samaan aikaan (yli puolet lyhyemmästä).
(List<HealthCandidate>, int) newHealthSessions(List<HealthCandidate> all, List<Workout> existing) {
  final ids = {for (final w in existing) ?w.hcId};
  bool overlaps(HealthCandidate c, Workout w) {
    if (w.activity == null || w.started == null) return false;
    final secs = w.seconds ?? (w.minutes ?? 0) * 60;
    if (secs <= 0) return false;
    final ws = w.started!, we = ws.add(Duration(seconds: secs));
    final o = (c.end.isBefore(we) ? c.end : we).difference(c.start.isAfter(ws) ? c.start : ws).inSeconds;
    final shorter = c.duration.inSeconds < secs ? c.duration.inSeconds : secs;
    return o > 0 && shorter > 0 && o * 2 > shorter;
  }

  // Salitreeni on jo lisätty, jos samaan aikaan olevaan salitreeniin on jo haettu kellon tiedot.
  bool gymHasIt(HealthCandidate c, Workout w) {
    if (w.activity != null || w.healthSource == null || w.started == null) return false;
    final we = w.started!.add(Duration(minutes: w.minutes ?? 0));
    return w.started!.isBefore(c.end) && we.isAfter(c.start);
  }

  final fresh = <HealthCandidate>[];
  var done = 0;
  for (final c in all) {
    final strength = isStrengthType(c.type);
    if ((c.id != null && ids.contains(c.id)) || existing.any((w) => strength ? gymHasIt(c, w) : overlaps(c, w))) {
      done++;
    } else {
      fresh.add(c);
    }
  }
  return (fresh, done);
}

/// Uusi liikunta harjoituksesta [c] lajille [sport]: alku, tarkka kesto, matka, syke, kalorit ja askeleet.
Workout workoutFromHealth(HealthCandidate c, String sport, {required int session}) {
  final sp = sportOf(sport);
  final secs = c.duration.inSeconds;
  final km = (c.meters ?? 0) > 0 && (sp?.distance ?? false) ? (c.meters! / 10).round() / 100 : null;
  final w = Workout(
    date: DateTime(c.start.year, c.start.month, c.start.day),
    title: sport,
    activity: sport,
    session: session,
    started: c.start,
    seconds: secs,
    minutes: (secs / 60).round(),
    distanceKm: km,
    kcal: c.kcal,
    hrAvg: c.hrAvg,
    hrMax: c.hrMax,
    watchTime: true,
  );
  if ((sp?.steps ?? false) && (c.steps ?? 0) > 0) w.steps = c.steps;
  w.healthSource = c.app;
  w.hcId = c.id;
  return w;
}

/// Salitreeni Health Connectista: kellon tiedot (aloitus, kesto, syke, kalorit) päivän salitreeniin, jos sellainen on
/// (lähimpänä samaa aikaa oleva, johon ei vielä ole liitetty harjoitusta), muuten uusi salitreeni ilman liikkeitä.
/// Palauttaa (treeni, uusi?). Ei tallenna.
(Workout, bool) gymFromHealth(HealthCandidate c, List<Workout> sameDay, {required int nextSession}) {
  final gyms = [
    for (final w in sameDay)
      if (w.activity == null && w.hcId == null) w,
  ];
  int dist(Workout w) => w.started == null ? 1 << 30 : w.started!.difference(c.start).inMinutes.abs();
  gyms.sort((a, b) => dist(a).compareTo(dist(b)));
  final found = gyms.isEmpty ? null : gyms.first.copy();
  final w =
      found ??
      Workout(
        date: DateTime(c.start.year, c.start.month, c.start.day),
        title: 'Treeni', // tiedostoon suomeksi kuten muutkin
        session: nextSession,
      );
  w.started = c.start;
  w.minutes = (c.duration.inSeconds / 60).round().clamp(1, 600);
  w.watchTime = true;
  w.hcId = c.id ?? 'hc-${c.start.millisecondsSinceEpoch}';
  applyCandidate(w, c);
  return (w, found == null);
}

/// Health Connectin askeltietue (stepRecords).
class StepRecord {
  final DateTime start, end;
  final int count;
  final String pkg, app;
  const StepRecord(this.start, this.end, this.count, {this.pkg = '', this.app = ''});
  factory StepRecord.fromMap(Map m) => StepRecord(
    DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
    DateTime.fromMillisecondsSinceEpoch((m['end'] as num).toInt()),
    (m['count'] as num).toInt(),
    pkg: m['pkg'] as String? ?? '',
    app: m['app'] as String? ?? '',
  );
}

int _overlapSec(DateTime a0, DateTime a1, DateTime b0, DateTime b1) {
  final s = a0.isAfter(b0) ? a0 : b0;
  final e = a1.isBefore(b1) ? a1 : b1;
  final d = e.difference(s).inSeconds;
  return d > 0 ? d : 0;
}

/// Yhtenäiset kävelyt askeltietueista, joille ei ole harjoitusta: vähintään [minLen] askelia tahdilla vähintään
/// [minCadence] askelta minuutissa, katkot enintään [gap]. Saman sovelluksen päällekkäiset tietueet lasketaan kerran;
/// jos kaksi sovellusta laski saman kävelyn (esim. puhelin ja kävelymatto), mukaan otetaan se, jolla on enemmän
/// askelia. Pois jäävät kävelyt, jotka ovat suurimmaksi osaksi jonkin Health Connectin harjoituksen aikana [sessions].
List<HealthCandidate> stepStretches(
  List<StepRecord> records, {
  List<HealthCandidate> sessions = const [],
  int minCadence = 60,
  Duration gap = const Duration(minutes: 2),
  Duration minLen = const Duration(minutes: 10),
}) {
  final byPkg = <String, List<StepRecord>>{};
  for (final r in records) {
    final secs = r.end.difference(r.start).inSeconds;
    if (secs <= 0 || r.count <= 0) continue;
    if (r.count * 60 / secs < minCadence) continue; // päivän summa tai hidas tallustelu
    (byPkg[r.pkg] ??= []).add(r);
  }
  final found = <(DateTime, DateTime, int, StepRecord)>[];
  for (final rs in byPkg.values) {
    // Alun mukaan; samasta hetkestä alkavista pisin ensin (koko kävelyn summa ennen minuuttitietueita).
    rs.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : b.end.compareTo(a.end);
    });
    DateTime? s, e;
    var n = 0.0;
    late StepRecord first;
    void close() {
      final a = s, b = e;
      if (a != null && b != null && b.difference(a) >= minLen) found.add((a, b, n.round(), first));
    }

    for (final r in rs) {
      final cur = e;
      if (s == null || cur == null || r.start.isAfter(cur.add(gap))) {
        close();
        s = r.start;
        e = r.end;
        n = r.count.toDouble();
        first = r;
        continue;
      }
      if (!r.end.isAfter(cur)) continue; // kokonaan jo laskettu
      final len = r.end.difference(r.start).inMilliseconds;
      final fresh = r.end.difference(r.start.isAfter(cur) ? r.start : cur).inMilliseconds;
      n += r.count * fresh / len;
      e = r.end;
    }
    close();
  }
  found.sort((a, b) => b.$3.compareTo(a.$3)); // eniten askelia ensin
  final kept = <(DateTime, DateTime, int, StepRecord)>[];
  for (final f in found) {
    final len = f.$2.difference(f.$1).inSeconds;
    bool mostly(DateTime a, DateTime b) {
      final shorter = [len, b.difference(a).inSeconds].reduce((x, y) => x < y ? x : y);
      return _overlapSec(f.$1, f.$2, a, b) * 2 > shorter;
    }

    if (kept.any((k) => mostly(k.$1, k.$2))) continue;
    if (sessions.any((c) => c.session && mostly(c.start, c.end))) continue;
    kept.add(f);
  }
  kept.sort((a, b) => a.$1.compareTo(b.$1));
  return [
    for (final (st, en, n, r) in kept)
      HealthCandidate(
        session: false,
        stepsOnly: true,
        start: st,
        end: en,
        app: r.app,
        pkg: r.pkg,
        steps: n,
        id: 'steps:${st.millisecondsSinceEpoch}',
      ),
  ];
}
