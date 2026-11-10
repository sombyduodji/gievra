import 'dart:math' as math;

import 'exercises.dart';
import 'l10n.dart' as l10n;
import 'program_check.dart' show majorMuscles;
import 'program_edit.dart' show weeklyLoad;
import 'injuries.dart';
import 'models.dart';

// Treeniohjelma: tavoite × kokemus × päivät -> viikkojako, liikkeet, sarjat × toistot, varaa (RIR), tauot,
// kevennysviikot. Perusta ja lähteet: docs/tutkimus/ohjelmat.md (ACSM 2009, Pelland ym. 2026,
// Schoenfeld ym., Refalo ym. 2023, Robinson ym. 2024, Rogerson ym. 2024, Helms ym. 2015, Travis ym. 2020).
// Ohjelma tallentuu treenikansioon ohjelma.md:ksi, jota voi muokata käsin.

const programFileName = 'ohjelma.md';

// l10n: data
const goals = {
  'voimanosto': 'Voimanosto',
  'lihaskasvu': 'Lihaskasvu (kehonrakennus)',
  'rasvanpoltto': 'Rasvanpoltto',
  'kunto': 'Yleiskunto',
  'vapaa': 'Mennään fiiliksellä',
};
// l10n: data
const experiences = {
  'aloittelija': 'Aloittelija (alle 1 v)',
  'keski': 'Keskitaso (1–3 v)',
  'kokenut': 'Kokenut (yli 3 v)',
};

// --- Liikepaikat (movement-pattern slots) ----------------------------------

class Slot {
  final String name;
  final List<String> defaults;
  final bool compound;
  const Slot(this.name, this.defaults, {this.compound = false});
}

const slots = <String, Slot>{
  'KYY': Slot('Kyykky', ['Takakyykky', 'Etukyykky', 'Jalkaprässi'], compound: true),
  'LON': Slot('Lonkkasarana', ['Maastaveto', 'Romanialainen maastaveto', 'Hip thrust'], compound: true),
  'YKS': Slot('Yksijalkainen', ['Bulgarialainen askelkyykky', 'Askelkyykky', 'Jalkaprässi'], compound: true),
  'POJ': Slot('Polven ojennus', ['Reiden ojennus', 'Jalkaprässi']),
  'POK': Slot('Polven koukistus', ['Reiden koukistus', 'Nordic hamstring', 'Romanialainen maastaveto']),
  'PAK': Slot('Pakara', ['Hip thrust', 'Romanialainen maastaveto', 'Bulgarialainen askelkyykky']),
  'POH': Slot('Pohje', ['Pohjenousu seisten', 'Pohjenousu istuen']),
  'VTY': Slot('Vaakatyöntö', ['Penkkipunnerrus', 'Käsipainopenkki', 'Rintaprässi laitteessa'], compound: true),
  'VIN': Slot('Vino työntö', ['Vinopenkki', 'Vinokäsipainopenkki', 'Rintaprässi laitteessa'], compound: true),
  'PTY': Slot('Pystytyöntö', ['Pystypunnerrus', 'Käsipainopystypunnerrus', 'Olkapääprässi laitteessa'], compound: true),
  'VVE': Slot('Vaakaveto', ['Kulmasoutu', 'Alatalja', 'Käsipainosoutu', 'Soutu laitteessa'], compound: true),
  'PVE': Slot('Pystyveto', ['Leuanveto', 'Ylätalja'], compound: true),
  'RIE': Slot('Rinta-eristys', ['Kaapeliristikkäis', 'Peck deck', 'Käsipainoaukaisu']),
  'OSI': Slot('Olkapää sivu', ['Vipunosto sivulle', 'Vipunosto taljassa']),
  'TAK': Slot('Takaolka', ['Face pull', 'Takaolkavipunosto']),
  'HAU': Slot('Hauis', ['Hauiskääntö tangolla', 'Vasarakääntö', 'Hauiskääntö taljassa']),
  'OJE': Slot('Ojentaja', ['Ojentajapunnerrus taljassa', 'Ranskalainen punnerrus', 'Kapea penkki']),
  'KES': Slot('Keskivartalo', ['Pallof press', 'Jalannosto roikkuen', 'Kaapelirutistus']),
  'KAN': Slot('Kanto', ['Farmer walk', 'Kylkilankku']),
  'KK': Slot('Kilpakyykky', ['Takakyykky', 'Box-kyykky', 'Jalkaprässi'], compound: true),
  'KP': Slot('Kilpapenkki', ['Penkkipunnerrus', 'Lattiapunnerrus', 'Käsipainopenkki'], compound: true),
  'KM': Slot('Kilpamaastaveto', ['Maastaveto', 'Rack pull', 'Hip thrust'], compound: true),
  'KYV': Slot('Kyykkyvariaatio', ['Etukyykky', 'Hack-kyykky', 'Jalkaprässi'], compound: true),
  'PEV': Slot('Penkkivariaatio', ['Taukopenkki', 'Kapea penkki', 'Vinopenkki'], compound: true),
  'MAV': Slot('Maastavetovariaatio', [
    'Romanialainen maastaveto',
    'Hip thrust',
    'Suorin jaloin maastaveto',
    'Good morning',
  ], compound: true),
};

/// Liikemallit liikkeille, jotka eivät ole minkään paikan oletuslistassa.
const _extraSlot = <String, String>{
  'Rintatuettu kulmasoutu käsipainoilla': 'VVE',
  'Sumomaastaveto': 'LON',
  'Low bar -kyykky': 'KYY',
  'Askelkyykkykävely': 'YKS',
  'Goblet-kyykky': 'KYY',
  'Smith-kyykky': 'KYY',
  'Lonkan loitonnus': 'PAK',
  'Kööpenhaminan lähennys': 'KES',
  'Dipit': 'VTY',
  'Punnerrus': 'VTY',
  'Smith-vinopenkki': 'VIN',
  'Leuanveto vastaotteella': 'PVE',
  'T-tankosoutu': 'VVE',
  'Pendlay-soutu': 'VVE',
  'Selän ojennus': 'LON',
  'Suorin käsin ylätalja': 'PVE',
  'Vipunosto eteen': 'OSI',
  'Arnold-punnerrus': 'PTY',
  'Pystysoutu': 'OSI',
  'Push press': 'PTY',
  'Ulkokierto taljassa': 'TAK',
  'Hauiskääntö käsipainoilla': 'HAU',
  'Scott-kääntö': 'HAU',
  'Keskittynyt hauiskääntö': 'HAU',
  'Ojentajapunnerrus pään yli': 'OJE',
  'Penkkidipit': 'OJE',
  'Lankku': 'KES',
  'Vatsarutistus': 'KES',
  'Ab wheel': 'KES',
  'Venäläinen twisti': 'KES',
  'Pistoolikyykky': 'YKS',
  'Lantionnosto': 'PAK',
  'Australialainen leuanveto': 'VVE',
  'Pike-punnerrus': 'PTY',
  'Kahvakuulaheilautus': 'LON',
  'Yhden käden heilautus': 'LON',
  'Kahvakuulamaastaveto': 'LON',
  'Kahvakuulan rinnalleveto': 'LON',
  'Rinnalleveto ja punnerrus': 'PTY',
  'Kahvakuulatempaus': 'LON',
  'Kahvakuulapystypunnerrus': 'PTY',
  'Kahvakuulan etukyykky': 'KYY',
  'Kahvakuulan sumomaastaveto': 'LON',
  'Kahvakuulan sumoveto': 'LON',
  'Kahvakuulahauiskääntö': 'HAU',
  'Kahvakuula-askelkyykky': 'YKS',
  'Lentokone': 'KES',
  'Tuplakahvakuulaheilautus': 'LON',
  'Tuplakahvakuulamaastaveto': 'LON',
  'Tuplakahvakuulan rinnalleveto': 'LON',
  'Tuplakahvakuulapystypunnerrus': 'PTY',
  'Tuplakahvakuulatyöntö': 'PTY',
  'Tuplakahvakuulan rinnalleveto ja punnerrus': 'PTY',
  'Tuplakahvakuulasoutu': 'VVE',
  'Tuplakahvakuulalattiapunnerrus': 'VTY',
  'Tuplakahvakuula-askelkyykky': 'YKS',
  'Kahvakuula-thruster': 'KYY',
  'Yhden jalan maastaveto': 'LON',
  'Kahvakuulasoutu': 'VVE',
  'Renegade-soutu': 'VVE',
  'Kahvakuulalattiapunnerrus': 'VTY',
  'Turkkilainen ylösnousu': 'KES',
  'Tuulimylly': 'KES',
  'Matkalaukkukanto': 'KAN',
  'Kyykky kehonpainolla': 'KYY',
  'Hyppykyykky': 'KYY',
  'Sissy-kyykky': 'POJ',
  'Käänteinen nordic': 'POJ',
  'Askelnousu': 'YKS',
  'Jalat koholla punnerrus': 'VIN',
  'Timanttipunnerrus': 'OJE',
  'Ojentajaojennus kehonpainolla': 'OJE',
  'Kehonpainohauiskääntö': 'HAU',
  'Käsilläseisontapunnerrus': 'PTY',
  'Y-T-W-nostot makuulla': 'TAK',
  'Yhden jalan lantionnosto': 'PAK',
  'Reiden koukistus kehonpainolla': 'POK',
  'Veneasento': 'KES',
  'Dead bug': 'KES',
  'Burpee': 'KES',
  'Superman-nosto': 'LON',
  'Vinopunnerrus': 'VTY',
  'Polvipunnerrus': 'VTY',
  'Negatiivinen leuanveto': 'PVE',
  'Kuminauhaleuanveto': 'PVE',
  'Seinäistunta': 'POJ',
  'Lintukoira': 'KES',
  'Vuorikiipeilijä': 'KES',
  'Karhukävely': 'KES',
  'Yhden jalan pohjenousu': 'POH',
};

