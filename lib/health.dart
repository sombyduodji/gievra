import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

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

  static Future<bool> granted() async => await _ch.invokeMethod<bool>('granted') ?? false;

  /// Lupakysely; [write] vain kehitysversiossa (testitiedot emulaattorille).
  static Future<bool> request({bool write = false}) async =>
      await _ch.invokeMethod<bool>('request', {'write': write}) ?? false;

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
