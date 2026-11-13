import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/whats_new_dialog.dart';
import 'package:treenipaivakirja/whats_new.dart';

// "Uutta tässä versiossa": kerran päivityksen jälkeen, ei uudelle asennukselle, ei uudelleen OK:n jälkeen.
void main() {
  final someWorkout = Workout(
    date: DateTime(2026, 11, 1),
    title: 'X',
    exercises: [
      ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 8)]),
    ],
  );

  Future<void> run(WidgetTester tester, String version) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => maybeShowWhatsNew(context, version: version),
              child: const Text('käynnistys'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('käynnistys'));
    await tester.pumpAndSettle();
  }

  setUp(() => debugSetCatalog('fi', const {}));

  test('Versioiden vertailu ja näytettävät', () {
    expect(compareVersions('0.6.10', '0.6.9'), 1);
    expect(compareVersions('0.6', '0.6.0'), 0);
    expect(compareVersions('0.6.1', '0.6'), 1);
    expect(unseenFeatures('0.6.2', '0.6.2'), isEmpty, reason: 'kehitysversio ennen julkaisua');
    expect(unseenFeatures('0.6.3', '0.6.2').length, whatsNew.where((f) => f.version == '0.6.3').length);
    expect(unseenFeatures('0.6.3', '0.6.3'), isEmpty);
    expect(latestFeatures('0.6.3'), isNotEmpty);
  });

  testWidgets('Päivitys: näkyy kerran, OK kuittaa', (tester) async {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [someWorkout];
    await run(tester, '0.6.3');
    expect(find.text('Uutta versiossa 0.6.3'), findsOneWidget);
    expect(find.text('Levylaskuri'), findsOneWidget);
    expect(find.textContaining('korjat'), findsNothing, reason: 'ei korjauksia listalla');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Uutta versiossa 0.6.3'), findsNothing);
    await run(tester, '0.6.3');
    expect(find.text('Uutta versiossa 0.6.3'), findsNothing, reason: 'ei uudelleen');
    // Seuraava versio: vain sen uudet (askeleet), ei 0.6.3:n kohtia uudelleen.
    await run(tester, '0.6.4');
    expect(find.text('Uutta versiossa 0.6.4'), findsOneWidget);
    expect(find.text('Päivän askeleet'), findsOneWidget);
    expect(find.text('Levylaskuri'), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // 0.6.5: kalenterin askelrengas selitetään (muuten rengas ei aukea käyttäjälle).
    await run(tester, '0.6.5');
    expect(find.text('Uutta versiossa 0.6.5'), findsOneWidget);
    expect(find.text('Askeleet kalenterissa'), findsOneWidget);
    expect(find.textContaining('Vihreä rengas'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // Versio ilman uusia ominaisuuksia: ei ikkunaa.
    await run(tester, '0.6.6');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Uusi asennus ei näe ikkunaa', (tester) async {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    await run(tester, '0.6.3');
    expect(find.byType(AlertDialog), findsNothing);
    expect((await SharedPreferences.getInstance()).getString('whatsNewSeen'), '0.6.3');
  });

  testWidgets('Ikkuna englanniksi ja saameksi kapealla näytöllä', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final lang in ['en', 'se']) {
      SharedPreferences.setMockInitialValues({'whatsNewSeen': '0.6.2'});
      store.workouts = [someWorkout];
      debugSetCatalog(lang, parsePo(File('assets/l10n/$lang.po').readAsStringSync()));
      await run(tester, '0.6.3');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Levylaskuri'), findsNothing, reason: '$lang käännetty');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
    debugSetCatalog('fi', const {});
  });
}
