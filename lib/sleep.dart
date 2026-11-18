// Uni-kortti (käyttäjä 17.11.; valinnainen, oletus pois): yöunet Health Connectista uni.md-tiedostoon ja etusivun
// kortti. Vain luku: Gievra ei kirjoita Health Connectiin. Tallennus omaan tiedostoon, jotta yöt säilyvät
// varmuuskopioissa ja vientitiedostoissa, vaikka Health Connect antaa yleensä vain noin 30 päivää ennen luvan
// antamista.
//
// Tutkimuspohja (vain vihjeitä, ei automaattisia painomuutoksia eikä diagnoosia):
// - AASM ja SRS 2015 (Watson ym., Sleep): aikuisille 7 tuntia tai enemmän säännöllisesti.
// - Craven ym. 2022 (Sports Medicine, meta-analyysi): enintään 6 tunnin uni heikentää suoritusta keskimäärin noin
//   7,5 %; enemmän illalla ja taitolajeissa, voimassa vähän.
// - Windred ym. 2024 (Sleep, UK Biobank): unen säännöllisyys ennusti kuolleisuutta (havainnoiva tutkimus).
// - Mishra ym. 2020 (Nature Biomedical Engineering), Radin ym. 2020 (Lancet Digital Health): leposyke omaan
//   28 päivän tasoon verrattuna nousi usein ennen sairauden oireita.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'health.dart';
import 'models.dart';

const sleepFileName = 'uni.md';

/// Ensimmäinen haku ja tavallinen taso: 30 yötä (noin se, minkä Health Connect antaa ilman historialupaa).
const sleepFirstDays = 30;

/// Joka haulla luetaan uudelleen viimeiset yöt (Oura synkronoi usein vasta aamulla tai myöhemmin).
const sleepRefreshDays = 3;

/// Vanhempi unihistoria (asetusten painike, historialupa).
const sleepHistoryDays = 731;

/// Lyhyempi kuin tämä on päiväunet (ei yöuni).
const _minNight = Duration(hours: 3);

/// Saman sovelluksen jaksot yhdeksi yöksi, jos väli on enintään tämä (heräsi yöllä).
const _joinGap = Duration(hours: 2);

/// Health Connectin unijakso.
class SleepSession {
  final DateTime start, end;
  final Duration awake;
  final String app;
  final int? lowHr;
  const SleepSession(this.start, this.end, {this.awake = Duration.zero, this.app = '', this.lowHr});
}

/// Yksi yö: [day] = herätyspäivä.
class SleepNight {
  final DateTime day, bed, wake;
  final Duration asleep;
  final int? lowHr;
  final String app;
  const SleepNight(this.day, this.bed, this.wake, this.asleep, {this.lowHr, this.app = ''});

  @override
  bool operator ==(Object other) =>
      other is SleepNight &&
      other.day == day &&
      other.bed == bed &&
      other.wake == wake &&
      other.asleep == asleep &&
      other.lowHr == lowHr &&
      other.app == app;
  @override
  int get hashCode => Object.hash(day, bed, wake, asleep, lowHr, app);
  @override
  String toString() => 'SleepNight(${isoDate(day)} ${_hm(bed)}–${_hm(wake)} ${asleep.inMinutes} min $lowHr $app)';
}

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Unijaksot öiksi: herätyspäivää kohden yksi yö. Saman sovelluksen peräkkäiset jaksot (väli enintään 2 h)
/// yhdistetään, alle 3 tunnin jaksot ovat päiväunia. Usea sovellus (esim. Oura, Fitbit ja Health Sync kirjaavat
/// saman yön): käytetään sovellusta, jolla on eniten öitä, ja vain sen puuttuessa muuta. [prefer] = sovellus, jolla
/// on jo eniten tallennettuja öitä: se voittaa aina (muuten 3 yön päivityshaussa tasapeli ratkesi aakkosilla ja
/// lähde vaihtui kesken historian, esim. Oura → Fitbit).
Map<DateTime, SleepNight> nightsFrom(List<SleepSession> sessions, {String? prefer}) {
  final byApp = <String, List<SleepSession>>{};
  for (final s in sessions) {
    if (!s.end.isAfter(s.start)) continue;
    byApp.putIfAbsent(s.app, () => []).add(s);
  }
  final perApp = <String, Map<DateTime, SleepNight>>{};
  for (final e in byApp.entries) {
    final list = e.value..sort((a, b) => a.start.compareTo(b.start));
    final blocks = <List<SleepSession>>[];
    for (final s in list) {
      if (blocks.isNotEmpty) {
        final lastEnd = blocks.last.map((x) => x.end).reduce((a, b) => a.isAfter(b) ? a : b);
        if (!s.start.isAfter(lastEnd.add(_joinGap))) {
          blocks.last.add(s);
          continue;
        }
      }
      blocks.add([s]);
    }
    final nights = <DateTime, SleepNight>{};
    for (final b in blocks) {
      final bed = b.first.start;
      final wake = b.map((x) => x.end).reduce((a, c) => a.isAfter(c) ? a : c);
      if (wake.difference(bed) < _minNight) continue;
      var asleep = Duration.zero;
      for (final s in b) {
        final d = s.end.difference(s.start) - s.awake;
        if (d > Duration.zero) asleep += d;
      }
      // Päällekkäiset jaksot (sama yö kahdesti, esim. uudelleensynkronointi): uni ei voi olla yötä pidempi.
      if (asleep > wake.difference(bed)) asleep = wake.difference(bed);
      final lows = [for (final s in b) ?s.lowHr];
      final n = SleepNight(
        dateOnly(wake),
        bed,
        wake,
        asleep,
        lowHr: lows.isEmpty ? null : lows.reduce(math.min),
        app: e.key,
      );
      final old = nights[n.day];
      if (old == null || n.asleep > old.asleep) nights[n.day] = n;
    }
    perApp[e.key] = nights;
  }
  if (perApp.isEmpty) return {};
  final apps = perApp.keys.toList()
    ..sort((a, b) {
      if (a == prefer || b == prefer) return a == prefer ? -1 : 1;
      final c = perApp[b]!.length.compareTo(perApp[a]!.length);
      return c != 0 ? c : a.compareTo(b);
    });
  final out = <DateTime, SleepNight>{};
  for (final a in apps) {
    for (final n in perApp[a]!.values) {
      out.putIfAbsent(n.day, () => n);
    }
  }
  return out;
}

