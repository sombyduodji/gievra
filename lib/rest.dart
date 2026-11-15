import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'heart_rate.dart' show hr;
import 'exercises.dart';
import 'insights.dart';
import 'l10n.dart';
import 'models.dart';
import 'program.dart';

// Palautusaika sarjojen välillä.
//
// Lähteet (ks. docs/tutkimus/palautus.md):
//  - de Salles ym. 2009 (Sports Med): maksimivoima 3–5 min, raskaat moninivelliikkeet.
//  - Schoenfeld ym. 2016 (JSCR): lihaskasvussa 3 min tuotti enemmän kuin 1 min.
//  - Grgic ym. 2017 (Eur J Sport Sci): moninivelliikkeissä vähintään 2 min, eristävissä 60–90 s riittää.
//  - ACSM 2009 (Med Sci Sports Exerc): voima 2–3 min raskaissa, kevyemmissä 1–2 min; kestävyys alle 1–2 min.
//  - NSCA (Haff & Triplett 2016): voima 2–5 min, lihaskasvu 30–90 s (vanhempi suositus), kestävyys ≤ 30 s.
// Ohjelman liikkeillä on oma tauko (ohjelma.md: "tauko 3 min"); se voittaa.

/// Moninivelliike: jonkin moninivelpaikan (kyykky, lonkkasarana, työnnöt, vedot) vakioliike.
bool isCompound(String exercise) => slots.values.any((s) => s.compound && s.defaults.contains(exercise));

/// Paras arvioitu maksimi (e1RM) ennen päivää, työsarjoista.
double bestE1rmBefore(String exercise, DateTime date) {
  var best = 0.0;
  for (final w in store.workouts) {
    if (!w.date.isBefore(date)) continue;
    for (final e in w.exercises) {
      if (e.name != exercise) continue;
      for (final s in e.workSets) {
        final v = e1rm(s.kg, s.reps);
        if (v != null && v > best) best = v;
      }
    }
  }
  return best;
}

/// Kuormaluokka: 0 kevyt (yli 12 toistoa), 1 keskiraskas (6–12), 2 raskas (1–5 tai ≥ 85 % maksimista).
int loadClass(SetEntry set, {double? best}) {
  final max = best ?? 0;
  final pct = max > 0 && set.kg > 0 ? set.kg / max : null;
  if (set.reps <= 5 || (pct != null && pct >= .85)) return 2;
  return set.reps <= 12 ? 1 : 0;
}

/// Ohjelman liikkeen kuormaluokka: pääliikkeet (raskas / volyymi, prosenttipainot) ovat raskaita; muuten
/// toistoalueen keskikohta (esim. 3–6 -> raskas, 5–7 -> keskiraskas, 12–20 -> kevyt).
int itemLoadClass(PlanItem i) {
  if (i.kind == 'H' || i.kind == 'V') return 2;
  final mid = (i.lo + i.hi) / 2;
  return mid <= 5 ? 2 : (mid <= 12 ? 1 : 0);
}

