import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/injury_data.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';

void main() {
  test('Kaikki ohjelmat ovat päteviä (työntö/veto, liikemallit, volyymi, järjestys)', () {
    final problems = <String>[];
    final injurySets = [
      <String>[],
      for (final r in injuryRegions) [r.id],
    ];
    for (final g in goals.keys) {
      for (final e in experiences.keys) {
        for (var d = 2; d <= 6; d++) {
          for (final m in [45, 60, 90]) {
            for (final inj in injurySets) {
              for (final style in ['suositus', 'raskas', 'kevyt']) {
                final p = generateProgram(goal: g, experience: e, days: d, minutes: m, injuries: inj, repStyle: style);
                for (final i in validateProgram(p, injuries: inj)) {
                  problems.add('$g/$e/${d}pv/${m}min${inj.isEmpty ? '' : '/${inj.first}'}: $style: $i');
                }
                for (final it
                    in p.plan
                        .expand((x) => x.items)
                        .where((i) => i.kind != 'H' && i.kind != 'V' && measureOf(i.exercise) == Measure.reps)) {
                  if (it.lo < 1 || it.hi < it.lo || it.hi > 30) {
                    problems.add('$g/$e/${d}pv: $style: ${it.exercise} ${it.lo}-${it.hi}');
                  }
                }
              }
            }
          }
        }
      }
    }
    // Välinetoiveet: jokainen yksittäinen väline ja yhdistelmä tuottaa pätevän ohjelman.
    for (final eq in [
      {'vapaat'},
      {'laitteet'},
      {'kahvakuula'},
      {'kehonpaino'},
      {'kahvakuula', 'kehonpaino'},
      {'vapaat', 'laitteet'},
    ]) {
      for (final g in goals.keys) {
        for (final e in experiences.keys) {
          for (var d = 2; d <= 6; d++) {
            for (final inj in injurySets) {
              final p = generateProgram(goal: g, experience: e, days: d, minutes: 75, injuries: inj, equipment: eq);
              for (final i in validateProgram(p, injuries: inj)) {
                problems.add('$g/$e/${d}pv/75min${inj.isEmpty ? '' : '/${inj.first}'}: $eq: $i');
              }
            }
          }
        }
      }
    }
    final unique = problems.map((x) => x.replaceFirst(RegExp(r'/\d+min(/[a-z_]+)?'), '')).toSet().toList()..sort();
    // ignore: avoid_print
    print('${problems.length} ongelmaa, ${unique.length} erilaista:\n${unique.take(80).join('\n')}');
    expect(problems, isEmpty);
  });
}
