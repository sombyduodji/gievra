import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/csv_export.dart';
import 'package:treenipaivakirja/hr_calc.dart';
import 'package:treenipaivakirja/import_detect.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';

// Luettava CSV-vienti ja tuotavan tiedoston tunnistus. Keksityt treenit.
void main() {
  final en = parsePo(File('assets/l10n/en.po').readAsStringSync());
  tearDown(() => debugSetCatalog('fi', const {}));

  final day = DateTime(2026, 11, 3);
  final ws = [
    Workout(date: day, title: 'Koko keho A')
      ..exercises.add(
        ExerciseEntry('Takakyykky', [SetEntry(60, 5, warmup: true), SetEntry(100.5, 5, rir: 1, pr: true)]),
      )
      ..exercises.add(ExerciseEntry('Lankku', [SetEntry(0, 45)]))
      ..notes = 'Hyvä päivä; jalat "raskaat"',
    Workout(date: day, title: 'Juoksu', activity: 'Juoksu', session: 2)
      ..distanceKm = 5.2
      ..seconds = 1560
      ..hrAvg = 150
      ..feeling = 4,
    Workout(date: DateTime(2025, 1, 1), title: 'Vanha')
      ..exercises.add(ExerciseEntry('Penkkipunnerrus', [SetEntry(80, 5)])),
  ];
  final body = BodyLog(heightCm: 180, weights: {day: 82.4});

  test('Englanniksi: pilkkuerotin, desimaalipiste, englanninkieliset liikkeet ja lajit, aikaväli rajaa', () {
    debugSetCatalog('en', en, english: en);
    final files = buildCsvExport(
      ws,
      body,
      CsvExportOptions(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 10), body: true, notes: true),
    );
    expect(files.map((f) => f.name), ['gym-sets.csv', 'activities.csv', 'weigh-ins.csv']);
    final gym = files[0].text;
    expect(gym.startsWith('﻿$gievraCsvMarker'), isTrue);
    expect(
      gym,
      contains('Date,Workout,Exercise,Set,Weight (kg),Amount,Measured as,Reps in reserve,Warm-up,Record,Notes'),
    );
    expect(gym, contains('2026-11-03,Full body A,Barbell Squat,2,100.5,5,reps,1-2,,yes,'));
    expect(gym, contains('Plank'));
    expect(gym, contains('seconds'));
    expect(gym, contains('"Hyvä päivä; jalat ""raskaat"""'), reason: 'lainausmerkit kahdennetaan');
    expect(gym, isNot(contains('Bench Press')), reason: 'aikavälin ulkopuolella');
    expect(files[0].rows, 3);
    expect(files[1].text, contains('2026-11-03,Running,26:00,5.2,5:00,150,,,,,,,Good'));
    expect(files[2].text, contains('2026-11-03,82.4,180'));
  });

  test('Suomeksi: puolipiste ja desimaalipilkku; valinnat rajaavat tiedostot ja sarakkeet', () {
    final files = buildCsvExport(ws, body, CsvExportOptions(from: DateTime(2000), to: DateTime(2030), cardio: false));
    expect(files.map((f) => f.name), ['salisarjat.csv']);
    final gym = files.single.text;
    expect(
      gym,
      contains('Päivä;Treeni;Liike;Sarja;Paino (kg);Määrä;Mittaustapa;Varaa (toistoja);Lämmittely;Ennätys\n'),
    );
    expect(gym, contains('2026-11-03;Koko keho A;Takakyykky;2;100,5;5;toistot;1-2;;kyllä'));
    expect(gym, isNot(contains('Hyvä päivä')), reason: 'muistiinpanot vain valittaessa');
    expect(gym, contains('Penkkipunnerrus'));
  });

  test('Tuotavan tiedoston tunnistus sisällöstä', () {
    Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));
    expect(
      detectImport('x.fitnotes', Uint8List.fromList([...utf8.encode('SQLite format 3'), 0, 1])),
      ImportKind.fitnotes,
    );
    expect(
      detectImport('a.csv', b('Activity Type,Date,Favorite,Title,Distance\nRunning,2026-11-01,false,x,5')),
      ImportKind.garmin,
    );
    expect(detectImport('a.csv', b('Suorituksen tyyppi,Päiväys,Suosikki\n')), ImportKind.garmin);
    final p = generateProgram(goal: 'kunto', experience: 'keski', days: 3, minutes: 60, injuries: const []);
    expect(detectImport('x.gmd', b(programToTemplate(p))), ImportKind.template);
    expect(detectImport('2026-11-03.md', b(workoutToMarkdown(ws.first))), ImportKind.md);
    expect(detectImport('noname.txt', b(workoutToMarkdown(ws.first))), ImportKind.md);
    final zip = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('Treenit/2026/2026-11-03.md', b('x'))));
    expect(detectImport('b.zip', Uint8List.fromList(zip)), ImportKind.gievraZip);
    final maps = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('kerava.pmtiles', [1, 2])));
    expect(detectImport('m.zip', Uint8List.fromList(maps)), ImportKind.mapPack);
    final csv = buildCsvExport(ws, body, CsvExportOptions(from: DateTime(2000), to: DateTime(2030))).first.text;
    expect(detectImport('salisarjat.csv', b(csv)), ImportKind.gievraCsv);
    expect(detectImport('kuva.png', Uint8List.fromList([0x89, 0x50, 0x4e, 0x47])), ImportKind.unknown);
  });

  test('Useampi tiedosto zippinä (ennen: Cannot add to an unmodifiable list)', () {
    final files = buildCsvExport(ws, body, CsvExportOptions(from: DateTime(2000), to: DateTime(2030), body: true));
    expect(files.length, greaterThan(1));
    final zip = ZipDecoder().decodeBytes(csvZip(files));
    expect(zip.files.map((f) => f.name), files.map((f) => f.name));
    expect(zip.files.first.content, utf8.encode(files.first.text));
  });

  test('Sykevyö: salitreenien yhteenveto, lähteet ja sykekäyrä omana tiedostonaan', () {
    final hrWs = [
      Workout(date: day, title: 'Koko keho A', minutes: 55)
        ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)]))
        ..hrAvg = 121
        ..hrMax = 158
        ..kcal = 250
        ..hrSource = 'sykevyö'
        ..kcalSource = 'syke'
        ..hrSeries = HrSeries(DateTime(2026, 11, 3, 17), 5, [110, 0, 130]),
      Workout(date: day, title: 'Juoksu', activity: 'Juoksu', session: 2)
        ..seconds = 1560
        ..hrAvg = 150
        ..hrSource = 'käsin'
        ..kcal = 300
        ..kcalSource = 'kello',
    ];
    final files = {
      for (final f in buildCsvExport(hrWs, body, CsvExportOptions(from: DateTime(2000), to: DateTime(2030))))
        f.name: f.text,
    };
    expect(files.keys, ['salisarjat.csv', 'liikunta.csv', 'salitreenit.csv', 'syke.csv']);
    // Muilla kielillä samanmuotoiset nimet: pienet kirjaimet ja väliviivat (ennen "heart rate.csv", "gym_workouts").
    for (final l in ['en', 'se']) {
      debugSetCatalog(l, parsePo(File('assets/l10n/$l.po').readAsStringSync()));
      final names = [
        for (final f in buildCsvExport(hrWs, body, CsvExportOptions(from: DateTime(2000), to: DateTime(2030)))) f.name,
      ];
      debugSetCatalog('fi', const {});
      for (final n in names) {
        expect(n, matches(RegExp(r'^[^\s_A-Z]+\.csv$')), reason: '$l: $n');
      }
      if (l == 'en') expect(names, ['gym-sets.csv', 'activities.csv', 'gym-workouts.csv', 'heart-rate.csv']);
    }
    expect(files['salitreenit.csv'], contains('2026-11-03;Koko keho A;55:00;121;158;250;Sykevyö;Sykevyö;'));
    expect(files['liikunta.csv'], contains(';150;;300;Käsin syötetty;Älykello;'));
    expect(files['syke.csv'], contains('Päivä;Treeni;Kellonaika;Syke\n'));
    expect(files['syke.csv'], contains('2026-11-03;Koko keho A;17:00:00;110\n2026-11-03;Koko keho A;17:00:10;130'));
    // Pelkkä liikunta valittuna: salin käyrä ei tule mukaan.
    final cardioOnly = buildCsvExport(
      hrWs,
      body,
      CsvExportOptions(from: DateTime(2000), to: DateTime(2030), gym: false),
    );
    expect(cardioOnly.map((f) => f.name), ['liikunta.csv']);
  });
}