/// Voimanoston paikat kuuluvat samaan malliin kuin perusohjelman paikat.
const _family = {'KK': 'KYY', 'KYV': 'KYY', 'KP': 'VTY', 'PEV': 'VTY', 'KM': 'LON', 'MAV': 'LON'};
String family(String slot) => _family[slot] ?? slot;

/// Liikkeen liikemalli ('' = ei tiedossa, esim. oma liike tai ranneliike).
String slotOf(String exercise, {String? prefer}) {
  if (prefer != null && (slots[prefer]?.defaults.contains(exercise) ?? false)) return prefer;
  for (final e in slots.entries) {
    if (e.value.defaults.contains(exercise) && !_family.containsKey(e.key)) return e.key;
  }
  for (final e in slots.entries) {
    if (e.value.defaults.contains(exercise)) return e.key;
  }
  return _extraSlot[exercise] ?? '';
}

// --- Mallipohjat -------------------------------------------------------------

/// slot, sarjat, toistot ala–ylä, [laji: 'H' raskas / 'V' volyymi / 'T' tekniikka], [liike]
typedef T = (String, int, int, int, String?, String?);

T slotT(String s, int sets, int lo, int hi, {String? kind, String? ex}) => (s, sets, lo, hi, kind, ex);

/// Kahvakuulaohjelman painotus (kun välineenä on vain kahvakuula). Gievran omia ohjelmia (GPL-3.0):
/// rakenne yleisistä voimaharjoittelun periaatteista (Markell & Peterson 2019, Health and Fitness for Life,
/// CC BY 4.0; Kabaroff & Dubuc 2024, Fitness for Paramedics, CC BY 4.0), ei kopioitu kirjoista.
/// Ks. docs/tutkimus/kahvakuulaohjelmat.md.
// l10n: data
const kbFocuses = {
  'voima': ('🏋️', 'Voima', 'Raskaat tuplakuulaliikkeet, vähän toistoja, pitkät tauot'),
  'lihaskasvu': ('💪', 'Lihaskasvu', 'Tuplakuulat, 6–12 toistoa, enemmän sarjoja'),
  'kunto': ('🔥', 'Kunto ja jaksaminen', 'Heilautukset ja kierrot lyhyin tauoin'),
  'perusta': ('🌱', 'Perusta yhdellä kuulalla', 'Heilautus, ylösnousu ja perusliikkeet, sopii aloittajalle'),
};

/// Kahvakuulaohjelmien päivät (A, B, C). Paino per kuula; tuplakuulaliikkeissä kaksi samanpainoista.
final Map<String, List<(String, List<T>)>> _kettlebell = {
  'voima': [
    (
      'Kahvakuula A',
      [
        slotT('LON', 3, 3, 5, ex: 'Tuplakahvakuulan rinnalleveto'),
        slotT('PTY', 5, 3, 5, ex: 'Tuplakahvakuulapystypunnerrus'),
        slotT('KYY', 5, 3, 5, ex: 'Kahvakuulan etukyykky'),
        slotT('VVE', 3, 5, 8, ex: 'Tuplakahvakuulasoutu'),
      ],
    ),
    (
      'Kahvakuula B',
      [
        slotT('LON', 4, 3, 6, ex: 'Tuplakahvakuulamaastaveto'),
        slotT('VTY', 4, 4, 6, ex: 'Tuplakahvakuulalattiapunnerrus'),
        slotT('YKS', 3, 5, 6, ex: 'Tuplakahvakuula-askelkyykky'),
        slotT('VVE', 3, 5, 6, ex: 'Renegade-soutu'),
        slotT('KES', 3, 1, 2, ex: 'Turkkilainen ylösnousu'),
      ],
    ),
    (
      'Kahvakuula C',
      [
        slotT('PTY', 5, 2, 3, ex: 'Tuplakahvakuulatyöntö'),
        slotT('KYY', 4, 3, 5, ex: 'Kahvakuulan etukyykky'),
        slotT('LON', 5, 5, 5, ex: 'Tuplakahvakuulaheilautus'),
        slotT('KAN', 3, 1, 2, ex: 'Matkalaukkukanto'),
      ],
    ),
  ],
  'lihaskasvu': [
    (
      'Kahvakuula A',
      [
        slotT('PTY', 4, 6, 10, ex: 'Tuplakahvakuulan rinnalleveto ja punnerrus'),
        slotT('KYY', 4, 8, 12, ex: 'Kahvakuulan etukyykky'),
        slotT('VVE', 4, 8, 12, ex: 'Tuplakahvakuulasoutu'),
        slotT('HAU', 3, 10, 15, ex: 'Kahvakuulahauiskääntö'),
      ],
    ),
    (
      'Kahvakuula B',
      [
        slotT('LON', 4, 8, 12, ex: 'Tuplakahvakuulamaastaveto'),
        slotT('VTY', 4, 8, 12, ex: 'Tuplakahvakuulalattiapunnerrus'),
        slotT('YKS', 3, 8, 12, ex: 'Tuplakahvakuula-askelkyykky'),
        slotT('VVE', 3, 8, 12, ex: 'Renegade-soutu'),
      ],
    ),
    (
      'Kahvakuula C',
      [
        slotT('KYY', 4, 8, 10, ex: 'Kahvakuula-thruster'),
        slotT('PTY', 3, 8, 12, ex: 'Tuplakahvakuulapystypunnerrus'),
        slotT('LON', 3, 10, 15, ex: 'Kahvakuulan sumoveto'),
        slotT('VVE', 3, 10, 12, ex: 'Tuplakahvakuulasoutu'),
      ],
    ),
  ],
  'kunto': [
    (
      'Kahvakuula A',
      [
        slotT('LON', 5, 15, 20, ex: 'Kahvakuulaheilautus'),
        slotT('KYY', 3, 10, 12, ex: 'Kahvakuula-thruster'),
        slotT('VVE', 3, 10, 12, ex: 'Kahvakuulasoutu'),
        slotT('KAN', 3, 1, 2, ex: 'Matkalaukkukanto'),
      ],
    ),
    (
      'Kahvakuula B',
      [
        slotT('LON', 5, 10, 15, ex: 'Yhden käden heilautus'),
        slotT('YKS', 3, 10, 12, ex: 'Kahvakuula-askelkyykky'),
        slotT('PTY', 3, 8, 12, ex: 'Kahvakuulapystypunnerrus'),
        slotT('LON', 3, 10, 15, ex: 'Kahvakuulan sumoveto'),
      ],
    ),
    (
      'Kahvakuula C',
      [
        slotT('LON', 5, 5, 10, ex: 'Kahvakuulatempaus'),
        slotT('KYY', 3, 10, 15, ex: 'Goblet-kyykky'),
        slotT('VTY', 3, 10, 12, ex: 'Kahvakuulalattiapunnerrus'),
        slotT('KES', 3, 1, 2, ex: 'Turkkilainen ylösnousu'),
      ],
    ),
  ],
  'perusta': [
    (
      'Kahvakuula A',
      [
        slotT('LON', 5, 10, 10, ex: 'Kahvakuulaheilautus'),
        slotT('KYY', 3, 8, 10, ex: 'Goblet-kyykky'),
        slotT('PTY', 3, 5, 8, ex: 'Kahvakuulapystypunnerrus'),
        slotT('KES', 3, 1, 1, ex: 'Turkkilainen ylösnousu'),
      ],
    ),
    (
      'Kahvakuula B',
      [
        slotT('LON', 5, 10, 10, ex: 'Kahvakuulaheilautus'),
        slotT('LON', 3, 5, 8, ex: 'Kahvakuulamaastaveto'),
        slotT('VVE', 3, 8, 10, ex: 'Kahvakuulasoutu'),
        slotT('KES', 3, 1, 1, ex: 'Turkkilainen ylösnousu'),
      ],
    ),
    (
      'Kahvakuula C',
      [
        slotT('LON', 5, 10, 10, ex: 'Yhden käden heilautus'),
        slotT('YKS', 3, 6, 8, ex: 'Kahvakuula-askelkyykky'),
        slotT('VTY', 3, 8, 10, ex: 'Kahvakuulalattiapunnerrus'),
        slotT('KAN', 3, 1, 2, ex: 'Matkalaukkukanto'),
      ],
    ),
  ],
};

/// Ohjelmapäivien nimien perusosat käännöksiä varten (näytetään trName()-funktiolla).
// l10n: data
const dayNameBases = [
  'Kahvakuula',
  'Koko keho',
  'Ylävartalo',
  'Alavartalo',
  'Työntö',
  'Veto',
  'Jalat',
  'Voima',
  'Treeni',
];

