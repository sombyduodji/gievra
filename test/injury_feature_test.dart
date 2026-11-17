import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/program.dart';

/// Vammatila ominaisuutena (käyttäjä 16.11.: "toimiiko tarpeeksi hyvin"): jokainen alue jokaisen tavoitteen,
/// kokemustason ja päivämäärän ohjelmaa vasten.
void main() {
  final known = {for (final l in allExercises().values) ...l};
  final ids = [for (final r in injuryRegions) r.id];

  test('Korvaavat liikkeet ovat olemassa eivätkä ole saman vamman välteltäviä', () {
    final bad = <String>[];
    for (final r in injuryRegions) {
      for (final MapEntry(key: from, value: to) in r.substitute.entries) {
        if (!known.contains(to)) bad.add('${r.id}: $from → $to (ei liikeluettelossa)');
        if (r.avoid.contains(to)) bad.add('${r.id}: $from → $to (korvaaja itse vältettävä)');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('Ohjelma tehtynä vamman kanssa ei sisällä vältettäviä liikkeitä', () {
    final bad = <String>[];
    for (final goal in goals.keys) {
      for (final exp in experiences.keys) {
        for (final days in [2, 3, 4, 5]) {
          for (final id in ids) {
            final p = generateProgram(goal: goal, experience: exp, days: days, minutes: 60, injuries: [id]);
            for (final d in p.plan) {
              for (final i in d.items) {
                if (injuryStatus(i.exercise, [id]).avoid.isNotEmpty) bad.add('$goal/$exp/$days/$id: ${i.exercise}');
              }
            }
          }
        }
      }
    }
    expect(bad.toSet(), isEmpty, reason: bad.toSet().take(40).join('\n'));
  });

  test('Vamma jälkikäteen (väliaikainen): välteltävä korvautuu tai jää näkyviin varoituksen kanssa; poisto palauttaa', () {
    final noSub = <String>{}, badSub = <String>{};
    for (final goal in goals.keys) {
      for (final days in [2, 3, 4]) {
        final p = generateProgram(goal: goal, experience: 'keski', days: days, minutes: 60, injuries: const []);
        for (final id in ids) {
          for (final d in p.plan) {
            final adj = injuryAdjusted(d, [id]);
            expect(injuryAdjusted(d, const []), same(d));
            for (final (k, i) in adj.items.indexed) {
              final st = injuryStatus(i.exercise, [id]);
              if (st.avoid.isNotEmpty) noSub.add('$id: ${i.exercise}');
              if (i.exercise != d.items[k].exercise && !known.contains(i.exercise)) badSub.add('$id: ${i.exercise}');
            }
          }
        }
      }
    }
    expect(badSub, isEmpty, reason: badSub.join('\n'));
    // Ilman korvaajaa jäävät näkyvät sarjanäkymässä varoituksena ja Valitse muu liike -painikkeella.
    // ignore: avoid_print
    if (noSub.isNotEmpty) print('Ilman korvaajaa (${noSub.length}):\n${noSub.join('\n')}');
  });

  test('Kaksi vammaa yhtä aikaa: korvaaja ei ole kummankaan välteltävä', () {
    final bad = <String>{};
    for (final a in ids) {
      for (final b in ids) {
        if (a.compareTo(b) >= 0) continue;
        for (final x in known) {
          final st = injuryStatus(x, [a, b]);
          final s = st.substitute;
          if (s != null && injuryStatus(s, [a, b]).avoid.isNotEmpty) bad.add('$a+$b: $x → $s');
        }
      }
    }
    // ignore: avoid_print
    if (bad.isNotEmpty) print('Korvaaja toisen vamman välteltävä (${bad.length}):\n${bad.take(30).join('\n')}');
  });
}
