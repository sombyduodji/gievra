import 'exercise_names_en.dart';
import 'l10n.dart';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

/// Valmis liikeluettelo. Omat liikkeet tallentuvat asetuksiin (kategoria "Omat").
const Map<String, List<String>> exerciseCatalog = {
  'Voimanosto': [
    'Takakyykky',
    'Penkkipunnerrus',
    'Maastaveto',
    'Sumomaastaveto',
    'Etukyykky',
    'Taukopenkki',
    'Pystypunnerrus',
    'Low bar -kyykky',
    'Box-kyykky',
    'Lattiapunnerrus',
  ],
  'Jalat': [
    'Jalkaprässi',
    'Romanialainen maastaveto',
    'Suorin jaloin maastaveto',
    'Askelkyykky',
    'Bulgarialainen askelkyykky',
    'Askelkyykkykävely',
    'Reiden ojennus',
    'Reiden koukistus',
    'Hip thrust',
    'Pohjenousu seisten',
    'Pohjenousu istuen',
    'Hack-kyykky',
    'Goblet-kyykky',
    'Smith-kyykky',
    'Lonkan loitonnus',
    'Lonkan lähennys',
    'Good morning',
    'Nordic hamstring',
    'Kööpenhaminan lähennys',
    'Pistoolikyykky',
    'Lantionnosto',
  ],
  'Rinta': [
    'Vinopenkki',
    'Käsipainopenkki',
    'Vinokäsipainopenkki',
    'Kaapeliristikkäis',
    'Dipit',
    'Punnerrus',
    'Peck deck',
    'Käsipainoaukaisu',
    'Rintaprässi laitteessa',
    'Smith-vinopenkki',
  ],
  'Selkä': [
    'Leuanveto',
    'Leuanveto vastaotteella',
    'Ylätalja',
    'Kulmasoutu',
    'Alatalja',
    'Käsipainosoutu',
    'T-tankosoutu',
    'Pendlay-soutu',
    'Selän ojennus',
    'Olankohautus',
    'Suorin käsin ylätalja',
    'Rack pull',
    'Soutu laitteessa',
    'Australialainen leuanveto',
  ],
  'Olkapäät': [
    'Käsipainopystypunnerrus',
    'Vipunosto sivulle',
    'Vipunosto eteen',
    'Takaolkavipunosto',
    'Arnold-punnerrus',
    'Pystysoutu',
    'Face pull',
    'Push press',
    'Vipunosto taljassa',
    'Olkapääprässi laitteessa',
    'Ulkokierto taljassa',
    'Pike-punnerrus',
  ],
  'Kädet': [
    'Hauiskääntö tangolla',
    'Hauiskääntö käsipainoilla',
    'Vasarakääntö',
    'Scott-kääntö',
    'Hauiskääntö taljassa',
    'Keskittynyt hauiskääntö',
    'Ojentajapunnerrus taljassa',
    'Ranskalainen punnerrus',
    'Kapea penkki',
    'Ojentajapunnerrus pään yli',
    'Penkkidipit',
    'Ranteen koukistus',
    'Ranteen ojennus',
  ],
  'Keskivartalo': [
    'Lankku',
    'Vatsarutistus',
    'Jalannosto roikkuen',
    'Ab wheel',
    'Pallof press',
    'Venäläinen twisti',
    'Kaapelirutistus',
    'Kylkilankku',
    'Farmer walk',
  ],
  // Lähde: StrengthLog, The Ultimate Guide to Bodyweight Exercises (45+ liikettä liikemalleittain).
  'Kehonpaino': [
    'Kyykky kehonpainolla',
    'Hyppykyykky',
    'Sissy-kyykky',
    'Käänteinen nordic',
    'Askelnousu',
    'Jalat koholla punnerrus',
    'Timanttipunnerrus',
    'Ojentajaojennus kehonpainolla',
    'Kehonpainohauiskääntö',
    'Käsilläseisontapunnerrus',
    'Y-T-W-nostot makuulla',
    'Yhden jalan lantionnosto',
    'Reiden koukistus kehonpainolla',
    'Veneasento',
    'Dead bug',
    'Superman-nosto',
    'Burpee',
    'Vinopunnerrus',
    'Polvipunnerrus',
    'Negatiivinen leuanveto',
    'Kuminauhaleuanveto',
    'Roikunta',
    'Lapaluuveto roikkuen',
    'Seinäistunta',
    'Lintukoira',
    'Vuorikiipeilijä',
    'Karhukävely',
    'Yhden jalan pohjenousu',
  ],
  // Lähteet: garagegymreviews.com, Rogue Movement Library, Nuffield Health (ydinliikkeet: heilautus,
  // goblet-kyykky, rinnalleveto, punnerrus, tempaus, ylösnousu, tuulimylly, soutu, kanto).
  'Kahvakuula': [
    'Kahvakuulaheilautus',
    'Yhden käden heilautus',
    'Kahvakuulamaastaveto',
    'Kahvakuulan rinnalleveto',
    'Kahvakuulapystypunnerrus',
    'Rinnalleveto ja punnerrus',
    'Kahvakuulatempaus',
    'Kahvakuulan etukyykky',
    'Kahvakuula-thruster',
    'Yhden jalan maastaveto',
    'Kahvakuulasoutu',
    'Renegade-soutu',
    'Kahvakuulalattiapunnerrus',
    'Turkkilainen ylösnousu',
    'Tuulimylly',
    'Matkalaukkukanto',
    'Kahvakuulan sumomaastaveto',
    'Kahvakuulan sumoveto',
    'Kahvakuulahauiskääntö',
    'Kahvakuula-askelkyykky',
    'Lentokone',
    'Tuplakahvakuulaheilautus',
    'Tuplakahvakuulamaastaveto',
    'Tuplakahvakuulan rinnalleveto',
    'Tuplakahvakuulapystypunnerrus',
    'Tuplakahvakuulatyöntö',
    'Tuplakahvakuulan rinnalleveto ja punnerrus',
    'Tuplakahvakuulasoutu',
    'Tuplakahvakuulalattiapunnerrus',
    'Tuplakahvakuula-askelkyykky',
  ],
};