final Map<int, List<(String, List<T>)>> _hypertrophy = {
  2: [
    (
      'Koko keho A',
      [
        slotT('KYY', 3, 6, 10),
        slotT('VTY', 3, 6, 10),
        slotT('VVE', 3, 8, 12),
        slotT('POK', 2, 10, 15),
        slotT('OSI', 2, 12, 20),
        slotT('HAU', 2, 10, 15),
      ],
    ),
    (
      'Koko keho B',
      [
        slotT('LON', 3, 6, 10),
        slotT('PVE', 3, 8, 12),
        slotT('PTY', 3, 6, 10),
        slotT('YKS', 2, 8, 12),
        slotT('OJE', 2, 10, 15),
        slotT('TAK', 2, 12, 20),
        slotT('POH', 2, 10, 15),
      ],
    ),
  ],
  3: [
    (
      'Koko keho A',
      [
        slotT('KYY', 3, 6, 10),
        slotT('VTY', 3, 6, 10),
        slotT('VVE', 3, 8, 12),
        slotT('POK', 2, 10, 15),
        slotT('OSI', 2, 12, 20),
        slotT('HAU', 2, 10, 15),
      ],
    ),
    (
      'Koko keho B',
      [
        slotT('LON', 3, 6, 10),
        slotT('PTY', 3, 6, 10),
        slotT('PVE', 3, 8, 12),
        slotT('POJ', 2, 10, 15),
        slotT('POH', 2, 10, 15),
        slotT('OJE', 2, 10, 15),
      ],
    ),
    (
      'Koko keho C',
      [
        slotT('YKS', 3, 8, 12),
        slotT('VIN', 3, 8, 12),
        slotT('VVE', 3, 10, 12),
        slotT('PAK', 2, 8, 12),
        slotT('TAK', 2, 12, 20),
        slotT('KES', 2, 10, 15),
      ],
    ),
  ],
  4: [
    (
      'Ylävartalo A',
      [
        slotT('VTY', 4, 6, 8),
        slotT('VVE', 4, 6, 10, ex: 'Käsipainosoutu'),
        slotT('PTY', 3, 6, 10),
        slotT('PVE', 3, 8, 12),
        slotT('HAU', 3, 8, 12),
        slotT('OJE', 3, 10, 15),
      ],
    ),
    (
      'Alavartalo A',
      [
        slotT('KYY', 4, 6, 8),
        slotT('LON', 3, 8, 10, ex: 'Romanialainen maastaveto'),
        slotT('POJ', 3, 10, 15),
        slotT('POK', 3, 10, 15),
        slotT('POH', 3, 10, 15),
        slotT('KES', 2, 10, 15),
      ],
    ),
    (
      'Ylävartalo B',
      [
        slotT('VIN', 3, 8, 12),
        slotT('PVE', 4, 8, 12),
        slotT('VVE', 3, 10, 12, ex: 'Alatalja'),
        slotT('RIE', 3, 12, 15),
        slotT('OSI', 4, 12, 20),
        slotT('TAK', 3, 12, 20),
      ],
    ),
    (
      'Alavartalo B',
      [
        slotT('LON', 3, 5, 8),
        slotT('KYY', 3, 10, 12, ex: 'Jalkaprässi'),
        slotT('YKS', 3, 8, 12),
        slotT('POK', 3, 10, 15),
        slotT('POH', 3, 10, 15),
        slotT('KES', 2, 10, 15),
      ],
    ),
  ],
  5: [
    (
      'Ylävartalo',
      [
        slotT('VTY', 3, 6, 8),
        slotT('VVE', 3, 6, 10, ex: 'Käsipainosoutu'),
        slotT('PTY', 2, 8, 10),
        slotT('PVE', 3, 8, 12),
        slotT('HAU', 2, 10, 15),
        slotT('OJE', 2, 10, 15),
      ],
    ),
    ('Alavartalo', [slotT('KYY', 4, 6, 8), slotT('LON', 3, 6, 10), slotT('POK', 3, 10, 15), slotT('POH', 3, 10, 15)]),
    (
      'Työntö',
      [
        slotT('VIN', 3, 8, 12),
        slotT('PTY', 3, 8, 12),
        slotT('RIE', 3, 12, 15),
        slotT('OSI', 4, 12, 20),
        slotT('OJE', 3, 10, 15),
      ],
    ),
    (
      'Veto',
      [
        slotT('PVE', 4, 8, 12),
        slotT('VVE', 3, 10, 12, ex: 'Alatalja'),
        slotT('TAK', 3, 12, 20),
        slotT('HAU', 3, 10, 15),
        slotT('KAN', 2, 30, 40),
      ],
    ),
    (
      'Jalat',
      [
        slotT('YKS', 3, 8, 12),
        slotT('POJ', 3, 10, 15),
        slotT('PAK', 3, 8, 12),
        slotT('POK', 3, 10, 15),
        slotT('POH', 3, 10, 15),
        slotT('KES', 2, 10, 15),
      ],
    ),
  ],
  6: [
    (
      'Työntö 1',
      [
        slotT('VTY', 3, 6, 8),
        slotT('PTY', 3, 8, 10),
        slotT('RIE', 3, 12, 15),
        slotT('OSI', 3, 12, 20),
        slotT('OJE', 3, 10, 15),
      ],
    ),
    (
      'Veto 1',
      [
        slotT('PVE', 3, 6, 10),
        slotT('VVE', 3, 8, 10, ex: 'Käsipainosoutu'),
        slotT('TAK', 3, 12, 20),
        slotT('HAU', 3, 8, 12),
      ],
    ),
    (
      'Jalat 1',
      [
        slotT('KYY', 3, 6, 8),
        slotT('LON', 3, 8, 10, ex: 'Romanialainen maastaveto'),
        slotT('POJ', 3, 10, 15),
        slotT('POH', 3, 10, 15),
        slotT('KES', 3, 10, 15),
      ],
    ),
    (
      'Työntö 2',
      [
        slotT('VIN', 3, 8, 12),
        slotT('VTY', 3, 10, 12, ex: 'Käsipainopenkki'),
        slotT('OSI', 3, 12, 20),
        slotT('OJE', 3, 12, 15),
      ],
    ),
    (
      'Veto 2',
      [
        slotT('VVE', 3, 10, 12, ex: 'Alatalja'),
        slotT('PVE', 3, 10, 15, ex: 'Ylätalja'),
        slotT('TAK', 3, 15, 20),
        slotT('HAU', 3, 10, 15, ex: 'Vasarakääntö'),
      ],
    ),
    (
      'Jalat 2',
      [
        slotT('LON', 3, 5, 10, ex: 'Hip thrust'),
        slotT('YKS', 3, 8, 12),
        slotT('POK', 3, 10, 15),
        slotT('POH', 3, 10, 15),
        slotT('KES', 3, 10, 15),
      ],
    ),
  ],
};

final Map<int, List<(String, List<T>)>> _powerlifting = {
  2: [
    (
      'Voima A',
      [
        slotT('KK', 0, 0, 0, kind: 'H'),
        slotT('KP', 0, 0, 0, kind: 'H'),
        slotT('MAV', 3, 6, 8),
        slotT('VVE', 3, 8, 10),
        slotT('KES', 2, 10, 15),
      ],
    ),
    (
      'Voima B',
      [
        slotT('KM', 0, 0, 0, kind: 'H'),
        slotT('KP', 0, 0, 0, kind: 'V'),
        slotT('KYV', 3, 6, 8),
        slotT('PVE', 3, 8, 10),
        slotT('OJE', 2, 10, 12),
      ],
    ),
  ],
  3: [
    (
      'Voima 1',
      [
        slotT('KK', 0, 0, 0, kind: 'H'),
        slotT('KP', 0, 0, 0, kind: 'V'),
        slotT('VVE', 3, 8, 10, ex: 'Alatalja'),
        slotT('POK', 2, 10, 12),
        slotT('KES', 2, 10, 15),
      ],
    ),
    (
      'Voima 2',
      [
        slotT('KP', 0, 0, 0, kind: 'H'),
        slotT('KM', 0, 0, 0, kind: 'H'),
        slotT('PVE', 3, 8, 10),
        slotT('OJE', 2, 10, 12),
        slotT('TAK', 2, 15, 15),
      ],
    ),
    (
      'Voima 3',
      [
        slotT('KK', 0, 0, 0, kind: 'V'),
        slotT('PEV', 3, 6, 8),
        slotT('MAV', 3, 6, 8),
        slotT('VVE', 3, 10, 10, ex: 'Käsipainosoutu'),
        slotT('HAU', 2, 10, 12),
      ],
    ),
  ],
  4: [
    (
      'Kyykky',
      [slotT('KK', 0, 0, 0, kind: 'H'), slotT('MAV', 3, 6, 8), slotT('POJ', 2, 10, 12), slotT('KES', 2, 10, 15)],
    ),
    (
      'Penkki raskas',
      [
        slotT('KP', 0, 0, 0, kind: 'H'),
        slotT('VVE', 4, 6, 10, ex: 'Käsipainosoutu'),
        slotT('PTY', 3, 6, 8),
        slotT('OJE', 2, 10, 12),
      ],
    ),
    (
      'Maastaveto',
      [slotT('KM', 0, 0, 0, kind: 'H'), slotT('KYV', 3, 5, 8), slotT('POK', 3, 10, 12), slotT('KAN', 3, 30, 40)],
    ),
    (
      'Penkki volyymi',
      [
        slotT('KP', 0, 0, 0, kind: 'V'),
        slotT('PEV', 3, 6, 8),
        slotT('PVE', 3, 8, 10),
        slotT('TAK', 3, 15, 15),
        slotT('HAU', 2, 10, 12),
      ],
    ),
  ],
};

