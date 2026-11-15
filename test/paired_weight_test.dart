import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/csv_export.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/plates.dart';
import 'package:treenipaivakirja/progression.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/ui/dumbbell_review.dart';

// Kahden käsipainon liikkeet yhteispainona (käyttäjä 15.11.). Vanhat merkitsemättömät tarkistetaan kerran
// liikkeittäin; kahden kuulan liikkeet kuulaa kohden (ennen 9.11. yhteispainona tiedostossa). Keksityt tiedot,
// samat luvut kuin käyttäjän tilanteessa (penkki yhteensä, sitten käsipainoa kohden; soutu aina yhteensä).
void main() {
  String md(String d, String ex, String sets, {bool marked = false}) =>
      '---\ndate: $d\ntitle: Treeni\n${marked ? 'dumbbells: total\n' : ''}---\n\n## $ex\n$sets\n';

  test('merkitsemätön käsipainotreeni: luvut ennallaan, tarkistettava; tallennus ei merkitse', () {
    final w = parseWorkout(md('2026-11-12', 'Käsipainopystypunnerrus', '1. 10 kg × 8'));
    expect(w.exercises.single.sets.single.kg, 10);
    expect(w.dumbbellReview, isTrue);
    expect(workoutToMarkdown(w), isNot(contains('dumbbells:')));
  });

  test('uusi treeni merkitään yhteispainoksi; merkitty luetaan tarkistettuna', () {
    final w = Workout(date: DateTime(2026, 11, 16), title: 'Treeni')
      ..exercises.add(ExerciseEntry('Käsipainopystypunnerrus', [SetEntry(44, 8)]));
    final text = workoutToMarkdown(w);
    expect(text, contains('dumbbells: total'));
    final back = parseWorkout(text);
    expect(back.dumbbellReview, isFalse);
    expect(back.exercises.single.sets.single.kg, 44);
    // Ilman käsipainoliikettä ei merkintää.
    final bar = Workout(date: DateTime(2026, 11, 16), title: 'T')
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)]));
    expect(workoutToMarkdown(bar), isNot(contains('dumbbells:')));
  });

  test('kahden kuulan liike: ennen 9.11. tiedostossa yhteispaino, sovelluksessa kuulaa kohden', () {
    final old = parseWorkout(md('2026-11-08', 'Tuplakahvakuulapystypunnerrus', '1. 32 kg × 8'));
    expect(old.exercises.single.sets.single.kg, 16);
    expect(workoutToMarkdown(old), contains('1. 32 kg × 8'));
    final now = parseWorkout(md('2026-11-12', 'Tuplakahvakuulapystypunnerrus', '1. 16 kg × 8'));
    expect(now.exercises.single.sets.single.kg, 16);
  });

  test(
    'näyttö (vaihtoehto B): sarjat tiiviisti kummankin käden painolla, yksikkö kerran; yksittäinen sarja yhteispainona',
    () {
      final sets = [SetEntry(24, 12), SetEntry(44, 10, pr: true)];
      expect(fmtSetsCompact('Rintatuettu kulmasoutu käsipainoilla', sets), '12 × 12 · 22 × 10 🏆');
      expect(kgUnit('Rintatuettu kulmasoutu käsipainoilla'), 'kg kummassakin kädessä');
      expect(kgUnit('Rintatuettu kulmasoutu käsipainoilla', short: true), 'kg/käsi');
      expect(fmtSetHand('Käsipainopystypunnerrus', SetEntry(24, 10)), '12 kg/käsi × 10');
      expect(fmtSet('Käsipainopystypunnerrus', SetEntry(24, 10)), '24 kg × 10', reason: 'sama luku kuin syötössä');
      expect(fmtSetsCompact('Farmer walk', [SetEntry(48, 2)]), '24 × 2 edestakaisin');
      expect(fmtSetsCompact('Farmer walk hex barilla', [SetEntry(100, 2)]), '100 × 2 edestakaisin');
      expect(kgUnit('Farmer walk hex barilla'), 'kg');
      expect(fmtSetsCompact('Takakyykky', [SetEntry(100, 5), SetEntry(80, 8, kind: dropSet)]), '100 × 5 · ↘ 80 × 8');
      expect(hasWeight([SetEntry(0, 10)]), isFalse);
      // Hex bar: ei levylaskuria (tangon paino ei ole suoran tangon), ei kahden painon liike.
      expect(isBarbell('Farmer walk hex barilla'), isFalse);
      expect(totalDumbbells('Farmer walk hex barilla'), isFalse);
      expect(measureOf('Farmer walk hex barilla'), Measure.trips);
    },
  );

  test('askel: kahden käsipainon yhteispainossa molempiin käsiin', () {
    settings.weightStep = 2.5;
    expect(stepFor('Käsipainopystypunnerrus'), 5);
    expect(stepFor('Käsipainosoutu'), 2.5);
    expect(stepFor('Takakyykky'), 2.5);
  });

  group('tarkistus', () {
    late List<Workout> ws;
    setUp(() {
      // Samana päivänä samassa treenissä kuten oikeasti (yksi tiedosto päivää kohden).
      ws = [
        parseWorkout(
          '${md('2026-11-15', 'Käsipainopystypunnerrus', '1. 14 kg × 10\n2. 18 kg × 10')}'
          '\n## Rintatuettu kulmasoutu käsipainoilla\n1. 24 kg × 12\n2. 48 kg × 10\n',
        ),
        parseWorkout(md('2026-11-12', 'Käsipainopystypunnerrus', '1. 10 kg × 8\n2. 10 kg × 8')),
        parseWorkout(
          '${md('2026-11-08', 'Käsipainopystypunnerrus', '1. 24 kg × 10\n2. 44 kg × 7')}'
          '\n## Rintatuettu kulmasoutu käsipainoilla\n1. 24 kg × 12\n2. 44 kg × 12\n',
        ),
      ];
    });

    test('arvaus: puolet tavallisesta = käsipainoa kohden; soutu yhteensä', () {
      final rows = dumbbellRows(ws);
      String key(DumbbellRow r) => '${r.e.name} ${r.w.date.day}';
      final guess = {
        for (final l in rows.values)
          for (final r in l) key(r): guessPerDumbbell(r, ws),
      };
      expect(guess, {
        'Käsipainopystypunnerrus 15': true,
        'Käsipainopystypunnerrus 12': true,
        'Käsipainopystypunnerrus 8': false,
        'Rintatuettu kulmasoutu käsipainoilla 15': false,
        'Rintatuettu kulmasoutu käsipainoilla 8': false,
      });
    });

    test('tallennus: käsipainoa kohden kerrotaan kahdella, kaikki merkitään, tiedostot kirjoitetaan', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = Directory.systemTemp.createTempSync('gievra-db');
      settings.folder = dir.path;
      store.workouts = ws;
      final rows = dumbbellRows(ws);
      final per = {
        for (final l in rows.values)
          for (final r in l)
            if (guessPerDumbbell(r, ws)) r,
      };
      expect(await applyDumbbellReview(rows, per), 3);
      expect(store.workouts.every((w) => !w.dumbbellReview), isTrue);
      List<double> kgs(int day, String ex) => store.workouts
          .firstWhere((w) => w.date.day == day)
          .exercises
          .firstWhere((e) => e.name == ex)
          .sets
          .map((s) => s.kg)
          .toList();
      expect(kgs(15, 'Käsipainopystypunnerrus'), [28, 36]);
      expect(kgs(15, 'Rintatuettu kulmasoutu käsipainoilla'), [24, 48], reason: 'soutu jo yhteispaino');
      expect(kgs(8, 'Käsipainopystypunnerrus'), [24, 44], reason: '8.11. jo yhteispaino');
      final file = File('${dir.path}/${workoutPath(DateTime(2026, 11, 12))}').readAsStringSync();
      expect(file, contains('dumbbells: total'));
      expect(file, contains('1. 20 kg × 8'));
      // Uudelleenluku ei kerro uudelleen.
      expect(parseWorkout(file).exercises.single.sets.first.kg, 20);
      expect(parseWorkout(file).dumbbellReview, isFalse);
    });
  });

  test('tarkistus: Farmer walk hex bariksi (paino ennallaan, nimi kaikkialla), muut ennallaan', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('gievra-hex');
    settings.folder = dir.path;
    final w = parseWorkout(
      '---\ndate: 2026-10-01\ntitle: Treeni\ndone: Farmer walk\nmove_feeling: Farmer walk=4\n---\n\n'
      '## Farmer walk\n1. 100 kg × 2 edestakaisin\n',
    );
    store.workouts = [w];
    final rows = dumbbellRows(store.workouts);
    expect(await applyDumbbellReview(rows, const {}, hexBar: {...rows['Farmer walk']!}), 1);
    final saved = store.workouts.single;
    expect(saved.exercises.single.name, 'Farmer walk hex barilla');
    expect(saved.exercises.single.sets.single.kg, 100);
    expect(saved.doneMoves, {'Farmer walk hex barilla'});
    expect(saved.moveFeeling, {'Farmer walk hex barilla': 4});
    final file = File('${dir.path}/${workoutPath(DateTime(2026, 10, 1))}').readAsStringSync();
    expect(file, contains('## Farmer walk hex barilla\n1. 100 kg × 2 edestakaisin'));
    expect(parseWorkout(file).dumbbellReview, isFalse, reason: 'ei enää kahden painon liike');
  });

  test('FitNotes: käsipainot tarkistettaviksi luvut ennallaan; vienti ennallaan', () async {
    final tmp = Directory.systemTemp.createTempSync('gievra-fn');
    final w = Workout(date: DateTime(2026, 3, 9), title: 'Treeni')
      ..exercises.add(ExerciseEntry('Rintatuettu kulmasoutu käsipainoilla', [SetEntry(56, 10)]));
    final path = '${tmp.path}/x.fitnotes';
    await writeFitnotes(path, [w]);
    final back = (await readFitnotes(path)).workouts.single;
    expect(back.exercises.single.sets.single.kg, 56);
    expect(back.dumbbellReview, isTrue);
  });

  test('CSV: käsipainot tallennettuna (yhteispaino), kuulat kuulaa kohden kahdesti', () {
    final r = readMdBytes({
      '2026-11-16.md': utf8.encode(md('2026-11-16', 'Käsipainopystypunnerrus', '1. 44 kg × 7', marked: true)),
      '2026-11-17.md': utf8.encode(md('2026-11-17', 'Tuplakahvakuulapystypunnerrus', '1. 16 kg × 8')),
    });
    final csv = buildCsvExport(
      r.workouts,
      BodyLog(),
      CsvExportOptions(from: DateTime(2000), to: DateTime(2030)),
    ).firstWhere((f) => f.name == 'salisarjat.csv').text;
    expect(csv, contains(';44;7;'));
    expect(csv, contains(';32;8;'));
  });

  for (final lang in ['fi', 'en', 'se']) {
    testWidgets('tarkistusnäkymä $lang kapealla näytöllä: arvaukset valmiina, ei ylivuotoa', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      debugSetCatalog(lang, lang == 'fi' ? const {} : parsePo(File('assets/l10n/$lang.po').readAsStringSync()));
      addTearDown(() => debugSetCatalog('fi', const {}));
      store.workouts = [
        parseWorkout(md('2026-11-12', 'Käsipainopystypunnerrus', '1. 10 kg × 8\n2. 10 kg × 8')),
        parseWorkout(md('2026-11-08', 'Käsipainopystypunnerrus', '1. 24 kg × 10\n2. 44 kg × 7')),
      ];
      await tester.pumpWidget(const MaterialApp(home: DumbbellReviewScreen()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final segs = tester.widgetList<SegmentedButton<int>>(find.byType(SegmentedButton<int>)).toList();
      expect(segs.map((s) => s.selected.single), [1, 0], reason: '12.11. käsipainoa kohden, 8.11. yhteensä');
    });
  }
}
