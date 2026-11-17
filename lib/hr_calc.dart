import 'dart:math' as math;

// Sykekäyrä, sykealueet ja kalorit. Lähteet tarkistettu alkuperäisistä julkaisuista (2026-11-13).
//
// KESTÄVYYSLAJIT (juoksu, kävely, pyöräily …): Keytel LR, Goedecke JH, Noakes TD ym. 2005, "Prediction of energy
// expenditure from heart rate monitoring during submaximal exercise", J Sports Sci 23(3):289–297. Yhtälö ilman
// VO2max-arvoa (kJ/min), johdettu 115 henkilöstä (19–45 v) juoksumatolla ja kuntopyörällä 35–80 % VO2max:sta,
// r = 0,857 mitattuun (epäsuora kalorimetria), riippumattomassa ryhmässä r = 0,77:
//   miehet:  EE = −55,0969 + 0,6309·HR + 0,1988·paino + 0,2017·ikä
//   naiset:  EE = −20,4022 + 0,4472·HR − 0,1263·paino + 0,074·ikä
// Sama artikkeli: syke ja energiankulutus ovat lineaarisessa suhteessa vain noin 90–150/min ("flex heart rate");
// sen alapuolella kulutukseksi oletetaan lepoaineenvaihdunta (Rennie ym. 2001). Siksi alle 90/min ja aina
// vähintään lepotaso. Jokainen 5 s:n jakso lasketaan erikseen ja summataan.
//
// SALI (voimaharjoittelu): sykkeeseen perustuvia kaloriarvioita ei ole todettu luotettaviksi voimaharjoittelussa
// (katsaus: Methods to Assess Energy Expenditure of Resistance Exercise, systematic scoping review, PMC11393209:
// virheet 15–57 % epäsuoraan kalorimetriaan verrattuna, kumpaankin suuntaan); kenttäolosuhteisiin se suosittaa
// MET-menetelmää. 2024 Adult Compendium of Physical Activities (Herrmann ym. 2024):
//   02054  3,5 MET  voimaharjoittelu, useita liikkeitä, 8–15 toistoa
//   02052  5,0 MET  kyykky, maastaveto, hidas tai räjähtävä suoritus
//   02050  6,0 MET  voimaharjoittelu, voimanosto tai kehonrakennus, raskas suoritus
// Taso valitaan sykevyön keskisykkeestä (alle 60 % maksimista 3,5, 60–70 % 5,0, yli 70 % 6,0): tämä raja on
// Gievran oma valinta, ei julkaistu. Compendiumin suosituksen mukaan MET kerrotaan henkilön omalla
// lepoaineenvaihdunnalla ("corrected METs") eikä vakiolla 3,5 ml/kg/min.
//
// KÄVELY, kun vauhti tiedetään (matka ja aika; käyttäjä 17.11.: kävelymatolla 2,5 km/h syke 97 antoi Keytelillä
// 525 kcal, kävelymatto noin kolmanneksen siitä): Ludlow LW, Weyand PG 2016, "Energy expenditure during level human
// walking: seeking a simple and accurate predictive solution", J Appl Physiol 120(5):481–494,
// doi:10.1152/japplphysiol.00864.2015. Johdettu 127 julkaistusta mittauksesta (25 ryhmää, 0,4–1,9 m/s):
//   VO2 = VO2lepo + 3,85 + 5,97 · V² / pituus   (ml O2/kg/min; V m/s; pituus m), keskivirhe noin 1,2 ml/kg/min
// (ACSM:n kävely-yhtälöllä 4,5; se aliarvioi lähes kaikki mittaukset). Lepotaso omasta Mifflin–St Jeor
// -arviosta; 1 l O2 ≈ 5 kcal. Kokonaiskulutus kuten muissakin Gievran arvioissa ja Health Connectin
// TotalCaloriesBurned-tiedossa. Tasamaa: ylämäet eivät näy (kävelymatoilla ei yleensä kallistusta).
// Keytelin yhtälö on johdettu 35–80 %:n VO2max-tasoilta; hidas kävely jää sen alle, ja tulos oli noin kolminkertainen.
//
// LEPOAINEENVAIHDUNTA: Mifflin MD, St Jeor ST ym. 1990, Am J Clin Nutr 51:241–247 (paino, pituus, ikä, sukupuoli):
//   miehet 10·paino + 6,25·pituus − 5·ikä + 5, naiset … − 161 (kcal/vrk).
// MAKSIMISYKE ilman omaa mittausta: Tanaka H ym. 2001, J Am Coll Cardiol 37(1):153–156: 208 − 0,7·ikä.
// SYKEALUEET % maksimista: 50–60, 60–70, 70–80, 80–90, 90–100.

/// Sykekäyrä tasavälein: [values] lyöntiä/min, 0 = ei lukemaa. Tiedostossa yhdellä rivillä:
/// "hr_series: 5 17:32:10 112 115 0 118" (väli s, aloitusaika, arvot).
class HrSeries {
  final DateTime start;
  final int interval;
  final List<int> values;
  const HrSeries(this.start, this.interval, this.values);