String sleepToMarkdown(Map<DateTime, SleepNight> nights) {
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('tags: [uni]')
    ..writeln('---')
    ..writeln()
    ..writeln('# Uni')
    ..writeln()
    ..writeln('Yöunet Health Connectista: herätyspäivä, nukkumaan–herätys, uni ilman valveillaoloa, yön alin syke')
    ..writeln('(alin 15 minuutin keskiarvo unen aikana) ja sovellus. Yksi lähde yötä kohden.')
    ..writeln();
  final keys = nights.keys.toList()..sort((a, c) => c.compareTo(a));
  for (final d in keys) {
    final n = nights[d]!;
    final m = n.asleep.inMinutes;
    b.writeln(
      '- ${isoDate(d)}: ${_hm(n.bed)}–${_hm(n.wake)}, ${m ~/ 60} h ${_two(m % 60)} min'
      '${n.lowHr == null ? '' : ', syke ${n.lowHr}'}${n.app.isEmpty ? '' : ' (${n.app})'}',
    );
  }
  return b.toString();
}

/// uni.md: tuntemattomat ja virheelliset rivit ohitetaan. Nukkumaanmeno edellisenä päivänä, jos kellonaika on
/// herätystä myöhemmin.
Map<DateTime, SleepNight> parseSleep(String text) {
  final out = <DateTime, SleepNight>{};
  final re = RegExp(
    r'^[-*]\s*(\d{4}-\d{2}-\d{2}):\s*(\d{1,2}):(\d{2})\s*[–-]\s*(\d{1,2}):(\d{2}),\s*(\d+)\s*h\s*(\d+)\s*min'
    r'(?:,\s*syke\s*(\d+))?\s*(?:\((.*)\))?\s*$',
  );
  for (final line in text.split('\n')) {
    final m = re.firstMatch(line.trim());
    if (m == null) continue;
    final d = DateTime.tryParse(m[1]!);
    if (d == null || isoDate(d) != m[1]) continue;
    final bh = int.parse(m[2]!), bm = int.parse(m[3]!), wh = int.parse(m[4]!), wm = int.parse(m[5]!);
    final h = int.parse(m[6]!), mi = int.parse(m[7]!);
    if (bh > 23 || wh > 23 || bm > 59 || wm > 59 || mi > 59 || h > 23) continue;
    final wake = DateTime(d.year, d.month, d.day, wh, wm);
    var bed = DateTime(d.year, d.month, d.day, bh, bm);
    if (bed.isAfter(wake)) bed = DateTime(d.year, d.month, d.day - 1, bh, bm);
    final hr = m[8] == null ? null : int.tryParse(m[8]!);
    out[d] = SleepNight(
      d,
      bed,
      wake,
      Duration(minutes: h * 60 + mi),
      lowHr: hr != null && hr >= 25 && hr <= 220 ? hr : null,
      app: (m[9] ?? '').trim(),
    );
  }
  return out;
}

/// Kortin luvut [today]-päivälle.
class SleepStats {
  /// Viimeisin yö (null, jos yli 2 päivää sitten).
  final SleepNight? last;

  /// 7 viimeisen päivän yöt: keskiarvo, alle 7 tunnin yöt ja öiden määrä.
  final Duration? avg7;
  final int short7, n7;

  /// Tavallinen taso: mediaani öistä 8–35 päivää sitten (vähintään 7 yötä).
  final Duration? usual;

