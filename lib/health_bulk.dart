import 'health.dart';
import 'models.dart';
import 'sports.dart';

// Health Connectin joukkotuonti (Tuonti ja vienti, käyttäjä 21.11.): kaikki harjoitukset valitulta ajalta kerralla,
// esim. sovelluksesta, jolla ei ole omaa vientiä. Päivän tuonti (health_import.dart) avaa jokaisen tarkistettavaksi;
// tässä käyttäjä valitsee listasta. Logiikka tässä, jotta sen voi testata.
//
// Ei kaksoiskappaleita (käyttäjä 21.11.): harjoitus, joka on jo Gievrassa (sama Health Connectin tunniste, sama aika,
// tai samana päivänä sama laji ilman aloitusaikaa), ei tule uudeksi treeniksi. Jos Health Connectissa on sille
// tietoja, joita Gievrassa ei ole, käyttäjä voi päivittää sen: vain puuttuvat tiedot lisätään, mitään ei korvata.

/// Laji joukkotuonnissa: tunnettu tyyppi Gievran lajiksi, muuten Muu liikunta (päivän tuonti kysyy lajin).
String bulkSport(HealthCandidate c) => sportForHealthType(c.type) ?? 'Muu liikunta';

enum BulkKind {
  /// Uusi treeni.
  add,

  /// Jo Gievrassa; Health Connectissa on lisätietoja (päätetään, kun tiedot on haettu: [bulkGains]).
  update,

  /// Jo Gievrassa, eikä uutta tietoa.
  skip,
}

class BulkItem {
  HealthCandidate c;
  BulkKind kind;

  /// Sama laji (salitreeni / liikunta) ja yli puolet lyhyemmästä samaan aikaan Gievran treenin [w] kanssa.
  bool overlapsInTime(HealthCandidate c, Workout w) {
    if (isStrengthType(c.type) != (w.activity == null) || w.started == null) return false;
    final secs = _secs(w);
    if (secs <= 0) return false;
    final ws = w.started!, we = ws.add(Duration(seconds: secs));
    final o = (c.end.isBefore(we) ? c.end : we).difference(c.start.isAfter(ws) ? c.start : ws).inSeconds;
    final shorter = c.duration.inSeconds < secs ? c.duration.inSeconds : secs;
    return o > 0 && shorter > 0 && o * 2 > shorter;
  }

  /// Gievran treeni, joka on sama harjoitus (päivitys tai ohitus).
  final Workout? match;

  /// Uusi, mutta sama aika kuin listan aiemmalla (toinen sovellus tallensi saman): oletuksena valitsematta.
  final bool dupe;
  BulkItem(this.c, this.kind, {this.match, this.dupe = false});
}

int _secs(Workout w) => w.seconds ?? (w.minutes ?? 0) * 60;

/// Onko [c] sama harjoitus kuin Gievran [w]: sama tunniste; salitreeni samana päivänä; liikunta, joka on yli puoliksi
/// samaan aikaan; tai liikunta ilman aloitusaikaa samana päivänä samalla lajilla ja suunnilleen saman kestoinen.
bool sameWorkout(HealthCandidate c, Workout w) {
  if (c.id != null && w.hcId == c.id) return true;
  final day = DateTime(c.start.year, c.start.month, c.start.day);
  if (isStrengthType(c.type)) {
    if (w.activity != null || w.date != day) return false;
    // Salitreeni, johon on jo liitetty kellon tiedot: sama vain, jos aika osuu; muuten päivän salitreeni.
    if (w.healthSource != null && w.started != null) {
      final we = w.started!.add(Duration(seconds: _secs(w)));
      return w.started!.isBefore(c.end) && we.isAfter(c.start);
    }
    return w.hcId == null;
  }
  if (w.activity == null) return false;
  final secs = _secs(w);
  if (w.started != null) {
    if (secs <= 0) return w.date == day && w.activity == bulkSport(c);
    final ws = w.started!, we = ws.add(Duration(seconds: secs));
    final o = (c.end.isBefore(we) ? c.end : we).difference(c.start.isAfter(ws) ? c.start : ws).inSeconds;
    final shorter = c.duration.inSeconds < secs ? c.duration.inSeconds : secs;
    return o > 0 && shorter > 0 && o * 2 > shorter;
  }
  // Käsin kirjattu ilman kellonaikaa: sama päivä ja laji, kesto ±25 % (vähintään ±10 min) tai kesto puuttuu.
  if (w.date != day || w.activity != bulkSport(c)) return false;
  if (secs <= 0) return true;
  final diff = (secs - c.duration.inSeconds).abs();
  final tol = secs ~/ 4 > 600 ? secs ~/ 4 : 600;
  return diff <= tol;
}

