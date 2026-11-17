import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/share_card.dart';

// Käyttäjä 16.11.: jako kuvana (WhatsApp ym.). Keksityt tiedot.
void main() {
  Workout workout() =>
      Workout(
          date: DateTime(2026, 11, 16),
          title: 'Koko keho A',
          exercises: [
            ExerciseEntry('Takakyykky', [SetEntry(60, 5, warmup: true), SetEntry(100, 5), SetEntry(100, 5)]),
            ExerciseEntry('Kapea taukopenkki', [SetEntry(70, 6, pr: true)]),
            ExerciseEntry('Lankku', [SetEntry(0, 60)]),
          ],
        )
        ..minutes = 52
        ..feeling = 4
        ..notes = 'yksityinen muistiinpano';

  Program program() => Program(
    goal: 'voima',
    experience: 'keski',
    days: 2,
    minutes: 60,
    start: DateTime(2026, 11, 2),
    deloadEvery: 0,
    name: 'Kesän ohjelma',
    plan: [
      PlanDay('Koko keho A', [
        PlanItem('Takakyykky', 'KY', 3, 5, 5, '1–2', 180),
        PlanItem('Penkkipunnerrus', 'VTY', 3, 6, 10, '1–2', 180, alts: ['Taukopenkki', 'Kapea taukopenkki']),
      ]),
      PlanDay('Koko keho B', [PlanItem('Maastaveto', 'LS', 3, 5, 5, '1–2', 180)]),
    ],
  );

  for (final lang in ['fi', 'en', 'se']) {
    testWidgets('kortit kielellä $lang ilman ylivuotoa; kuva 1080 px leveä', (tester) async {
      if (lang != 'fi') {
        final en = parsePo(File('assets/l10n/en.po').readAsStringSync());
        debugSetCatalog(
          lang,
          lang == 'en' ? en : parsePo(File('assets/l10n/$lang.po').readAsStringSync()),
          english: en,
        );
        addTearDown(() => debugSetCatalog('fi', const {}));
      }
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      for (final card in [WorkoutShareCard(workout()), ProgramShareCard(program())]) {
        await tester.pumpWidget(
          MaterialApp(
            home: ShareCardScreen(card: card, fileName: 'x.png'),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('yksityinen'), findsNothing, reason: 'muistiinpanot eivät kuvaan');
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.ancestor(of: find.byWidget(card), matching: find.byType(RepaintBoundary)).first,
        );
        final img = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
        expect(img!.width, 1080);
        img.dispose();
      }
      if (lang == 'fi') {
        await tester.pumpWidget(
          MaterialApp(
            home: ShareCardScreen(card: WorkoutShareCard(workout()), fileName: 'x.png'),
          ),
        );
        expect(find.text('🏆'), findsOneWidget);
        expect(find.text('Kapea taukopenkki'), findsOneWidget);
        await tester.pumpWidget(
          MaterialApp(
            home: ShareCardScreen(card: ProgramShareCard(program()), fileName: 'x.png'),
          ),
        );
        expect(find.text('Kesän ohjelma'), findsOneWidget);
        expect(find.text('tai: Taukopenkki, Kapea taukopenkki'), findsOneWidget);
      }
    });
  }

  testWidgets('yksi sarja yksikössä ja kesto sekunteina kuten treenin näkymässä (yötesti 17.11.)', (tester) async {
    final w = Workout(
      date: DateTime(2026, 11, 16),
      title: 'Koko keho A',
      exercises: [
        ExerciseEntry('Penkkipunnerrus', [SetEntry(17.5, 10)]),
      ],
    )
      ..minutes = 1
      ..seconds = 33;
    await tester.pumpWidget(MaterialApp(home: SingleChildScrollView(child: WorkoutShareCard(w))));
    expect(find.text('sarja'), findsOneWidget);
    expect(find.text('sarjaa'), findsNothing);
    expect(find.text('0:33'), findsOneWidget);
  });

  test('jakokansiosta poistetaan yli tunnin vanhat tiedostot, tuoreet jäävät (yötesti 17.11.)', () {
    final dir = Directory.systemTemp.createTempSync('jako');
    addTearDown(() => dir.deleteSync(recursive: true));
    final now = DateTime(2026, 11, 17, 1);
    final old = File('${dir.path}/vanha.png')..writeAsStringSync('x');
    old.setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    final fresh = File('${dir.path}/uusi.png')..writeAsStringSync('x');
    fresh.setLastModifiedSync(now.subtract(const Duration(minutes: 5)));
    cleanShareDir(dir, now: now);
    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });
}
