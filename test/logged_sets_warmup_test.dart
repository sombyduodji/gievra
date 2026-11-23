import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program_edit.dart';

// Yötesti 23.11.: viikon kuorman toteutunut laski lämmittelysarjaksi merkityn sarjan (20 kg ennen 30 kg:n sarjaa,
// 60 %:n raja ylittyi), joten rinta näytti 2 vaikka työsarjoja oli 1.
void main() {
  test('viikon kuorma: lämmittelysarja ei ole toteutunutta kuormaa', () {
    final d = DateTime(2026, 11, 23);
    final w = Workout(
      date: d,
      exercises: [
        ExerciseEntry('Penkkipunnerrus', [SetEntry(20, 8, warmup: true), SetEntry(30, 8)]),
      ],
    );
    final done = loggedSets([w], d, d.add(const Duration(days: 1)));
    expect(done['rinta'], 1);
  });

  test('viikon kuorma: pelkkiä lämmittelysarjoja → ei kuormaa', () {
    final d = DateTime(2026, 11, 23);
    final w = Workout(
      date: d,
      exercises: [
        ExerciseEntry('Penkkipunnerrus', [SetEntry(20, 8, warmup: true)]),
      ],
    );
    expect(loggedSets([w], d, d.add(const Duration(days: 1)))['rinta'] ?? 0, 0);
  });
}