  Duration get length => Duration(seconds: interval * values.length);
  Iterable<int> get readings => values.where((v) => v > 0);
  int get readingCount => values.where((v) => v > 0).length;

  /// Puuttuvat lukemat (katko, ei ihokontaktia) sekunteina.
  int get missingSec => values.where((v) => v <= 0).length * interval;

  int? get avg {
    final r = readings.toList();
    return r.isEmpty ? null : (r.reduce((a, b) => a + b) / r.length).round();
  }

  int? get max => readings.isEmpty ? null : readings.reduce(math.max);

  /// Osuus treenin kestosta, jolta on lukema (0–1). Vyö irrotettu tai katkennut yhteys pienentää osuutta.
  double coverage(int durationSec) =>
      durationSec <= 0 ? 0 : (readingCount * interval / durationSec).clamp(0.0, 1.0).toDouble();

  String encode() {
    String two(int v) => v.toString().padLeft(2, '0');
    return '$interval ${two(start.hour)}:${two(start.minute)}:${two(start.second)} ${values.join(' ')}';
  }

  /// [date]: treenin päivä (aloitusajan päivämäärä).
  static HrSeries? decode(String s, DateTime date) {
    final p = s.trim().split(RegExp(r'\s+'));
    if (p.length < 3) return null;
    final interval = int.tryParse(p[0]);
    final hms = p[1].split(':').map(int.tryParse).toList();
    if (interval == null || interval <= 0 || hms.length != 3 || hms.contains(null)) return null;
    final values = <int>[];
    for (final v in p.skip(2)) {
      final n = int.tryParse(v);
      if (n == null) return null;
      values.add(n.clamp(0, 300));
    }
    return HrSeries(DateTime(date.year, date.month, date.day, hms[0]!, hms[1]!, hms[2]!), interval, values);
  }

  /// Lukemista (aika, syke) tasavälinen käyrä: jakson keskiarvo, 0 jos jaksossa ei lukemaa.
  static HrSeries? fromSamples(List<(DateTime, int)> samples, {int interval = 5, DateTime? start, DateTime? end}) {
    if (samples.isEmpty) return null;
    final s0 = start ?? samples.first.$1;
    final e = end ?? samples.last.$1;
    final n = math.max(1, (e.difference(s0).inMilliseconds / 1000 / interval).ceil());
    final sum = List<int>.filled(n, 0), cnt = List<int>.filled(n, 0);
    for (final (t, v) in samples) {
      final i = (t.difference(s0).inMilliseconds / 1000 / interval).floor();
      if (i < 0 || i >= n) continue;
      sum[i] += v;
      cnt[i]++;
    }
    return HrSeries(s0, interval, [for (var i = 0; i < n; i++) cnt[i] == 0 ? 0 : (sum[i] / cnt[i]).round()]);
  }
}

/// Kalorilaskennan tiedot: syntymävuosi, sukupuoli, pituus ja paino.
class HrProfile {
  final int birthYear, heightCm;
  final double weightKg;
  final bool male;

  /// Käyttäjän oma korjaus kaloreihin −10…+10 % (oletus 0 = julkaistu yhtälö sellaisenaan).
  final int adjustPct;

  /// Oma mitattu maksimisyke; null = arvio iästä.
  final int? maxHrOverride;
  const HrProfile({
    this.maxHrOverride,
    required this.birthYear,
    required this.male,
    required this.heightCm,
    required this.weightKg,
    this.adjustPct = 0,
  });

  double get _adj => 1 + adjustPct / 100;

  int ageAt(DateTime d) => d.year - birthYear;

  /// Tanaka 2001.
  int maxHr(DateTime d) => maxHrOverride ?? (208 - 0.7 * ageAt(d)).round();

  /// Maksimisyke on käyttäjän itse mittaama (ei arvio iästä).
  bool get maxHrMeasured => maxHrOverride != null;

  /// Lepoaineenvaihdunta kcal/min (Mifflin–St Jeor).
  double restKcalPerMin(DateTime d) => (10 * weightKg + 6.25 * heightCm - 5 * ageAt(d) + (male ? 5 : -161)) / 1440;

  /// Energiankulutus kcal/min sykkeellä [hr] (Keytel 2005); alle 90/min ja vähintään lepotaso.
  double kcalPerMin(int hr, DateTime d) {
    final rest = restKcalPerMin(d);
    if (hr < flexHr) return rest;
    final a = ageAt(d);
    final kj = male
        ? -55.0969 + 0.6309 * hr + 0.1988 * weightKg + 0.2017 * a
        : -20.4022 + 0.4472 * hr - 0.1263 * weightKg + 0.074 * a;
    return math.max(kj / 4.184, rest);
  }

  /// Kestävyyslaji: koko käyrän kalorit, jokainen jakso omalla sykkeellään, lukemattomat lepotasolla.
  int kcalEndurance(HrSeries s) {
    var total = 0.0;
    for (final v in s.values) {
      final perMin = v > 0 ? kcalPerMin(v, s.start) : restKcalPerMin(s.start);
      total += perMin * s.interval / 60;
    }
    return (total * _adj).round();
  }