/// Kuormaluokkien oletuspalautus ohjelman taukojen mukaan, jos ohjelma on käytössä, muuten tutkimusten
/// mukaiset 60 s / 2 min / 3 min. Raskas = pääliikkeiden pisin tauko, muut luokat yleisin tauko
/// (moninivelliikkeet; kevyessä luokassa myös eristävät).
List<int> restDefaults([Program? p]) {
  final out = [60, 120, 180];
  if (p == null) return out;
  for (var c = 0; c < 3; c++) {
    final counts = <int, int>{};
    for (final d in p.plan) {
      for (final i in d.items) {
        if (!i.compound && c > 0 && i.kind == null) continue;
        if (itemLoadClass(i) == c) counts[i.restSec] = (counts[i.restSec] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) continue;
    out[c] = c == 2
        ? counts.keys.reduce((a, b) => a > b ? a : b)
        : counts.entries.reduce((a, b) => b.value > a.value || (b.value == a.value && b.key > a.key) ? b : a).key;
  }
  // Raskaampi kuorma ei koskaan saa lyhyempää palautusta kuin kevyempi.
  if (out[1] > out[2]) out[2] = out[1];
  if (out[0] > out[1]) out[0] = out[1];
  return out;
}

/// Suositeltu palautus (sekunteina) juuri tallennetun sarjan jälkeen.
/// [target]: ohjelman tavoite (oma tauko, kevennysviikko). [deload]: kevennysviikko ilman ohjelmatavoitetta.
/// [best]: arvioitu maksimi (e1RM). [work]: päivän työpaino (lämmittelysarjojen palautus sen mukaan).
int restSeconds(String exercise, SetEntry set, {Target? target, bool deload = false, double? best, double? work}) {
  if (set.warmup) {
    // Kevyet lämmittelyt lyhyesti, työpainoa lähestyvät pidempään (ei väsytetä ennen työsarjoja).
    final r = work != null && work > 0 ? set.kg / work : 0;
    return r >= .8 ? 90 : (r >= .6 ? 60 : 45);
  }
  if (measureOf(exercise) != Measure.reps) return 60;
  final compound = isCompound(exercise);
  int sec;
  if (target != null) {
    sec = target.restSec;
    if (target.loadFactor < 1) deload = true;
  } else {
    final max = best ?? 0;
    final pct = max > 0 && set.kg > 0 ? set.kg / max : null;
    if (set.reps <= 5 || (pct != null && pct >= .85)) {
      sec = compound ? (pct != null && pct >= .9 ? 240 : 180) : 120;
    } else if (set.reps <= 12) {
      sec = compound ? 120 : 90;
    } else {
      sec = 60;
    }
  }
  // Käyttäjän oma säätö kuormaluokalle (☰ → Asetukset → Palautusajastin).
  sec += settings.restAdjust[loadClass(set, best: best)];
  // Sarja vietiin loppuun asti (ei varaa): vähän pidempi palautus. Reilusti varaa: kevyempi sarja, hieman lyhyempi.
  if (set.rir == 0) sec += 30;
  if (set.rir != null && set.rir! >= 3 && sec < 180) sec -= 15;
  // Kevennysviikolla kuorma on pienempi: lyhyempi palautus riittää.
  if (deload) sec = (sec * .75).round();
  sec = ((sec / 15).round() * 15).clamp(45, 300).toInt();
  return sec;
}

/// Käynnissä oleva palautusajastin (yksi kerrallaan, koko sovellukselle).
class RestTimer extends ChangeNotifier {
  DateTime? _end;
  int total = 0;
  String exercise = '';
  Timer? _tick;

  /// Testejä varten: nyt.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Kutsutaan, kun palautus päättyy (värinä, ääni ja viesti käyttöliittymässä): [message] kertoo miksi.
  void Function(String message)? onDone;

  /// Palautus sykkeen mukaan (sykevyö, Asetukset → Sykevyö): ajastin odottaa, kunnes syke laskee palautumisrajan
  /// alle, ja ilmoittaa silloin. Jos palautuminen kestää [hrWaitSeconds], muistutetaan kohteliaasti tarkistamaan.
  bool byHr = false;
  static const hrWaitSeconds = 300;

  /// Palautus päättyi (aika täynnä tai syke laski) eikä seuraavaa sarjaa ole vielä aloitettu: treeni-ilmoitus
  /// näyttää sen omassa rivissään. Ohita (stop) ei jätä tätä tilaa.
  bool over = false;

  /// Sykevyö on käytössä, treeni kerää sykettä ja palautumisraja tiedetään (profiili annettu).
  static bool get hrModeAvailable =>
      settings.restByHr && hr.address != null && hr.recording && hr.bpm != null && hr.recoveryBpm(clock()) != null;

  /// Sykkeen mukaan: ohjelman palautusaika varalle (vyön akku loppuu tai yhteys katkeaa tauon aikana).
  int planned = 0;
  DateTime? _hrSeen;

  /// Ilman sykelukemaa näin kauan sykkeen mukaan odottava palautus vaihtuu tavalliseen palautusaikaan.
  static const hrLostSeconds = 15;

  /// Kulunut aika tauon alusta (sykkeen mukaan odotettaessa näytetään tämä).
  int get elapsed => (total - remaining).clamp(0, 3600);

  bool get running => _end != null;

  int get remaining {
    final e = _end;
    if (e == null) return 0;
    final s = e.difference(clock()).inMilliseconds;
    return s <= 0 ? 0 : (s / 1000).ceil();
  }

  /// Seuraavan sarjan kuvaus palautuspalkkiin. Sarjanäkymä antaa funktion, jolloin painon muutos tauon aikana näkyy
  /// heti; näkymästä poistuttaessa viimeisin arvo jää tekstiksi.
  String? Function()? nextFn;
  String? nextText;
  String? get next => nextFn?.call() ?? nextText;

  /// Sykevyö: syke laski palautumisrajan alle tällä tauolla (värinä kerran; aika jatkuu, käyttäjä päättää).
  bool recovered = false;

  void _checkRecovered() {
    if (byHr) {
      if (hr.bpm != null) {
        _hrSeen = clock();
      } else if (clock().difference(_hrSeen ?? clock()).inSeconds >= hrLostSeconds) {
        // Syke katosi (vyön akku, kantama): tavallinen palautusaika tauon alusta laskien.
        final start = _end!.subtract(Duration(seconds: total));
        byHr = false;
        total = planned;
        _end = start.add(Duration(seconds: planned));
        _schedule(); // korvaa 5 min muistutuksen; jos aika on jo kulunut, hälytys heti

        notifyListeners();
        return;
      }
    }
    if (recovered) return;
    final v = hr.bpm, target = hr.recoveryBpm(clock());
    if (v == null || target == null || hr.contact == false || v > target) return;
    // Vähintään 20 s tauosta: heti sarjan jälkeen syke voi vielä olla matala (lyhyt sarja).
    if (total - remaining < 20) return;
    recovered = true;
    HapticFeedback.mediumImpact();
    if (byHr) {
      // Sykkeen mukaan: palautus päättyy nyt. Ajastettu 5 min muistutus perutaan ja lyhyt ponnahdus näytetään.
      _finish(over: true);
      _native('cancel');
      _native('preview', {
        'title': t('Palautunut! 💪'),
        'body': t('Seuraava sarja: {0}', [exerciseLabel(exercise)]),
      });
      onDone?.call(t('❤️ Palautunut – seuraava sarja!'));
    }
  }

  void start(int seconds, String exercise) {
    byHr = hrModeAvailable;
    over = false;
    planned = seconds;
    _hrSeen = clock();
    total = byHr ? hrWaitSeconds : seconds;
    this.exercise = exercise;
    nextFn = null;
    nextText = null;
    _end = clock().add(Duration(seconds: total));
    _schedule();
    _tick?.cancel();
    recovered = false;
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => tick());
    notifyListeners();
  }

  /// Puolen sekunnin välein: aika täynnä tai (sykevyö) palautunut. Testit kutsuvat suoraan.
  @visibleForTesting
  void tick() {
    if (remaining == 0) {
      _finish(over: true); // ei perua natiivi-ilmoitusta: se soi juuri nyt
      onDone?.call(
        byHr
            ? t('❤️ Palautuminen kestää – tarkista syke tai jatka, kun olet valmis.')
            : t('⏱ Palautus ohi – seuraava sarja!'),
      );
    } else {
      _checkRecovered();
      notifyListeners();
    }
  }

  /// Lisää tai vähentää aikaa (−15 s / +15 s). Vähennys ei lopeta ajastinta: vähintään [minLeft] s jää (tai nykyinen,
  /// jos vähemmän). Ennen toistuva −15 s -napautus vei ajan nollaan, palkki katosi sormen alta ja seuraavat
  /// napautukset osuivat alla olevaan Merkitse liike valmiiksi -painikkeeseen (testikierros 15.11.). Lopetus: Ohita.
  static const minLeft = 5;
  void adjust(int seconds) {
    final e = _end;
    if (e == null) return;
    if (seconds < 0) {
      final left = remaining;
      final allowed = left <= minLeft ? 0 : left - minLeft;
      if (-seconds > allowed) seconds = -allowed;
      if (seconds == 0) return;
    }
    _end = e.add(Duration(seconds: seconds));
    total = (total + seconds).clamp(0, 3600);
    if (remaining == 0) {
      stop();
    } else {
      _schedule();
      notifyListeners();
    }
  }

  /// Milloin palkki viimeksi sulkeutui (Ohita tai aika loppui). Palkin alla olevat painikkeet (sarjan tallennus,
  /// Merkitse liike valmiiksi, Treeni valmis) eivät ota napautuksia [tapGuard] ajan: Ohita-tuplanapautuksen toinen
  /// napautus osui alla olevaan painikkeeseen (testikierros 15.11., käyttäjä: 1 s).
  DateTime? closedAt;
  static const tapGuard = Duration(seconds: 1);
  bool get justClosed => closedAt != null && clock().difference(closedAt!) < tapGuard;

  void _finish({bool over = false}) {
    if (_end != null) closedAt = clock();
    _tick?.cancel();
    _tick = null;
    _end = null;
    this.over = over;
    notifyListeners();
  }

  /// Ohita: ajastin ja ilmoitus perutaan.
  void stop() {
    _finish();
    _native('cancel');
  }

  /// Seuraava sarja tallennettiin tai treeni päättyi: "palautus ohi" -tila pois treeni-ilmoituksesta.
  void clearOver() {
    if (!over) return;
    over = false;
    notifyListeners();
  }

  /// Ilmoituslupa annettu (Android 13+): silloin ääni ja värinä tulevat ilmoituksesta.
  static bool notificationsOk = false;

  /// Sykkeen mukaan: hälytys vasta 5 min kohdalla (kohtelias muistutus); palautuminen ilmoitetaan heti sen tapahtuessa.
  void _schedule() => _native('schedule', {
    'seconds': remaining,
    if (byHr) 'title': t('Palautuminen kestää'),
    if (byHr) 'body': t('Syke ei ole vielä laskenut palautumisrajan alle. Tarkista syke tai jatka, kun olet valmis.'),
  });

  /// Androidilla tarkka hälytys ja ilmoitus (ääni, värinä), joka toimii myös näytön ollessa pois päältä tai
  /// toisessa sovelluksessa. Muualla (verkkodemo, testit) vain sovelluksen sisäinen ajastin.
  static bool get native => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _ch = MethodChannel('fi.somby.gievra/rest');

  static Future<void> _native(String method, [Map<String, Object?> args = const {}]) async {
    if (!native) return;
    try {
      await _ch.invokeMethod(method, {
        'title': t('Mennään, tauko ohi! 💪'),
        'body': t('Seuraava sarja: {0}', [exerciseLabel(rest.exercise)]),
        'sound': settings.restSound,
        'channel': t('Palautus ohi'),
        'channelDesc': t('Palautusajastin: sarjojen välinen tauko on ohi'),
        ...args,
      });
    } catch (_) {
      // Ei natiivipuolta (esim. testit): sovelluksen sisäinen ajastin riittää.
    }
  }

  /// Aikasarjan ajastin päättyi: sama ääni ja värinä kuin palautuksen lopussa.
  static Future<void> holdDone(String exercise) =>
      _native('preview', {'title': t('Aika täynnä! 💪'), 'body': exerciseLabel(exercise)});

  /// Äänen esikuuntelu asetuksista.
  static Future<void> preview() => _native('preview', {'body': t('Näin palautusajastin ilmoittaa.')});
}

final rest = RestTimer();
