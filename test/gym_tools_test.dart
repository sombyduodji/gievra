import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/progression.dart';
import 'package:treenipaivakirja/superset.dart';
import 'package:treenipaivakirja/ui/percent_sheet.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Levylaskurin, prosenttien, erikoissarjojen ja supersarjojen tiedostomuoto ja logiikka. Keksityt treenit.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    settings.program = null;
  });

  test('Pudotus- ja AMRAP-sarja tallentuvat ja luetaan takaisin', () {
    final w = Workout(
      date: DateTime(2026, 11, 12),
      title: 'Ylävartalo',
      exercises: [
        ExerciseEntry('Penkkipunnerrus', [
          SetEntry(60, 8, rir: 0),
          SetEntry(45, 6, kind: dropSet),
          SetEntry(80, 11, rir: 0, kind: amrapSet),
        ]),
      ],
    );
    final md = workoutToMarkdown(w);
    expect(md, contains('2. 45 kg × 6 (pudotus)'));
    expect(md, contains('3. 80 kg × 11 RIR 0 (amrap)'));
    final back = parseWorkout(md);
    expect(back.exercises.single.sets.map((s) => s.kind), [null, dropSet, amrapSet]);
    expect(workoutToMarkdown(back), md);
  });

  test('Supersarjat tallentuvat treenin tietoihin', () {
    final w =
        Workout(
            date: DateTime(2026, 11, 12),
            title: 'Veto',
            exercises: [
              ExerciseEntry('Leuanveto', [SetEntry(0, 8)]),
            ],
          )
          ..supersets = [
            ['Leuanveto', 'Pystypunnerrus'],
          ];
    final md = workoutToMarkdown(w);
    expect(md, contains('superset: Leuanveto + Pystypunnerrus'));
    expect(parseWorkout(md).supersets, [
      ['Leuanveto', 'Pystypunnerrus'],
    ]);
    // Yhden liikkeen "ryhmä" ohitetaan.
    expect(parseWorkout(md.replaceFirst('+ Pystypunnerrus', '+ Leuanveto')).supersets, isEmpty);
  });

  test('Supersarjan järjestys: kesken kierroksen seuraava, lopussa palautus', () {
    final w =
        Workout(
            date: DateTime(2026, 11, 12),
            title: 'X',
            exercises: [
              ExerciseEntry('A', [SetEntry(10, 8)]),
            ],
          )
          ..supersets = [
            ['A', 'B', 'C'],
          ];
    expect(supersetNext(w, 'A'), ('B', false));
    w.exercises.add(ExerciseEntry('B', [SetEntry(10, 8)]));
    expect(supersetNext(w, 'B'), ('C', false));
    w.exercises.add(ExerciseEntry('C', [SetEntry(10, 8)]));
    expect(supersetNext(w, 'C'), ('A', true), reason: 'kierros valmis: tauko, sitten A');
    expect(supersetRound(w, w.supersets.first), 2);
    // Ohjelman sarjamäärä täynnä: ryhmä valmis.
    expect(supersetNext(w, 'C', planned: (_) => 1), (null, true));
    expect(supersetLabel(w, 'C'), 'A3');
  });

  test('Ohjelman prosentti ja supersarja ohjelma.md:ssä', () {
    final p = Program(
      goal: 'voima',
      experience: 'keski',
      days: 2,
      minutes: 60,
      start: DateTime(2026, 11, 2),
      deloadEvery: 0,
      maxes: {},
      notes: [],
      plan: [
        PlanDay('Koko keho A', [
          PlanItem('Penkkipunnerrus', 'VT', 3, 5, 5, '1–2', 180, pct: .75),
          PlanItem('Leuanveto', 'VV', 3, 6, 10, '1–3', 90, group: 'A'),
          PlanItem('Pystypunnerrus', 'PT', 3, 8, 10, '1–3', 90, group: 'A'),
        ]),
      ],
    );
    final md = programToMarkdown(p);
    expect(md, contains('Penkkipunnerrus | 3 × 5 | @ 75 % |'));
    expect(md, contains('| supersarja A'));
    final back = parseProgram(md)!;
    expect(back.plan.first.items.first.pct, .75);
    expect(back.plan.first.items.map((i) => i.group), [null, 'A', 'A']);
    final tg = targetFor(back, back.plan.first.items.first, DateTime(2026, 11, 3));
    expect(tg.pct, .75);
    // Paino lasketaan arvioidusta maksimista.
    store.workouts = [
      Workout(
        date: DateTime(2026, 11, 1),
        title: 'X',
        exercises: [
          ExerciseEntry('Penkkipunnerrus', [SetEntry(90, 4, rir: 0)]),
        ],
      ),
    ];
    final s = suggestForTarget('Penkkipunnerrus', DateTime(2026, 11, 3), tg)!;
    expect(s.kg, 77.5); // 90 × (1 + 4/30) = 102 → 75 % = 76,5 → 77,5 (2,5 kg)
  });

  test('Prosenttilaskurin toistot ja maksimi', () {
    expect(repsAt(.75), 10);
    expect(repsAt(.9), 3);
    expect(repsAt(.5), isNull);
    store.workouts = [
      Workout(
        date: DateTime(2026, 11, 1),
        title: 'X',
        exercises: [
          ExerciseEntry('Takakyykky', [SetEntry(100, 5, rir: 0)]),
        ],
      ),
    ];
    expect(estimatedMax('Takakyykky', DateTime(2026, 11, 3)), closeTo(116.7, .1));
  });

  testWidgets('Aikasarjan ajastin laskee ja tallentaa ajan', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final e = ExerciseEntry('Lankku');
    await tester.pumpWidget(
      MaterialApp(
        home: SetLoggerScreen(date: DateTime(2026, 11, 12), entry: e, onChanged: () async {}),
      ),
    );
    await tester.pump();
    final start = find.textContaining('Aloita ajastin');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Lopeta nyt (2 s)'), findsOneWidget);
    await tester.tap(find.textContaining('Lopeta nyt'));
    await tester.pump();
    expect(find.textContaining('Aloita ajastin (0:02)'), findsOneWidget);
  });

  testWidgets('Supersarja treenissä: yksi kortti, seuraava korostettu', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final w =
        Workout(
            date: DateTime(2026, 11, 12),
            title: 'Veto',
            exercises: [
              ExerciseEntry('Leuanveto', [SetEntry(0, 8)]),
            ],
          )
          ..supersets = [
            ['Leuanveto', 'Pystypunnerrus'],
          ];
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: w)));
    await tester.pump();
    expect(find.text('Supersarja A'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
    expect(find.text('seuraava ›'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
