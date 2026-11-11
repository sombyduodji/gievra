import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'app_state.dart';
import 'body.dart';
export 'fitnotes_db_stub.dart' if (dart.library.ffi) 'fitnotes_db.dart';
import 'exercises.dart';
import 'injuries.dart' show injuryById;
import 'models.dart';
import 'program.dart';

/// Tuonnin tulos ennen tallennusta (esikatselua varten).
class ImportResult {
  final String source;
  final List<Workout> workouts;

  /// Uudet omat liikkeet: nimi -> kategoria.
  final Map<String, String> newExercises;
  final int sets;
  final int bodyweights;
  final int cardioNotes;

  /// Varmuuskopion asetukset.md ja ohjelma.md (vain omassa varmuuskopiossa).
  final String? settingsMd;
  final String? programMd;

  /// kehonpaino.md (punnitukset ja pituus), jos tuonnissa oli sellainen.
  final String? bodyMd;

  /// Tunnistetut mittaustavat (esim. askelkyykky kirjattu edestakaisina).
  final Map<String, Measure> measures;

  /// Tallennetut ohjelmat (ohjelmat/*.gmd) omasta varmuuskopiosta: tiedostonimi -> sisältö.
  final Map<String, String> savedPrograms;

  /// Väärällä merkistöllä tallennetut tiedostot, jotka luettiin korjattuina ([decodeTextFile]).
  final int repaired;

  /// Treenitiedostot, joita ei voitu lukea: nimi -> alkuperäinen sisältö (ongelmaraportin liitteeksi).
  final Map<String, List<int>> unreadable;

  /// Lukukelvottomien syyt ([unreadableReason]): nimi -> syy.
  Map<String, String> get unreadableWhy => {
    for (final e in unreadable.entries) e.key: why[e.key] ?? unreadableReason(e.value),
  };
  final Map<String, String> why;

  ImportResult({
    required this.source,
    required this.workouts,
    this.repaired = 0,
    this.unreadable = const {},
    this.why = const {},
    this.newExercises = const {},
    this.sets = 0,
    this.bodyweights = 0,
    this.cardioNotes = 0,
    this.settingsMd,
    this.programMd,
    this.bodyMd,
    this.measures = const {},
    this.savedPrograms = const {},
  });

  DateTime? get first => workouts.isEmpty ? null : workouts.first.date;
  DateTime? get last => workouts.isEmpty ? null : workouts.last.date;
  int get existing => workouts.where((w) => store.onDay(w.date).any((x) => x.session == w.session)).length;
}

// ---------------------------------------------------------------------------
// FitNotes (.fitnotes = SQLite-tietokanta)
// ---------------------------------------------------------------------------

const fitnotesCategories = {
  'Shoulders': 'Olkapäät',
  'Triceps': 'Kädet',
  'Biceps': 'Kädet',
  'Forearms': 'Kädet',
  'Chest': 'Rinta',
  'Back': 'Selkä',
  'Legs': 'Jalat',
  'Glutes': 'Jalat',
  'Abs': 'Keskivartalo',
  'Cardio': 'Kardio',
  'Full': 'Koko keho',
};