/// Aloittelijan lineaarinen nousu (Starting Strength / StrongLifts -tyyli, docs/tutkimus/ohjelmat.md 3b).
final _plBeginner = <(String, List<T>)>[
  (
    'Voima A',
    [
      slotT('KK', 3, 5, 5, kind: 'L'),
      slotT('KP', 3, 5, 5, kind: 'L'),
      slotT('VVE', 3, 8, 8, ex: 'Kulmasoutu'),
      slotT('POK', 2, 10, 12),
      slotT('HAU', 2, 10, 12),
    ],
  ),
  (
    'Voima B',
    [
      slotT('KK', 3, 5, 5, kind: 'L'),
      slotT('PTY', 3, 5, 5, kind: 'L'),
      slotT('KM', 1, 5, 5, kind: 'L'),
      slotT('PVE', 3, 8, 10, ex: 'Ylätalja'),
      slotT('OJE', 2, 10, 12),
      slotT('KES', 2, 10, 15),
    ],
  ),
];

// Voimanoston 10 viikon sykli (3a): viikko -> (sarjat, toistot, % e1RM, RPE-katto). Viikko 5 = kevennys.
const plHeavy = [
  (5, 5, .725, 7.0),
  (5, 5, .75, 7.5),
  (5, 4, .775, 8.0),
  (5, 4, .80, 8.0),
  (3, 3, .70, 6.0),
  (4, 3, .825, 8.0),
  (4, 3, .85, 8.0),
  (4, 2, .875, 8.5),
  (4, 2, .90, 8.5),
  (2, 1, .90, 8.0),
];
const plVolume = [
  (4, 8, .65, 7.0),
  (4, 8, .675, 7.0),
  (4, 7, .70, 7.5),
  (4, 6, .725, 8.0),
  (2, 6, .60, 6.0),
  (3, 6, .725, 7.5),
  (3, 5, .75, 8.0),
  (3, 5, .775, 8.0),
  (3, 4, .775, 7.5),
  (2, 2, .75, 6.0),
];
// l10n: data
const plPhases = [
  'Kasaus',
  'Kasaus',
  'Kasaus',
  'Kasaus',
  'Kevennys',
  'Tehostus',
  'Tehostus',
  'Tehostus',
  'Tehostus',
  'Huippu ja testi',
];

// --- Malli ---------------------------------------------------------------

class PlanItem {
  String exercise;
  String slot;
  int sets;
  int lo, hi;
  String rir; // esim. "1–3"
  int restSec;
  String? kind; // H, V, L (lineaarinen), null = tuplaprogressio
  String? note;
  PlanItem(this.exercise, this.slot, this.sets, this.lo, this.hi, this.rir, this.restSec, {this.kind, this.note});
  bool get compound => slots[slot]?.compound ?? false;
}

class PlanDay {
  String name; // pysyvä nimi ("Koko keho A"); treenien vertailu käyttää tätä
  String? label; // käyttäjän oma nimi (esim. "Maanantai", "Veto"), oletuksena ei mitään
  final List<PlanItem> items;
  PlanDay(this.name, this.items, {this.label});

  /// Tiedostoon ja treenin otsikoksi (suomeksi).
  String get display => (label?.trim().isNotEmpty ?? false) ? label!.trim() : name;

  /// Käyttöliittymään käyttäjän kielellä.
  String get uiName => (label?.trim().isNotEmpty ?? false) ? label!.trim() : l10n.trName(name);
  bool matches(String key) => key == name || key == label;
}

class Program {
  String goal;
  String experience;
  int days;
  int minutes;
  DateTime start;
  int deloadEvery; // 0 = vain tarvittaessa
  Map<String, double> maxes;
  List<String> notes;
  List<PlanDay> plan;
  String repStyle; // suositus / raskas / kevyt
  Set<String> equipment; // välinetoiveet (tyhjä = kaikki käy)
  String? kbFocus; // kahvakuulaohjelman painotus (kbFocuses), null = tavallinen ohjelma
  Program({
    required this.goal,
    required this.experience,
    required this.days,
    required this.minutes,
    required this.start,
    required this.deloadEvery,
    Map<String, double>? maxes,
    List<String>? notes,
    List<PlanDay>? plan,
    this.repStyle = 'suositus',
    Set<String>? equipment,
    this.kbFocus,
  }) : equipment = equipment ?? {},
       maxes = maxes ?? {},
       notes = notes ?? [],
       plan = plan ?? [];

  bool get powerlifting => goal == 'voimanosto';

  /// Tiedostoon (ohjelma.md) aina suomeksi.
  String get title => kbFocus != null
      ? 'Kahvakuula: ${kbFocuses[kbFocus]?.$2 ?? kbFocus} · ${plan.length} päivää viikossa'
      : '${goals[goal] ?? goal} · ${plan.length} päivää viikossa';

  /// Käyttöliittymään käyttäjän kielellä.
  String get displayTitle => l10n.t('{0} · {1} päivää viikossa', [
    kbFocus != null
        ? l10n.t('Kahvakuula: {0}', [l10n.t(kbFocuses[kbFocus]?.$2 ?? kbFocus!)])
        : l10n.t(goals[goal] ?? goal),
    plan.length,
  ]);

  /// Ohjelmaviikko (0 = aloitusviikko).
  int weekOf(DateTime d) {
    final s = addDays(start, 1 - start.weekday);
    return math.max(0, dateOnly(d).difference(s).inDays ~/ 7);
  }

  bool isDeloadWeek(DateTime d) {
    final w = weekOf(d);
    if (powerlifting && experience != 'aloittelija') return w % 10 == 4;
    return deloadEvery > 0 && (w + 1) % deloadEvery == 0;
  }

  /// Seuraava ohjelmapäivä: se, joka tulee viimeksi tehdyn jälkeen.
  PlanDay nextDay(List<Workout> history, DateTime today) {
    for (final w in history) {
      if (w.date.isBefore(start) || !w.date.isBefore(dateOnly(today))) continue;
      final i = plan.indexWhere((d) => d.matches(w.dayKey));
      if (i >= 0) return plan[(i + 1) % plan.length];
    }
    return plan.first;
  }
}

/// Tämän päivän tavoite yhdelle liikkeelle (viikko, kevennys ja voimanoston taulukko huomioituna).
class Target {
  final int sets, lo, hi;
  final String rir;
  final int restSec;
  final double? pct; // % arvioidusta maksimista (voimanosto)
  final double loadFactor; // kevennysviikolla 0,9
  final String label;
  Target(this.sets, this.lo, this.hi, this.rir, this.restSec, this.label, {this.pct, this.loadFactor = 1});
  String get reps => lo == hi ? '$lo' : '$lo–$hi';
}

Target targetFor(Program p, PlanItem it, DateTime date) {
  final week = p.weekOf(date);
  if (it.kind == 'H' || it.kind == 'V') {
    final w = week % 10;
    final (sets, reps, pct, rpe) = (it.kind == 'H' ? plHeavy : plVolume)[w];
    final extra = it.slot == 'KM' && it.kind == 'H' ? -1 : 0; // maastavedossa yksi sarja vähemmän
    final rir = (10 - rpe);
    return Target(
      math.max(1, sets + extra),
      reps,
      reps,
      rir <= 0 ? '0' : fmtNum(rir),
      it.restSec,
      l10n.t('Viikko {0}/10 · {1} · {2} %', [
        w + 1,
        l10n.t(plPhases[w]),
        fmtNum(double.parse((pct * 100).toStringAsFixed(1))),
      ]),
      pct: pct,
    );
  }
  if (p.isDeloadWeek(date)) {
    return Target(
      math.max(1, (it.sets / 2).ceil()),
      it.lo,
      it.hi,
      '3–4',
      it.restSec,
      l10n.t('Kevennysviikko: puolet sarjoista, painot −10 %, ei maksimiyrityksiä'),
      loadFactor: .9,
    );
  }
  return Target(it.sets, it.lo, it.hi, it.rir, it.restSec, l10n.t('Viikko {0}', [week + 1]));
}

// --- Generointi ----------------------------------------------------------

