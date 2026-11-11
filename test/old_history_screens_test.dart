import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/running_screen.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Treenihistoria aiempien versioiden tiedostoista: kansio luetaan kuten sovelluksessa, ja jokainen treeni avataan
// historian näkymissä (etusivu, tilastot, juoksun kehitys, salitreeni, liikunta, tallennettu treeni).
// Tiedostot ovat kunkin version omalla koodilla kirjoitettuja (keksityt arvot):
// test/fixtures/old_imports/<versio> ja varmuuskopiot test/fixtures/old_backups/<versio>.zip.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    settings.folder = null;
    store.workouts = [];
  });

  Future<void> screens(WidgetTester tester, String v) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    // Testifontti (Ahem) on leveämpi kuin oikea: rivien ylitykset eivät liity tiedostoihin.
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    Future<void> show(String name, Widget w) async {
      await tester.pumpWidget(MaterialApp(home: w));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // reitin luku
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: '$v: $name');
    }

    await show('etusivu', const HomeScreen());
    for (final k in ['all', 'gym', 'cardio']) {
      await show('tilastot $k', StatsScreen(kind: k));
    }
    await show('juoksun kehitys', const RunningScreen());
    for (final w in store.workouts) {
      final name = '${isoDate(w.date)}-${w.session} ${w.title}';
      if (w.activity != null) {
        await show(name, ActivityScreen(workout: w.copy()));
      } else {
        await show(name, WorkoutScreen(workout: w.copy()));
        await show('$name (tallennettu)', SavedScreen(workout: w.copy()));
      }
    }
  }

  for (final v in ['v0.1.0', 'v0.1.10', 'v0.2.9', 'v0.3.2', 'v0.5.9.1']) {
    testWidgets('$v: kansio luetaan ja jokainen treeni aukeaa historiassa', (tester) async {
      final src = Directory('test/fixtures/old_imports/$v');
      final dir = Directory.systemTemp.createTempSync('gievra-hist');
      addTearDown(() => dir.deleteSync(recursive: true));
      final mds = <String, String>{};
      for (final f in src.listSync(recursive: true).whereType<File>()) {
        final rel = f.path.substring(src.path.length + 1);
        File('${dir.path}/$rel')
          ..createSync(recursive: true)
          ..writeAsBytesSync(f.readAsBytesSync());
        if (rel.endsWith('.md')) mds[rel] = f.readAsStringSync();
      }
      settings.folder = dir.path;
      await tester.runAsync(store.reload);
      expect(store.error, isNull);
      expect(store.workouts.length, mds.length, reason: 'jokainen tiedosto luettiin');
      // Tallennus kirjoittaa saman tiedoston (ei muutoksia vanhaan historiaan avaamalla ja tallentamalla).
      for (final w in store.workouts) {
        expect(workoutToMarkdown(w), mds[workoutPath(w.date, w.session)], reason: '$v ${w.date}');
      }
      await screens(tester, v);
    });
  }

  for (final v in ['v0.1.2', 'v0.2.6', 'v0.4.2']) {
    testWidgets('$v-varmuuskopio uuteen puhelimeen: jokainen treeni aukeaa historiassa', (tester) async {
      final dir = Directory.systemTemp.createTempSync('gievra-hist');
      addTearDown(() => dir.deleteSync(recursive: true));
      settings.folder = dir.path;
      store.workouts = [];
      final r = readZip(File('test/fixtures/old_backups/$v.zip').readAsBytesSync());
      final n = await tester.runAsync(() async {
        final n = await applyImport(r);
        await store.reload();
        return n;
      });
      expect(n, r.workouts.length);
      expect(store.workouts.length, r.workouts.length);
      await screens(tester, v);
    });
  }
}
