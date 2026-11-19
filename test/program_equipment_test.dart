import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';

// Ehdotetut ohjelmat kaikilla tavoitteilla, tasoilla, päivämäärillä ja välineillä (yötesti 19.11.): liikkeet
// valituilla välineillä (kehonpainoliike käy aina), sama liike vain kerran päivässä, enintään 5 sarjaa liikettä
// kohden, eikä kahvakuulaohjelma huomauta itsestään.
void main() {
  test('välineet, sarjat ja päivän liikkeet kaikissa yhdistelmissä', () {
    final problems = <String>[];
    for (final g in goals.keys) {
      for (final e in experiences.keys) {
        for (var d = 2; d <= 6; d++) {
          for (final eq in [
            ...equipmentChoices.keys.map((k) => {k}),
            {'vapaat', 'kahvakuula'},
            {'laitteet', 'kehonpaino'},
          ]) {
            final p = generateProgram(goal: g, experience: e, days: d, minutes: 60, injuries: const [], equipment: eq);
            final allowed = {for (final k in eq) ...equipmentChoices[k]!.$3, Equip.kehonpaino};
            for (final day in p.plan) {
              final seen = <String>{};
              for (final it in day.items.where((i) => i.kind == null)) {
                final c = '$g/$e/${d}d/${eq.join('+')} ${day.name}: ${it.exercise}';
                final ee = exerciseEquipment[it.exercise];
                if (ee != null && ee.intersection(allowed).isEmpty) problems.add('väline $c');
                if (!seen.add(it.exercise)) problems.add('kahdesti $c');
                if (it.sets > 5) problems.add('${it.sets} sarjaa $c');
              }
            }
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.take(10).join('\n'));
  });

  test('kahvakuulaohjelma ei huomauta itsestään (ei pystyvetoa ym.)', () {
    for (final kb in kbFocuses.keys) {
      for (final e in experiences.keys) {
        for (var d = 2; d <= 6; d++) {
          final p = generateProgram(
            goal: 'lihaskasvu',
            experience: e,
            days: d,
            minutes: 60,
            injuries: const [],
            equipment: {'kahvakuula'},
            kbFocus: kb,
          );
          expect(validateProgram(p), isEmpty, reason: '$kb $e $d');
        }
      }
    }
  });
}