Program generateProgram({
  required String goal,
  required String experience,
  required int days,
  required int minutes,
  required List<String> injuries,
  Map<String, double> maxes = const {},
  DateTime? start,
  String repStyle = 'suositus',
  Set<String> equipment = const {},
  Map<String, String> favorites = const {},
  List<String> chosen = const [],
  String? kbFocus,
}) {
  // Kahvakuulaohjelma vain, kun välineenä on pelkkä kahvakuula ja painotus on valittu.
  final kb =
      kbFocus != null && kbFocuses.containsKey(kbFocus) && equipment.length == 1 && equipment.contains('kahvakuula')
      ? kbFocus
      : null;
  final g = goal == 'vapaa' ? 'kunto' : goal;
  final exp = goal == 'vapaa' ? 'keski' : experience;
  final beginner = exp == 'aloittelija';
  final notes = <String>[];
  var d = days.clamp(2, 6);

  List<(String, List<T>)> tpl;
  if (kb != null) {
    if (d > 3) {
      notes.add(
        l10n.fi('Kahvakuulaohjelmassa 3 treenipäivää riittää. Muina päivinä kävelyä tai muuta kevyttä liikuntaa.'),
      );
    }
    tpl = _kettlebell[kb]!.take(d.clamp(2, 3)).toList();
    notes.add(
      l10n.fi(
        'Paino merkitään per kuula; tuplakuulaliikkeissä kaksi samanpainoista kuulaa. Kun kaikki sarjat menevät '
        'toistoalueen ylärajalla ja varaa jää, vaihda seuraavaan kuulakokoon (yleensä +4 kg) ja aloita alarajalta.',
      ),
    );
    notes.add(switch (kb) {
      'voima' => l10n.fi(
        'Voimapainotus: 3–5 toistoa raskaalla kuulalla, 2–3 min tauot. Raskaat moninivelliikkeet ensin, '
        'pienemmät lopuksi (ACSM:n suositus, Markell & Peterson 2019, CC BY 4.0).',
      ),
      'lihaskasvu' => l10n.fi(
        'Lihaskasvupainotus: 6–12 toistoa lähelle uupumusta, 60–90 s tauot. Sarjoja voi tehdä pareina '
        '(esim. punnerrus + soutu) ajan säästämiseksi.',
      ),
      'kunto' => l10n.fi(
        'Kuntopainotus: liikkeet kiertona lyhyin tauoin (30–60 s), 3–5 kierrosta. Heilautuksissa voima tulee '
        'lantiosta, ei käsistä.',
      ),
      _ => l10n.fi(
        'Perusta: opettele heilautus ja ylösnousu kevyellä kuulalla ennen raskaampia liikkeitä. Ylösnousut '
        'vuorotellen kummallekin puolelle. Vaihda isompaan kuulaan, kun kaikki toistot sujuvat hyvällä tekniikalla.',
      ),
    });
  } else if (g == 'voimanosto') {
    if (beginner) {
      tpl = _plBeginner;
      notes.add(
        l10n.fi(
          'Aloittelijan lineaarinen nousu: vuorottele A ja B, {0} kertaa viikossa. '
          'Lisää painoa joka kerta, kun kaikki sarjat menivät läpi.',
          [d >= 3 ? 3 : 2],
        ),
      );
      if (d > 3) notes.add(l10n.fi('Aloittelijalle 3 salipäivää riittää. Muina päivinä kevyttä liikuntaa.'));
    } else {
      final dd = d >= 4 ? 4 : d;
      tpl = _powerlifting[dd]!;
      if (d > 4) {
        notes.add(l10n.fi('Voimanostossa 4 päivää riittää tähän ohjelmaan. Lisäpäivät: kevyt tekniikka tai kardio.'));
      }
      notes.add(
        l10n.fi(
          '10 viikon sykli: 4 vk kasaus, kevennysviikko, 4 vk tehostus, huippu ja testi. Painot '
          'lasketaan arvioidusta maksimista (e1RM).',
        ),
      );
    }
  } else {
    if (beginner && d > 3) {
      notes.add(l10n.fi('Aloittelijalle 2–3 salipäivää on suositus (ACSM). Muina päivinä kevyttä liikuntaa.'));
      d = 3;
    }
    if (g == 'kunto' && d >= 5) {
      notes.add(l10n.fi('Yleiskunnossa 3 salipäivää + {0} kestävyyspäivää (30–45 min reipasta).', [d - 3]));
      d = 3;
    }
    if (g == 'rasvanpoltto' && d >= 5) {
      notes.add(l10n.fi('Rasvanpoltossa 4 salipäivää + {0} kevyttä kardiopäivää.', [d - 4]));
      d = 4;
    }
    tpl = _hypertrophy[d]!;
  }
  if (g == 'rasvanpoltto') {
    notes.add(
      l10n.fi(
        'Pidä painot, sarjoja saa olla vähemmän. Tavoite −0,5–1 % kehonpainosta viikossa, '
        'proteiinia 1,6–2,2 g/kg. Lisäksi 2–3 × 20–40 min kevyttä kardiota salin jälkeen tai eri '
        'aikaan.',
      ),
    );
  }
  if (g == 'kunto') notes.add(l10n.fi('Kestävyysliikuntaa 150–300 min viikossa (WHO).'));

  // Kokemuksen mukaan: sarjat ×0,7 aloittelija, ×1,25 kokenut; rasvanpoltossa alaraja.
  final scale =
      switch (exp) {
        'aloittelija' => .7,
        'kokenut' => 1.25,
        _ => 1.0,
      } *
      (g == 'rasvanpoltto' ? .85 : 1);
  final rirC = switch ((g, exp)) {
    ('kunto', _) => '2–3',
    (_, 'aloittelija') => '2–3',
    (_, 'kokenut') => '1–2',
    _ => '1–3',
  };
  final rirI = switch ((g, exp)) {
    ('kunto', _) => '2–3',
    (_, 'aloittelija') => '1–2',
    (_, 'kokenut') => '0–1',
    _ => '0–2',
  };
  final deloadEvery = switch ((g, exp)) {
    ('voimanosto', 'aloittelija') => 0,
    ('voimanosto', _) => 5,
    (_, 'aloittelija') => 0,
    ('rasvanpoltto', _) => 5,
    ('kunto', _) => 7,
    (_, 'kokenut') => 5,
    _ => 6,
  };

  final plan = <PlanDay>[];
  for (final (name, items) in tpl) {
    final out = <PlanItem>[];
    for (final (slot, sets, lo, hi, kind, ex) in items) {
      final s = slots[slot]!;
      final used = out.map((i) => i.exercise).toSet();
      // Treenihistorian suosikki ensin (sama liikemalli), sitten mallipohjan ja paikan oletukset.
      final fav = kind == null && kb == null ? favorites[family(slot)] : null;
      var cands = [?fav, ?ex, ...s.defaults].where((c) => !used.contains(c)).toList();
      if (kb != null) {
        // Kahvakuulaohjelma: mallipohjan liike, vammatilassa saman liikemallin muut kahvakuulaliikkeet.
        cands = [
          ?ex,
          for (final x in exerciseCatalog.values.expand((x) => x))
            if (x != ex && family(slotOf(x)) == family(slot) && fitsEquipment(x, equipment)) x,
        ].where((c) => !used.contains(c)).toList();
      } else if (kind == null && !fitsAll(equipment)) {
        // Välinetoive: sopivat ensin, myös saman liikemallin muut liikkeet. Voimanoston kilpaliikkeet tangolla.
        final fam = family(slot);
        final more = [
          for (final x in exerciseCatalog.values.expand((x) => x))
            if (family(slotOf(x)) == fam && !used.contains(x) && !cands.contains(x)) x,
        ];
        // Jos paikalle ei ole yhtään sopivaa liikettä (esim. rinta-eristys kehonpainolla), lähin korvaaja.
        if (![...cands, ...more].any((c) => fitsEquipment(c, equipment))) {
          more.insertAll(0, (_equipFallback[slot] ?? const []).where((c) => !used.contains(c)));
        }
        // Ensin liikkeet, jotka tehdään vain valituilla välineillä (kahvakuulapunnerrus ennen push pressiä).
        final fit = [...cands, ...more].where((c) => fitsEquipment(c, equipment)).toList();
        cands = [
          ...fit.where((c) => onlyEquipment(c, equipment)),
          ...fit.where((c) => !onlyEquipment(c, equipment)),
          ...cands.where((c) => !fitsEquipment(c, equipment)),
        ];
      }
      final (exercise, note) = chooseExercise(cands.isEmpty ? s.defaults : cands, injuries);
      final main = kind != null;
      final (mlo, mhi) = switch (measureOf(exercise)) {
        Measure.seconds => (20, 40),
        Measure.steps => (10, 20),
        Measure.trips => (1, 2),
        Measure.meters => (20, 40),
        Measure.reps =>
          kind == null && kb == null
              ? repRangeOverride[exercise] ?? styledReps(lo, hi, s.compound, repStyle)
              : (lo, hi),
      };
      out.add(
        PlanItem(
          exercise,
          slot,
          kind == 'H' || kind == 'V' ? 0 : (main ? sets : math.max(2, (sets * scale).round())),
          mlo,
          mhi,
          s.compound ? rirC : rirI,
          kb != null
              ? switch (kb) {
                  'voima' => 150,
                  'kunto' => 45,
                  _ => 90,
                }
              : main
              ? 240
              : (s.compound || slot == 'PAK' ? 150 : 90),
          kind: kind,
          note: note,
        ),
      );
    }
    _fitTime(out, minutes);
    plan.add(PlanDay(name, out));
  }
  // Käyttäjän itse valitsemat liikkeet: ohjelma rakennetaan niiden ympärille.
  if (chosen.isNotEmpty) {
    _placeChosen(plan, chosen, injuries, scale, rirC, rirI);
    for (final d in plan) {
      _fitTime(d.items, minutes, keep: chosen.toSet());
    }
  }
  // Minimiannos, työntö/veto-tasapaino ja treenikohtainen yläraja vaikuttavat toisiinsa: toistetaan, kunnes vakaa.
  for (var round = 0; round < (kb == null ? 4 : 0); round++) {
    final before = programToMarkdownPlan(plan);
    if (g != 'voimanosto') _minimumDose(plan);
    _balancePushPull(plan);
    _capPerSession(plan, exp);
    if (programToMarkdownPlan(plan) == before) break;
  }
  final longest = plan.map((d) => estimateMinutes(d.items)).reduce(math.max);
  if (longest > minutes + 5) {
    notes.add(
      chosen.length > 2 * plan.length
          ? l10n.fi(
              'Valitsit {0} liikettä {1} treenipäivälle: pisin treeni kestää noin {2} min ({3} min '
              'toivottu). Lisää treenipäivä, pidennä treeniä tai jätä osa liikkeistä pois.',
              [chosen.length, plan.length, longest.round(), minutes],
            )
          : l10n.fi(
              'Pisin treeni kestää noin {0} min. Pääliikkeiden tauot ovat pitkiä; lyhennä tarvittaessa '
              'lisäliikkeistä.',
              [longest.round()],
            ),
    );
  }
  if (injuries.isNotEmpty) {
    notes.add(
      l10n.fi(
        'Vammatila: {0}. Liikkeitä on vaihdettu tai muokattu. Kipua saa olla enintään 3–5/10, ja sen pitää '
        'rauhoittua seuraavaan aamuun mennessä.',
        [injuries.map((i) => injuryById(i)?.name ?? i).join(', ')],
      ),
    );
  }
  if (chosen.isNotEmpty) {
    notes.add(
      l10n.fi(
        'Rakennettu valitsemiesi liikkeiden ympärille: {0}. Muut liikkeet täydentävät liikemalleja ja '
        'työntö/veto-tasapainoa.',
        [chosen.join(', ')],
      ),
    );
  }
  final usedFavs = {
    for (final d in plan)
      for (final i in d.items)
        if (favorites.values.contains(i.exercise)) i.exercise,
  };
  if (usedFavs.isNotEmpty) {
    notes.add(l10n.fi('Suosikkiliikkeesi treenihistoriasta: {0}.', [usedFavs.join(', ')]));
  }
  if (!fitsAll(equipment) && kb == null) {
    notes.add(
      g == 'voimanosto'
          ? l10n.fi(
              'Välineet: {0}. Muita välineitä käytetään vain, jos sopivaa liikettä ei löydy; kilpaliikkeet tangolla.',
              [equipment.map((e) => equipmentChoices[e]!.$2.toLowerCase()).join(', ')],
            )
          : l10n.fi('Välineet: {0}. Muita välineitä käytetään vain, jos sopivaa liikettä ei löydy.', [
              equipment.map((e) => equipmentChoices[e]!.$2.toLowerCase()).join(', '),
            ]),
    );
  }
  if (kb != null) {
    // Kahvakuulaohjelman toistot tulevat painotuksesta.
  } else if (repStyle == 'raskas') {
    notes.add(
      l10n.fi(
        'Raskaampi toistoalue: lisäliikkeissä vähemmän toistoja ja isommat painot. Kasvattaa '
        'voimaa, lihaskasvu on yhtä hyvä, kun sarjat viedään lähelle uupumusta (Schoenfeld ym. '
        '2017, 2021).',
      ),
    );
  } else if (repStyle == 'kevyt') {
    notes.add(
      l10n.fi(
        'Kevyempi toistoalue: enemmän toistoja ja pienemmät painot. Säästää niveliä; lihaskasvu on '
        'yhtä hyvä, kun sarjat viedään lähelle uupumusta. Voima kehittyy hitaammin.',
      ),
    );
  }
  if (deloadEvery > 0) {
    notes.add(l10n.fi('Kevennysviikko joka {0}. viikko (puolet sarjoista, painot −10 %).', [deloadEvery]));
  }

  final program = Program(
    goal: goal,
    experience: experience,
    days: days,
    minutes: minutes,
    start: dateOnly(start ?? DateTime.now()),
    deloadEvery: deloadEvery,
    maxes: maxes,
    notes: notes,
    plan: plan,
    repStyle: repStyle,
    equipment: {...equipment},
    kbFocus: kb,
  );
  // Viikon sarjat tavoitteen suositukseen (Viikon kuorma), kun aika ja treenikohtainen yläraja sallivat.
  if (kb == null) {
    final short = _reachWeeklyTargets(program, exp);
    if (short.isNotEmpty) {
      program.notes.add(
        l10n.fi(
          'Viikon sarjamäärä jää alle tavoitteen suosituksen: {0}. {1} × {2} min ei riitä enempään; lisää '
          'treenipäivä tai pidennä treeniä. Vähemmälläkin kehittyy, kunhan treenaat säännöllisesti.',
          [short.map(l10n.fi).join(', '), plan.length, minutes],
        ),
      );
    }
  }
  return program;
}