  /// Säännöllisyys 14 päivältä (vähintään 4 yötä): nukkumaanmenon ja herätyksen keskihajonta minuutteina.
  /// Rajat (Huang ym. 2020, JACC): ≤ 30 min säännöllinen, 31–90 vaihteleva, yli 90 epäsäännöllinen.
  final int? bedSpread, wakeSpread;

  /// Univaje 7 päivältä omaan tavoitteeseen verrattuna.
  final Duration debt7;

  const SleepStats({
    this.debt7 = Duration.zero,
    this.last,
    this.avg7,
    this.short7 = 0,
    this.n7 = 0,
    this.usual,
    this.bedSpread,
    this.wakeSpread,
  });
}

int? _spread(List<int> minutes) {
  if (minutes.length < 4) return null;
  final mean = minutes.reduce((a, b) => a + b) / minutes.length;
  final v = minutes.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / minutes.length;
  return math.sqrt(v).round();
}

/// Oma unitavoite (Walsh ym. 2021, BJSM: yksilöllinen tavoite; oletus AASM:n 7 h).
const defaultSleepGoal = Duration(hours: 7);

SleepStats sleepStats(Map<DateTime, SleepNight> nights, DateTime today, {Duration goal = defaultSleepGoal}) {
  final t = dateOnly(today);
  final days = nights.keys.toList()..sort();
  final lastDay = days.lastOrNull;
  final last = lastDay != null && daysBetween(lastDay, t) <= 2 ? nights[lastDay] : null;
  final week = [
    for (final d in days)
      if (!d.isBefore(addDays(t, -6)) && !d.isAfter(t)) nights[d]!,
  ];
  // Säännöllisyys 14 yöltä (Fischer ym. 2021: keskihajonta tarvitsee yli viikon ollakseen harhaton).
  final fortnight = [
    for (final d in days)
      if (!d.isBefore(addDays(t, -13)) && !d.isAfter(t)) nights[d]!,
  ];
  final older = [
    for (final d in days)
      if (!d.isBefore(addDays(t, -34)) && d.isBefore(addDays(t, -6))) nights[d]!.asleep.inMinutes,
  ]..sort();
  int? usual;
  if (older.length >= 7) {
    final m = older.length ~/ 2;
    usual = older.length.isOdd ? older[m] : ((older[m - 1] + older[m]) / 2).round();
  }
  // Kellonajat minuutteina klo 12:sta, jotta keskiyö ei katkaise (23.30 ja 0.30 ovat tunnin päässä).
  int fromNoon(DateTime d) => ((d.hour - 12) % 24) * 60 + d.minute;
  return SleepStats(
    last: last,
    avg7: week.isEmpty
        ? null
        : Duration(minutes: (week.map((n) => n.asleep.inMinutes).reduce((a, b) => a + b) / week.length).round()),
    short7: week.where((n) => n.asleep < goal).length,
    // Univaje 7 päivältä: tavoitteen alitukset yhteensä (kuvaava, ei validoitu mittari).
    debt7: Duration(minutes: week.fold(0, (a, n) => a + math.max(0, goal.inMinutes - n.asleep.inMinutes))),
    n7: week.length,
    usual: usual == null ? null : Duration(minutes: usual),
    bedSpread: _spread([for (final n in fortnight) fromNoon(n.bed)]),
    wakeSpread: _spread([for (final n in fortnight) fromNoon(n.wake)]),
  );
}

/// Vihjeen laji: lyhyt yö (≤ 6 h) ja lisäksi koholla oleva yösyke, lyhyt yö, viikon keskiarvo alle 7 h tai kunnossa.
enum SleepHint { shortAndHr, short, lowWeek, ok }

SleepHint sleepHint(SleepStats s, {double? hrDelta, Duration goal = defaultSleepGoal}) {
  final last = s.last;
  if (last != null && last.asleep <= const Duration(hours: 6)) {
    return (hrDelta ?? 0) >= 5 ? SleepHint.shortAndHr : SleepHint.short;
  }
  if (s.avg7 != null && s.n7 >= 4 && s.avg7! < goal) return SleepHint.lowWeek;
  return SleepHint.ok;
}

/// HRV-vihje vasta, kun 7 yön keskiarvo on ollut omaa vaihteluväliä alempana kahtena päivänä peräkkäin (yötesti
/// 18.11. käyttäjän omilla tiedoilla: 45 → 34 liputettua päivää vuodessa; yksittäiset päivät jäävät pois, oikeat
/// jaksot säilyvät). Javaloyes ym. 2019 (IJSPP): sama 0,5 SD:n vaihteluväli päivittäisen treenin ohjaukseen.
bool hrvLowSustained(Map<DateTime, NightMetrics> m, DateTime today) {
  final st = metricStat(m, 'hrv', today);
  if (st == null || metricFlag('hrv', st) != 1) return false;
  final y = addDays(dateOnly(st.lastDay), -1);
  final before = {
    for (final e in m.entries)
      if (!e.key.isAfter(y)) e.key: e.value,
  };
  final prev = metricStat(before, 'hrv', y);
  return prev != null && metricFlag('hrv', prev) == 1;
}

