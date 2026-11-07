import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';

void main() {
  test('ohjelmapohja (.gmd): ei maksimeja eikä aloituspäivää, tuonti toimii', () {
    final p = generateProgram(
      goal: 'voimanosto',
      experience: 'keski',
      days: 3,
      minutes: 60,
      injuries: const [],
      maxes: const {'Takakyykky': 150},
      start: DateTime(2025, 1, 6),
    );
    final tpl = programToTemplate(p, name: 'Testi', author: 'Elle');
    expect(tpl, contains('template: gievra-1'));
    expect(tpl, contains('name: Testi'));
    expect(tpl, isNot(contains('maxes:')));
    expect(tpl, isNot(contains('start:')));
    expect(looksLikeProgram(tpl), isTrue);
    final back = parseProgram(tpl)!;
    expect(back.start, dateOnly(DateTime.now()));
    expect(back.plan.length, p.plan.length);
    expect(back.plan.first.items.map((i) => i.exercise), p.plan.first.items.map((i) => i.exercise));
    expect(back.maxes, isEmpty);
  });

  test('muu teksti ei ole ohjelmapohja', () {
    expect(looksLikeProgram('---\ndate: 2026-01-01\n---\n# Treeni'), isFalse);
  });
}
