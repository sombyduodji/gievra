import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/program.dart';

void main() {
  for (final f in kbFocuses.keys) {
    for (final d in [2, 3, 4]) {
      test('kahvakuulaohjelma $f, $d pv: vain kahvakuulaliikkeitä, ei tuplia päivässä', () {
        final p = generateProgram(
          goal: 'kunto',
          experience: 'keski',
          days: d,
          minutes: 60,
          injuries: const [],
          equipment: const {'kahvakuula'},
          kbFocus: f,
        );
        expect(p.kbFocus, f);
        expect(p.plan.length, d.clamp(2, 3));
        for (final day in p.plan) {
          final names = day.items.map((i) => i.exercise).toList();
          expect(names.toSet().length, names.length, reason: '${day.name}: $names');
          for (final n in names) {
            expect(fitsEquipment(n, const {'kahvakuula'}), isTrue, reason: n);
            expect(exerciseCatalog.values.expand((x) => x), contains(n));
          }
        }
        // Tallennus ja luku säilyttävät painotuksen.
        final back = parseProgram(programToMarkdown(p))!;
        expect(back.kbFocus, f);
        expect(back.plan.length, p.plan.length);
      });
    }
  }

  test('painotus ohitetaan, jos välineitä on muitakin', () {
    final p = generateProgram(
      goal: 'kunto',
      experience: 'keski',
      days: 3,
      minutes: 60,
      injuries: const [],
      equipment: const {'kahvakuula', 'vapaat'},
      kbFocus: 'voima',
    );
    expect(p.kbFocus, isNull);
  });

  test('kuulakoot: seuraava kuula', () {
    expect(nextKettlebell(16), 20);
    expect(nextKettlebell(12), 14);
    expect(nextKettlebell(48), 52);
    expect(kettlebellOnly('Tuplakahvakuulasoutu'), isTrue);
    expect(kettlebellOnly('Goblet-kyykky'), isFalse);
  });
}
