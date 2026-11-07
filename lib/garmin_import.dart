import 'import_export.dart';
import 'models.dart';
import 'sports.dart';

// Garmin Connect -suoritukset (Suoritukset → Vie CSV) Gievran liikunnaksi.
//
// Sarakkeet tunnistetaan otsikon nimestä, suomen- tai englanninkielisestä viennistä. Tuodaan: laji, päivä ja
// aloitusaika, matka, kesto (h:mm:ss), kalorit sekä keski- ja maksimisyke. Kokonaisnousu, askeltiheys, aerobinen
// TE, askeleet ja keskiteho kirjataan muistiinpanoihin, koska Gievrassa ei ole niille omia kenttiä.
// Voimaharjoittelu ohitetaan: salitreenit kirjataan Gievrassa sarjoineen.

/// Garmin-laji -> Gievran laji (sports.dart). Avaimet pienillä kirjaimilla; ensimmäinen osuma voittaa.
const _types = <(String, String)>[
  ('juoksumatto', 'Juoksu'),
  ('treadmill', 'Juoksu'),
  ('polkujuoksu', 'Juoksu'),
  ('trail', 'Juoksu'),
  ('juoksu', 'Juoksu'),
  ('running', 'Juoksu'),
  ('sauvakävely', 'Sauvakävely'),
  ('kävely', 'Kävely'),
  ('walking', 'Kävely'),
  ('vaellus', 'Retkeily'),
  ('retkeily', 'Retkeily'),
  ('hiking', 'Retkeily'),
  ('pyöräily', 'Pyöräily'),
  ('cycling', 'Pyöräily'),
  ('biking', 'Pyöräily'),
  ('uinti', 'Uinti'),
  ('swim', 'Uinti'),
  ('hiihto', 'Hiihto'),
  ('skiing', 'Hiihto'),
  ('soutu', 'Soutu'),
  ('rowing', 'Soutu'),
  ('melonta', 'Melonta'),
  ('kayak', 'Melonta'),
  ('paddl', 'Melonta'),
  ('luistelu', 'Luistelu'),
  ('skating', 'Luistelu'),
  ('lumikenk', 'Lumikenkäily'),
  ('snowshoe', 'Lumikenkäily'),
  ('jooga', 'Jooga'),
  ('yoga', 'Jooga'),
  ('pilates', 'Pilates'),
  ('tanssi', 'Tanssi'),
  ('dance', 'Tanssi'),
  ('kiipeily', 'Kiipeily'),
  ('climb', 'Kiipeily'),
  ('golf', 'Golf'),
  ('tennis', 'Tennis'),
  ('padel', 'Padel'),
  ('squash', 'Squash'),
  ('sulkapallo', 'Sulkapallo'),
  ('badminton', 'Sulkapallo'),
];

const _strength = ['voimaharjoittelu', 'strength'];

/// Garminin laji Gievran lajiksi; null = ohitetaan (voimaharjoittelu).
String? garminSport(String type) {
  final t = type.toLowerCase();
  if (_strength.any(t.contains)) return null;
  for (final (k, v) in _types) {
    if (t.contains(k)) return v;
  }
  return 'Muu liikunta';
}

/// CSV-rivit (lainausmerkit ja niiden sisäiset pilkut huomioiden).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString());
  if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
  return rows;
}

/// Garminin luku: "--" = puuttuu, "1,050" = tuhaterotin, "12.34" tai "12,34" = desimaali.
double? garminNum(String s) {
  var t = s.trim().replaceAll("'", '').replaceAll(' ', '').replaceAll(' ', '');
  if (t.isEmpty || t.startsWith('--')) return null;
  if (t.contains('.') && t.contains(',')) {
    t = t.replaceAll(',', '');
  } else if (RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(t)) {
    t = t.replaceAll(',', '');
  } else {
    t = t.replaceAll(',', '.');
  }
  return double.tryParse(t);
}

/// "01:02:03", "16:30" tai "00:00:08.5" -> sekunteja.
int? garminDuration(String s) {
  final t = s.trim();
  if (t.isEmpty || t.startsWith('--')) return null;
  final p = t.split(':');
  final nums = p.map((x) => double.tryParse(x.replaceAll(',', '.'))).toList();
  if (nums.any((x) => x == null)) return null;
  var sec = 0.0;
  for (final n in nums) {
    sec = sec * 60 + n!;
  }
  return sec.round();
}

/// Sarake otsikon mukaan (suomi tai englanti).
class _Cols {
  final Map<String, int> _ix;
  _Cols(List<String> header) : _ix = {for (final (i, h) in header.indexed) h.trim().toLowerCase(): i};

  String get(List<String> row, List<String> names) {
    for (final n in names) {
      final i = _ix[n.toLowerCase()];
      if (i != null && i < row.length) return row[i].trim();
    }
    return '';
  }

  bool has(List<String> names) => names.any((n) => _ix.containsKey(n.toLowerCase()));
}