/// Välineet. Ohjelman välinetoive suosii liikkeitä, joiden väline on valittu.
enum Equip { tanko, kasipaino, laite, talja, kahvakuula, kehonpaino }

/// Ohjelman välinetoiveet (aloituskysely) -> välineet.
// l10n: data
const equipmentChoices = <String, (String, String, Set<Equip>)>{
  'vapaat': ('🏋️', 'Vapaat painot (tangot, käsipainot)', {Equip.tanko, Equip.kasipaino}),
  'laitteet': ('⚙️', 'Laitteet ja taljat', {Equip.laite, Equip.talja}),
  'kahvakuula': ('🔔', 'Kahvakuulat', {Equip.kahvakuula}),
  'kehonpaino': ('🤸', 'Oma kehonpaino', {Equip.kehonpaino}),
};

const _t = Equip.tanko,
    _k = Equip.kasipaino,
    _l = Equip.laite,
    _ta = Equip.talja,
    _kb = Equip.kahvakuula,
    _bw = Equip.kehonpaino;

/// Liike -> välineet, joilla sen voi tehdä.
const exerciseEquipment = <String, Set<Equip>>{
  'Takakyykky': {_t},
  'Penkkipunnerrus': {_t},
  'Maastaveto': {_t},
  'Sumomaastaveto': {_t},
  'Etukyykky': {_t},
  'Taukopenkki': {_t},
  'Pystypunnerrus': {_t},
  'Low bar -kyykky': {_t},
  'Box-kyykky': {_t},
  'Lattiapunnerrus': {_t, _k},
  'Jalkaprässi': {_l},
  'Romanialainen maastaveto': {_t, _k, _kb},
  'Suorin jaloin maastaveto': {_t, _k},
  'Askelkyykky': {_k, _t, _kb, _bw},
  'Bulgarialainen askelkyykky': {_k, _kb, _bw},
  'Askelkyykkykävely': {_k, _kb, _bw},
  'Reiden ojennus': {_l},
  'Reiden koukistus': {_l},
  'Hip thrust': {_t, _l},
  'Pohjenousu seisten': {_l, _k, _bw},
  'Pohjenousu istuen': {_l},
  'Hack-kyykky': {_l},
  'Goblet-kyykky': {_k, _kb},
  'Smith-kyykky': {_l},
  'Lonkan loitonnus': {_l, _ta},
  'Lonkan lähennys': {_l, _ta},
  'Good morning': {_t},
  'Nordic hamstring': {_bw},
  'Kööpenhaminan lähennys': {_bw},
  'Pistoolikyykky': {_bw},
  'Lantionnosto': {_bw, _kb},
  'Vinopenkki': {_t},
  'Käsipainopenkki': {_k},
  'Vinokäsipainopenkki': {_k},
  'Kaapeliristikkäis': {_ta},
  'Dipit': {_bw},
  'Punnerrus': {_bw},
  'Peck deck': {_l},
  'Käsipainoaukaisu': {_k},
  'Rintaprässi laitteessa': {_l},
  'Smith-vinopenkki': {_l},
  'Leuanveto': {_bw},
  'Leuanveto vastaotteella': {_bw},
  'Ylätalja': {_ta},
  'Kulmasoutu': {_t},
  'Alatalja': {_ta},
  'Käsipainosoutu': {_k},
  'T-tankosoutu': {_t},
  'Pendlay-soutu': {_t},
  'Selän ojennus': {_bw, _l},
  'Olankohautus': {_t, _k},
  'Suorin käsin ylätalja': {_ta},
  'Rack pull': {_t},
  'Soutu laitteessa': {_l},
  'Australialainen leuanveto': {_bw},
  'Käsipainopystypunnerrus': {_k},
  'Vipunosto sivulle': {_k},
  'Vipunosto eteen': {_k, _kb},
  'Takaolkavipunosto': {_k, _ta},
  'Arnold-punnerrus': {_k},
  'Pystysoutu': {_t, _k, _kb},
  'Face pull': {_ta},
  'Push press': {_t, _kb},
  'Vipunosto taljassa': {_ta},
  'Olkapääprässi laitteessa': {_l},
  'Ulkokierto taljassa': {_ta},
  'Pike-punnerrus': {_bw},
  'Hauiskääntö tangolla': {_t},
  'Hauiskääntö käsipainoilla': {_k},
  'Vasarakääntö': {_k},
  'Scott-kääntö': {_t, _l},
  'Hauiskääntö taljassa': {_ta},
  'Keskittynyt hauiskääntö': {_k},
  'Ojentajapunnerrus taljassa': {_ta},
  'Ranskalainen punnerrus': {_t, _k},
  'Kapea penkki': {_t},
  'Ojentajapunnerrus pään yli': {_k, _ta, _kb},
  'Penkkidipit': {_bw},
  'Ranteen koukistus': {_t, _k},
  'Ranteen ojennus': {_t, _k},
  'Lankku': {_bw},
  'Vatsarutistus': {_bw},
  'Jalannosto roikkuen': {_bw},
  'Ab wheel': {_bw},
  'Pallof press': {_ta},
  'Venäläinen twisti': {_bw, _k, _kb},
  'Kaapelirutistus': {_ta},
  'Kylkilankku': {_bw},
  'Farmer walk': {_k, _kb},
  'Kyykky kehonpainolla': {_bw},
  'Hyppykyykky': {_bw},
  'Sissy-kyykky': {_bw},
  'Käänteinen nordic': {_bw},
  'Askelnousu': {_bw, _k},
  'Jalat koholla punnerrus': {_bw},
  'Timanttipunnerrus': {_bw},
  'Ojentajaojennus kehonpainolla': {_bw},
  'Kehonpainohauiskääntö': {_bw},
  'Käsilläseisontapunnerrus': {_bw},
  'Y-T-W-nostot makuulla': {_bw},
  'Yhden jalan lantionnosto': {_bw},
  'Reiden koukistus kehonpainolla': {_bw},
  'Veneasento': {_bw},
  'Dead bug': {_bw},
  'Superman-nosto': {_bw},
  'Burpee': {_bw},
  'Vinopunnerrus': {_bw},
  'Polvipunnerrus': {_bw},
  'Negatiivinen leuanveto': {_bw},
  'Kuminauhaleuanveto': {_bw},
  'Roikunta': {_bw},
  'Lapaluuveto roikkuen': {_bw},
  'Seinäistunta': {_bw},
  'Lintukoira': {_bw},
  'Vuorikiipeilijä': {_bw},
  'Karhukävely': {_bw},
  'Yhden jalan pohjenousu': {_bw},
  'Kahvakuulaheilautus': {_kb},
  'Yhden käden heilautus': {_kb},
  'Kahvakuulamaastaveto': {_kb},
  'Kahvakuulan rinnalleveto': {_kb},
  'Rinnalleveto ja punnerrus': {_kb},
  'Kahvakuulatempaus': {_kb},
  'Kahvakuulapystypunnerrus': {_kb},
  'Kahvakuulan etukyykky': {_kb},
  'Kahvakuulan sumomaastaveto': {_kb},
  'Kahvakuulan sumoveto': {_kb},
  'Kahvakuulahauiskääntö': {_kb},
  'Kahvakuula-askelkyykky': {_kb},
  'Lentokone': {_kb},
  'Tuplakahvakuulaheilautus': {_kb},
  'Tuplakahvakuulamaastaveto': {_kb},
  'Tuplakahvakuulan rinnalleveto': {_kb},
  'Tuplakahvakuulapystypunnerrus': {_kb},
  'Tuplakahvakuulatyöntö': {_kb},
  'Tuplakahvakuulan rinnalleveto ja punnerrus': {_kb},
  'Tuplakahvakuulasoutu': {_kb},
  'Tuplakahvakuulalattiapunnerrus': {_kb},
  'Tuplakahvakuula-askelkyykky': {_kb},
  'Kahvakuula-thruster': {_kb},
  'Yhden jalan maastaveto': {_kb, _k},
  'Kahvakuulasoutu': {_kb},
  'Renegade-soutu': {_kb, _k},
  'Kahvakuulalattiapunnerrus': {_kb},
  'Turkkilainen ylösnousu': {_kb},
  'Tuulimylly': {_kb},
  'Matkalaukkukanto': {_kb, _k},
};

