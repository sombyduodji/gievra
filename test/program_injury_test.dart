import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';

// Vammatila (käyttäjä 19.11.): ehdotettu ohjelma sopii sekä tavoitteeseen että vammaan kaikilla tavoitteilla,
// päivämäärillä ja välineillä: ei vältettäviä liikkeitä, muokkausohje mukana, ohjelman tarkistus kunnossa,
// liikkeet valituilla välineillä (kehonpaino käy aina) ja vamman hyvin siedetty liike mukana, kun aika riittää.
void main() {
  test('jokainen vamma × tavoite × päivät × välineet', () {
    final problems = <String>[];
    final eqs = <Set<String>>[
      {},
      {'vapaat'},
      {'laitteet'},
      {'kahvakuula'},
      {'kehonpaino'},
    ];
    for (final r in injuryRegions) {
      for (final g in goals.keys) {
        for (var d = 2; d <= 6; d++) {
          for (final eq in eqs) {
            final inj = [r.id];
            final c = '${r.id}/$g/${d}d/${eq.isEmpty ? 'kaikki' : eq.join('+')}';
            final p = generateProgram(goal: g, experience: 'keski', days: d, minutes: 75, injuries: inj, equipment: eq);
            final allowed = eq.isEmpty ? null : {for (final k in eq) ...equipmentChoices[k]!.$3, Equip.kehonpaino};
            final names = <String>{};
            for (final day in p.plan) {
              for (final it in day.items) {
                names.add(it.exercise);
                final st = injuryStatus(it.exercise, inj);
                if (st.avoid.isNotEmpty) problems.add('vältettävä $c: ${it.exercise}');
                if (st.modify.isNotEmpty && !(it.note ?? '').contains(st.modify.first)) {
                  problems.add('ohje puuttuu $c: ${it.exercise}');
                }
                final ee = exerciseEquipment[it.exercise];
                if (it.kind == null && allowed != null && ee != null && ee.intersection(allowed).isEmpty) {
                  problems.add('väline $c: ${it.exercise}');
                }
              }
            }
            for (final v in validateProgram(p, injuries: inj)) {
              problems.add('tarkistus $c: $v');
            }
            final fit = r.recommended.where((x) => fitsEquipment(x, eq) && injuryStatus(x, inj).avoid.isEmpty);
            if (g != 'voimanosto' && fit.isNotEmpty && !fit.any(names.contains)) problems.add('ei suositeltua $c');
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.take(12).join('\n'));
  });

  test('ranne: punnerrusten muunnelmat saavat ohjeen (nyrkkien varassa)', () {
    final st = injuryStatus('Jalat koholla punnerrus', ['ranne']);
    expect(st.modify.join(), contains('nyrkkien'));
  });
}
