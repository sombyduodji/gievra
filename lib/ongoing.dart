import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_state.dart';
import 'heart_rate.dart';
import 'hr_calc.dart';
import 'l10n.dart';
import 'models.dart';
import 'rest.dart';
import 'sports.dart';

// Sovelluksen ainoa "treeni käynnissä" -ilmoitus Androidin pudotusvalikossa: laji ja kulunut aika, esim.
// "Salitreeni käynnissä" tai "Juoksu käynnissä". Ei painikkeita; napautus avaa sovelluksen. Poistuu, kun treeni
// merkitään valmiiksi (Treeni valmis!), poistetaan tai hylätään. Etusija: GPS-lenkki (sen palvelu käyttää samaa
// ilmoitusta, joten se näkyy asetuksesta riippumatta), sitten liikunnan ajanotto, sitten salitreeni.
// Palautusajastin on oma, erillinen ilmoituksensa.
//
// Elävä näkymä (live): lajin taustakuva ja treenin tiedot kuten musiikkisoittimissa: kello, syke alueineen,
// keskisyke, maksimi ja kalorit (sykevyöllä), salilla liike ja sarjat tai palautuksen lähtölaskenta ja seuraava
// sarja, GPS-lenkillä matka ja vauhti. Kello ja lähtölaskenta kulkevat Androidin omilla kelloilla; syke ja muut
// luvut päivitetään enintään 5 s välein (ilmoitusten tiheä päivitys kuluttaa akkua ja Android rajoittaa sitä).

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

  /// GPS-lenkin matka ja vauhti ilmoitukseen (tallennin antaa; null = ei GPS:ää).
  static String? Function()? gpsLine;

  /// Testejä varten: nyt.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static String? _shown, _shownLive, _shownMajor;
  static DateTime? _liveAt;
  static Timer? _tick;
  static bool _asked = false;

  /// Sykkeen ja lukujen päivitysväli ilmoituksessa.
  static const liveEvery = Duration(seconds: 5);

  static bool get _supported => !kIsWeb && !isDemo && defaultTargetPlatform == TargetPlatform.android;

  /// Tämän päivän keskeneräinen salitreeni: sarjoja, ei merkitty valmiiksi, alkanut alle 5 h sitten.
  static Workout? gymInProgress(List<Workout> workouts, DateTime now) {
    for (final w in workouts) {
      // Treeni voi jatkua yli puolenyön (alle 5 h aloituksesta), mutta sen on alettava omana päivänään.
      if (w.activity != null || w.started == null || dateOnly(w.started!) != w.date) continue;
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

  /// Ilmoituksen taustakuva: sali, juoksu, kävely (askellajit) tai muu.
  static String kindOf(String? sport, {bool gym = false}) {
    if (gym) return 'gym';
    if (isRun(sport)) return 'run';
    if (sportOf(sport)?.steps == true) return 'walk';
    return 'other';
  }

  /// Elävän näkymän sisältö (ks. OngoingNote.Live). Tyhjä merkkijono = rivi piilossa.
  static Map<String, Object?> live(List<Workout> workouts, DateTime now) {
    final a = gps ?? activity;
    final gym = a == null ? gymInProgress(workouts, now) : null;
    final m = <String, Object?>{'kind': kindOf(a?.sport, gym: gym != null)};
    // Syke (sykevyö valittu ja treeni kerää sykettä).
    if (hr.address != null && hr.recording) {
      final v = hr.bpm;
      final p = hrProfile();
      final maxHr = p?.maxHr(now);
      final z = v == null || maxHr == null ? null : zoneOf(v, maxHr);
      m['hr'] = v == null ? '♥ –' : '♥ $v';
      m['zone'] = z ?? -1;
      m['zoneText'] =
          hrStatusText() ??
          (z == null ? (maxHr == null ? '' : t('alle alueiden')) : t('Alue {0} · {1}', [z + 1, t(zoneNames[z])]));
      if (hr.batteryLow) m['zoneText'] = t('Sykevyön akku vähissä ({0} %)', [hr.battery!]);
      final key = hr.currentKey;
      final so = key == null ? null : hr.peek(key);
      final series = so?.series;
      final kcal = p == null || series == null
          ? null
          : key!.startsWith('gym')
          ? p.kcalGym(series, series.length.inMinutes)
          : p.kcalEndurance(series);
      if (kcal != null && kcal > 0) m['kcal'] = t('≈ {0} kcal', [kcal]);
      if (so != null) {
        m['stats'] = [
          t('ka {0} · max {1}', [so.avg, so.max]),
          if (kcal != null && kcal > 0) t('≈ {0} kcal', [kcal]),
        ].join(' · ');
      }
    }
    if (gym != null) {
      // Palautus: lähtölaskenta ja seuraava sarja; muuten viimeisin liike ja sen sarjat.
      if (rest.running && rest.byHr) {
        // Sykkeen mukaan: kello laskee ylöspäin, tavoitteena palautumisraja.
        final target = hr.recoveryBpm(now);
        m['line'] = target == null ? t('Palautus') : t('Palautus · syke alle {0}', [target]);
        m['restStart'] = now.subtract(Duration(seconds: rest.elapsed)).millisecondsSinceEpoch;
        m['line2'] = rest.next ?? '';
      } else if (rest.running) {
        m['line'] = t('Palautus');
        m['restEnd'] = now.add(Duration(seconds: rest.remaining)).millisecondsSinceEpoch;
        m['line2'] = rest.next ?? '';
      } else if (rest.over) {
        // Palautus päättyi (ponnahdus on jo poistunut): tila näkyy tässä, kunnes seuraava sarja alkaa.
        m['line'] = rest.byHr ? t('✓ Palautunut') : t('✓ Tauko ohi');
        m['line2'] = rest.next ?? '';
      } else {
        final done = gym.exercises.where((e) => e.sets.isNotEmpty).toList();
        final e = done.where((e) => e.name == rest.exercise).firstOrNull ?? done.lastOrNull;
        if (e != null) {
          final n = e.workSets.length;
          m['line'] = '${e.name} · ${n == 1 ? t('1 sarja') : t('{0} sarjaa', [n])}';
        }
      }
      // Koko treeni tähän asti, kun liikkeitä on useampi (yhdellä liikkeellä rivi toistaisi edellisen).
      final done = gym.exercises.where((e) => e.workSets.isNotEmpty).toList();
      if (done.length > 1 && m['line2'] == null) {
        final sets = done.fold<int>(0, (n, e) => n + e.workSets.length);
        m['line2'] = t('{0} liikettä · {1} sarjaa', [done.length, sets]);
      }
    } else if (gps != null) {
      m['line'] = gpsLine?.call() ?? '';
    }
    return m;
  }

  /// Päivittää ilmoituksen tilaa vastaavaksi (kutsutaan treenien ja asetusten muuttuessa).
  static Future<void> refresh() async {
    if (!_supported) return;
    // GPS-lenkin ilmoitus on Androidin vaatima (etualan palvelu), joten se näkyy asetuksesta riippumatta.
    final c = settings.ongoingNote || gps != null ? current(store.workouts, now()) : null;
    final key = c == null ? null : '${c.$1}|${c.$2.millisecondsSinceEpoch ~/ 1000}|${c.$3}|${c.$4}';
    final t0 = now();
    final l = c == null ? null : live(store.workouts, t0);
    // Rakenne (laji, palautus alkoi/loppui, liike) päivittyy heti; syke ja luvut enintään [liveEvery] välein.
    final major = l == null
        ? null
        : '${l['kind']}|${l['restEnd'] != null}|${l['restStart'] != null}|${l['line']}|${l['hr'] == null}';
    final liveKey = l?.toString();
    final due = _liveAt == null || t0.difference(_liveAt!) >= liveEvery;
    if (key == _shown && (liveKey == _shownLive || (!due && major == _shownMajor))) return;
    _shown = key;
    _shownLive = liveKey;
    _shownMajor = major;
    _liveAt = t0;
    // Ajastin hakee sykkeen ja GPS-matkan, vaikka mikään muu ei muuttuisi.
    if (c == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(liveEvery, (_) => unawaited(refresh()));
    }
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
        'publicTitle': t('Treeni käynnissä'), // lukitusnäyttö: ei sykettä, kaloreita eikä liikettä
        'live': l,
      });
    } catch (_) {}
  }
}
