import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/workout.dart' show SavedScreen;

// Tallennetun salitreenin fiiliksen vaihto (yötesti 21.11.): Raskas → Hyvä poistaa "Mikä painoi?" -vastaukset
// (raskaat liikkeet ja päivän syyt), kuten lukitun liikunnan fiilis; Raskas → Tahmea kysyy ne uudelleen.
void main() {
  late Directory dir;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-fiilis');
    settings.folder = dir.path;
    store.workouts = [];
  });
  tearDown(() {
    settings.folder = null;
    store.workouts = [];
    dir.deleteSync(recursive: true);
  });

  Workout heavy() => Workout(date: DateTime(2026, 11, 20), title: 'Treeni', session: 1)
    ..seconds = 1800
    ..feeling = 1
    ..tooHeavy.add('Penkkipunnerrus')
    ..moveFeeling['Penkkipunnerrus'] = 1
    ..dayReasons.add('väsynyt')
    ..exercises.add(ExerciseEntry('Penkkipunnerrus', [SetEntry(40, 8), SetEntry(40, 8)]));

  Future<void> open(WidgetTester tester, Workout w) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => store.save(w));
    await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600)); // napautussuoja
  }

  Workout stored(Workout w) => store.workouts.firstWhere((x) => x.date == w.date && x.session == w.session);

  Future<void> settle(WidgetTester tester) async {
    for (var k = 0; k < 10; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Raskas → Hyvä: raskaat liikkeet ja päivän syyt pois', (tester) async {
    final w = heavy();
    await open(tester, w);
    expect(find.textContaining('väsynyt'), findsOneWidget);
    await tester.tap(find.text('Muuta'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600)); // napautussuoja
    await tester.ensureVisible(find.byKey(const ValueKey('face_4')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('face_4')));
    await settle(tester);
    expect(stored(w).feeling, 4);
    expect(stored(w).tooHeavy, isEmpty);
    expect(stored(w).dayReasons, isEmpty);
    expect(find.textContaining('väsynyt'), findsNothing);
    expect(find.textContaining('Liian raskas'), findsNothing);
    final text = dir
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('2026-11-20.md'))
        .readAsStringSync();
    expect(text, contains('feeling: 4'));
    expect(text, isNot(contains('day_feeling')));
    expect(text, isNot(contains('liian raskas')));
  });

  testWidgets('Ohita ei muuta mitään', (tester) async {
    final w = heavy();
    await open(tester, w);
    await tester.tap(find.text('Muuta'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600)); // napautussuoja
    await tester.tap(find.text('Ohita').last);
    await settle(tester);
    expect(stored(w).feeling, 1);
    expect(stored(w).tooHeavy, {'Penkkipunnerrus'});
    expect(stored(w).dayReasons, ['väsynyt']);
  });
}
