import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_state.dart';
import 'l10n.dart';
import 'models.dart';

// Sovelluksen ainoa "treeni käynnissä" -ilmoitus Androidin pudotusvalikossa: laji ja kulunut aika, esim.
// "Salitreeni käynnissä" tai "Juoksu käynnissä". Ei painikkeita; napautus avaa sovelluksen. Poistuu, kun treeni
// merkitään valmiiksi (Treeni valmis!), poistetaan tai hylätään. Etusija: GPS-lenkki (sen palvelu käyttää samaa
// ilmoitusta, joten se näkyy asetuksesta riippumatta), sitten liikunnan ajanotto, sitten salitreeni.
// Palautusajastin on oma, erillinen ilmoituksensa.

/// Liikunnan ajanotto (liikuntasivu kertoo tilansa tänne).
class OngoingActivity {
  final String sport;

  /// Käynnissä: milloin kello olisi alkanut, jos taukoja ei olisi ollut (nyt − kertynyt aika). Tauolla: null.
  final DateTime? since;
  final Duration elapsed;

  /// Tauon sijaan näytettävä teksti (esim. GPS-signaalia etsitään, ajanotto ei vielä käy).
  final String? note;
  const OngoingActivity(this.sport, {this.since, this.elapsed = Duration.zero, this.note});
  bool get paused => since == null;
}

class Ongoing {
  static const _ch = MethodChannel('fi.somby.gievra/ongoing');

  /// Liikuntasivun ajanotto (null = ei käynnissä).
  static OngoingActivity? activity;

  /// GPS-tallennus (null = ei käynnissä).
  static OngoingActivity? gps;

  /// Testejä varten: nyt.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static String? _shown;
  static bool _asked = false;

  static bool get _supported => !kIsWeb && !isDemo && defaultTargetPlatform == TargetPlatform.android;

  /// Tämän päivän keskeneräinen salitreeni: sarjoja, ei merkitty valmiiksi, alkanut alle 5 h sitten.
  static Workout? gymInProgress(List<Workout> workouts, DateTime now) {
    final today = dateOnly(now);
    for (final w in workouts) {
      if (w.date != today || w.activity != null || w.started == null) continue;
      if (w.minutes != null || w.feeling != null) continue; // Treeni valmis!
      if (w.exercises.every((e) => e.sets.isEmpty)) continue;
      final age = now.difference(w.started!);
      if (age.isNegative || age > const Duration(hours: 5)) continue;
      return w;
    }
    return null;
  }

  /// Mitä näytetään: (otsikko, alku, tauolla, taukoteksti) tai null = ei mitään.
  static (String, DateTime, bool, String)? current(List<Workout> workouts, DateTime now) {
    final a = gps ?? activity;
    if (a != null) {
      final title = t('{0} käynnissä', [sportName(a.sport)]);
      if (a.note != null) return (title, now, true, a.note!);
      if (a.paused) return (title, now, true, t('tauolla · {0}', [fmtDurationSec(a.elapsed.inSeconds)]));
      return (title, a.since!, false, '');
    }
    final gym = gymInProgress(workouts, now);
    if (gym != null) return (t('Salitreeni käynnissä'), gym.started!, false, '');
    return null;
  }

  /// Päivittää ilmoituksen tilaa vastaavaksi (kutsutaan treenien ja asetusten muuttuessa).
  static Future<void> refresh() async {
    if (!_supported) return;
    // GPS-lenkin ilmoitus on Androidin vaatima (etualan palvelu), joten se näkyy asetuksesta riippumatta.
    final c = settings.ongoingNote || gps != null ? current(store.workouts, now()) : null;
    final key = c == null ? null : '${c.$1}|${c.$2.millisecondsSinceEpoch ~/ 1000}|${c.$3}|${c.$4}';
    if (key == _shown) return;
    _shown = key;
    try {
      if (c == null) {
        await _ch.invokeMethod('hide');
        return;
      }
      if (!_asked) {
        _asked = true;
        await Permission.notification.request(); // ilman lupaa treeni toimii, ilmoitusta ei vain näy
      }
      await _ch.invokeMethod('show', {
        'title': c.$1,
        'start': c.$2.millisecondsSinceEpoch,
        'paused': c.$3,
        'pausedText': c.$4,
        'channel': t('Käynnissä oleva treeni'),
      });
    } catch (_) {}
  }
}