/// FitNotesin oletusliikkeet, joille on vastine valmiissa luettelossa.
/// Muut (esim. laitekohtaiset) säilyttävät alkuperäisen nimensä ja tulevat omiksi liikkeiksi.
const fitnotesNames = {
  'Barbell Squat': 'Takakyykky',
  'Bench Press': 'Penkkipunnerrus',
  'Flat Barbell Bench Press': 'Penkkipunnerrus',
  'Deadlift': 'Maastaveto',
  'Sumo Deadlift': 'Sumomaastaveto',
  'Barbell Front Squat': 'Etukyykky',
  'Front Squat': 'Etukyykky',
  'Overhead Press': 'Pystypunnerrus',
  'Barbell Shoulder Press': 'Pystypunnerrus',
  'Seated Military Press': 'Pystypunnerrus',
  'Romanian Deadlift': 'Romanialainen maastaveto',
  'Stiff-Legged Deadlift': 'Suorin jaloin maastaveto',
  'Leg Press': 'Jalkaprässi',
  'Lunge': 'Askelkyykky',
  'Dumbbell Lunge': 'Askelkyykky',
  'Bulgarian Split Squat': 'Bulgarialainen askelkyykky',
  'Leg Extension Machine': 'Reiden ojennus',
  'Lying Leg Curl Machine': 'Reiden koukistus',
  'Seated Leg Curl Machine': 'Reiden koukistus',
  'Barbell Hip Thrust': 'Hip thrust',
  'Hip Thrust': 'Hip thrust',
  'Standing Calf Raise Machine': 'Pohjenousu seisten',
  'Seated Calf Raise Machine': 'Pohjenousu istuen',
  'Hack Squat': 'Hack-kyykky',
  'Goblet Squat': 'Goblet-kyykky',
  'Good Morning': 'Good morning',
  'Incline Barbell Bench Press': 'Vinopenkki',
  'Flat Dumbbell Bench Press': 'Käsipainopenkki',
  'Dumbbell Bench Press': 'Käsipainopenkki',
  'Incline Dumbbell Bench Press': 'Vinokäsipainopenkki',
  'Cable Crossover': 'Kaapeliristikkäis',
  'Parallel Bar Triceps Dip': 'Dipit',
  'Dips': 'Dipit',
  'Push Up': 'Punnerrus',
  'Flat Dumbbell Fly': 'Käsipainoaukaisu',
  'Pull Up': 'Leuanveto',
  'Chin Up': 'Leuanveto vastaotteella',
  'Lat Pulldown': 'Ylätalja',
  'Barbell Row': 'Kulmasoutu',
  'Bent Over Row': 'Kulmasoutu',
  'Pendlay Row': 'Pendlay-soutu',
  'Seated Cable Row': 'Alatalja',
  'Dumbbell Row': 'Käsipainosoutu',
  'One-Arm Dumbbell Row': 'Käsipainosoutu',
  'Chest Supported Dumbbell Row': 'Rintatuettu kulmasoutu käsipainoilla',
  'Chest-Supported Dumbbell Row': 'Rintatuettu kulmasoutu käsipainoilla',
  'Incline Dumbbell Row': 'Rintatuettu kulmasoutu käsipainoilla',
  'T-Bar Row': 'T-tankosoutu',
  'Cable Face Pull': 'Face pull',
  'Face Pull': 'Face pull',
  'Back Extension': 'Selän ojennus',
  'Rack Pull': 'Rack pull',
  'Seated Dumbbell Press': 'Käsipainopystypunnerrus',
  'Dumbbell Shoulder Press': 'Käsipainopystypunnerrus',
  'Lateral Dumbbell Raise': 'Vipunosto sivulle',
  'Front Dumbbell Raise': 'Vipunosto eteen',
  'Rear Delt Dumbbell Raise': 'Takaolkavipunosto',
  'Arnold Dumbbell Press': 'Arnold-punnerrus',
  'Upright Barbell Row': 'Pystysoutu',
  'Barbell Shrug': 'Olankohautus',
  'Dumbbell Shrug': 'Olankohautus',
  'Push Press': 'Push press',
  'Barbell Curl': 'Hauiskääntö tangolla',
  'EZ-Bar Curl': 'Hauiskääntö tangolla',
  'Dumbbell Curl': 'Hauiskääntö käsipainoilla',
  'Hammer Curl': 'Vasarakääntö',
  'EZ-Bar Preacher Curl': 'Scott-kääntö',
  'Cable Curl': 'Hauiskääntö taljassa',
  'Dumbbell Concentration Curl': 'Keskittynyt hauiskääntö',
  'Rope Push Down': 'Ojentajapunnerrus taljassa',
  'V-Bar Push Down': 'Ojentajapunnerrus taljassa',
  'Lying Triceps Extension': 'Ranskalainen punnerrus',
  'EZ-Bar Skullcrusher': 'Ranskalainen punnerrus',
  'Close Grip Barbell Bench Press': 'Kapea penkki',
  'Bench Press (Narrow)': 'Kapea penkki',
  'Overhead Triceps Extension': 'Ojentajapunnerrus pään yli',
  'Barbell Wrist Curls': 'Ranteen koukistus',
  'Plank': 'Lankku',
  'Side Plank': 'Kylkilankku',
  'Crunch': 'Vatsarutistus',
  'Hanging Leg Raise': 'Jalannosto roikkuen',
  'Ab Wheel': 'Ab wheel',
  'Cable Crunch': 'Kaapelirutistus',
  'Russian Twist': 'Venäläinen twisti',
  'Farmer Walk': 'Farmer walk',
};

String mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Nimi treenille sen perusteella, mitä siinä tehtiin eniten.
String autoTitle(Workout w) {
  final count = <BodyGroup, int>{};
  for (final e in w.exercises) {
    count[bodyGroupOf(e.name)] = (count[bodyGroupOf(e.name)] ?? 0) + e.sets.length;
  }
  if (count.isEmpty) return 'Treeni';
  final total = count.values.fold(0, (a, b) => a + b);
  final legs = count[BodyGroup.legs] ?? 0;
  final upper = count[BodyGroup.upper] ?? 0;
  if (legs > total * .6) return 'Jalkapäivä';
  if (upper > total * .6) return 'Ylävartalo';
  return 'Koko keho';
}

// --- Vienti FitNotes-muotoon (kokeellinen) ---------------------------------

/// FitNotesin kategoria liikkeelle (FitNotesissa liike kuuluu yhteen kategoriaan).
String fitnotesCategoryFor(String name) {
  final n = name.toLowerCase();
  switch (categoryOf(name)) {
    case 'Jalat':
      return 'Legs';
    case 'Rinta':
      return 'Chest';
    case 'Selkä':
      return 'Back';
    case 'Olkapäät':
      return 'Shoulders';
    case 'Keskivartalo':
      return 'Abs';
    case 'Kardio':
      return 'Cardio';
    case 'Koko keho':
      return 'Full';
    case 'Kädet':
      if (RegExp(r'tricep|ojentaj|kapea|dip|push ?down|skull').hasMatch(n)) return 'Triceps';
      if (RegExp(r'wrist|ranne|ranteen|grip|forearm').hasMatch(n)) return 'Forearms';
      return 'Biceps';
    case 'Voimanosto':
      if (n.contains('kyykky')) return 'Legs';
      if (n.contains('maastaveto')) return 'Back';
      if (n.contains('pystypunnerrus')) return 'Shoulders';
      return 'Chest';
    default:
      return 'Full';
  }
}

// ---------------------------------------------------------------------------
// Treenipäiväkirjan oma varmuuskopio: zip, jossa kansion .md-tiedostot sellaisenaan.
// ---------------------------------------------------------------------------

final _dateFile = RegExp(r'^(\d{4}-\d{2}-\d{2}).*\.md$');

