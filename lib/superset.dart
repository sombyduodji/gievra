import 'models.dart';

// Supersarjat ja kiertoharjoittelu: ryhmän liikkeet vuorotellen, palautus vasta kierroksen jälkeen.

/// Ryhmä, johon liike kuuluu (null = ei supersarjaa).
List<String>? supersetOf(Workout w, String name) => w.supersets.where((g) => g.contains(name)).firstOrNull;

/// Ryhmän kirjain (A, B, …) ja liikkeen numero: "A2".
String supersetLabel(Workout w, String name) {
  final gi = w.supersets.indexWhere((g) => g.contains(name));
  if (gi < 0) return '';
  return '${String.fromCharCode(65 + gi % 26)}${w.supersets[gi].indexOf(name) + 1}';
}

int _count(Workout w, String name) => w.exercises.where((e) => e.name == name).firstOrNull?.workSets.length ?? 0;

/// Liike tehty ryhmässä: merkitty valmiiksi tai ohjelman sarjat täynnä ([planned] null = ei rajaa).
bool _finished(Workout w, String name, int? Function(String)? planned) {
  if (w.doneMoves.contains(name)) return true;
  final p = planned?.call(name);
  return p != null && _count(w, name) >= p;
}

/// Kierros, joka on menossa (1…): pienin tehtyjen sarjojen määrä keskeneräisistä + 1.
int supersetRound(Workout w, List<String> group, {int? Function(String)? planned}) {
  final open = group.where((x) => !_finished(w, x, planned)).toList();
  final counts = (open.isEmpty ? group : open).map((x) => _count(w, x));
  return counts.reduce((a, b) => a < b ? a : b) + (open.isEmpty ? 0 : 1);
}

/// Seuraava liike, kun [name]:lle on juuri kirjattu sarja: (seuraava, kierros valmis).
/// Kesken kierroksen seuraava on ryhmässä seuraava liike, jolla on vähemmän sarjoja (ei palautusta väliin).
/// Kierroksen lopussa seuraava kierros alkaa ensimmäisestä keskeneräisestä liikkeestä (palautus ensin).
/// (null, true) = koko ryhmä tehty. Ei ryhmää: (null, false).
(String?, bool) supersetNext(Workout w, String name, {int? Function(String)? planned}) {
  final g = supersetOf(w, name);
  if (g == null) return (null, false);
  final r = _count(w, name);
  final i = g.indexOf(name);
  for (var k = 1; k < g.length; k++) {
    final x = g[(i + k) % g.length];
    if (!_finished(w, x, planned) && _count(w, x) < r) return (x, false);
  }
  final open = g.where((x) => !_finished(w, x, planned)).toList();
  if (open.isEmpty) return (null, true);
  final low = open.map((x) => _count(w, x)).reduce((a, b) => a < b ? a : b);
  return (open.firstWhere((x) => _count(w, x) == low), true);
}

/// Seuraavaksi tehtävä liike ryhmässä (korostus treenin näkymässä); null = ryhmä tehty.
String? supersetCurrent(Workout w, List<String> group, {int? Function(String)? planned}) {
  final open = group.where((x) => !_finished(w, x, planned)).toList();
  if (open.isEmpty) return null;
  final low = open.map((x) => _count(w, x)).reduce((a, b) => a < b ? a : b);
  return open.firstWhere((x) => _count(w, x) == low);
}
