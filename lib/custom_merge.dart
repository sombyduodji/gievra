import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'exercise_names_en.dart';
import 'exercises.dart';
import 'models.dart';

// Omat liikkeet ja valmiit liikkeet: kun Gievraan tulee uusi valmis liike (tai haku ei löytänyt olemassa
// olevaa), käyttäjän itse lisäämä samanniminen liike yhdistetään siihen. Täsmälleen sama nimi (kirjainkoosta,
// väleistä ja viivoista riippumatta) yhdistetään suoraan; samankaltaisesta kysytään ensin, ja "ei" muistetaan.
// Yhdistäminen siirtää treenit, ohjelman ja ennätykset valmiin liikkeen nimelle, jolloin mukana tulevat
// liikeohje, animaatio, liikemalli ja painoehdotukset.

String normName(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[-–—_/().,:;]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Sanojen alut (5 merkkiä): taivutusmuodot ja yhdyssanat osuvat yhteen (käsipainoilla ~ käsipainosoutu).
Set<String> _stems(String s) => {
  for (final w in normName(s).split(' '))
    if (w.length >= 3) w.length > 5 ? w.substring(0, 5) : w,
};

class MoveMatch {
  final String custom, builtin;

  /// Sama nimi (normalisoituna): yhdistetään kysymättä.
  final bool identical;
  const MoveMatch(this.custom, this.builtin, {required this.identical});
}

/// Samankaltaisuus 0–1 omalle nimelle [c] ja valmiille liikkeelle [b].
double moveSimilarity(String c, String b) {
  final nc = normName(c);
  for (final a in [...aliasesOf(b), if (exerciseEnglish[b] != null) exerciseEnglish[b]!]) {
    if (normName(a) == nc) return 1;
  }
  final sc = _stems(c), sb = _stems(b);
  if (sc.isEmpty || sb.isEmpty) return 0;
  return sc.intersection(sb).length / sc.union(sb).length;
}

/// Omat liikkeet, joille löytyy vastine valmiista liikkeistä. [declined]: "c|b"-parit, joista on vastattu ei.
List<MoveMatch> findMoveMatches(List<String> custom, Iterable<String> builtin, {Set<String> declined = const {}}) {
  final all = builtin.toList();
  final out = <MoveMatch>[];
  for (final c in custom) {
    final same = all.where((b) => normName(b) == normName(c)).firstOrNull;
    if (same != null) {
      out.add(MoveMatch(c, same, identical: true));
      continue;
    }
    String? best;
    var score = 0.0;
    for (final b in all) {
      if (declined.contains('$c|$b')) continue;
      final v = moveSimilarity(c, b);
      if (v > score) {
        score = v;
        best = b;
      }
    }
    if (best != null && score >= .6) out.add(MoveMatch(c, best, identical: false));
  }
  return out;
}

/// Kaikki valmiit liikkeet (ilman omia).
Iterable<String> builtinExercises() => exerciseCatalog.values.expand((x) => x);

const _declinedKey = 'not_same_moves';

Future<Set<String>> declinedMatches() async => {
  ...(await SharedPreferences.getInstance()).getStringList(_declinedKey) ?? const <String>[],
};

Future<void> declineMatch(MoveMatch m) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setStringList(_declinedKey, [...(await declinedMatches()), '${m.custom}|${m.builtin}']);
}

/// Yhdistää oman liikkeen valmiiseen: treenit, ohjelma ja ennätykset uudelle nimelle, oma liike pois.
/// Palauttaa muutettujen treenien määrän.
Future<int> mergeMove(MoveMatch m) async {
  final from = m.custom, to = m.builtin;
  var n = 0;
  if (from != to) {
    for (final w in [...store.workouts]) {
      if (!w.exercises.any((e) => e.name == from)) continue;
      final c = w.copy();
      _renameIn(c, from, to);
      await store.save(c);
      n++;
    }
    final p = settings.program;
    if (p != null) {
      var changed = false;
      for (final d in p.plan) {
        for (final it in d.items) {
          if (it.exercise == from) {
            it.exercise = to;
            changed = true;
          }
        }
      }
      final max = p.maxes.remove(from);
      if (max != null) {
        p.maxes.putIfAbsent(to, () => max);
        changed = true;
      }
      if (changed) await settings.setProgram(p);
    }
  }
  settings.removeCustomExercise(from);
  return n;
}

/// Nimi vaihtuu treenissä; jos treenissä on jo valmis liike, sarjat yhdistetään siihen.
void _renameIn(Workout w, String from, String to) {
  final i = w.exercises.indexWhere((e) => e.name == from);
  if (i < 0) return;
  final sets = w.exercises[i].sets;
  final j = w.exercises.indexWhere((e) => e.name == to);
  if (j >= 0) {
    w.exercises[j].sets.addAll(sets);
    w.exercises.removeAt(i);
  } else {
    w.exercises[i] = ExerciseEntry(to, sets);
  }
  final f = w.moveFeeling.remove(from);
  if (f != null) w.moveFeeling.putIfAbsent(to, () => f);
  if (w.tooHeavy.remove(from)) w.tooHeavy.add(to);
  if (w.doneMoves.remove(from)) w.doneMoves.add(to);
  if (w.skipMoves.remove(from)) w.skipMoves.add(to);
}