  /// Kestävyyslaji, kun lukemia puuttuu (vyön akku loppui, yhteys katkesi): mitatun osan keskimääräinen kulutus
  /// minuutissa kerrotaan koko treenin kestolla [durationSec]. Ilman tätä esim. 60 min lenkki, jonka 10. minuutilla
  /// vyö sammui, saisi vain 10 minuutin kalorit. Gievran oma arvio (puuttuva aika oletetaan samanlaiseksi kuin
  /// mitattu); käytetään, kun lukemia on alle 95 % kestosta ja vähintään minuutti.
  int kcalEnduranceFor(HrSeries s, int? durationSec) {
    final readSec = s.readingCount * s.interval;
    if (durationSec == null || readSec < 60 || readSec >= durationSec * .95) return kcalEndurance(s);
    var measured = 0.0;
    for (final v in s.values) {
      if (v > 0) measured += kcalPerMin(v, s.start) * s.interval / 60;
    }
    return (measured / readSec * durationSec * _adj).round();
  }

  /// Kävely tai juoksu matkasta ja ajasta (ACSM:n metaboliset yhtälöt, ACSM's Guidelines for Exercise Testing
  /// and Prescription): VO2 = 3,5 + 0,1 × nopeus (kävely) tai 0,2 × nopeus (juoksu) ml/kg/min, nopeus m/min;
  /// 1 l O2 ≈ 5 kcal. Käytetään, kun sykettä on alle puolelta treenistä (vyö katkesi): pienestä otoksesta
  /// ekstrapoloitu syke ei kuvaa koko lenkkiä.
  int kcalFromSpeed({required bool run, required double km, required int seconds}) {
    final minutes = seconds / 60;
    if (minutes <= 0 || km <= 0) return 0;
    final mPerMin = km * 1000 / minutes;
    final vo2 = 3.5 + (run ? 0.2 : 0.1) * mPerMin;
    return (vo2 * weightKg / 1000 * 5 * minutes * _adj).round();
  }

  /// Lepo-VO2 (ml/kg/min) omasta lepoaineenvaihdunnasta (Mifflin–St Jeor; 1 l O2 ≈ 5 kcal).
  double restVo2(DateTime d) => restKcalPerMin(d) / 5 / weightKg * 1000;

  /// Kävelyn nopeusalue, jolta Ludlow & Weyand 2016 -yhtälö on johdettu (m/s).
  static const walkMinMs = .4, walkMaxMs = 1.9;

  /// Kävely matkasta ja ajasta (Ludlow & Weyand 2016, ks. tiedoston alku): kokonaiskulutus kcal, tai null, jos
  /// vauhti on yhtälön alueen ulkopuolella (esim. väärä matka) tai pituus puuttuu.
  int? kcalWalk({required double km, required int seconds, required DateTime date}) {
    if (seconds <= 0 || km <= 0 || heightCm <= 0) return null;
    final v = km * 1000 / seconds;
    if (v < walkMinMs || v > walkMaxMs) return null;
    final vo2 = restVo2(date) + 3.85 + 5.97 * v * v / (heightCm / 100);
    return (vo2 * weightKg / 1000 * 5 * seconds / 60 * _adj).round();
  }

  /// Sali: Compendiumin MET sykevyön keskisykkeen mukaan (ks. tiedoston alku).
  double gymMet(HrSeries s) {
    final a = s.avg;
    if (a == null) return 3.5;
    final pct = a / maxHr(s.start);
    return pct >= .7 ? 6.0 : (pct >= .6 ? 5.0 : 3.5);
  }

  /// Sali: MET × oma lepoaineenvaihdunta × kesto.
  int kcalGym(HrSeries s, int minutes) => (gymMet(s) * restKcalPerMin(s.start) * minutes * _adj).round();
}

/// Syke, jonka alapuolella kulutus = lepotaso (Keytel 2005: lineaarinen noin 90–150/min).
const flexHr = 90;

/// Aika (s) kullakin viidellä sykealueella (50–60 … 90–100 % maksimista); alle 50 % ei lasketa.
List<int> zoneSeconds(HrSeries s, int maxHr) {
  final out = List<int>.filled(5, 0);
  for (final v in s.values) {
    if (v <= 0) continue;
    final pct = v / maxHr;
    if (pct < .5) continue;
    out[math.min(4, ((pct - .5) / .1).floor())] += s.interval;
  }
  return out;
}

/// Sykealue 0–4 (alue 1–5) tai null alle 50 %:n.
int? zoneOf(int bpm, int maxHr) {
  final pct = bpm / maxHr;
  if (pct < .5) return null;
  return math.min(4, ((pct - .5) / .1).floor());
}

/// Sykealueiden nimet (suomeksi; käännetään näkymässä).
// l10n: data
const zoneNames = ['Palauttava', 'Kevyt', 'Kestävyys', 'Kynnys', 'Maksimi'];
