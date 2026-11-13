import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/widgets.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Keksitty treeni (ei oikeita tietoja).
Workout _done() => Workout(
  date: DateTime(2026, 11, 7),
  title: 'Koko keho A',
  exercises: [
    ExerciseEntry('Takakyykky', [SetEntry(60, 8), SetEntry(80, 6)]),
  ],
)..minutes = 52;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Valmis treeni avautuu lukutilaan; napautus kysyy ennen muokkausta', (tester) async {
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: _done())));
    await tester.pump();
    expect(find.byType(LockButton), findsOneWidget);
    expect(find.byKey(const ValueKey('addExercise')), findsNothing);
    expect(find.text('Treeni valmis!'), findsNothing);

    // Napautus liikkeeseen: kysymys, Peruuta pitää lukutilan.
    await tester.tap(find.text('Takakyykky'));
    await tester.pumpAndSettle();
    expect(find.text('Muokataanko tallennettua treeniä?'), findsOneWidget);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(find.byType(LockButton), findsOneWidget);

    // Muokkaa: lukutila pois, liikkeen lisäys ja Treeni valmis näkyvät.
    await tester.tap(find.text('Takakyykky'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Muokkaa'));
    await tester.pumpAndSettle();
    expect(find.byType(LockButton), findsNothing);
    expect(find.byKey(const ValueKey('addExercise')), findsOneWidget);
    expect(find.text('Treeni valmis!'), findsOneWidget);
  });

  testWidgets('Keskeneräinen treeni ei ole lukittu', (tester) async {
    final w = _done()..minutes = null;
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: w)));
    await tester.pump();
    expect(find.byType(LockButton), findsNothing);
    expect(find.byKey(const ValueKey('addExercise')), findsOneWidget);
  });

  testWidgets('Kesken oleva treeni: Treeni valmis alareunassa, Lisää liike listan perässä, fiilis kysytään lopussa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('gievra-valmis');
    settings.folder = dir.path;
    addTearDown(() {
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    final w = _done()..minutes = null;
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: w)));
    await tester.pump();
    expect(find.text('Miltä tuntui?'), findsNothing, reason: 'kysytään vasta lopussa');
    final add = tester.getRect(find.byKey(const ValueKey('addExercise')));
    final finish = tester.getRect(find.text('Treeni valmis!'));
    expect(add.bottom, lessThan(finish.top));
    expect(finish.bottom, greaterThan(tester.view.physicalSize.height / tester.view.devicePixelRatio - 80));
    await tester.tap(find.text('Treeni valmis!'));
    // Tallennus kirjoittaa tiedoston: oikeaa aikaa ennen ponnahdusikkunaa.
    for (var k = 0; k < 20 && find.text('Miltä tuntui?').evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('Miltä tuntui?'), findsOneWidget);
    await tester.tap(find.text('Hyvä'));
    for (var k = 0; k < 20 && find.byType(SavedScreen).evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(w.feeling, 4);
    expect(find.byType(SavedScreen), findsOneWidget);
  });

  testWidgets('Liikkeen tila: valmis tiiviinä ✓, kesken renkaalla ja jäljellä olevilla sarjoilla', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final day = PlanDay('Koko keho A', [
      PlanItem('Takakyykky', 'kyykky', 2, 6, 8, '1–3', 120),
      PlanItem('Penkkipunnerrus', 'työntö', 3, 6, 8, '1–3', 120),
    ]);
    final w = Workout(
      date: DateTime(2026, 11, 7),
      title: 'Koko keho A',
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(60, 8), SetEntry(62.5, 8)]),
        ExerciseEntry('Penkkipunnerrus', [SetEntry(40, 8)]),
        ExerciseEntry('Lankku', [SetEntry(0, 60)]),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutScreen(workout: w, planDay: day),
      ),
    );
    await tester.pump();
    // Valmis: tiivis rivi, sarjat yhdellä rivillä.
    expect(find.byKey(const ValueKey('done-Takakyykky')), findsOneWidget);
    expect(find.textContaining('2 sarjaa · 60 kg × 8, 62,5 kg × 8'), findsOneWidget);
    // Kesken: 1/3, kesken-merkki ja jäljellä olevat sarjat.
    expect(find.byKey(const ValueKey('progress-Penkkipunnerrus')), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('kesken'), findsOneWidget);
    expect(find.text('+ 2 sarjaa'), findsOneWidget);
    // Oma lisäys ilman ohjelman tavoitetta: ei kesken-merkkiä.
    expect(find.text('1 sarja'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pitkä painallus: poista tästä treenistä ja lisää supersarjaan (Peruuta ei muuta mitään)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    settings.program = generateProgram(goal: 'kunto', experience: 'keski', days: 3, minutes: 60, injuries: const []);
    addTearDown(() => settings.program = null);
    final day = settings.program!.plan.first;
    final a = day.items[0].exercise, b = day.items[1].exercise, c = day.items[2].exercise;
    final w = Workout(date: DateTime(2026, 11, 7), title: day.name);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutScreen(workout: w, planDay: day),
      ),
    );
    await tester.pump();
    // Peruuta: ei muutoksia.
    await tester.longPress(find.text(a).first);
    await tester.pumpAndSettle();
    expect(find.text('Poista tästä treenistä'), findsOneWidget);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(find.text(a), findsWidgets);
    // Poisto: ohjelman liike katoaa tämän päivän listalta ja tallentuu tiedostoon.
    await tester.longPress(find.text(a).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poista tästä treenistä'));
    await tester.pumpAndSettle();
    expect(find.text(a), findsNothing);
    expect(w.skipMoves, {a});
    expect(parseWorkout(workoutToMarkdown(w)).skipMoves, {a});
    // Supersarja: b + c, OK.
    await tester.longPress(find.text(b).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lisää supersarjaan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(w.supersets, [
      [b, c],
    ]);
    expect(find.text('Supersarja A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