/// Myöhäinen kova treeni (käyttäjä 18.11.): edellisenä iltana kova treeni päättyi alle tunti ennen OMAA tavallista
/// nukkumaanmenoa (tai sen jälkeen), ja yö jäi selvästi tavallista lyhyemmäksi. Stutz ym. 2019 (Sports Med,
/// meta-analyysi): iltaliikunta ei yleensä haittaa unta, mutta kova treeni, joka päättyy alle tunti ennen
/// nukkumaanmenoa, voi pidentää nukahtamista ja lyhentää unta. Näytetään vain, kun yö oikeasti jäi lyhyeksi, ettei
/// vihje lisää stressiä turhaan.
class LateWorkout {
  final DateTime end, usualBed;
  final Duration asleep, usual;
  const LateWorkout(this.end, this.usualBed, this.asleep, this.usual);

  /// Minuutteja ennen tavallista nukkumaanmenoa (negatiivinen = sen jälkeen).
  int get minutesBefore => usualBed.difference(end).inMinutes;
}

/// Tavallinen nukkumaanmenoaika minuutteina keskipäivästä (mediaani öistä 8–35 päivää ennen [day]; vähintään 7).
int? usualBedMinutes(Map<DateTime, SleepNight> nights, DateTime day) {
  final from = addDays(day, -35), to = addDays(day, -7);
  final xs = [
    for (final n in nights.values)
      if (!n.day.isBefore(from) && n.day.isBefore(to))
        n.bed.difference(DateTime(n.day.year, n.day.month, n.day.day - 1, 12)).inMinutes,
  ]..sort();
  if (xs.length < 7) return null;
  final m = xs.length ~/ 2;
  return xs.length.isOdd ? xs[m] : ((xs[m - 1] + xs[m]) / 2).round();
}

/// Kova treeni: kirjattu rasitus Kova, keskisyke vähintään 77 % maksimista ([maxHr]) tai salissa vähintään 3
/// työsarjaa 0–1 toiston varalla.
bool hardWorkout(Workout w, {int? maxHr}) {
  if (w.intensity == 'kova') return true;
  if (w.intensity == 'kevyt') return false;
  if (maxHr != null && maxHr > 0 && w.hrAvg != null && w.hrAvg! / maxHr >= .77) return true;
  var hard = 0;
  for (final e in w.exercises) {
    for (final st in e.sets) {
      if (!st.warmup && st.rir != null && st.rir! <= 1) hard++;
    }
  }
  return hard >= 3;
}

LateWorkout? lateHardWorkout(SleepStats s, Map<DateTime, SleepNight> nights, List<Workout> ws, {int? maxHr}) {
  final last = s.last, usual = s.usual;
  if (last == null || usual == null || last.asleep > usual - const Duration(minutes: 30)) return null;
  final bedMin = usualBedMinutes(nights, last.day);
  if (bedMin == null) return null;
  final usualBed = DateTime(last.day.year, last.day.month, last.day.day - 1, 12).add(Duration(minutes: bedMin));
  LateWorkout? out;
  for (final w in ws) {
    final st = w.started, dur = w.durationSec;
    if (st == null || dur == null || !hardWorkout(w, maxHr: maxHr)) continue;
    final end = st.add(Duration(seconds: dur));
    // Päättyi alle tunti ennen tavallista nukkumaanmenoa (tai myöhemmin), mutta ennen kuin meni nukkumaan.
    if (end.isBefore(usualBed.subtract(const Duration(minutes: 60))) || !end.isBefore(last.bed)) continue;
    if (out == null || end.isAfter(out.end)) out = LateWorkout(end, usualBed, last.asleep, usual);
  }
  return out;
}

/// Yön mittaukset (Yöarvot-kortti, käyttäjä 17.11.): HRV (RMSSD, ms), happisaturaatio (%, keskiarvo ja alin),
/// hengitystiheys (/min), ihon lämpötilan poikkeama (°C kellon omasta tasosta) ja leposyke (bpm).
class NightMetrics {
  final double? hrv, spo2, spo2Min, rr, temp, rest;
  const NightMetrics({this.hrv, this.spo2, this.spo2Min, this.rr, this.temp, this.rest});
  bool get isEmpty => hrv == null && spo2 == null && rr == null && temp == null && rest == null;