const _cType = ['Suorituksen tyyppi', 'Activity Type'];
const _cDate = ['Päiväys', 'Date'];
const _cTitle = ['Otsikko', 'Title'];
const _cDist = ['Etäisyys', 'Distance'];
const _cKcal = ['Kalorit', 'Calories'];
const _cTime = ['Aika', 'Time', 'Kulunut aika', 'Elapsed Time'];
const _cHr = ['Keskisyke', 'Avg HR'];
const _cHrMax = ['Maksimisyke', 'Max HR'];
const _cTe = ['Aerobinen TE', 'Aerobic TE'];
const _cCad = ['Keskimääräinen askeltiheys', 'Avg Run Cadence', 'Avg Cadence'];
const _cAscent = ['Kokonaisnousu', 'Total Ascent'];
const _cSteps = ['Askeleet', 'Steps'];
const _cPower = ['Keskiteho', 'Avg Power'];

/// Lukee Garmin Connectin CSV-viennin. [existing]: jo päiväkirjassa olevat treenit (kaksoiskappaleiden tunnistus
/// ja saman päivän treenien numerointi). Palauttaa myös ohitettujen voimaharjoitusten määrän.
(ImportResult, int skipped) readGarminCsv(String text, List<Workout> existing) {
  final rows = parseCsv(text.replaceFirst('﻿', ''));
  if (rows.isEmpty) return (ImportResult(source: 'Garmin Connect', workouts: const []), 0);
  final c = _Cols(rows.first);
  if (!c.has(_cType) || !c.has(_cDate)) {
    return (ImportResult(source: 'Garmin Connect', workouts: const []), 0);
  }
  final list = <Workout>[];
  var skipped = 0;
  // Päivän seuraava vapaa treeninumero: olemassa olevat ja tässä tuonnissa jo lisätyt.
  final used = <DateTime, Set<int>>{};
  for (final w in existing) {
    (used[w.date] ??= {}).add(w.session);
  }
  for (final r in rows.skip(1)) {
    final type = c.get(r, _cType);
    final sport = garminSport(type);
    if (sport == null) {
      skipped++;
      continue;
    }
    final start = DateTime.tryParse(c.get(r, _cDate).replaceFirst(' ', 'T'));
    if (start == null) continue;
    final day = dateOnly(start);
    final sec = garminDuration(c.get(r, _cTime));
    var km = garminNum(c.get(r, _cDist));
    // Uinnissa Garmin ilmoittaa metrit.
    if (km != null && sport == 'Uinti' && km > 20) km = km / 1000;
    if (km != null && km <= 0) km = null;
    final te = garminNum(c.get(r, _cTe));
    final extra = <String>[
      if (garminNum(c.get(r, _cAscent)) case final v?) 'nousu ${v.round()} m',
      if (garminNum(c.get(r, _cCad)) case final v?) 'askeltiheys ${v.round()} /min',
      if (te != null) 'aerobinen TE ${fileNum(te)}',
      // Kävelylajeissa askeleet omaan kenttäänsä, muissa muistiinpanoihin.
      if (!(sportOf(sport)?.steps ?? false))
        if (garminNum(c.get(r, _cSteps)) case final v?) 'askeleet ${v.round()}',
      if (garminNum(c.get(r, _cPower)) case final v?) 'keskiteho ${v.round()} W',
    ];
    final title = c.get(r, _cTitle);
    final w =
        Workout(
            date: day,
            title: sport,
            activity: sport,
            distanceKm: km == null ? null : (km * 100).round() / 100,
            seconds: sec,
            minutes: sec == null ? null : (sec / 60).round(),
            started: start,
            kcal: garminNum(c.get(r, _cKcal))?.round(),
            hrAvg: garminNum(c.get(r, _cHr))?.round(),
            hrMax: garminNum(c.get(r, _cHrMax))?.round(),
            intensity: te == null ? null : (te < 2.5 ? 'kevyt' : (te < 4 ? 'reipas' : 'kova')),
            watchTime: true,
          )
          ..steps = (sportOf(sport)?.steps ?? false) ? garminNum(c.get(r, _cSteps))?.round() : null
          ..notes = [
            'Garmin: ${title.isEmpty ? type : title}${type.toLowerCase().contains('matto') || type.toLowerCase().contains('treadmill') ? ' (juoksumatto)' : ''}',
            if (extra.isNotEmpty) extra.join(' · '),
          ].join('\n');
    // Sama suoritus jo päiväkirjassa (sama laji ja aloitusminuutti tai sama matka): käytetään sen numeroa, jolloin
    // esikatselu laskee sen olemassa olevaksi eikä sitä tuoda uudelleen.
    final dup = existing.where(
      (x) =>
          x.date == day &&
          x.activity == sport &&
          ((x.started != null && x.started!.hour == start.hour && x.started!.minute == start.minute) ||
              (x.distanceKm != null && w.distanceKm != null && (x.distanceKm! - w.distanceKm!).abs() < .015)),
    );
    if (dup.isNotEmpty) {
      w.session = dup.first.session;
    } else {
      final s = used[day] ??= {};
      var n = 1;
      while (s.contains(n)) {
        n++;
      }
      s.add(n);
      w.session = n;
    }
    list.add(w);
  }
  list.sort((a, b) => a.date.compareTo(b.date));
  return (ImportResult(source: 'Garmin Connect', workouts: list), skipped);
}
