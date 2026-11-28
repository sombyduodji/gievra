import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/widgets.dart' show WordFit;
import 'package:treenipaivakirja/ui/workout.dart' show SavedScreen;

// Yötesti 28.11.: juuri lopetetun treenin yhteenvedon napautussuoja 0,9 s ("Lopeta treeni" -painikkeen hidas
// kaksoisnapautus ~0,6 s osui Ohitaan, Motorola), muistiinpanot salitreenin yhteenvedossa ja yksisanaisen nimen
// pienennys. Keksityt treenit.
void main() {
  late Directory dir;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-suoja');
    settings.folder = dir.path;
    store.workouts = [];
  });
  tearDown(() {
    settings.folder = null;
    store.workouts = [];
    dir.deleteSync(recursive: true);
  });

  Workout gym({String notes = ''}) => Workout(date: DateTime(2026, 11, 20), title: 'Koko keho A', notes: notes)
    ..minutes = 50
    ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 8)]));

  int? feeling(Workout w) => store.workouts.where((x) => x.date == w.date).firstOrNull?.feeling;

  Future<void> settle(WidgetTester tester) async {
    for (var k = 0; k < 10; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Yhteenveto: napautus 0,6 s kohdalla ei tallenna fiilistä, 1 s jälkeen tallentaa', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final w = gym();
    await tester.runAsync(() => store.save(w));
    await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w, fresh: true)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('face_4')), warnIfMissed: false);
    await settle(tester);
    expect(feeling(w), isNull);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('face_4')));
    await settle(tester);
    expect(feeling(w), 4);
  });

  for (final notes in ['', 'Polvi tuntui hyvältä.']) {
    testWidgets('Salitreenin yhteenveto: muistiinpanot ${notes.isEmpty ? 'puuttuvat' : 'näkyvät'}', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      final w = gym(notes: notes)..feeling = 4;
      await tester.runAsync(() => store.save(w));
      await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w, history: true)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('summaryNotes')), notes.isEmpty ? findsNothing : findsOneWidget);
      if (notes.isNotEmpty) expect(find.text(notes), findsOneWidget);
    });
  }

  testWidgets('WordFit: yksi sana pienenee, usea sana rivittyy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 90,
              child: Column(children: [WordFit('Penkkipunnerrus'), WordFit('jätä vähän varaa')]),
            ),
          ),
        ),
      ),
    );
    expect(find.descendant(of: find.byType(WordFit).first, matching: find.byType(FittedBox)), findsOneWidget);
    expect(find.descendant(of: find.byType(WordFit).last, matching: find.byType(FittedBox)), findsNothing);
  });
}