  double? of(String k) => switch (k) {
    'hrv' => hrv,
    'spo2' => spo2,
    'rr' => rr,
    'temp' => temp,
    'rest' => rest,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is NightMetrics &&
      other.hrv == hrv &&
      other.spo2 == spo2 &&
      other.spo2Min == spo2Min &&
      other.rr == rr &&
      other.temp == temp &&
      other.rest == rest;
  @override
  int get hashCode => Object.hash(hrv, spo2, spo2Min, rr, temp, rest);
}

/// Yöarvojen tunnisteet näyttöjärjestyksessä (asetus night_tiles).
const nightMetricKeys = ['hrv', 'rest', 'rr', 'spo2', 'temp'];

String _dec(double v, int digits) => v.toStringAsFixed(digits).replaceAll('.', ',');

String metricsToMarkdown(Map<DateTime, NightMetrics> m) {
  final b = StringBuffer()
    ..writeln()
    ..writeln('## Yöarvot')
    ..writeln()
    ..writeln('HRV (ms), happisaturaatio (% ja alin), hengitystiheys (/min), ihon lämpötilan poikkeama (°C) ja')
    ..writeln('leposyke Health Connectista, yön ajalta.')
    ..writeln();
  final keys = m.keys.toList()..sort((a, c) => c.compareTo(a));
  for (final d in keys) {
    final n = m[d]!;
    final parts = [
      if (n.hrv != null) 'hrv ${_dec(n.hrv!, 0)}',
      if (n.spo2 != null) 'spo2 ${_dec(n.spo2!, 1)}${n.spo2Min == null ? '' : ' (alin ${_dec(n.spo2Min!, 1)})'}',
      if (n.rr != null) 'hengitys ${_dec(n.rr!, 1)}',
      if (n.temp != null) 'lämpö ${n.temp! >= 0 ? '+' : ''}${_dec(n.temp!, 2)}',
      if (n.rest != null) 'leposyke ${_dec(n.rest!, 0)}',
    ];
    if (parts.isNotEmpty) b.writeln('- ${isoDate(d)}: ${parts.join(', ')}');
  }
  return b.toString();
}

/// Yöarvot uni.md:n Yöarvot-osiosta (rivit, joissa ei ole kellonaikaväliä).
Map<DateTime, NightMetrics> parseMetrics(String text) {
  final out = <DateTime, NightMetrics>{};
  final line = RegExp(r'^[-*]\s*(\d{4}-\d{2}-\d{2}):\s*(.+)$');
  double? num(String s) => double.tryParse(s.replaceAll(',', '.'));
  for (final raw in text.split('\n')) {
    final m = line.firstMatch(raw.trim());
    if (m == null || RegExp(r'\d:\d\d\s*[–-]').hasMatch(m[2]!)) continue;
    final d = DateTime.tryParse(m[1]!);
    if (d == null || isoDate(d) != m[1]) continue;
    double? hrv, spo2, spo2Min, rr, temp, rest;
    for (final kv in RegExp(
      r'(hrv|spo2|hengitys|lämpö|leposyke)\s+([+-]?\d+(?:[.,]\d+)?)(?:\s*\(alin\s+(\d+(?:[.,]\d+)?)\))?',
    ).allMatches(m[2]!)) {
      final v = num(kv[2]!);
      if (v == null) continue;
      switch (kv[1]) {
        case 'hrv':
          if (v > 0 && v < 400) hrv = v;
        case 'spo2':
          if (v >= 50 && v <= 100) {
            spo2 = v;
            spo2Min = kv[3] == null ? null : num(kv[3]!);
          }
        case 'hengitys':
          if (v > 3 && v < 60) rr = v;
        case 'lämpö':
          if (v.abs() < 5) temp = v;
        case 'leposyke':
          if (v >= 25 && v <= 150) rest = v;
      }
    }
    final n = NightMetrics(hrv: hrv, spo2: spo2, spo2Min: spo2Min, rr: rr, temp: temp, rest: rest);
    if (!n.isEmpty) out[d] = n;
  }
  return out;
}

/// Yhden yöarvon tila omaan tasoon verraten (rajat tutkimuksista, ks. [metricFlag]): viimeisin yö, viimeisimmät
/// yöt (HRV: 7 yön keskiarvo logaritmina, muut: 3 viimeistä yötä), tavallinen taso ja hajonta vertailujaksolta
/// ennen niitä (HRV 60, lämpötila 40, muut 28 yötä), vertailuöiden määrä.
class MetricStat {
  final DateTime lastDay;
  final double last, recent;
  final List<double> lastNights; // uusin viimeisenä
  final double? usual, sd;
  final int n;

  /// Onko edellisen päivän yö tallessa (hengitystiheyden "kaksi yötä peräkkäin": väliin jäänyt yö ei kelpaa).
  final bool prevDay;