/// Liikkeet, joilla on oma toistoalue: räjähtävät kahvakuulaliikkeet tehdään useammalla toistolla
/// kevyemmällä kuulalla, ylösnousu ja tuulimylly harvoilla hallituilla toistoilla.
const repRangeOverride = <String, (int, int)>{
  'Kahvakuulaheilautus': (10, 20),
  'Yhden käden heilautus': (8, 15),
  'Kahvakuulan rinnalleveto': (5, 10),
  'Kahvakuulatempaus': (5, 10),
  'Turkkilainen ylösnousu': (1, 3),
  'Tuulimylly': (3, 6),
};

/// Tehdäänkö liike pelkästään valituilla välineillä.
bool onlyEquipment(String exercise, Set<String> prefs) {
  final eq = exerciseEquipment[exercise];
  if (eq == null) return false;
  final allowed = {for (final p in prefs) ...equipmentChoices[p]!.$3};
  return eq.every(allowed.contains);
}

/// Sopiiko liike välinetoiveisiin (tyhjä = ei toivetta). Omat liikkeet sopivat aina.
bool fitsEquipment(String exercise, Set<String> prefs) {
  if (prefs.isEmpty || prefs.length == equipmentChoices.length) return true;
  final eq = exerciseEquipment[exercise];
  if (eq == null) return true;
  return prefs.any((p) => equipmentChoices[p]!.$3.any(eq.contains));
}

