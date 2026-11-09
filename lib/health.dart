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
  });

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

  final fresh = <HealthCandidate>[];
  var done = 0;
  for (final c in all) {
    if (isStrengthType(c.type)) continue;
    if ((c.id != null && ids.contains(c.id)) || existing.any((w) => overlaps(c, w))) {
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
