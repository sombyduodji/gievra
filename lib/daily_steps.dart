import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'health.dart';
import 'models.dart';

// Päivän askeleet Health Connectista (Android, asetus, oletus pois). Vain luku: Gievra ei kirjoita Health
// Connectiin eikä luo treenejä. Health Connectin koonti poistaa päällekkäiset askeleet sovellusten
// tärkeysjärjestyksen mukaan (puhelin ja Oura samalta tunnilta kerran). Joka haku lukee viimeiset päivät uudelleen
// ja korvaa ne (ei lisää), joten myöhemmin synkronoituva Oura korjaa luvut. Treenien askeleet sisältyvät päivän
// lukuun jo valmiiksi; niitä ei lisätä.
//
// Tallennus: askeleet.md (yksi rivi päivää kohden), jotta luvut ovat varmuuskopioissa ja tilastoissa myös, kun
// Health Connect ei enää anna vanhoja tietoja (yleensä noin 30 päivää ennen luvan antamista).

const stepsFileName = 'askeleet.md';

/// Montako viimeisintä päivää luetaan joka kerta uudelleen (Oura synkronoi usein vasta yöllä tai myöhemmin).
const stepsRefreshDays = 7;

/// Askelten laskusäännön versio. Kun sääntö muuttuu, tallennetut päivät luetaan kerran uudelleen (enintään
/// [stepsRuleDays] päivää taaksepäin): 2 = liikunnan askeleet lisätään vain, kun koonnista puuttuu yli puolet
/// (0.6.4-testiversioissa lisättiin pienetkin erot); 3 = vain laitteen sovelluksesta tuodut liikunnat (Gievran
/// omat kävelyt tuplaantuivat, kun Oura kirjaa päivän yhtenä tietueena); 4 = maton askeleet päivän koonneista
/// (aikavälin koonti antoi maton askeleet, vaikka päivän koonnista ne puuttuivat).
const stepsRule = 4;

/// Vanhemman historian haku: näin monta päivää taaksepäin (Health Connect säilyttää tiedot, jotka sovellukset ovat
/// sinne kirjoittaneet; ilman historialupaa vain noin 30 päivää ennen luvan antamista).
const stepsHistoryDays = 731;
const stepsRuleDays = 60;
const _ruleKey = 'stepsRule';

/// Päivä, joka voi vielä muuttua (tänään ja eilen: Ouran yösynkronointi).
bool stepsMayChange(DateTime day, {DateTime? now}) =>
    !dateOnly(day).isBefore(addDays(dateOnly(now ?? DateTime.now()), -1));

String stepsToMarkdown(Map<DateTime, int> days, Map<DateTime, List<String>> apps) {
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('tags: [askeleet]')
    ..writeln('---')
    ..writeln()
    ..writeln('# Askeleet')
    ..writeln()
    ..writeln('Päivän askeleet Health Connectista ilman päällekkäisyyksiä. Treenien askeleet sisältyvät näihin.')
    ..writeln();
  final keys = days.keys.toList()..sort((a, c) => c.compareTo(a));
  for (final d in keys) {
    final a = apps[d] ?? const [];
    b.writeln('- ${isoDate(d)}: ${days[d]}${a.isEmpty ? '' : ' (${a.join(', ')})'}');
  }
  return b.toString();
}

/// askeleet.md: päivä -> askeleet ja sovellukset. Tuntemattomat rivit ohitetaan.
(Map<DateTime, int>, Map<DateTime, List<String>>) parseSteps(String text) {
  final days = <DateTime, int>{};
  final apps = <DateTime, List<String>>{};
  final re = RegExp(r'^[-*]\s*(\d{4}-\d{2}-\d{2}):\s*(\d+)(?:\s*\((.*)\))?\s*$');
  for (final line in text.split('\n')) {
    final m = re.firstMatch(line.trim());
    if (m == null) continue;
    final d = DateTime.tryParse(m[1]!);
    if (d == null || isoDate(d) != m[1]) continue;
    days[d] = int.parse(m[2]!);
    final a = (m[3] ?? '').split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (a.isNotEmpty) apps[d] = a;
  }
  return (days, apps);
}

/// Liikunnan askeleet, jotka lisättiin päivän lukuun: [steps] liikunnassa, [had] Health Connectin koonnissa
/// samalta ajalta; lisätty = steps − had.
typedef StepsAddition = ({String name, String? source, DateTime start, int steps, int had});

class DailySteps extends ChangeNotifier {
  final Map<DateTime, int> days = {};
  final Map<DateTime, List<String>> apps = {};
  bool loading = false;
  String? error;

  /// Health Connectin lupa puuttuu (kortti näyttää Salli-painikkeen).
  bool needsPermission = false;
  DateTime? lastRefresh;
  Timer? _timer;
  bool _loaded = false;