/// Liikkeet, jotka väritetään jaloiksi kategoriasta riippumatta (kyykyt ja lonkkasaranat).
const _legsPowerlifting = {
  'Seinäistunta',
  'Yhden jalan pohjenousu',
  'Kyykky kehonpainolla',
  'Hyppykyykky',
  'Sissy-kyykky',
  'Käänteinen nordic',
  'Askelnousu',
  'Yhden jalan lantionnosto',
  'Reiden koukistus kehonpainolla',
  'Takakyykky',
  'Maastaveto',
  'Sumomaastaveto',
  'Etukyykky',
  'Low bar -kyykky',
  'Box-kyykky',
  'Rack pull',
  'Kahvakuulaheilautus',
  'Yhden käden heilautus',
  'Kahvakuulamaastaveto',
  'Kahvakuulan rinnalleveto',
  'Kahvakuulatempaus',
  'Kahvakuulan etukyykky',
  'Kahvakuula-thruster',
  'Yhden jalan maastaveto',
  'Kahvakuulan sumomaastaveto',
  'Kahvakuulan sumoveto',
  'Kahvakuula-askelkyykky',
  'Tuplakahvakuulaheilautus',
  'Tuplakahvakuulamaastaveto',
  'Tuplakahvakuulan rinnalleveto',
  'Tuplakahvakuula-askelkyykky',
};
const _coreExtra = {
  'Lintukoira',
  'Vuorikiipeilijä',
  'Karhukävely',
  'Turkkilainen ylösnousu',
  'Tuulimylly',
  'Matkalaukkukanto',
  'Veneasento',
  'Dead bug',
  'Superman-nosto',
  'Burpee',
};

