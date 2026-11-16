import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';
import 'package:treenipaivakirja/program_edit.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Käyttäjä 16.11.: ohjelman päivässä vaihtoehtoiset liikkeet, joista treenissä valitaan tämän päivän liike.
// Keksityt tiedot.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Program program() => Program(
    goal: 'voima',
    experience: 'keski',
    days: 1,
    minutes: 60,
    start: DateTime(2026, 11, 2),
    deloadEvery: 0,
    plan: [
      PlanDay('Koko keho A', [
        PlanItem('Penkkipunnerrus', 'VTY', 3, 5, 5, '1–2', 180, alts: ['Taukopenkki', 'Kapea penkki']),
        PlanItem('Takakyykky', 'KY', 3, 5, 5, '1–2', 180),
      ]),
    ],
  );

  test('tiedostossa "tai: A; B" edestakaisin', () {
    final md = programToMarkdown(program());
    expect(md, contains('| tai: Taukopenkki; Kapea penkki'));
    final p = parseProgram(md)!;
    expect(p.plan.first.items.first.alts, ['Taukopenkki', 'Kapea penkki']);
    expect(p.plan.first.items.last.alts, isEmpty);
    expect(p.plan.first.items.first.covers('Taukopenkki'), isTrue);
    expect(p.plan.first.items.first.covers('Takakyykky'), isFalse);
    // Pohja ja kopio säilyttävät vaihtoehdot.
    expect(parseProgram(programToTemplate(p, name: 'X'))!.plan.first.items.first.alts, hasLength(2));
  });

  test('vaihtoehdon nostaminen päävaihtoehdoksi: entinen pää jää vaihtoehdoksi', () {
    final it = program().plan.first.items.first;
    applySwap(it, 'Taukopenkki');
    expect(it.exercise, 'Taukopenkki');
    expect(it.alts, ['Penkkipunnerrus', 'Kapea penkki']);
  });

  testWidgets('treenissä valitaan tämän päivän liike; tehty vaihtoehto kuittaa ohjelman liikkeen', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    settings.program = program();
    addTearDown(() => settings.program = null);
    final day = settings.program!.plan.first;
    final w = Workout(date: DateTime(2026, 11, 7), title: day.name);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutScreen(workout: w, planDay: day),
      ),
    );
    await tester.pump();
    expect(find.textContaining('tai: Taukopenkki, Kapea penkki'), findsOneWidget);
    await tester.tap(find.text('Penkkipunnerrus').first);
    await tester.pumpAndSettle();
    expect(find.text('Minkä teet tänään?'), findsOneWidget);
    expect(find.text('ei vielä tehty'), findsNWidgets(3));
    await tester.tap(find.text('Taukopenkki').last);
    await tester.pumpAndSettle();
    expect(find.byType(SetLoggerScreen), findsOneWidget);
    expect(tester.widget<SetLoggerScreen>(find.byType(SetLoggerScreen)).target?.sets, 3, reason: 'sama tavoite');
    expect(w.exercises.single.name, 'Taukopenkki');
    w.exercises.single.sets.add(SetEntry(60, 5));
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Ohjelman liike on tehty vaihtoehdolla: ei enää jäljellä olevana.
    expect(find.textContaining('tai: Taukopenkki'), findsNothing);
    expect(find.text('Takakyykky'), findsWidgets);
  });

  test('viikon kuorma: eri liikemallin vaihtoehto jakaa sarjat tasan; sama liikemalli ei muuta (käyttäjä 16.11.)', () {
    Program one(List<String> alts) => Program(
      goal: 'voima',
      experience: 'keski',
      days: 1,
      minutes: 60,
      start: DateTime(2026, 11, 2),
      deloadEvery: 0,
      plan: [
        PlanDay('A', [PlanItem('Takakyykky', slotOf('Takakyykky'), 4, 5, 5, '1–2', 180, alts: alts)]),
      ],
    );
    final base = statsOf(one([])).weekly;
    expect(statsOf(one(['Etukyykky'])).weekly, base, reason: 'sama liikemalli');
    final mixed = statsOf(one(['Maastaveto'])).weekly;
    final dl = statsOf(
      Program(
        goal: 'voima',
        experience: 'keski',
        days: 1,
        minutes: 60,
        start: DateTime(2026, 11, 2),
        deloadEvery: 0,
        plan: [
          PlanDay('A', [PlanItem('Maastaveto', slotOf('Maastaveto'), 4, 5, 5, '1–2', 180)]),
        ],
      ),
    ).weekly;
    for (final m in {...base.keys, ...dl.keys}) {
      expect(mixed[m] ?? 0, closeTo(((base[m] ?? 0) + (dl[m] ?? 0)) / 2, 1e-9), reason: m);
    }
    // Kolme vaihtoehtoa: kolmasosat.
    expect(one(['Etukyykky', 'Maastaveto']).plan.first.items.first.choices, hasLength(3));
  });
}