  /// Montako yötä [recent]-keskiarvossa (HRV: 7 viimeisen päivän ajalta).
  final int recentN;
  const MetricStat(
    this.lastDay,
    this.last,
    this.recent,
    this.lastNights,
    this.usual,
    this.sd,
    this.n, {
    this.prevDay = true,
    this.recentN = 3,
  });
  double? get delta => usual == null ? null : recent - usual!;
}

/// Vähintään näin monta vertailuyötä ennen kuin arvoa verrataan omaan tasoon (Altini & Plews 2021, Mishra 2020).
const metricMinNights = 14;

/// HRV:n (ln RMSSD) hajonnan alaraja vertailussa.
const hrvMinSd = 0.05;

MetricStat? metricStat(Map<DateTime, NightMetrics> m, String key, DateTime today) {
  final days = [
    for (final e in m.entries)
      if (e.value.of(key) != null) e.key,
  ]..sort();
  if (days.isEmpty) return null;
  final lastDay = days.last;
  if (daysBetween(lastDay, today) > 3) return null;
  double v(DateTime d) => m[d]!.of(key)!;
  final hrv = key == 'hrv';
  double tr(double x) => hrv ? math.log(math.max(x, 1)) : x;
  final recentLen = hrv ? 7 : 3;
  final recentDays = days.where((d) => !d.isBefore(addDays(lastDay, -(recentLen - 1)))).toList();
  final recent = recentDays.map((d) => tr(v(d))).reduce((a, b) => a + b) / recentDays.length;
  final window = switch (key) {
    'hrv' => 60,
    'temp' => 40,
    _ => 28,
  };
  final from = addDays(recentDays.first, -window);
  final older = [
    for (final d in days)
      if (!d.isBefore(from) && d.isBefore(recentDays.first)) tr(v(d)),
  ]..sort();
  double? usual, sd;
  if (older.isNotEmpty) {
    final mean = older.reduce((a, b) => a + b) / older.length;
    final mid = older.length ~/ 2;
    // HRV: keskiarvo (ln RMSSD, Plews ym.); muut: mediaani (yksittäiset sairauspäivät eivät siirrä tasoa).
    usual = hrv ? mean : (older.length.isOdd ? older[mid] : (older[mid - 1] + older[mid]) / 2);
    sd = math.sqrt(older.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / older.length);
  }
  final last3 = [for (final d in days.where((d) => !d.isBefore(addDays(lastDay, -2)))) v(d)];
  return MetricStat(
    lastDay,
    v(lastDay),
    recent,
    last3,
    usual,
    sd,
    older.length,
    prevDay: m[addDays(lastDay, -1)]?.of(key) != null,
    recentN: recentDays.length,
  );
}

/// Tavallinen taso näytettäväksi (HRV logaritmista takaisin millisekunneiksi).
double? metricUsual(String key, MetricStat s) => s.usual == null ? null : (key == 'hrv' ? math.exp(s.usual!) : s.usual);

/// Poikkeaako arvo omasta tasosta: 1 = kyllä (huonompaan suuntaan), 0 = ei, -1 = liian vähän öitä vertailuun.
/// Rajat (vain vihjeitä, ei diagnoosia):
/// - HRV: 7 yön ln RMSSD -keskiarvo alle 60 yön tason − 0,5 keskihajontaa (Plews ym. 2012/2013, Buchheit 2014).
/// - Leposyke: 3 yön keskiarvo vähintään +5 lyöntiä tai +2 keskihajontaa 28 yön tasosta (Mishra 2020, Quer 2020).
/// - Hengitystiheys: yö vähintään +3 /min tai kaksi yötä peräkkäin +2 /min (Natarajan ym. 2021, Miller ym. 2020).
/// - Ihon lämpötila: vähintään +0,5 °C 40 yön tasosta (Smarr ym. 2020, Mason ym. 2022).
/// - Happisaturaatio: kolme yötä vähintään 2 prosenttiyksikköä alle oman tason tai alle 92 % (Shapiro ym. 2023);
///   kuluttajalaitteen virhe on noin ±3 %, joten vain kehotus seurata.
int metricFlag(String key, MetricStat s) {
  if (s.usual == null || s.n < metricMinNights) return -1;
  final u = s.usual!, sd = s.sd ?? 0;
  final l = s.lastNights;
  return switch (key) {
    // Yötesti 18.11.: vähintään 3 yötä viimeisestä viikosta (yksi yö ei ole viikon keskiarvo) ja hajonnalle
    // alaraja 0,05 ln-yksikköä (≈ 5 %): täysin tasainen vertailujakso ei saa liputtaa pientäkään laskua.
    'hrv' => s.recentN >= 3 && s.recent < u - 0.5 * math.max(sd, hrvMinSd) ? 1 : 0,
    'rest' => (s.recent - u >= 5 || (sd > 0 && s.recent - u >= 2 * sd)) ? 1 : 0,
    'rr' => (s.last - u >= 3 || (s.prevDay && l.length >= 2 && l.reversed.take(2).every((x) => x - u >= 2))) ? 1 : 0,
    'temp' => s.last - u >= 0.5 ? 1 : 0,
    'spo2' => ((l.length >= 3 && l.every((x) => x <= u - 2)) || (l.length >= 3 && l.every((x) => x < 92))) ? 1 : 0,
    _ => 0,
  };
}

/// Uni-kortin tiedot: uni.md, Health Connect -haku ja varmuuskopion yhdistäminen.
class SleepData extends ChangeNotifier {
  final Map<DateTime, SleepNight> nights = {};