/// Vanhat nimet -> uudet (lähdetarkistus 2026-11-06). Vanhat .md-tiedostot luetaan uusilla nimillä.
const exerciseRenames = {'Hyperextensio': 'Selän ojennus', 'Ojentajadipit': 'Penkkidipit'};

/// Toispuoliset liikkeet: määrä kirjataan per puoli.
const perSideExercises = {
  'Lintukoira',
  'Yhden jalan pohjenousu',
  'Askelnousu',
  'Yhden jalan lantionnosto',
  'Dead bug',
  'Käsipainosoutu',
  'Bulgarialainen askelkyykky',
  'Askelkyykky',
  'Keskittynyt hauiskääntö',
  'Vipunosto taljassa',
  'Ulkokierto taljassa',
  'Kööpenhaminan lähennys',
  'Kylkilankku',
  'Venäläinen twisti',
  'Pistoolikyykky',
  'Yhden käden heilautus',
  'Kahvakuulapystypunnerrus',
  'Yhden jalan maastaveto',
  'Kahvakuulasoutu',
  'Turkkilainen ylösnousu',
  'Tuulimylly',
  'Kahvakuulatempaus',
  'Kahvakuulan rinnalleveto',
  'Rinnalleveto ja punnerrus',
};

enum BodyGroup { legs, upper, core }

/// Miten liike mitataan. Paino on aina lisäpaino (0 kg = oma paino).
// l10n: data
enum Measure {
  reps('toistot', 'toistoa', '', 1, 8),
  seconds('sekunnit', 's', 's', 5, 30),
  steps('askeleet', 'askelta', 'askelta', 2, 20),
  trips('edestakaiset', 'edestakaisin', 'edestakaisin', 1, 2),
  meters('metrit', 'm', 'm', 10, 30);

  final String label, unit, suffix;
  final int step, initial;
  const Measure(this.label, this.unit, this.suffix, this.step, this.initial);
  static Measure? byName(String s) => Measure.values.where((m) => m.name == s || m.label == s).firstOrNull;
}

/// Oletusmittaustavat (muut: toistot). Käyttäjä voi vaihtaa liikkeen mittaustavan.
const _builtinMeasure = {
  'Lankku': Measure.seconds,
  'Kylkilankku': Measure.seconds,
  'Farmer walk': Measure.trips,
  'Matkalaukkukanto': Measure.trips,
  'Veneasento': Measure.seconds,
  'Roikunta': Measure.seconds,
  'Seinäistunta': Measure.seconds,
  'Vuorikiipeilijä': Measure.seconds,
  'Karhukävely': Measure.seconds,
  'Askelkyykkykävely': Measure.steps,
};

/// Kahdella kahvakuulalla tehtävät liikkeet: paino kirjataan per kuula (kuten käsipainoissa per käsi),
/// ja volyymiin lasketaan molemmat kuulat.
const pairedKettlebell = {
  'Kahvakuulan etukyykky',
  'Kahvakuula-thruster',
  'Tuplakahvakuulaheilautus',
  'Tuplakahvakuulamaastaveto',
  'Tuplakahvakuulan rinnalleveto',
  'Tuplakahvakuulapystypunnerrus',
  'Tuplakahvakuulatyöntö',
  'Tuplakahvakuulan rinnalleveto ja punnerrus',
  'Tuplakahvakuulasoutu',
  'Tuplakahvakuulalattiapunnerrus',
  'Tuplakahvakuula-askelkyykky',
};

/// Liike tehdään vain kahvakuulalla (painoehdotus kuulakokojen mukaan).
bool kettlebellOnly(String exercise) {
  final eq = exerciseEquipment[exercise];
  return eq != null && eq.length == 1 && eq.contains(Equip.kahvakuula);
}

/// Yleiset kahvakuulakoot (kg).
const kettlebellSizes = [4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0];

/// Seuraava kuulakoko (tai +4 kg, jos isompaa ei ole luettelossa).
double nextKettlebell(double kg) => kettlebellSizes.firstWhere((s) => s > kg + .01, orElse: () => kg + 4);

/// Kerroin volyymille: tuplakahvakuulaliikkeissä 2 (kaksi kuulaa), muuten 1.
int loadMultiplier(String exercise) => pairedKettlebell.contains(exercise) ? 2 : 1;

