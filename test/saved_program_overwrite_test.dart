import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/program_template.dart';

// Tallennetun ohjelman nimi, joka on jo toisella ohjelmalla: kysytään ennen korvaamista (käyttäjä 15.11.).
// Keksitty ohjelma.
void main() {
  late Directory dir;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-prog');
    settings.folder = dir.path;
  });
  tearDown(() {
    settings.folder = null;
    dir.deleteSync(recursive: true);
  });

  Program program() => Program(
    goal: 'voima',
    experience: 'keski',
    days: 1,
    minutes: 60,
    start: DateTime(2026, 11, 2),
    deloadEvery: 0,
    maxes: {},
    notes: [],
    plan: [
      PlanDay('Koko keho A', [PlanItem('Penkkipunnerrus', 'VT', 3, 5, 5, '1–2', 180)]),
    ],
  );

  testWidgets('sama nimi toisella ohjelmalla kysyy; uusi nimi ja oma tiedosto eivät kysy', (tester) async {
    await tester.runAsync(() async {
      await saveProgramAs(program(), 'Kesä');
      await saveProgramAs(program(), 'Talvi');
    });
    final results = <bool>[];
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      ),
    );
    Future<void> ask(String name, {String? keep}) async {
      confirmProgramOverwrite(ctx, name, keep: keep).then(results.add);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
    }

    // Uusi nimi: ei kysymystä.
    await ask('Syksy');
    expect(find.text('Korvataanko ohjelma?'), findsNothing);
    expect(results, [true]);

    // Oma tiedosto (nimi ei muutu levyllä): ei kysymystä.
    await ask('Kesä', keep: savedProgramPath('Kesä'));
    expect(results, [true, true]);

    // Vain kirjainkoko muuttuu (kesä): sama ohjelma, ei kysymystä (yötesti 16.11.: Androidin tallennustila ei
    // erota kirjainkokoa, ja korvaus + vanhan poisto hävitti ohjelman).
    await ask('kesä', keep: savedProgramPath('Kesä'));
    expect(find.text('Korvataanko ohjelma?'), findsNothing);
    expect(results, [true, true, true]);
    results.removeLast();

    // Toisen ohjelman nimi: kysytään; Peruuta ei korvaa.
    await ask('Talvi', keep: savedProgramPath('Kesä'));
    expect(find.text('Korvataanko ohjelma?'), findsOneWidget);
    expect(find.textContaining('Talvi'), findsOneWidget);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(results, [true, true, false]);

    // Korvaa hyväksyy.
    await ask('Talvi');
    await tester.tap(find.byKey(const ValueKey('overwriteProgram')));
    await tester.pumpAndSettle();
    expect(results, [true, true, false, true]);
  });
}
