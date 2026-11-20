import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/workout.dart' show SavedScreen;

// Tiivis yhteenveto treenin lopussa (käyttäjä 20.11.): fiilis tai Ohita alareunassa vie etusivulle; salin
// Raskas/Tahmea kysyy ensin liikkeet. Keksityt treenit.
void main() {
  late Directory dir;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-yhteenveto');
    settings.folder = dir.path;
    store.workouts = [];
  });
  tearDown(() {
    settings.folder = null;
    store.workouts = [];
    dir.deleteSync(recursive: true);
  });

  Future<Workout> open(WidgetTester tester, Workout w, {bool intensity = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => store.save(w));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute(
                  builder: (_) => SavedScreen(workout: w, fresh: true, askIntensity: intensity),
                ),
              ),
              child: const Text('koti'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('koti'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600)); // napautussuoja
    return w;
  }

  Workout stored(Workout w) => store.workouts.firstWhere((x) => x.date == w.date && x.session == w.session);

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var k = 0; k < 30 && !done(); k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Workout gym() => Workout(date: DateTime(2026, 11, 20), title: 'Koko keho A', session: 1)
    ..seconds = 3492
    ..exercises.addAll([
      ExerciseEntry('Takakyykky', [SetEntry(80, 8), SetEntry(80, 8)]),
      ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 8)]),
      ExerciseEntry('Kulmasoutu', [SetEntry(50, 10)]),
      ExerciseEntry('Hauiskääntö', [SetEntry(14, 12)]),
    ]);

  testWidgets('Sali: luvut, kolme liikettä ja +1, fiilis vie etusivulle', (tester) async {
    final w = await open(tester, gym());
    expect(find.textContaining('Giitu!'), findsOneWidget);
    expect(find.text('+1 liikettä'), findsOneWidget);
    expect(find.text('Ohita'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('face_4')));
    await settle(tester, () => find.text('koti').evaluate().isNotEmpty);
    expect(find.text('koti'), findsOneWidget);
    expect(stored(w).feeling, 4);
  });

  testWidgets('Sali: Raskas kysyy liikkeet ennen etusivua', (tester) async {
    final w = await open(tester, gym());
    await tester.tap(find.byKey(const ValueKey('face_1')));
    await tester.pumpAndSettle();
    expect(find.text('Mikä tuntui raskaalta?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('heavy_Takakyykky')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('heavyDone')));
    await settle(tester, () => find.text('koti').evaluate().isNotEmpty);
    expect(find.text('koti'), findsOneWidget);
    expect((stored(w).feeling, stored(w).tooHeavy.contains('Takakyykky')), (1, true));
  });

  testWidgets('Liikunta: Ohita vie etusivulle ilman fiilistä; rasitus valittavissa', (tester) async {
    final w = await open(
      tester,
      Workout(date: DateTime(2026, 11, 20), title: 'Kävely', activity: 'Kävely', session: 2)
        ..seconds = 2525
        ..distanceKm = 4.21,
      intensity: true,
    );
    expect(find.text('Rasitus'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('savedSkip')));
    await settle(tester, () => find.text('koti').evaluate().isNotEmpty);
    expect(find.text('koti'), findsOneWidget);
    expect(stored(w).feeling, isNull);
  });

  testWidgets('Pyöräily: keskinopeus km/h vauhdin sijaan', (tester) async {
    await open(
      tester,
      Workout(date: DateTime(2026, 11, 20), title: 'Pyöräily', activity: 'Pyöräily', session: 3)
        ..seconds = 1800
        ..distanceKm = 10.0,
      intensity: true,
    );
    expect(find.text('20 km/h'), findsOneWidget);
    expect(find.textContaining('min/km'), findsNothing);
  });
}