/// Sama laji (salitreeni / liikunta) ja yli puolet lyhyemmästä samaan aikaan Gievran treenin [w] kanssa.
bool overlapsInTime(HealthCandidate c, Workout w) {
  if (isStrengthType(c.type) != (w.activity == null) || w.started == null) return false;
  final secs = _secs(w);
  if (secs <= 0) return false;
  final ws = w.started!, we = ws.add(Duration(seconds: secs));
  final o = (c.end.isBefore(we) ? c.end : we).difference(c.start.isAfter(ws) ? c.start : ws).inSeconds;
  final shorter = c.duration.inSeconds < secs ? c.duration.inSeconds : secs;
  return o > 0 && shorter > 0 && o * 2 > shorter;
}

/// Gievran treeni, joka on sama harjoitus kuin [c] ([sameWorkout]); jo käytetyt [used] ohitetaan, jotta kaksi kellon
/// harjoitusta ei osu samaan treeniin. Lähin aika ensin.
Workout? findSame(HealthCandidate c, Iterable<Workout> existing, {Set<Workout> used = const {}}) {
  Workout? best;
  var bestD = 1 << 40;
  for (final w in existing) {
    if (used.contains(w) || !sameWorkout(c, w)) continue;
    if (c.id != null && w.hcId == c.id) return w;
    final d = w.started == null ? 1 << 30 : w.started!.difference(c.start).inSeconds.abs();
    if (d < bestD) {
      best = w;
      bestD = d;
    }
  }
  return best;
}

