import 'injury_data.dart';

export 'injury_data.dart';

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