/// Suorat liikepaikat päälihasryhmille (samat kuin minimiannoksessa).
const _directSlots = <String, List<String>>{
  'rinta': ['VTY', 'VIN', 'RIE'],
  'selkä': ['VVE', 'PVE'],
  'etureisi': ['KYY', 'YKS', 'POJ'],
  'takareisi': ['LON', 'POK'],
  'pakara': ['PAK', 'LON', 'KYY', 'YKS'],
  'olkapää': ['PTY', 'OSI'],
};

/// Lisää sarjoja päälihasryhmille, joiden viikkosarjat jäävät alle tavoitteen suosituksen (weeklyRange):
/// sarja kerrallaan sille päivälle, jolla on eniten aikaa jäljellä, kunhan treeni mahtuu kestoonsa, liikkeen
/// sarjoja on enintään 5 ja treenikohtainen yläraja (sessionCap) pitää. Palauttaa lihasryhmät, jotka jäivät
/// silti alle suosituksen.
List<String> _reachWeeklyTargets(Program p, String exp) {
  final cap = sessionCap(exp);
  double sum(Set<String> s) =>
      p.plan.expand((d) => d.items).where((i) => s.contains(i.slot)).fold(0.0, (a, i) => a + _weekSets(i));

  /// Sarja, joka mahtuu päivän kestoon, liikkeen enimmäismäärään ja treenikohtaiseen ylärajaan; eniten aikaa
  /// jäljellä olevalta päivältä.
  PlanItem? pick(bool Function(PlanItem) ok) {
    PlanItem? best;
    var bestRoom = -1.0;
    for (final d in p.plan) {
      final room = p.minutes - estimateMinutes(d.items);
      final per = _sessionSets(d);
      for (final i in d.items) {
        if (i.kind != null || i.sets >= 5 || !ok(i) || i.restSec / 60 + .75 > room) continue;
        final credit = _sessionCredit[i.slot] ?? const <String, double>{};
        if (credit.entries.any((e) => (per[e.key] ?? 0) + e.value > cap + .01)) continue;
        if (room > bestRoom) {
          best = i;
          bestRoom = room;
        }
      }
    }
    return best;
  }

  for (var guard = 0; guard < 300; guard++) {
    final low = weeklyLoad(p).where((m) => majorMuscles.contains(m.muscle) && m.sets < m.lo - .01).toList()
      ..sort((a, b) => (a.sets / a.lo).compareTo(b.sets / b.lo));
    if (low.isEmpty) return const [];
    PlanItem? best;
    for (final m in low) {
      best = pick((i) => _directSlots[m.muscle]?.contains(i.slot) ?? false);
      if (best != null) break; // vajaimmalle lihasryhmälle löytyi paikka
    }
    if (best == null) return [for (final m in low) m.muscle];
    // Työntö/veto-tasapaino (veto vähintään 0,95 × työntö): tarvittaessa ensin vetosarja.
    if (_push.contains(best.slot) && sum(_pull) < (sum(_push) + 1) * .95) {
      final pull = pick((i) => _pull.contains(i.slot));
      if (pull == null) return [for (final m in low) m.muscle];
      pull.sets++;
      continue;
    }
    best.sets++;
  }
  return const [];
}

bool fitsAll(Set<String> prefs) => prefs.isEmpty || prefs.length == equipmentChoices.length;

/// Toistoalue käyttäjän valinnan mukaan. Pääliikkeiden (voimanoston taulukko) toistoja ei muuteta.
(int, int) styledReps(int lo, int hi, bool compound, String style) {
  final (l, h) = switch (style) {
    'raskas' => compound ? (math.max(3, lo - 3), hi - 4) : (math.max(6, lo - 2), hi - 4),
    'kevyt' => compound ? (lo + 4, math.min(20, hi + 5)) : (lo + 3, math.min(30, hi + 5)),
    _ => (lo, hi),
  };
  return (l, math.max(h, lo == hi ? l : l + 2)); // alue säilyy, ei käänny ylösalaisin
}

/// Korvaajat liikemalleille, joille jollakin välineellä ei ole omaa liikettä.
const _equipFallback = <String, List<String>>{
  'RIE': ['Jalat koholla punnerrus', 'Punnerrus', 'Dipit', 'Kahvakuulalattiapunnerrus'],
  'OSI': ['Pike-punnerrus', 'Y-T-W-nostot makuulla', 'Käsilläseisontapunnerrus', 'Vipunosto eteen'],
  'KAN': ['Kylkilankku', 'Farmer walk'],
};

