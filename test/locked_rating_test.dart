import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/activity.dart';

// Keksityt tiedot (ei oikeita).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Health Connectista lisätty kävely: ponnahdusikkunan fiilis tallentuu', (tester) async {
    final dir = Directory.systemTemp.createTempSync('gievra-hcf');
    settings.folder = dir.path;
    addTearDown(() {
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final w = Workout(date: DateTime(now.year, now.month, now.day), title: 'Kävely', activity: 'Kävely', session: 1)
      ..hcId = 'testi-1'
      ..healthSource = 'UREVO'
      ..started = now.subtract(const Duration(hours: 3))
      ..seconds = 9126
      ..distanceKm = 6.67
      ..steps = 11765;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () =>
                  Navigator.of(c).push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: w, manual: true))),
              child: const Text('koti'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('koti'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Treeni valmis!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Treeni valmis!'));
    for (var k = 0; k < 20 && find.byKey(const ValueKey('face_4')).evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('face_4')).last);
    for (var k = 0; k < 20 && find.text('koti').evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(store.workouts.firstWhere((x) => x.hcId == 'testi-1').feeling, 4);
    // Tallennuksen jälkeen suoraan takaisin, ei "Tallennetaanko muutokset?" -kysymystä.
    expect(find.text('Tallennetaanko muutokset?'), findsNothing);
    expect(find.text('koti'), findsOneWidget);
  });

  testWidgets(
    'Lukittu tallennettu liikunta: rasitus, fiilis ja muistiinpanot tallentuvat ilman muokkauslupaa (käyttäjä 20.11.)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('gievra-lock');
      settings.folder = dir.path;
      addTearDown(() {
        settings.folder = null;
        store.workouts = [];
        dir.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final saved =
          Workout(date: DateTime(now.year, now.month, now.day), title: 'Kävely', activity: 'Kävely', session: 1)
            ..hcId = 'testi-2'
            ..healthSource = 'UREVO'
            ..seconds = 9126
            ..distanceKm = 6.67
            ..intensity = 'reipas'; // vanha valinta säilyy (taaksepäin yhteensopiva)
      await tester.runAsync(() => store.save(saved));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () =>
                    Navigator.of(c)
                        .push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: store.workouts.first.copy()))),
                child: const Text('koti'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('koti'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hyvä'));
      await tester.tap(find.text('Hyvä'));
      await tester.pumpAndSettle();
      expect(find.text('Kevyt'), findsNothing, reason: 'rasitusta ei valita (käyttäjä 20.11.)');
      for (var k = 0; k < 10; k++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect((store.workouts.single.feeling, store.workouts.single.intensity), (4, 'reipas'));
      await tester.enterText(find.byType(TextField).last, 'Kävelymatto');
      await tester.pumpAndSettle();
      await tester.pageBack();
      for (var k = 0; k < 10; k++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final s = store.workouts.firstWhere((x) => x.hcId == 'testi-2');
      expect((s.feeling, s.intensity, s.notes), (4, 'reipas', 'Kävelymatto'));
    },
  );
}