  /// Testeille ja kehitykselle: korvaa Health Connect -haun.
  Future<Map<DateTime, (int, List<String>)>> Function(DateTime from, DateTime to)? debugSource;

  /// Päivän luvun koostumus viimeisimmästä hausta (vain muistissa): Health Connectin koonti ja siihen lisätyt
  /// liikuntojen askeleet (nimi, aloitus, lisätty, koonnissa liikunnan ajalta).
  final Map<DateTime, int> hcTotal = {};
  final Map<DateTime, List<StepsAddition>> added = {};

  /// Laitteen sovelluksesta tuodut liikunnat, joita ei lisätty (koonnissa jo yli puolet niiden askelista):
  /// näytetään koostumuksessa, jotta luvun voi tarkistaa.
  final Map<DateTime, List<StepsAddition>> skipped = {};

  /// Testeille: korvaa aikavälin askelhaun (stepsInRange).
  Future<int> Function(DateTime start, DateTime end)? debugRange;

  /// Kävelymaton ja muiden liikuntojen askeleet, jotka Health Connectin koonnista puuttuvat: koonti ottaa
  /// päällekkäiseltä ajalta vain tärkeimmän sovelluksen askeleet (esim. puhelin, joka ei liiku maton päällä),
  /// jolloin maton sovelluksen (esim. WalkingPad) askeleet jäävät pois. Gievraan kirjatulle liikunnalle, jolla on
  /// askeleet ja aloitusaika: lisätään erotus, jos koonnissa on liikunnan ajalta vähemmän askeleita kuin
  /// liikunnassa. Lisätään vain, kun koonnista puuttuu selvästi (alle puolet liikunnan askelista): pieni ero
  /// johtuu siitä, että sovellukset laskevat eri tavalla (esim. Oura ja puhelin), eikä sitä lisätä.
  ///
  /// Vain laitteen sovelluksesta tuodut liikunnat (healthSource, esim. kävelymaton sovellus): Gievrassa tallennetun kävelyn
  /// askeleet tulevat puhelimesta tai sormuksesta, jotka ovat jo päivän luvussa. Oura kirjaa päivän yhtenä
  /// tietueena (4:00–23:59), jolloin koonti jakaa sen tasaisesti tunneille eikä kerro, mitä sormus kävelyn aikana
  /// laski: ulkokävely näyttäisi puuttuvan, vaikka se on Ouran luvussa (tuplaus).
  Future<(int, List<String>)> _withActivities(DateTime d, int total, List<String> apps) async {
    var sum = total;
    final out = [...apps];
    final adds = <StepsAddition>[], skips = <StepsAddition>[];
    for (final w in store.workouts) {
      if (w.date != d || w.activity == null) continue;
      if (w.healthSource?.isEmpty ?? true) continue; // Gievran oma kävely: askeleet jo päivän luvussa
      final steps = w.steps ?? 0;
      final sec = w.durationSec ?? 0;
      final start = w.started;
      if (steps <= 0 || sec <= 0 || start == null) continue;
      final end = start.add(Duration(seconds: sec));
      // Päivän koonnin jo sisältämät maton askeleet + muiden sovellusten askeleet liikunnan ajalta. Testeissä ja,
      // jos sovellusta ei löydy, aikavälin koonti.
      final dev = debugRange != null ? null : await HealthConnect.deviceSteps(d, start, end, w.healthSource!);
      final have = dev == null ? await (debugRange ?? HealthConnect.stepsInRange)(start, end) : dev.$1 + dev.$2;
      final a = (
        name: w.activity!,
        source: (w.healthSource?.isNotEmpty ?? false) ? w.healthSource : null,
        start: start,
        steps: steps,
        had: have,
      );
      if (have * 2 >= steps) {
        skips.add(a);
        continue;
      }
      sum += steps - have;
      adds.add(a);
    }
    hcTotal[d] = total;
    if (skips.isEmpty) {
      skipped.remove(d);
    } else {
      skipped[d] = skips;
    }
    if (adds.isEmpty) {
      added.remove(d);
    } else {
      added[d] = adds;
    }
    return (sum, out);
  }

  int? at(DateTime d) => days[dateOnly(d)];
  int? get today => at(DateTime.now());
  int? get yesterday => at(addDays(DateTime.now(), -1));

  /// Keskiarvo päivistä, joilta on luku, [n] viimeiseltä täydeltä päivältä (tänään ei mukana).
  int? average(int n, {DateTime? now}) {
    final end = dateOnly(now ?? DateTime.now());
    final v = [for (var i = 1; i <= n; i++) ?days[addDays(end, -i)]];
    return v.isEmpty ? null : (v.reduce((a, b) => a + b) / v.length).round();
  }

