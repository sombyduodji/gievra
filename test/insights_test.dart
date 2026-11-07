import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/insights.dart';
import 'package:treenipaivakirja/models.dart';

Workout squat(DateTime d, double kg, {int sets = 5}) => Workout(
  date: d,
  exercises: [
    ExerciseEntry('Takakyykky', [for (var i = 0; i < sets; i++) SetEntry(kg, 5)]),
  ],
);

void main() {
  final mon = DateTime(2026, 11, 2); // maanantai

  test('7 viikkoa nousujohteista kuormitusta -> ehdota kevennystä', () {
    final ws = [
      for (var w = 0; w < 7; w++) ...[
        squat(addDays(mon, -7 * w), 140 - w * 2.5),
        squat(addDays(mon, 3 - 7 * w), 140 - w * 2.5),
      ],
    ];
    final r = analyze(ws, now: DateTime(2026, 11, 6), deloadEvery: 6);
    expect(r.loadingWeeks, 7);
    expect(r.suggestDeload, isTrue);
    expect(r.improving.single.exercise, 'Takakyykky');
  });

  test('Kevyt viikko nollaa putken', () {
    final ws = [for (var w = 0; w < 8; w++) squat(addDays(mon, -7 * w), 120, sets: w == 3 ? 2 : 6)];
    final r = analyze(ws, now: DateTime(2026, 11, 6), deloadEvery: 6);
    expect(r.loadingWeeks, 3);
    expect(r.suggestDeload, isFalse);
  });

  test('e1RM', () {
    expect(e1rm(100, 1), 100);
    expect(e1rm(100, 5)!.round(), 117);
    expect(e1rm(100, 20), isNull);
  });

  final real = Platform.environment['FITNOTES'];
  test('Oikea historia', () {
    final r = readFitnotes(real!);
    final ins = analyze(r.workouts, now: DateTime(2026, 10, 30));
    // ignore: avoid_print
    print(
      'putki ${ins.loadingWeeks} vk, kevennys ${ins.suggestDeload} (auto ${ins.autoregulated}), PR30 ${ins.prs30d}\n'
      'nousee: ${ins.improving.map((p) => '${p.exercise} ${p.before.round()}->${p.now.round()}')}\n'
      'junnaa: ${ins.stalled.map((p) => '${p.exercise} ${p.before.round()}->${p.now.round()}')}',
    );
  }, skip: real == null ? 'FITNOTES ei asetettu' : false);
}
