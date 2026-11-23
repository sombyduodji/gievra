import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/activity.dart';

// Lukitun ajanottoliikunnan muistiinpanot tallentuvat takaisin palattaessa (yötesti 21.11., Nothing: koripallon
// muistiinpanot katosivat). Keksityt tiedot.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final hc in [false, true]) {
    testWidgets('Muistiinpanot tallentuvat (${hc ? 'Health Connect' : 'ajanotto'})', (tester) async {
      final dir = Directory.systemTemp.createTempSync('gievra-notes');
      settings.folder = dir.path;
      addTearDown(() {
        settings.folder = null;
        store.workouts = [];
        dir.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      final day = dateOnly(DateTime.now()).subtract(const Duration(days: 1));
      final saved = Workout(date: day, title: 'Koripallo', activity: 'Koripallo', session: 2)
        ..started = day.add(const Duration(hours: 23, minutes: 47))
        ..seconds = 69
        ..minutes = 1
        ..feeling = 1;
      if (hc) saved.hcId = 'testi-n';
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
      await tester.enterText(find.byKey(const ValueKey('lockedNotes')), 'abc');
      await tester.pumpAndSettle();
      // Luonnoksen ajastin (3 s) ehtii käydä ennen takaisin-napautusta, kuten puhelimella.
      await tester.pump(const Duration(seconds: 4));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      await tester.pageBack();
      for (var k = 0; k < 10; k++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Tallennetaanko muutokset?'), findsNothing);
      expect(find.text('koti'), findsOneWidget);
      expect(store.workouts.single.notes, 'abc');
      final text = dir
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.md') && f.path.contains('${day.day}'))
          .readAsStringSync();
      expect(text, contains('abc'));
    });
  }
}