Future<Uint8List> exportZip() async {
  final root = await store.rootDir();
  final archive = Archive();
  if (await root.exists()) {
    await for (final f in root.list(recursive: true, followLinks: false)) {
      if (f is! File || !isDataFile(f.path)) continue;
      final rel = p.relative(f.path, from: root.path).replaceAll('\\', '/');
      // Sovelluksen omat varmuuskopiot eivät kuulu varmuuskopioon (ei sisäkkäisiä kopioita).
      if (isAutoBackupPath(rel)) continue;
      archive.addFile(ArchiveFile.bytes('Treenit/$rel', await f.readAsBytes()));
    }
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Yksittäiset .md-treenit (esim. PC:llä tehdyt, joita Drive-synkronointi ei näe): nimi -> sisältö.
/// Päivämäärä otsikkotiedoista tai tiedostonimestä. Asetukset ja ohjelma ohitetaan.
ImportResult readMdFiles(Map<String, String> files, {int repaired = 0, Map<String, List<int>>? unreadable}) {
  final failed = unreadable ?? <String, List<int>>{};
  final why = <String, String>{};
  final list = <Workout>[];
  var sets = 0;
  String? bodyMd;
  for (final e in files.entries) {
    final base = p.basename(e.key);
    if (base == settingsFileName || base == 'ohjelma.md') continue;
    if (base == bodyFileName) {
      bodyMd = e.value;
      continue;
    }
    final m = _dateFile.firstMatch(base);
    try {
      final w = parseWorkout(
        e.value,
        fallbackDate: m == null ? null : DateTime.parse(m[1]!),
        fallbackSession: sessionFromName(base),
      );
      sets += w.exercises.fold(0, (a, x) => a + x.sets.length);
      list.add(w);
    } catch (err) {
      failed[base] = utf8.encode(e.value);
      why[base] = unreadableReason(failed[base], error: err);
    }
  }
  list.sort((a, b) => a.date.compareTo(b.date));
  return ImportResult(
    source: '.md-tiedostot',
    workouts: list,
    sets: sets,
    bodyMd: bodyMd,
    repaired: repaired,
    unreadable: failed,
    why: why,
  );
}

/// Valitut .md-tiedostot tavuina: merkistö tunnistetaan ([decodeTextFile]), lukukelvottomat raporttia varten.
ImportResult readMdBytes(Map<String, List<int>> files) {
  final texts = <String, String>{};
  final failed = <String, List<int>>{};
  var repaired = 0;
  for (final e in files.entries) {
    final d = decodeTextFile(e.value);
    if (d == null) {
      failed[p.basename(e.key)] = e.value;
      continue;
    }
    texts[e.key] = d.$1;
    if (d.$2) repaired++;
  }
  return readMdFiles(texts, repaired: repaired, unreadable: failed);
}

ImportResult readZip(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final list = <Workout>[];
  String? settingsMd, programMd, bodyMd;
  final routes = <String, String>{}; // reittitiedoston nimi -> GPX
  final saved = <String, String>{}; // tallennetut ohjelmat (.gmd)
  final failed = <String, List<int>>{};
  final why = <String, String>{};
  var sets = 0, repaired = 0;
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final base = p.basename(f.name);
    final decoded = decodeTextFile(f.content);
    if (decoded != null && decoded.$2) repaired++;
    final text = decoded?.$1 ?? utf8.decode(f.content, allowMalformed: true);
    if (base.endsWith('.gpx')) {
      routes[base] = text;
      continue;
    }
    if (base.endsWith('.gmd')) {
      saved[base] = text;
      continue;
    }
    if (base == settingsFileName) {
      settingsMd = text;
      continue;
    }
    if (base == 'ohjelma.md') {
      programMd = text;
      continue;
    }
    if (base == bodyFileName) {
      bodyMd = text;
      continue;
    }
    final m = _dateFile.firstMatch(base);
    if (m == null) continue;
    if (decoded == null) {
      failed[base] = f.content;
      continue;
    }
    try {
      final w = parseWorkout(text, fallbackDate: DateTime.parse(m[1]!), fallbackSession: sessionFromName(base));
      sets += w.exercises.fold(0, (a, e) => a + e.sets.length);
      list.add(w);
    } catch (err) {
      failed[base] = f.content;
      why[base] = unreadableReason(f.content, error: err);
    }
  }
  // Reitit mukaan treeneille, joiden .md viittaa niihin; kirjoitetaan tallennettaessa (store.saveMany).
  for (final w in list) {
    final gpx = routes[w.route];
    if (gpx != null) {
      w.routeGpx = gpx;
    } else {
      w.route = null; // reittitiedosto puuttuu varmuuskopiosta
    }
  }
  list.sort((a, b) => a.date.compareTo(b.date));
  return ImportResult(
    source: 'Gievra',
    workouts: list,
    sets: sets,
    settingsMd: settingsMd,
    programMd: programMd,
    bodyMd: bodyMd,
    savedPrograms: saved,
    repaired: repaired,
    unreadable: failed,
    why: why,
  );
}

/// Palautetaanko oman varmuuskopion asetukset ja ohjelma kokonaan: kun päiväkirjassa ei vielä ole treenejä
/// (uusi puhelin tai uusi asennus). Muuten yhdistetään nykyisiin.
bool restoresAll(ImportResult r) => store.workouts.isEmpty && (r.settingsMd != null || r.programMd != null);

/// Varmuuskopion vamma-alueet, joita tässä päiväkirjassa ei ole valittuna. Vain yhdistettäessä (tyhjään
/// päiväkirjaan asetukset palautuvat sellaisinaan): vammatila kuvaa nykytilaa, joten käyttäjä päättää itse.
List<String> newInjuries(ImportResult r) {
  if (r.settingsMd == null || restoresAll(r)) return const [];
  final tmp = Settings()..applyMarkdown(r.settingsMd!);
  return [
    for (final id in tmp.injuries)
      if (!settings.injuries.contains(id) && injuryById(id) != null) id,
  ];
}

/// Tallentaa tuonnin: uudet treenit (olemassa olevat päivät ohitetaan) ja omat liikkeet.
/// Omasta varmuuskopiosta: tyhjään päiväkirjaan asetukset ja ohjelma sellaisinaan, muuten lämmittelylaitteet,
/// omat liikkeet mittaustapoineen ja tallennetut ohjelmat yhdistetään nykyisiin.
/// [addInjuries]: käyttäjä valitsi tuonnin yhteenvedossa ottaa varmuuskopion vamma-alueet käyttöön ([newInjuries]).
Future<int> applyImport(ImportResult r, {bool addInjuries = false}) async {
  if (addInjuries) {
    final add = newInjuries(r);
    if (add.isNotEmpty) settings.setInjuries([...settings.injuries, ...add]);
  }
  for (final e in r.savedPrograms.entries) {
    final rel = 'ohjelmat/${e.key}';
    if (!await files.exists(rel)) await files.write(rel, e.value);
  }
  if (restoresAll(r)) {
    if (r.settingsMd != null) await files.write(settingsFileName, r.settingsMd!);
    if (r.programMd != null) await files.write(programFileName, r.programMd!);
    await settings.loadFromFolder();
  } else if (r.settingsMd != null) {
    final tmp = Settings()..applyMarkdown(r.settingsMd!);
    final names = settings.equipment.map((e) => e.name).toSet();
    settings.setEquipment([...settings.equipment, ...tmp.equipment.where((e) => !names.contains(e.name))]);
    settings.addCustomExercises({for (final n in tmp.customExercises) n: tmp.customCategory[n] ?? ownCategory});
    // Treenityyli ja ohjelma, jos tällä laitteella ei vielä ole omaa (ei ylikirjoiteta).
    if ((settings.style == null || settings.style!.isEmpty) && tmp.style != null) settings.setStyle(tmp.style);
    // Omien liikkeiden mittaustavat (esim. aika tai matka), jos niitä ei vielä ole tällä laitteella.
    for (final e in tmp.customMeasure.entries) {
      if (!settings.customMeasure.containsKey(e.key)) settings.setMeasure(e.key, e.value);
    }
    // Sairas- ja lomatauot: ilman niitä paluun kevyemmät kuormat ja käynnissä oleva tauko katosivat.
    // Kuten sovelluksessa, vain salitreeni päättää tauon; kävely tai muu liikunta tauon aikana ei.
    settings.mergePauses(
      tmp.pauses,
      trainedDays: [
        for (final w in store.workouts)
          if (w.activity == null) w.date,
      ],
    );
  }
  if (r.programMd != null && settings.program == null) {
    final prog = parseProgram(r.programMd!);
    if (prog != null) await settings.setProgram(prog);
  }
  // Punnitukset ja pituus: puuttuvat lisätään, olemassa olevia ei muuteta. Seuranta päälle, jos sitä käytettiin.
  if (r.bodyMd != null) {
    final imported = parseBody(r.bodyMd!);
    if (!imported.isEmpty) {
      await settings.setBody(mergeBody(settings.body, imported));
      if (r.settingsMd != null && (Settings()..applyMarkdown(r.settingsMd!)).bodyTracker) {
        settings.setBodyTracker(true);
      }
    }
  }
  settings.addCustomExercises(r.newExercises);
  for (final e in r.measures.entries) {
    if (measureOf(e.key) != e.value) settings.setMeasure(e.key, e.value);
  }
  return store.saveMany(r.workouts);
}