/// Toistoalue liikkeelle mittaustavan ja tyypin mukaan.
(int, int) defaultRange(String exercise, bool compound) =>
    repRangeOverride[exercise] ??
    switch (measureOf(exercise)) {
      Measure.seconds => (20, 40),
      Measure.steps => (10, 20),
      Measure.trips => (1, 2),
      Measure.meters => (20, 40),
      Measure.reps => compound ? (6, 10) : (10, 15),
    };

/// Sijoittaa valitut liikkeet ohjelmaan: korvaa saman liikemallin paikan (pääliikkeitä ei korvata) tai,
/// jos mallia ei ole ohjelmassa, lisää liikkeen lyhimpään treeniin.
void _placeChosen(
  List<PlanDay> plan,
  List<String> chosen,
  List<String> injuries,
  double scale,
  String rirC,
  String rirI,
) {
  final placed = <String>{};
  for (final x in chosen) {
    if (plan.any((d) => d.items.any((i) => i.exercise == x))) {
      placed.add(x);
      continue;
    }
    final slot = slotOf(x);
    final fam = family(slot);
    PlanItem? target;
    for (final d in plan) {
      if (d.items.any((i) => i.exercise == x)) continue;
      target = d.items
          .where((i) => i.kind == null && fam.isNotEmpty && family(i.slot) == fam && !placed.contains(i.exercise))
          .firstOrNull;
      if (target != null) break;
    }
    final compound = slots[slot]?.compound ?? false;
    final note = injuryStatus(x, injuries).avoid.isEmpty
        ? null
        : l10n.fi('Varo: {0}', [injuryStatus(x, injuries).avoid.join(', ')]);
    if (target != null) {
      final (lo, hi) = measureOf(x) == measureOf(target.exercise) && repRangeOverride[x] == null
          ? (target.lo, target.hi)
          : defaultRange(x, compound);
      target
        ..exercise = x
        ..slot = slot.isEmpty ? target.slot : slot
        ..lo = lo
        ..hi = hi
        ..note = note;
    } else {
      final day = plan.reduce((a, b) => estimateMinutes(a.items) <= estimateMinutes(b.items) ? a : b);
      final (lo, hi) = defaultRange(x, compound);
      final it = PlanItem(
        x,
        slot,
        math.max(2, (3 * scale).round()),
        lo,
        hi,
        compound ? rirC : rirI,
        compound ? 150 : 90,
        note: note,
      );
      final at = compound ? day.items.indexWhere((i) => !i.compound && i.kind == null) : -1;
      at < 0 ? day.items.add(it) : day.items.insert(at, it);
    }
    placed.add(x);
  }
}

/// Ensimmäinen ehdokas, jota vammat eivät estä. Muuten vamman korvaava liike tai ensimmäinen varoituksella.
(String, String?) chooseExercise(List<String> candidates, List<String> injuries) {
  for (final c in candidates) {
    final st = injuryStatus(c, injuries);
    if (st.avoid.isEmpty) return (c, st.modify.isEmpty ? null : st.modify.join(' · '));
  }
  for (final c in candidates) {
    final sub = injuryStatus(c, injuries).substitute;
    if (sub != null && injuryStatus(sub, injuries).avoid.isEmpty) return (sub, null);
  }
  return (candidates.first, l10n.fi('Varo: {0}', [injuryStatus(candidates.first, injuries).avoid.join(', ')]));
}

const _push = {'VTY', 'VIN', 'PTY', 'RIE', 'KP', 'PEV'};
const _pull = {'VVE', 'PVE', 'TAK'};

int _weekSets(PlanItem i) => switch (i.kind) {
  'H' => plHeavy[0].$1,
  'V' => plVolume[0].$1,
  _ => i.sets,
};

/// Vetoa vähintään yhtä paljon kuin työntöä (valmennuskäytäntö olkapäiden tasapainoon; ks. program_check.dart).
/// Lisää ensin soutuun, sitten takaolkaan ja pystyvetoon (+2 sarjaa liikettä kohden), lopuksi face pull -liikkeen
/// työntöpäiviin.
void _balancePushPull(List<PlanDay> plan) {
  double sum(Set<String> s) =>
      plan.expand((d) => d.items).where((i) => s.contains(i.slot)).fold(0.0, (a, i) => a + _weekSets(i));
  final pulls = [
    for (final slot in ['VVE', 'TAK', 'PVE'])
      ...plan.expand((d) => d.items).where((i) => i.slot == slot && i.kind == null),
  ];
  final added = <PlanItem, int>{};
  var guard = 0;
  while (sum(_pull) < sum(_push) * .95 && guard++ < 40) {
    final it = pulls.where((i) => (added[i] ?? 0) < 2).firstOrNull;
    if (it == null) {
      // Ei enää lisättävää: face pull jokaiseen työntöpäivään, jossa sitä ei vielä ole.
      final day = plan
          .where((d) => d.items.any((i) => _push.contains(i.slot)) && !d.items.any((i) => i.slot == 'TAK'))
          .firstOrNull;
      if (day == null) break;
      final ex = slots['TAK']!.defaults.first;
      final item = PlanItem(ex, 'TAK', 2, 12, 20, '0–2', 90);
      day.items.add(item);
      pulls.add(item);
      continue;
    }
    it.sets++;
    added[it] = (added[it] ?? 0) + 1;
  }
}

/// Treenikohtainen yläraja suorille sarjoille lihasryhmää kohden (aloittelija 6, keskitaso 8, kokenut 10).
double sessionCap(String exp) => switch (exp) {
  'aloittelija' => 6.0,
  'kokenut' => 10.0,
  _ => 8.0,
};

/// Liikepaikan suora kuorma lihasryhmille treenikohtaista ylärajaa varten.
const _sessionCredit = <String, Map<String, double>>{
  'KYY': {'etureisi': 1},
  'KYV': {'etureisi': 1},
  'YKS': {'etureisi': 1},
  'POJ': {'etureisi': 1},
  'LON': {'takareisi': 1},
  'MAV': {'takareisi': 1},
  'POK': {'takareisi': 1},
  'PAK': {'takareisi': .5},
  'VTY': {'rinta': 1, 'olkapää': .5},
  'VIN': {'rinta': 1, 'olkapää': .5},
  'RIE': {'rinta': 1},
  'PEV': {'rinta': 1},
  'PTY': {'olkapää': 1},
  'OSI': {'olkapää': 1},
  'VVE': {'selkä': 1},
  'PVE': {'selkä': 1},
};

/// Päivän suorat sarjat lihasryhmää kohden.
Map<String, double> _sessionSets(PlanDay d) {
  final per = <String, double>{};
  for (final i in d.items.where((i) => i.kind == null)) {
    for (final e in (_sessionCredit[i.slot] ?? const <String, double>{}).entries) {
      per[e.key] = (per[e.key] ?? 0) + i.sets * e.value;
    }
  }
  return per;
}

/// Yhden treenin lihasryhmäkohtainen yläraja (Remmert ym. 2025): karsitaan eristäviä, sitten suurinta.
void _capPerSession(List<PlanDay> plan, String exp) {
  final cap = sessionCap(exp);
  const credit = _sessionCredit;
  for (final d in plan) {
    for (var guard = 0; guard < 30; guard++) {
      final per = <String, double>{};
      for (final i in d.items.where((i) => i.kind == null)) {
        for (final e in (credit[i.slot] ?? const <String, double>{}).entries) {
          per[e.key] = (per[e.key] ?? 0) + i.sets * e.value;
        }
      }
      final over = per.entries.where((e) => e.value > cap + .01).firstOrNull;
      if (over == null) break;
      final cands =
          d.items
              .where((i) => i.kind == null && i.sets > 2 && (credit[i.slot]?.containsKey(over.key) ?? false))
              .toList()
            ..sort((a, b) => (a.compound ? 1 : 0).compareTo(b.compound ? 1 : 0));
      if (cands.isEmpty) break;
      // Eristävä ensin; moninivelliikkeistä se, jolla on eniten sarjoja.
      final iso = cands.where((i) => !i.compound).toList();
      final pick = iso.isNotEmpty ? iso.first : (cands..sort((a, b) => b.sets.compareTo(a.sets))).first;
      pick.sets--;
    }
  }
}

/// Vähintään 4 sarjaa viikossa jokaiselle päälihasryhmälle (Iversen ym. 2021, minimiannos):
/// lisätään sarjoja suorimmin kuormittavaan moninivelliikkeeseen (enintään 5 sarjaa liikettä kohden).
void _minimumDose(List<PlanDay> plan) {
  const direct = <String, List<String>>{
    'rinta': ['VTY', 'VIN', 'RIE'],
    'selkä': ['VVE', 'PVE'],
    'etureisi': ['KYY', 'YKS', 'POJ'],
    'takareisi': ['LON', 'POK'],
    'olkapää': ['PTY', 'OSI'],
  };
  for (final e in direct.entries) {
    final items = plan.expand((d) => d.items).where((i) => e.value.contains(i.slot) && i.kind == null).toList();
    if (items.isEmpty) continue;
    var guard = 0;
    while (items.fold(0, (a, i) => a + i.sets) < 4 && guard++ < 8) {
      final it = items.where((i) => i.sets < 5).firstOrNull;
      if (it == null) break;
      it.sets++;
    }
  }
}

