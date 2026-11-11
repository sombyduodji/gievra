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

InjuryStatus injuryStatus(String exercise, List<String> injuries) {
  final avoid = <String>[], modify = <String>[];
  String? sub;
  for (final id in injuries) {
    final r = injuryById(id);
    if (r == null) continue;
    if (r.avoid.contains(exercise)) {
      avoid.add(r.name);
      sub ??= r.substitute[exercise];
    }
    final m = r.modify[exercise];
    if (m != null) modify.add(m);
  }
  return InjuryStatus(avoid, modify, sub);
}
