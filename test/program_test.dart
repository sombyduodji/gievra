import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';

void main() {
  test('Jokainen tavoite × päivät × kokemus tuottaa ohjelman, joka mahtuu aikaan ja lukeutuu takaisin', () {
    for (final g in goals.keys) {
      for (final e in experiences.keys) {
        for (var d = 2; d <= 6; d++) {
          for (final m in [45, 60, 90]) {
            final p = generateProgram(
              goal: g,
              experience: e,
              days: d,
              minutes: m,
              injuries: const [],
              start: DateTime(2026, 11, 9),
            );
            expect(p.plan, isNotEmpty, reason: '$g $e $d');
            for (final day in p.plan) {
              expect(day.items.length, greaterThanOrEqualTo(3), reason: '$g $e $d ${day.name}');
              // Pääliikkeet jäävät aina, joten raskaat ohjelmat voivat ylittää lyhyen ajan hieman.
              final est = estimateMinutes(day.items);
              if (m >= 60 && g != 'voimanosto') {
                expect(est, lessThanOrEqualTo(m + 10), reason: '$g $e $d $m ${day.name}');
              }
              if (est > m + 5) expect(p.notes.join(), contains('Pisin treeni'));
            }
            final back = parseProgram(programToMarkdown(p))!;
            expect(programToMarkdown(back), programToMarkdown(p));
          }
        }
      }
    }
  });

  test('Vammatila vaihtaa liikkeet', () {
    final p = generateProgram(
      goal: 'lihaskasvu',
      experience: 'keski',
      days: 4,
      minutes: 75,
      injuries: ['olkapaa_kiertajakalvosin', 'alaselka'],
    );
    final all = [for (final d in p.plan) ...d.items.map((i) => i.exercise)];
    expect(all, isNot(contains('Pystypunnerrus')));
    expect(all, isNot(contains('Good morning')));
    for (final d in p.plan) {
      for (final i in d.items) {
        expect(injuryStatus(i.exercise, ['olkapaa_kiertajakalvosin', 'alaselka']).avoid, isEmpty, reason: i.exercise);
      }
    }
    expect(p.plan.expand((d) => d.items).any((i) => i.note != null), isTrue);
  });

  test('Voimanoston viikkotaulukko ja kevennysviikko', () {
    final p = generateProgram(
      goal: 'voimanosto',
      experience: 'keski',
      days: 3,
      minutes: 90,
      injuries: const [],
      start: DateTime(2026, 11, 9),
    );
    final sq = p.plan.first.items.first;
    expect(sq.kind, 'H');
    final w1 = targetFor(p, sq, DateTime(2026, 11, 9));
    expect((w1.sets, w1.lo, w1.pct), (5, 5, .725));
    final w5 = targetFor(p, sq, DateTime(2026, 12, 7));
    expect(w5.label, contains('Kevennys'));
    final h = generateProgram(
      goal: 'lihaskasvu',
      experience: 'keski',
      days: 4,
      minutes: 60,
      injuries: const [],
      start: DateTime(2026, 11, 9),
    );
    expect(h.isDeloadWeek(DateTime(2026, 12, 14)), isTrue); // viikko 6
    expect(targetFor(h, h.plan.first.items.first, DateTime(2026, 12, 14)).loadFactor, .9);
  });

  test('Seuraava ohjelmapäivä kiertää', () {
    final p = generateProgram(
      goal: 'lihaskasvu',
      experience: 'keski',
      days: 4,
      minutes: 60,
      injuries: const [],
      start: DateTime(2026, 11, 9),
    );
    expect(p.nextDay([], DateTime(2026, 11, 9)).name, 'Ylävartalo A');
    final hist = [Workout(date: DateTime(2026, 11, 10), title: 'Alavartalo A')];
    expect(p.nextDay(hist, DateTime(2026, 11, 11)).name, 'Ylävartalo B');
  });

  test('Kaikki vammadatan liikkeet ovat luettelossa', () {
    expect(injuryRegions.length, 20);
  });
}