  /// Yöarvot (Yöarvot-kortti): uni.md:n Yöarvot-osio.
  final Map<DateTime, NightMetrics> metrics = {};
  bool loading = false, needsPermission = false, _loaded = false;

  /// Testeille: korvaa yöarvojen haun.
  Future<Map<DateTime, NightMetrics>> Function(Map<DateTime, (DateTime, DateTime)> windows)? debugMetrics;

  bool get metricsEnabled => settings.homeCardOn('night');

  String _md() => sleepToMarkdown(nights) + (metrics.isEmpty ? '' : metricsToMarkdown(metrics));
  String? error;
  DateTime? _at;

  /// Testeille: korvaa Health Connect -haun.
  Future<List<SleepSession>> Function(DateTime from, DateTime to)? debugSource;

  /// Kortti päällä (Asetukset → Etusivu); haku vain silloin.
  bool get enabled => settings.homeCardOn('sleep') || settings.homeCardOn('night');

  Future<void> load() async {
    try {
      final text = await files.read(sleepFileName);
      nights
        ..clear()
        ..addAll(text == null ? const {} : parseSleep(text));
      metrics
        ..clear()
        ..addAll(text == null ? const {} : parseMetrics(text));
    } catch (_) {}
    if (isDemo && nights.isEmpty) nights.addAll(demoNights(DateTime.now()));
    if (isDemo && metrics.isEmpty) metrics.addAll(demoMetrics(DateTime.now()));
    _loaded = true;
    notifyListeners();
  }