  Future<void> load() async {
    try {
      final text = await files.read(stepsFileName);
      days.clear();
      apps.clear();
      if (text != null) {
        final (d, a) = parseSteps(text);
        days.addAll(d);
        apps.addAll(a);
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  /// Lukee päivät Health Connectista ja korvaa ne (oletus: viimeiset [stepsRefreshDays] päivää). Tallentaa vain,
  /// jos jokin luku muuttui.
  Future<void> refresh({DateTime? from, DateTime? to}) async {
    if (!settings.dailySteps || loading) return;
    if (!_loaded) await load();
    final end = dateOnly(to ?? DateTime.now());
    var start = dateOnly(from ?? addDays(end, -(stepsRefreshDays - 1)));
    // Laskusääntö muuttunut: tallennetut päivät kerran uudelleen (vanhemmat kuin Health Connectin historia pysyvät).
    final sp = await SharedPreferences.getInstance();
    final redo = (sp.getInt(_ruleKey) ?? 0) < stepsRule && days.isNotEmpty;
    if (redo) {
      final oldest = days.keys.reduce((a, b) => a.isBefore(b) ? a : b);
      final limit = addDays(end, -(stepsRuleDays - 1));
      final first = oldest.isBefore(limit) ? limit : oldest;
      if (first.isBefore(start)) start = first;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final src = debugSource;
      if (src == null) {
        if (await HealthConnect.status() != 'available') {
          error = 'unavailable';
          return;
        }
        if (!await HealthConnect.granted(steps: true)) {
          needsPermission = true;
          return;
        }
      }
      needsPermission = false;
      final got = await (src ?? HealthConnect.dailySteps)(start, end);
      var changed = false;
      for (var d = start; !d.isAfter(end); d = addDays(d, 1)) {
        var r = got[d];
        // Liikuntojen (esim. kävelymatto) puuttuvat askeleet mukaan.
        final fixed = await _withActivities(d, r?.$1 ?? 0, r?.$2 ?? const []);
        if (fixed.$1 != (r?.$1 ?? 0)) r = fixed;
        final n = r?.$1 ?? 0;
        // Ei askeleita: tallennettu luku poistetaan vain viimeisiltä päiviltä (esim. vahingossa tallentunut ja
        // Health Connectista poistettu). Vanhempia ei: Health Connect antaa yleensä vain noin 30 päivää ennen
        // luvan antamista, ja vanhemmat päivät voivat tulla nollina, vaikka ne on tallennettu aiemmin.
        if (n <= 0) {
          final recent = !d.isBefore(addDays(dateOnly(DateTime.now()), -(stepsRefreshDays - 1)));
          if (recent && r != null && days.containsKey(d)) {
            days.remove(d);
            apps.remove(d);
            changed = true;
          }
          continue;
        }
        if (days[d] != n || !listEquals(apps[d], r!.$2)) {
          days[d] = n;
          if (r!.$2.isEmpty) {
            apps.remove(d);
          } else {
            apps[d] = r.$2;
          }
          changed = true;
        }
      }
      lastRefresh = DateTime.now();
      if (changed) await files.write(stepsFileName, stepsToMarkdown(days, apps));
      await sp.setInt(_ruleKey, stepsRule);
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Vanhemmat askeleet: Health Connectin historialupa (kysytään, jos puuttuu) ja haku [stepsHistoryDays] päivää
  /// taaksepäin. Palauttaa uusien tallennettujen päivien määrän tai null, jos lupaa ei saatu tai haku epäonnistui.
  /// Tallennettuja päiviä ei poisteta (ks. refresh).
  Future<int?> readHistory() async {
    if (debugSource == null) {
      try {
        if (!await HealthConnect.granted(history: true)) {
          await HealthConnect.request(history: true);
          if (!await HealthConnect.granted(history: true)) return null;
        }
      } catch (_) {
        return null;
      }
    }
    final before = days.length;
    await refresh(from: addDays(DateTime.now(), -(stepsHistoryDays - 1)));
    return error == null ? days.length - before : null;
  }

  /// Lupa Health Connectiin (Salli-painike), sitten haku.
  Future<void> requestPermission() async {
    try {
      await HealthConnect.request(steps: true);
    } catch (_) {}
    await refresh();
  }

  /// Etusivu auki: tämän päivän luku päivittyy noin 15 minuutin välein.
  void startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Varmuuskopion askeleet: lisätään päivät, joita täällä ei ole (tämän laitteen luvut pysyvät).
  Future<void> mergeFrom(String md) async {
    if (!_loaded) await load();
    final (d, a) = parseSteps(md);
    var changed = false;
    for (final e in d.entries) {
      if (days.containsKey(e.key)) continue;
      days[e.key] = e.value;
      if (a[e.key] case final x?) apps[e.key] = x;
      changed = true;
    }
    if (changed) {
      await files.write(stepsFileName, stepsToMarkdown(days, apps));
      notifyListeners();
    }
  }
}

final dailySteps = DailySteps();