/// Joukkotuonnin lista aikajärjestyksessä: uudet (kaksoiskappaleet merkittyinä) ja jo Gievrassa olevat. Jo olevista
/// [BulkKind.update], jos treenistä puuttuu jotain, mitä kellosta voisi saada ([couldGain]); muuten ohitetaan.
List<BulkItem> bulkPlan(List<HealthCandidate> all, List<Workout> existing) {
  final list = [
    for (final c in all)
      if (c.session) c,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final used = <Workout>{};
  final out = <BulkItem>[];
  for (final c in list) {
    // Toisen sovelluksen kopio harjoituksesta, joka on jo Gievrassa (sama aika): ohitetaan.
    final copyOf = existing.where((w) => used.contains(w) && overlapsInTime(c, w)).firstOrNull;
    if (copyOf != null) {
      out.add(BulkItem(c, BulkKind.skip, match: copyOf));
      continue;
    }
    final m = findSame(c, existing, used: used);
    if (m != null) {
      used.add(m);
      out.add(BulkItem(c, couldGain(m) ? BulkKind.update : BulkKind.skip, match: m));
      continue;
    }
    // Sama aika kuin listan aiemmalla uudella: todennäköisesti toisen sovelluksen kopio.
    var dupe = false;
    for (final o in out.reversed) {
      if (o.kind != BulkKind.add || o.dupe) continue;
      if (o.c.end.isBefore(c.start.subtract(const Duration(hours: 12)))) break;
      final s = c.start.isAfter(o.c.start) ? c.start : o.c.start;
      final e = c.end.isBefore(o.c.end) ? c.end : o.c.end;
      final overlap = e.difference(s).inSeconds;
      final a = c.duration.inSeconds, b = o.c.duration.inSeconds;
      final shorter = a < b ? a : b;
      if (overlap > 0 && shorter > 0 && overlap * 2 > shorter) {
        dupe = true;
        break;
      }
    }
    out.add(BulkItem(c, BulkKind.add, dupe: dupe));
  }
  return out;
}

/// Puuttuuko treenistä jotain, mitä Health Connectista voisi saada (tiedot haetaan vasta tämän jälkeen).
bool couldGain(Workout w) {
  final sp = sportOf(w.activity);
  return (w.hrAvg == null && w.hrMax == null) ||
      (w.hrSeries == null && w.hrSource == 'kello') ||
      w.kcal == null ||
      w.started == null ||
      (w.activity != null && (sp?.distance ?? false) && w.distanceKm == null) ||
      (w.activity != null && (sp?.steps ?? false) && w.steps == null) ||
      _secs(w) <= 0;
}

/// Lisätyt tiedot ([fillMissing]).
enum BulkGain { hr, curve, kcal, distance, steps, start, time }

/// Lisää treeniin [w] vain puuttuvat tiedot harjoituksesta [c]; mitään olemassa olevaa ei korvata (käsin kirjattu
/// syke pysyy, eikä siihen lisätä kellon käyrää). Palauttaa lisätyt; tyhjä = ei muutosta.
List<BulkGain> fillMissing(Workout w, HealthCandidate c) {
  final out = <BulkGain>[];
  final sp = sportOf(w.activity);
  if (w.hrAvg == null && w.hrMax == null && (c.hrAvg != null || c.hrMax != null)) {
    w.hrAvg = c.hrAvg;
    w.hrMax = c.hrMax;
    w.hrSource = 'kello';
    out.add(BulkGain.hr);
    final s = hrSeriesFromHealth(c.hrSamples);
    if (s != null && w.hrSeries == null) {
      w.hrSeries = s;
      out.add(BulkGain.curve);
    }
  } else if (w.hrSeries == null && w.hrSource == 'kello') {
    final s = hrSeriesFromHealth(c.hrSamples);
    if (s != null) {
      w.hrSeries = s;
      out.add(BulkGain.curve);
    }
  }
  if (w.kcal == null && c.kcal != null) {
    w.kcal = c.kcal;
    w.kcalSource = 'kello';
    out.add(BulkGain.kcal);
  }
  if (w.activity != null && (sp?.distance ?? false) && w.distanceKm == null && (c.meters ?? 0) > 0) {
    w.distanceKm = (c.meters! / 10).round() / 100;
    out.add(BulkGain.distance);
  }
  if (w.activity != null && (sp?.steps ?? false) && w.steps == null && (c.steps ?? 0) > 0) {
    w.steps = c.steps;
    out.add(BulkGain.steps);
  }
  if (w.started == null) {
    w.started = c.start;
    out.add(BulkGain.start);
  }
  if (_secs(w) <= 0 && c.duration.inSeconds > 0) {
    w.seconds = c.duration.inSeconds;
    w.minutes = minutesFromSeconds(c.duration.inSeconds);
    w.watchTime = true;
    out.add(BulkGain.time);
  }
  if (out.isNotEmpty) {
    w.hcId ??= c.id;
    w.healthSource ??= c.app;
  }
  return out;
}

/// Mitä päivitys lisäisi (kopioon, alkuperäinen ei muutu).
List<BulkGain> bulkGains(Workout w, HealthCandidate c) => fillMissing(w.copy(), c);

/// Valitut uudet harjoitukset (tiedot haettu, [HealthConnect.fullSession]) treeneiksi. Harjoitus, joka on jo
/// Gievrassa tai joka osuu saman tuonnin aiempaan, ohitetaan (ei kaksoiskappaleita, vaikka sama valittaisiin kahdesti
/// tai tuonti ajettaisiin uudelleen). Uudet saavat päivän seuraavan vapaan numeron. Voimaharjoittelu: uusi salitreeni
/// ilman liikkeitä. Tuntematon laji: Muu liikunta, ja Health Connectin nimi muistiinpanoksi.
/// Palauttaa (uudet, ohitettujen määrä). Ei tallenna.
(List<Workout>, int) bulkWorkouts(List<HealthCandidate> chosen, List<Workout> existing) {
  final created = <Workout>[];
  var skipped = 0;
  int next(DateTime d) =>
      [...existing, ...created].where((w) => w.date == d).fold(0, (a, w) => w.session > a ? w.session : a) + 1;
  for (final c in [...chosen]..sort((a, b) => a.start.compareTo(b.start))) {
    // Jo Gievrassa (sama tunniste tai sama aika) tai saman tuonnin aiempi: ei toista treeniä. Päivän salitreeni ja
    // käsin kirjattu ilman kellonaikaa ovat päivityksiä (bulkPlan), eivät estä uutta.
    bool dup(Workout w) => (c.id != null && w.hcId == c.id) || overlapsInTime(c, w);
    if (existing.any(dup) || created.any(dup)) {
      skipped++;
      continue;
    }
    final d = DateTime(c.start.year, c.start.month, c.start.day);
    if (isStrengthType(c.type)) {
      created.add(gymFromHealth(c, const [], nextSession: next(d)).$1);
      continue;
    }
    final sport = bulkSport(c);
    final w = workoutFromHealth(c, sport, session: next(d));
    applyCandidate(w, c); // sykekäyrä, lähteet (kello) kuten päivän tuonnissa
    if (sportForHealthType(c.type) == null) w.notes = bulkTitleNote(c.title);
    created.add(w);
  }
  return (created, skipped);
}

/// Toisen sovelluksen harjoituksen nimi muistiinpanoksi: yhdelle riville ja enintään 200 merkkiä (yötesti 22.11.:
/// Health Connectin nimi on minkä tahansa sovelluksen kirjoittama, eikä sen pituutta rajoiteta).
String bulkTitleNote(String? title) {
  final s = (title ?? '').replaceAll(RegExp(r'[\x00-\x1f\x7f]+'), ' ').replaceAll(RegExp(r' {2,}'), ' ').trim();
  return s.length <= 200 ? s : '${s.substring(0, 199).trimRight()}…';
}