  /// Lukee yöt Health Connectista ja korvaa ne (oletus: viimeiset 3 yötä, ensimmäisellä kerralla 30). Tallentaa
  /// vain, jos jokin muuttui. Tallennettuja öitä ei poisteta.
  Future<void> refresh({DateTime? from, bool force = false}) async {
    if (!_loaded) await load();
    if (!enabled || loading || isDemo) return;
    final now = DateTime.now();
    if (!force && from == null && _at != null && now.difference(_at!).inMinutes < 30) return;
    final today = dateOnly(now);
    final start = from ?? addDays(today, -((nights.isEmpty ? sleepFirstDays : sleepRefreshDays) - 1));
    loading = true;
    error = null;
    notifyListeners();
    try {
      final src = debugSource;
      if (src == null && debugMetrics == null) {
        if (await HealthConnect.status() != 'available') {
          error = 'unavailable';
          // Ei Health Connectia (esim. Android 11): ei kysytä uudelleen jokaisella etusivun piirrolla (kortti vilkkui
          // latausta); paluu sovellukseen ja asetusten kytkin hakevat silti heti (force).
          _at = now;
          return;
        }
        if (settings.homeCardOn('sleep') && !await HealthConnect.granted(sleep: true)) {
          needsPermission = true;
          return;
        }
      }
      needsPermission = false;
      final sleepOn = settings.homeCardOn('sleep');
      // Haku 90 päivän paloissa (pitkä historia), illasta 18:00 seuraavaan iltaan.
      final got = <SleepSession>[];
      var a = DateTime(start.year, start.month, start.day - 1, 18);
      final end = DateTime(today.year, today.month, today.day + 1);
      while (sleepOn && a.isBefore(end)) {
        final b = a.add(const Duration(days: 90)).isBefore(end) ? a.add(const Duration(days: 90)) : end;
        got.addAll(await (src ?? HealthConnect.sleepSessions)(a, b));
        a = b;
      }
      // Lähde: sovellus, jolla on eniten tallennettuja öitä. Vertailu tiedoston tarkkuudella (minuutit, desimaalit):
      // muuten jokainen käynnistys kirjoitti uni.md:n uudelleen, vaikka mikään ei muuttunut.
      final counts = <String, int>{};
      for (final n in nights.values) {
        counts[n.app] = (counts[n.app] ?? 0) + 1;
      }
      final prefer = counts.isEmpty ? null : (counts.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
      final fresh = parseSleep(sleepToMarkdown(nightsFrom(got, prefer: prefer)));
      var changed = false;
      for (final e in fresh.entries) {
        if (e.key.isBefore(dateOnly(start))) continue;
        if (nights[e.key] != e.value) {
          nights[e.key] = e.value;
          changed = true;
        }
      }
      // Yöarvot: unijakson ajalta, tai klo 21–10, jos unta ei ole (kortti päällä ja jokin arvo sallittu).
      // Oma try: yöarvojen virhe (esim. lupa poistettu) ei estä unen tallennusta.
      try {
        if (metricsEnabled && (debugMetrics != null || await HealthConnect.granted(metrics: true))) {
          final windows = <DateTime, (DateTime, DateTime)>{};
          for (var d = dateOnly(start); !d.isAfter(today); d = addDays(d, 1)) {
            final n = nights[d];
            windows[d] = n != null
                ? (n.bed, n.wake)
                : (DateTime(d.year, d.month, d.day - 1, 21), DateTime(d.year, d.month, d.day, 10));
          }
          final keys = windows.keys.toList();
          for (var i = 0; i < keys.length; i += 31) {
            final part = {for (final k in keys.skip(i).take(31)) k: windows[k]!};
            final got = parseMetrics(metricsToMarkdown(await (debugMetrics ?? HealthConnect.nightMetrics)(part)));
            for (final e in got.entries) {
              if (metrics[e.key] != e.value) {
                metrics[e.key] = e.value;
                changed = true;
              }
            }
          }
        }
      } catch (_) {}
      if (changed) await files.write(sleepFileName, _md());
      _at = now;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Kortti päälle: Health Connectin lupa (unijaksot ja syke). True, jos lupa saatiin (tai testissä).
  Future<bool> requestPermission() async {
    if (debugSource == null && !isDemo) {
      try {
        if (await HealthConnect.status() != 'available') return false;
        if (!await HealthConnect.granted(sleep: true)) {
          await HealthConnect.request(sleep: true);
          if (!await HealthConnect.granted(sleep: true)) return false;
        }
      } catch (_) {
        return false;
      }
    }
    needsPermission = false;
    return true;
  }

  /// Yöarvot-kortti päälle: Health Connectin luvat (HRV, happisaturaatio, hengitys, ihon lämpötila, leposyke).
  /// Käyttäjä voi sallia vain osan; true, jos jokin sallittiin.
  Future<bool> requestMetrics() async {
    if (debugMetrics != null || isDemo) return true;
    try {
      if (await HealthConnect.status() != 'available') return false;
      if (!await HealthConnect.granted(metrics: true)) await HealthConnect.request(metrics: true);
      return await HealthConnect.granted(metrics: true);
    } catch (_) {
      return false;
    }
  }

  /// Vanhempi unihistoria: historialupa (kysytään, jos puuttuu) ja haku [sleepHistoryDays] päivää taaksepäin.
  /// Palauttaa uusien öiden määrän tai null, jos lupaa ei saatu tai haku epäonnistui.
  Future<int?> readHistory() async {
    if (debugSource == null) {
      try {
        if (!await HealthConnect.granted(sleep: true, history: true)) {
          await HealthConnect.request(sleep: true, history: true);
          if (!await HealthConnect.granted(sleep: true, history: true)) return null;
        }
      } catch (_) {
        return null;
      }
    }
    final before = nights.length;
    await refresh(from: addDays(DateTime.now(), -(sleepHistoryDays - 1)));
    return error == null ? nights.length - before : null;
  }

  /// Varmuuskopion yöt: lisätään yöt, joita täällä ei ole (tämän laitteen yöt pysyvät).
  Future<void> mergeFrom(String md) async {
    if (!_loaded) await load();
    var changed = false;
    for (final e in parseSleep(md).entries) {
      if (nights.containsKey(e.key)) continue;
      nights[e.key] = e.value;
      changed = true;
    }
    for (final e in parseMetrics(md).entries) {
      if (metrics.containsKey(e.key)) continue;
      metrics[e.key] = e.value;
      changed = true;
    }
    if (changed) {
      await files.write(sleepFileName, _md());
      notifyListeners();
    }
  }
}

/// Demo ja verkkoversio (kotisivun kuvat): keksityt yöt.
Map<DateTime, SleepNight> demoNights(DateTime now) {
  final t = dateOnly(now);
  return {
    for (var i = 0; i < 30; i++)
      addDays(t, -i): () {
        final d = addDays(t, -i);
        final bedMin = 23 * 60 + 5 + (i * 17 % 50) - (d.weekday >= 6 ? 0 : 20);
        final bed = DateTime(d.year, d.month, d.day - 1).add(Duration(minutes: bedMin));
        final sleepMin = (i == 0 ? 6 * 60 + 10 : 7 * 60 + 5 + (i * 23 % 60) - 20);
        final wake = bed.add(Duration(minutes: sleepMin + 25));
        return SleepNight(
          d,
          bed,
          wake,
          Duration(minutes: sleepMin),
          lowHr: 50 + (i * 7 % 5),
          app: 'Oura',
        );
      }(),
  };
}

/// Demo: keksityt yöarvot (kotisivun kuvat).
Map<DateTime, NightMetrics> demoMetrics(DateTime now) {
  final t = dateOnly(now);
  return {
    for (var i = 0; i < 30; i++)
      addDays(t, -i): NightMetrics(
        hrv: 48.0 + (i * 7 % 9) - (i == 0 ? 6 : 0),
        spo2: 96.0 + (i % 3) * 0.4,
        spo2Min: 91.0 + (i % 4),
        rr: 14.2 + (i % 5) * 0.2,
        temp: -0.1 + (i % 4) * 0.08,
        rest: 50.0 + (i * 7 % 5),
      ),
  };
}

final sleepData = SleepData();
