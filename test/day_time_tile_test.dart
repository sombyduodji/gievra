import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/home.dart';

// Päivänäkymän aika-ruutu: sekunnit yhteen ja minuuteiksi vasta lopuksi (yötesti 21.11.: 54 s:n salitreeni näkyi
// treenikortissa "1 min" mutta aika-ruudussa "–", koska jokainen treeni katkaistiin erikseen alaspäin).
void main() {
  final today = dateOnly(DateTime.now());
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings
      ..started = true
      ..introDone = true
      ..trainMode = 'both';
  });
  tearDown(() => store.workouts = []);

  Future<void> openDay(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    showDay(tester.element(find.byType(HomeScreen)), today);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Alle minuutin treeni: aika 1 min, ei "–"', (tester) async {
    store.workouts = [
      Workout(date: today, title: 'Treeni', session: 1)
        ..seconds = 54
        ..minutes = 1
        ..feeling = 3
        ..exercises.add(ExerciseEntry('Penkkipunnerrus', [SetEntry(15, 10)])),
    ];
    await openDay(tester);
    expect(find.text('–'), findsNothing);
    expect(find.text('1 min'), findsWidgets);
  });

  testWidgets('Kaksi 50 s:n treeniä: aika 2 min (ennen 0)', (tester) async {
    store.workouts = [
      for (final s in [1, 2])
        Workout(date: today, title: 'Treeni', session: s)
          ..seconds = 50
          ..minutes = 1
          ..feeling = 3
          ..exercises.add(ExerciseEntry('Penkkipunnerrus', [SetEntry(15, 10)])),
    ];
    await openDay(tester);
    expect(find.text('–'), findsNothing);
    expect(find.text('2 min'), findsWidgets);
  });

  testWidgets('Pyöräilyn kortissa keskinopeus, ei vauhtia', (tester) async {
    store.workouts = [
      Workout(date: today, title: 'Pyöräily', activity: 'Pyöräily', session: 1)
        ..seconds = 3600
        ..minutes = 60
        ..distanceKm = 21.5
        ..feeling = 5,
      Workout(date: today, title: 'Kävely', activity: 'Kävely', session: 2)
        ..seconds = 3000
        ..minutes = 50
        ..distanceKm = 5.0
        ..feeling = 4,
    ];
    await openDay(tester);
    expect(find.text('21,5 km/h'), findsOneWidget);
    expect(find.text('2:47 /km'), findsNothing);
    expect(find.text('10:00 /km'), findsOneWidget, reason: 'kävelyssä vauhti kuten ennen');
  });
}