String programToMarkdownPlan(List<PlanDay> plan) =>
    plan.map((d) => '${d.name}:${d.items.map((i) => '${i.exercise}${i.sets}').join(',')}').join('|');

/// Arvioitu kesto (min): lämmittely 8 min + 4 min jokaisesta lisäpääliikkeestä + sarjat × (tauko + 45 s).
double estimateMinutes(List<PlanItem> items, [int Function(PlanItem)? setsOf]) {
  final compounds = items.where((i) => i.compound).length;
  var m = 8.0 + 4 * math.max(0, compounds - 1);
  for (final i in items) {
    final n = setsOf?.call(i) ?? (i.kind == 'H' || i.kind == 'V' ? 5 : i.sets);
    m += n * (i.restSec / 60 + .75);
  }
  return m;
}

/// Karsii eristysliikkeiden sarjoja ja lopuksi viimeisiä eristysliikkeitä, kunnes treeni mahtuu aikaan.
void _fitTime(List<PlanItem> items, int minutes, {Set<String> keep = const {}}) {
  bool over() => estimateMinutes(items) > minutes;
  var guard = 0;
  while (over() && guard++ < 80) {
    final iso = items.where((i) => !i.compound && i.kind == null && i.sets > 2).toList();
    if (iso.isNotEmpty) {
      iso.last.sets--;
      continue;
    }
    final acc = items.where((i) => i.compound && i.kind == null && i.sets > 2).toList();
    if (acc.isNotEmpty) {
      acc.last.sets--;
      continue;
    }
    // Pudotetaan ohjelman omia lisäliikkeitä, ei käyttäjän valitsemia: ensin eristävät, sitten
    // moninivelliikkeet, joiden liikemalli on tässä treenissä jo toisella liikkeellä.
    var drop = items.lastIndexWhere((i) => !i.compound && i.kind == null && !keep.contains(i.exercise));
    if (drop < 0 && keep.isNotEmpty) {
      drop = items.lastIndexWhere(
        (i) =>
            i.compound &&
            i.kind == null &&
            !keep.contains(i.exercise) &&
            items.any((o) => o != i && family(o.slot) == family(i.slot)),
      );
    }
    if (drop < 0 || items.length <= 3) break;
    items.removeAt(drop);
  }
}

// --- ohjelma.md ----------------------------------------------------------

String _min(int s) => s % 60 == 0 ? '${s ~/ 60} min' : '${fileNum(s / 60)} min';

String programToMarkdown(Program p) {
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('goal: ${p.goal}')
    ..writeln('experience: ${p.experience}')
    ..writeln('days: ${p.days}')
    ..writeln('minutes: ${p.minutes}')
    ..writeln('start: ${isoDate(p.start)}')
    ..writeln('deloadEvery: ${p.deloadEvery}');
  if (p.repStyle != 'suositus') b.writeln('reps: ${p.repStyle}');
  if (!fitsAll(p.equipment)) b.writeln('equipment: ${p.equipment.join(', ')}');
  if (p.kbFocus != null) b.writeln('kettlebell: ${p.kbFocus}');
  if (p.maxes.isNotEmpty) {
    b.writeln('maxes: ${p.maxes.entries.map((e) => '${e.key}=${fileNum(e.value)}').join('; ')}');
  }
  b
    ..writeln('---')
    ..writeln()
    ..writeln('# Ohjelma: ${p.title}')
    ..writeln();
  for (final n in p.notes) {
    b.writeln('> $n');
  }
  for (final d in p.plan) {
    b
      ..writeln()
      ..writeln('## ${d.name}${d.label == null ? '' : ' | ${d.label}'}');
    for (final i in d.items) {
      final pres = switch (i.kind) {
        'H' => 'raskas',
        'V' => 'volyymi',
        'L' => 'lineaarinen ${i.sets} × ${i.lo}',
        _ => '${i.sets} × ${i.lo == i.hi ? i.lo : '${i.lo}–${i.hi}'}',
      };
      b.write('- ${i.exercise} | $pres | varaa ${i.rir} | tauko ${_min(i.restSec)} | ${i.slot}');
      if (i.note != null) b.write(' | huom: ${i.note}');
      b.writeln();
    }
  }
  return b.toString();
}

/// Jaettava ohjelmapohja (.gmd = Gievra + Markdown): sama muoto kuin ohjelma.md, mutta ilman henkilökohtaisia
/// tietoja (maksimit, aloituspäivä). Tuonnissa aloituspäivä on tuontipäivä.
const templateExtension = 'gmd';

String programToTemplate(Program p, {String? name, String? author}) {
  final md = programToMarkdown(p);
  final lines = md.split('\n');
  final out = <String>[];
  var inMeta = false;
  for (final l in lines) {
    if (l == '---') {
      inMeta = !inMeta;
      out.add(l);
      if (inMeta) {
        out.add('template: gievra-1');
        if (name != null && name.trim().isNotEmpty) out.add('name: ${name.trim()}');
        if (author != null && author.trim().isNotEmpty) out.add('author: ${author.trim()}');
      }
      continue;
    }
    if (inMeta && (l.startsWith('start:') || l.startsWith('maxes:'))) continue;
    out.add(l);
  }
  return out.join('\n');
}

/// Onko teksti Gievran ohjelma tai ohjelmapohja.
bool looksLikeProgram(String md) => md.contains(RegExp(r'^goal:', multiLine: true)) && md.contains('\n## ');

Program? parseProgram(String md) {
  final lines = md.split('\n');
  final meta = <String, String>{};
  var i = 0;
  if (lines.isNotEmpty && lines[0].trim() == '---') {
    for (i = 1; i < lines.length && lines[i].trim() != '---'; i++) {
      final k = lines[i].indexOf(':');
      if (k > 0) meta[lines[i].substring(0, k).trim()] = lines[i].substring(k + 1).trim();
    }
    i++;
  }
  // Ohjelmapohjassa (.gmd) ei ole aloituspäivää: aloitetaan tänään.
  final start = DateTime.tryParse(meta['start'] ?? '') ?? (meta['template'] != null ? dateOnly(DateTime.now()) : null);
  if (start == null) return null;
  final p = Program(
    goal: meta['goal'] ?? 'kunto',
    experience: meta['experience'] ?? 'keski',
    days: int.tryParse(meta['days'] ?? '') ?? 3,
    minutes: int.tryParse(meta['minutes'] ?? '') ?? 60,
    start: start,
    deloadEvery: int.tryParse(meta['deloadEvery'] ?? '') ?? 6,
    repStyle: meta['reps'] ?? 'suositus',
    kbFocus: kbFocuses.containsKey(meta['kettlebell']) ? meta['kettlebell'] : null,
    equipment: {
      for (final x in (meta['equipment'] ?? '').split(','))
        if (equipmentChoices.containsKey(x.trim())) x.trim(),
    },
    maxes: {
      for (final kv in (meta['maxes'] ?? '').split(';'))
        if (kv.contains('=')) kv.split('=')[0].trim(): parseNum(kv.split('=')[1]) ?? 0,
    },
  );
  final presRe = RegExp(r'^(\d+)\s*[×x]\s*(\d+)(?:\s*[–-]\s*(\d+))?$');
  for (; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t.startsWith('> ')) {
      p.notes.add(t.substring(2));
    } else if (t.startsWith('## ')) {
      final parts = t.substring(3).split('|');
      final label = parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
      p.plan.add(PlanDay(parts.first.trim(), [], label: label.isEmpty ? null : label));
    } else if (t.startsWith('- ') && p.plan.isNotEmpty) {
      final f = t.substring(2).split('|').map((x) => x.trim()).toList();
      if (f.isEmpty || f[0].isEmpty) continue;
      String? kind;
      var sets = 3, lo = 8, hi = 12;
      var rir = '1–3', rest = 120, slot = '';
      String? note;
      for (final x in f.skip(1)) {
        final m = presRe.firstMatch(x.replaceFirst('lineaarinen ', ''));
        if (x == 'raskas') {
          kind = 'H';
        } else if (x == 'volyymi') {
          kind = 'V';
        } else if (m != null) {
          if (x.startsWith('lineaarinen')) kind = 'L';
          sets = int.parse(m[1]!);
          lo = int.parse(m[2]!);
          hi = m[3] == null ? lo : int.parse(m[3]!);
        } else if (x.startsWith('varaa ')) {
          rir = x.substring(6).trim();
        } else if (x.startsWith('tauko ')) {
          rest = ((parseNum(x.substring(6).replaceAll('min', '')) ?? 2) * 60).round();
        } else if (x.startsWith('huom:')) {
          note = x.substring(5).trim();
        } else if (slots.containsKey(x)) {
          slot = x;
        }
      }
      p.plan.last.items.add(PlanItem(f[0], slot, sets, lo, hi, rir, rest, kind: kind, note: note));
    }
  }
  p.plan.removeWhere((d) => d.items.isEmpty);
  return p.plan.isEmpty ? null : p;
}