/// "Jäikö varaa?" mittaustavan mukaan: toistoliikkeissä toistoja varastossa, aikaliikkeissä
/// olisiko jaksanut pidempään, matkaliikkeissä pidemmälle. Arvot 0 / 1 / 3 kuten RIR.
class ReserveWords {
  final String question;
  final List<(int, String)> answers; // napit
  final Map<int, String> short; // tallennetun sarjan merkintä
  const ReserveWords(this.question, this.answers, this.short);
}

/// Käyttöliittymän tekstit (käännetään), ei tallenneta tiedostoon.
ReserveWords reserveWords(Measure m) => switch (m) {
  Measure.reps => ReserveWords(
    t('Jäikö varaa?'),
    [(0, t('Ei yhtään')), (1, t('Muutama')), (3, t('Reilusti'))],
    {0: t('ei varaa'), 1: t('muutama'), 3: t('reilusti')},
  ),
  Measure.seconds => ReserveWords(
    t('Olisitko jaksanut pidempään?'),
    [(0, t('En yhtään')), (1, t('Vähän')), (3, t('Reilusti'))],
    {0: t('ei varaa'), 1: t('vähän varaa'), 3: t('reilusti varaa')},
  ),
  _ => ReserveWords(
    t('Olisitko jaksanut pidemmälle?'),
    [(0, t('En yhtään')), (1, t('Vähän')), (3, t('Reilusti'))],
    {0: t('ei varaa'), 1: t('vähän varaa'), 3: t('reilusti varaa')},
  ),
};

/// Ohjelman tavoitevara tekstinä: toistoliikkeissä "varaa 1–3", muissa sanallisesti.
String reserveTarget(Measure m, String rir) => m == Measure.reps
    ? t('varaa {0}', [rir])
    : rir.startsWith('0')
    ? t('melkein loppuun asti')
    : t('jätä vähän varaa');

Measure measureOf(String exercise) => settings.customMeasure[exercise] ?? _builtinMeasure[exercise] ?? Measure.reps;

/// Sarja tekstinä liikkeen mittaustavan mukaan: "100 kg × 5", "45 s", "20 kg × 2 edestakaisin".
String fmtSet(String exercise, SetEntry s) {
  final m = measureOf(exercise);
  if (m == Measure.reps) return '${fmtNum(s.kg)} kg × ${s.reps}';
  return s.kg == 0 ? '${s.reps} ${m.unit}' : '${fmtNum(s.kg)} kg × ${s.reps} ${m.unit}';
}

/// Hakusanat: arkikieli ja englanti (FitNotes / netti), jotta "lankutus" tai "plank" löytää Lankun.
const _aliases = {
  'Lankku': ['lankutus', 'plank'],
  'Kylkilankku': ['sivulankku', 'side plank'],
  'Takakyykky': ['kyykky', 'squat', 'back squat'],
  'Etukyykky': ['front squat'],
  'Penkkipunnerrus': ['penkki', 'bench', 'bench press'],
  'Maastaveto': ['deadlift', 'mave'],
  'Sumomaastaveto': ['sumo'],
  'Pystypunnerrus': ['overhead press', 'ohp', 'military press'],
  'Leuanveto': ['leuat', 'pull up', 'chin up'],
  'Ylätalja': ['lat pulldown', 'pulldown', 'pull down'],
  'Alatalja': ['seated row', 'cable row'],
  'Kulmasoutu': ['barbell row', 'bent over row'],
  'Askelkyykky': ['lunge', 'askel'],
  'Askelkyykkykävely': ['walking lunge', 'lunge', 'askel'],
  'Bulgarialainen askelkyykky': ['bulgarian', 'split squat'],
  'Romanialainen maastaveto': ['rdl', 'romanian'],
  'Jalkaprässi': ['leg press', 'prässi'],
  'Reiden ojennus': ['leg extension', 'etureisi'],
  'Reiden koukistus': ['leg curl', 'takareisi'],
  'Pohjenousu seisten': ['calf raise', 'pohje'],
  'Pohjenousu istuen': ['seated calf', 'pohje'],
  'Vipunosto sivulle': ['lateral raise', 'sivunosto'],
  'Takaolkavipunosto': ['rear delt', 'takaolka'],
  'Face pull': ['facepull', 'kasvoveto'],
  'Hauiskääntö tangolla': ['hauis', 'biceps curl', 'curl'],
  'Hauiskääntö käsipainoilla': ['hauis', 'dumbbell curl', 'curl'],
  'Vasarakääntö': ['hammer curl'],
  'Ojentajapunnerrus taljassa': ['ojentaja', 'triceps pushdown', 'push down'],
  'Ranskalainen punnerrus': ['skullcrusher', 'ojentaja'],
  'Dipit': ['dip', 'dippi'],
  'Farmer walk': ['farmari', 'kanto', 'farmers carry'],
  'Selän ojennus': ['hyperextensio', 'hyperekstensio', 'back extension'],
  'Penkkidipit': ['ojentajadipit', 'bench dip', 'dipit'],
  'Olankohautus': ['shrug', 'trapetsi'],
  'Vatsarutistus': ['vatsat', 'crunch'],
  'Kaapelirutistus': ['vatsat', 'cable crunch'],
  'Jalannosto roikkuen': ['leg raise', 'vatsat'],
  'Hip thrust': ['pakara', 'lantionnosto'],
  'Peck deck': ['rintaprässi', 'pec deck', 'fly'],
  'Kaapeliristikkäis': ['cable fly', 'crossover'],
};

