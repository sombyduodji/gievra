import 'injury_data.dart';

export 'injury_data.dart';

/// Alueet, jotka tämä versio tuntee. Tuntematon tunnus (esim. uudemman version alue tai käsin muokattu
/// tiedosto) säilyy asetuksissa, mutta sitä ei näytetä eikä vammatila ole sen takia päällä.
List<String> knownInjuries(Iterable<String> ids) => [
  for (final id in ids)
    if (injuryById(id) != null) id,
];

/// Lyhyt alueen nimi tilariville: ilman tarkennusta suluissa tai pilkun jälkeen ("Polvi (kierukka /
/// eturistiside), lyhyesti" → "Polvi"). Toimii käännetylle nimelle.
String injuryShortName(String name) =>
    name.replaceFirst(RegExp(r'\s*\(.*$'), '').replaceFirst(RegExp(r',.*$'), '').trim();

InjuryRegion? injuryById(String id) {
  for (final r in injuryRegions) {
    if (r.id == id) return r;
  }
  return null;
}

class InjuryStatus {
  /// Alueet (nimet), joiden takia liikettä kannattaa välttää.
  final List<String> avoid;

  /// Muokkausohjeet ("alue: ohje").
  final List<String> modify;

  /// Ehdotettu korvaava liike.
  final String? substitute;
  const InjuryStatus(this.avoid, this.modify, this.substitute);
  bool get flagged => avoid.isNotEmpty || modify.isNotEmpty;
}

/// Kahvakuulaliikkeet, joille vammatilan aineistossa (docs/tutkimus/vammatila.md) ei ole omia rivejä: niihin
/// käytetään lähimmän käsipaino- tai tankoliikkeen ohjetta (sama liikerata ja kuormitus). Esim. pään yli
/// punnertaminen kahvakuulalla = käsipainopystypunnerrus ("vain jos kivuton, kevyt"), räjähtävä pään yli vienti
/// (tempaus, työntö, thruster) = push press (vältä kiertäjäkalvosimen vaivassa ja epävakaudessa).
const injuryEquivalent = <String, String>{
  'Kahvakuulapystypunnerrus': 'Käsipainopystypunnerrus',
  'Tuplakahvakuulapystypunnerrus': 'Käsipainopystypunnerrus',
  'Rinnalleveto ja punnerrus': 'Käsipainopystypunnerrus',
  'Tuplakahvakuulan rinnalleveto ja punnerrus': 'Käsipainopystypunnerrus',
  'Turkkilainen ylösnousu': 'Käsipainopystypunnerrus',
  'Tuulimylly': 'Käsipainopystypunnerrus',
  'Kahvakuulatempaus': 'Push press',
  'Tuplakahvakuulatyöntö': 'Push press',
  'Kahvakuula-thruster': 'Push press',
  'Kahvakuulan sumoveto': 'Pystysoutu',
  'Kahvakuulalattiapunnerrus': 'Lattiapunnerrus',
  'Tuplakahvakuulalattiapunnerrus': 'Lattiapunnerrus',
  'Kahvakuulasoutu': 'Käsipainosoutu',
  'Tuplakahvakuulasoutu': 'Käsipainosoutu',
  'Renegade-soutu': 'Käsipainosoutu',
  'Kahvakuulamaastaveto': 'Maastaveto',
  'Tuplakahvakuulamaastaveto': 'Maastaveto',
  'Kahvakuulan sumomaastaveto': 'Maastaveto',
  'Kahvakuulaheilautus': 'Romanialainen maastaveto',
  'Yhden käden heilautus': 'Romanialainen maastaveto',
  'Tuplakahvakuulaheilautus': 'Romanialainen maastaveto',
  'Yhden jalan maastaveto': 'Romanialainen maastaveto',
  'Kahvakuulan etukyykky': 'Goblet-kyykky',
  'Kahvakuula-askelkyykky': 'Askelkyykky',
  'Tuplakahvakuula-askelkyykky': 'Askelkyykky',
  'Kahvakuulahauiskääntö': 'Hauiskääntö käsipainoilla',
  'Matkalaukkukanto': 'Farmer walk',
};

InjuryStatus injuryStatus(String exercise, List<String> injuries) {
  final avoid = <String>[], modify = <String>[];
  String? sub;
  final x = injuryEquivalent[exercise] ?? exercise;
  for (final id in injuries) {
    final r = injuryById(id);
    if (r == null) continue;
    if (r.avoid.contains(x)) {
      avoid.add(r.name);
      sub ??= r.substitute[x];
    }
    final m = r.modify[x];
    if (m != null) modify.add(m);
  }
  return InjuryStatus(avoid, mergeInjuryNotes(modify), sub);
}

/// Usean vamman ohjeet samalle liikkeelle: poistaa toistot. Ohje jätetään pois, jos jokin muu ohje sisältää jo
/// kaikki sen sanat (sanan alku, 5 kirjainta, riittää taivutusten takia: "vetoremmit" ⊂ "käytä vetoremmejä,
/// kevennä"). Kaikki sanat lasketaan, myös numerot ja "ei", joten "Ei kyykkyä" tai "5 s" ei katoa. Ohjeet
/// pidetään kokonaisina, jotta niiden käännökset löytyvät.
List<String> mergeInjuryNotes(List<String> notes) {
  final words = [
    for (final n in notes)
      [
        for (final w in n.toLowerCase().split(RegExp(r'[^a-zåäöšžčđŋŧá0-9]+')))
          if (w.isNotEmpty) w.substring(0, w.length < 5 ? w.length : 5),
      ],
  ];
  bool covers(int a, int b) => words[b].isNotEmpty && words[b].every(words[a].contains);

  final out = <String>[];
  for (var i = 0; i < notes.length; i++) {
    var redundant = false;
    for (var j = 0; j < notes.length && !redundant; j++) {
      if (i == j || !covers(j, i)) continue;
      // Kaksi toisensa kattavaa (esim. sama ohje kahdesti): pidetään ensimmäinen.
      redundant = !covers(i, j) || j < i;
    }
    if (!redundant) out.add(notes[i]);
  }
  return out;
}
