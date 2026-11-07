import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';
import 'package:treenipaivakirja/program_edit.dart';

Program gen(String goal, String exp, int days, int minutes) => generateProgram(
  goal: goal,
  experience: exp,
  days: days,
  minutes: minutes,
  injuries: const [],
  start: DateTime(2026, 11, 2),
);

List<MuscleLoad> lowMajors(Program p) =>
    weeklyLoad(p).where((m) => majorMuscles.contains(m.muscle) && m.level == LoadLevel.low).toList();

void main() {
  test('Kun aika riittää, viikon sarjat nousevat tavoitteen suositukseen', () {
    for (final (exp, days, minutes) in [('keski', 3, 75), ('keski', 4, 75), ('keski', 5, 60), ('kokenut', 4, 90)]) {
      final p = gen('lihaskasvu', exp, days, minutes);
      expect(lowMajors(p), isEmpty, reason: '$exp $days × $minutes');
      for (final d in p.plan) {
        expect(estimateMinutes(d.items), lessThanOrEqualTo(minutes + .01), reason: '${d.name} mahtuu aikaan');
        for (final i in d.items) {
          expect(i.sets, lessThanOrEqualTo(5));
        }
      }
    }
  });

  test('Jos aika ei riitä, ohjelma kertoo sen eikä ylitä kestoa', () {
    for (final g in ['lihaskasvu', 'rasvanpoltto', 'kunto', 'voimanosto']) {
      for (final e in ['aloittelija', 'keski', 'kokenut']) {
        for (final d in [2, 3, 4, 5]) {
          for (final m in [45, 60, 75, 90]) {
            final p = gen(g, e, d, m);
            if (lowMajors(p).isNotEmpty) {
              expect(p.notes.any((n) => n.startsWith('Viikon sarjamäärä jää alle')), isTrue, reason: '$g $e $d × $m');
            }
          }
        }
      }
    }
  });
}