bool matchesSearch(String exercise, String q) {
  final s = q.toLowerCase();
  return exercise.toLowerCase().contains(s) ||
      (exerciseEnglish[exercise]?.toLowerCase().contains(s) ?? false) ||
      (_aliases[exercise]?.any((a) => a.contains(s)) ?? false);
}

/// Englanninkielinen nimi, jos asetus on päällä (näytetään suomenkielisen rinnalla).
String? englishOf(String exercise) => effectiveNameMode == 'fi' ? null : exerciseEnglish[exercise];

/// Liikkeen pääasiallinen näyttönimi asetuksen mukaan (englanniksi, jos valittu ja käännös on olemassa).
String exerciseDisplay(String exercise) => effectiveNameMode == 'en' ? exerciseEnglish[exercise] ?? exercise : exercise;

/// Liikkeen nimi näytettäväksi yhdellä rivillä: "Takakyykky · Back Squat" tai pelkkä nimi.
String exerciseLabel(String exercise) {
  final en = englishOf(exercise);
  return switch (effectiveNameMode) {
    'en' => en ?? exercise,
    'both' when en != null => '$exercise ($en)',
    _ => exercise,
  };
}

/// Liikeluettelon kategorioiden nimet käännöksiä varten (näytetään t(nimi)-kutsulla).
// l10n: data
const categoryNames = [
  'Voimanosto',
  'Jalat',
  'Rinta',
  'Selkä',
  'Olkapäät',
  'Kädet',
  'Keskivartalo',
  'Kehonpaino',
  'Kahvakuula',
  'Kardio',
  'Koko keho',
  'Viimeksi',
  'Omat',
  'Lämmittely',
];

/// Kategoriat omalle liikkeelle.
const exerciseCategories = ['Jalat', 'Rinta', 'Selkä', 'Olkapäät', 'Kädet', 'Keskivartalo', 'Kardio', 'Koko keho'];

BodyGroup bodyGroupOf(String exercise) {
  if (_legsPowerlifting.contains(exercise)) return BodyGroup.legs;
  if (_coreExtra.contains(exercise)) return BodyGroup.core;
  return switch (categoryOf(exercise)) {
    'Jalat' => BodyGroup.legs,
    'Keskivartalo' || 'Kardio' || 'Koko keho' => BodyGroup.core,
    _ => BodyGroup.upper,
  };
}

/// Kategoria valmiista luettelosta tai omien liikkeiden asetuksista.
String? categoryOf(String exercise) {
  for (final e in exerciseCatalog.entries) {
    if (e.value.contains(exercise)) return e.key;
  }
  if (settings.customExercises.contains(exercise)) {
    return settings.customCategory[exercise] ?? ownCategory;
  }
  return null;
}

/// Valmis luettelo + omat liikkeet omissa kategorioissaan + "Omat"-välilehti kaikille omille.
Map<String, List<String>> allExercises() {
  final m = {
    for (final e in exerciseCatalog.entries) e.key: [...e.value],
  };
  for (final n in settings.customExercises) {
    final c = settings.customCategory[n];
    if (c != null) (m[c] ??= []).add(n);
  }
  if (settings.customExercises.isNotEmpty) m[ownCategory] = [...settings.customExercises];
  return m;
}

Color groupColor(BodyGroup g) => switch (g) {
  BodyGroup.legs => Sami.red,
  BodyGroup.upper => Sami.blue,
  BodyGroup.core => Sami.green,
};
