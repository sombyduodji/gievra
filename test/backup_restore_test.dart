import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';

// Kansion vaihto, varmuuskopio ja palautus: kaikki treenikansion tiedostot (treenit, GPS-reitit, asetukset,
// ohjelma, punnitukset, tallennetut ohjelmat) kulkevat mukana. Keksityt tiedot väliaikaisissa kansioissa.
// Aiempien versioiden oikeat varmuuskopiot: test/fixtures/old_backups/<versio>.zip (tehty vanhan version koodilla).

const _gpx =
    '<?xml version="1.0"?><gpx><trk><trkseg>'
    '<trkpt lat="62.0" lon="25.0"><time>2026-11-01T10:00:00Z</time></trkpt>'
    '<trkpt lat="62.0" lon="25.002"><time>2026-11-01T10:00:30Z</time></trkpt></trkseg></trk></gpx>';
const _gmd = '---\nnimi: Oma pohja\n---\n# Päivä A\n- Takakyykky | 3 × 5\n';

/// Nollaa sovelluksen tilan "uudeksi asennukseksi" annettuun kansioon.
void _fresh(Directory dir) {
  settings.folder = dir.path;
  store.workouts = [];
  settings.program = null;
  settings.moveNames = 'fi';
  settings.healthLang = 'fi';
  settings.trainMode = 'gym';
  settings.customExercises = [];
  settings.customCategory = {};
  settings.customMeasure = {};
  settings.body = BodyLog();
  settings.pauses = [];
  settings.injuries = [];
}

/// Täysi treenikansio: treeni + reitti, asetukset, ohjelma, punnitukset, tallennettu ohjelma.
Future<void> _fill(Directory dir) async {
  _fresh(dir);
  settings.moveNames = 'both';
  settings.healthLang = 'en';
  settings.trainMode = 'both';
  settings.customExercises = ['Oma veto'];
  settings.customCategory = {'Oma veto': 'Selkä'};
  settings.customMeasure = {'Oma veto': Measure.seconds};
  await files.write(settingsFileName, settings.settingsToMarkdown());
  final prog = generateProgram(goal: 'voimanosto', experience: 'keski', days: 4, minutes: 60, injuries: const []);
  await files.write(programFileName, programToMarkdown(prog));
  await files.write(bodyFileName, '---\nheight: 180 cm\n---\n- 2026-11-01: 82,4 kg\n');
  await files.write('ohjelmat/Oma pohja.gmd', _gmd);
  final w = Workout(date: DateTime(2026, 11, 1), title: 'Kävely', activity: 'Kävely', distanceKm: 0.1)..routeGpx = _gpx;
  await store.save(w);
  await store.save(
    Workout(date: DateTime(2026, 11, 2), title: 'Kyykky')
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)]))
      ..exercises.add(ExerciseEntry('Oma veto', [SetEntry(0, 30)])),
  );
}

List<String> _rel(Directory d) => [
  for (final f in d.listSync(recursive: true).whereType<File>()) p.relative(f.path, from: d.path).replaceAll(r'\', '/'),
]..sort();

void main() {
  settingsOrderTests();
  late Directory a, b;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    a = Directory.systemTemp.createTempSync('gievra-a');
    b = Directory.systemTemp.createTempSync('gievra-b');
  });
  tearDown(() {
    _fresh(Directory.systemTemp);
    settings.folder = null;
    for (final d in [a, b]) {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  const all = [
    '2026/2026-11-01.gpx',
    '2026/2026-11-01.md',
    '2026/2026-11-02.md',
    'asetukset.md',
    'kehonpaino.md',
    'ohjelma.md',
    'ohjelmat/Oma pohja.gmd',
  ];

  test('Kansion vaihto kopioi kaikki tiedostot, myös reitit ja tallennetut ohjelmat; ei ylikirjoita', () async {
    await _fill(a);
    expect(_rel(a), all);
    final (c, sk) = await Settings.copyMdFiles(a, b);
    expect((c, sk), (all.length, 0));
    expect(_rel(b), all);
    for (final r in all) {
      expect(File(p.join(b.path, r)).readAsStringSync(), File(p.join(a.path, r)).readAsStringSync(), reason: r);
    }
    File(p.join(b.path, 'asetukset.md')).writeAsStringSync('oma');
    expect(await Settings.copyMdFiles(a, b), (0, all.length));
    expect(File(p.join(b.path, 'asetukset.md')).readAsStringSync(), 'oma');
  });

  test('Nykyinen varmuuskopio: kaikki tiedostot mukana ja palautuvat uuteen asennukseen', () async {
    await _fill(a);
    final zip = await exportZip();
    _fresh(b);
    final r = readZip(zip);
    expect(r.workouts.length, 2);
    expect(r.savedPrograms.keys, ['Oma pohja.gmd']);
    expect(restoresAll(r), isTrue);
    expect(await applyImport(r), 2);
    expect(_rel(b), all);
    expect(File(p.join(b.path, '2026/2026-11-01.gpx')).readAsStringSync(), _gpx);
    expect(File(p.join(b.path, 'ohjelmat/Oma pohja.gmd')).readAsStringSync(), _gmd);
    // Asetukset ja ohjelma palautuivat sellaisinaan.
    expect(settings.moveNames, 'both');
    expect(settings.healthLang, 'en');
    expect(settings.trainMode, 'both');
    expect(settings.customExercises, ['Oma veto']);
    expect(settings.customMeasure['Oma veto'], Measure.seconds);
    expect(settings.program?.goal, 'voimanosto');
    expect(settings.program!.plan.map((d) => d.name), contains('Penkki raskas'));
    expect(settings.body.heightCm, 180);
    expect(settings.body.weights.length, 1);
  });

  test('Käytössä olevaan päiväkirjaan yhdistetään: nykyiset asetukset ja ohjelma säilyvät', () async {
    await _fill(a);
    final zip = await exportZip();
    _fresh(b);
    final own = generateProgram(goal: 'lihaskasvu', experience: 'keski', days: 3, minutes: 60, injuries: const []);
    settings.program = own;
    await store.save(Workout(date: DateTime(2026, 10, 1), title: 'Oma'));
    final r = readZip(zip);
    expect(restoresAll(r), isFalse);
    expect(await applyImport(r), 2);
    expect(settings.program, same(own));
    expect(settings.moveNames, 'fi');
    expect(settings.customExercises, contains('Oma veto'));
    expect(settings.customMeasure['Oma veto'], Measure.seconds, reason: 'mittaustapa tulee omien liikkeiden mukana');
    expect(File(p.join(b.path, 'ohjelmat/Oma pohja.gmd')).existsSync(), isTrue);
  });

  group('Sairas- ja lomatauot palautuksessa', () {
    final holiday = Pause(DateTime(2026, 10, 25), 'loma', DateTime(2026, 10, 27));
    // Varmuuskopio sairastaessa: loma takana, sairastaminen käynnissä 3.11. alkaen.
    Future<ImportResult> sickBackup() async {
      await _fill(a);
      settings.pauses = [Pause(holiday.start, 'loma', holiday.end), Pause(DateTime(2026, 11, 3), 'sairas')];
      await files.write(settingsFileName, settings.settingsToMarkdown());
      final zip = await exportZip();
      _fresh(b);
      return readZip(zip);
    }

    List<String> got() => [
      for (final p in settings.pauses) '${isoDate(p.start)}..${p.end == null ? '' : isoDate(p.end!)} ${p.reason}',
    ];

    test('Uusi puhelin: käynnissä oleva tauko ja aiemmat palautuvat', () async {
      final r = await sickBackup();
      await applyImport(r);
      expect(got(), ['2026-10-25..2026-10-27 loma', '2026-11-03.. sairas']);
      expect(settings.activePause!.sick, isTrue);
    });

    test('Käytössä oleva päiväkirja: puuttuvat tauot lisätään, sama tauko vain kerran', () async {
      final r = await sickBackup();
      await store.save(Workout(date: DateTime(2026, 10, 1), title: 'Oma'));
      settings.pauses = [Pause(holiday.start, 'loma', holiday.end)];
      await applyImport(r);
      expect(got(), ['2026-10-25..2026-10-27 loma', '2026-11-03.. sairas']);
      // Tallentui asetuksiin.
      final saved = Settings()..applyMarkdown(await files.read(settingsFileName) ?? '');
      expect(saved.activePause?.start, DateTime(2026, 11, 3));
    });

    test('Tämän puhelimen käynnissä oleva tauko säilyy, varmuuskopion käynnissä olevaa ei lisätä', () async {
      final r = await sickBackup();
      await store.save(Workout(date: DateTime(2026, 10, 1), title: 'Oma'));
      settings.pauses = [Pause(DateTime(2026, 11, 6), 'loma')];
      await applyImport(r);
      expect(got(), ['2026-10-25..2026-10-27 loma', '2026-11-06.. loma']);
    });

    test('Kävely tauon aikana ei päätä taukoa (kuten sovelluksessa)', () async {
      final r = await sickBackup();
      await store.save(Workout(date: DateTime(2026, 10, 1), title: 'Oma'));
      await store.save(Workout(date: DateTime(2026, 11, 5), title: 'Kävely', activity: 'Kävely'));
      await applyImport(r);
      expect(settings.activePause?.start, DateTime(2026, 11, 3));
    });

    test('Treeni tällä puhelimella tauon alun jälkeen: tauko päättyy edelliseen päivään', () async {
      final r = await sickBackup();
      await store.save(Workout(date: DateTime(2026, 11, 8), title: 'Oma'));
      await applyImport(r);
      expect(got(), ['2026-10-25..2026-10-27 loma', '2026-11-03..2026-11-07 sairas']);
      expect(settings.activePause, isNull);
    });
  });

  group('Vammatila palautuksessa', () {
    Future<ImportResult> injuryBackup() async {
      await _fill(a);
      settings.injuries = ['polvi_etu', 'ranne'];
      await files.write(settingsFileName, settings.settingsToMarkdown());
      final zip = await exportZip();
      _fresh(b);
      return readZip(zip);
    }

    test('Uusi puhelin: vamma-alueet palautuvat sellaisinaan, ei kysytä', () async {
      final r = await injuryBackup();
      expect(newInjuries(r), isEmpty);
      await applyImport(r);
      expect(settings.injuries, ['polvi_etu', 'ranne']);
    });

    test('Käytössä oleva päiväkirja: alueet vain, jos käyttäjä valitsee', () async {
      final r = await injuryBackup();
      await store.save(Workout(date: DateTime(2026, 10, 1), title: 'Oma'));
      settings.injuries = ['ranne'];
      expect(newInjuries(r), ['polvi_etu'], reason: 'jo valittu ranne ei tule uudelleen');
      await applyImport(r);
      expect(settings.injuries, ['ranne']);
    });

    test('Käytössä oleva päiväkirja, valittu: alueet lisätään ja tallentuvat', () async {
      final r = await injuryBackup();
      await store.save(Workout(date: DateTime(2026, 10, 1), title: 'Oma'));
      settings.injuries = ['ranne'];
      await applyImport(r, addInjuries: true);
      expect(settings.injuries, ['ranne', 'polvi_etu']);
      final saved = Settings()..applyMarkdown(await files.read(settingsFileName) ?? '');
      expect(saved.injuries, ['ranne', 'polvi_etu']);
    });

    test('Ei kysytä, kun varmuuskopion alueet ovat jo valittuna', () async {
      final r = await injuryBackup();
      await store.save(Workout(date: DateTime(2026, 10, 1), title: 'Oma'));
      settings.injuries = ['ranne', 'polvi_etu'];
      expect(newInjuries(r), isEmpty);
    });
  });

  test('Käsin muokattu tai vaurioitunut asetukset.md: mahdottomat päivät ohitetaan, alue kerran', () {
    final s = Settings()
      ..applyMarkdown(
        '## Vammat\n- ranne\n- ranne\n- vanha_alue\n-\n'
        '## Tauot\n- 2026-13-40 – sairas\n- 2026-02-30 – loma\n- 2026-11-02 – 2026-11-40 sairas\n'
        '- 2026-11-05 – 2026-11-01 loma\n- roskaa\n- 2026-11-07 – sairas\n',
      );
    expect(s.injuries, ['ranne', 'vanha_alue'], reason: 'tuntematon säilyy tiedostossa, tupla ei');
    expect(knownInjuries(s.injuries), ['ranne']);
    expect(
      [for (final p in s.pauses) '${isoDate(p.start)}..${p.end == null ? '' : isoDate(p.end!)} ${p.reason}'],
      ['2026-11-05..2026-11-05 loma', '2026-11-07.. sairas'],
    );
    expect(s.activePause!.start, DateTime(2026, 11, 7), reason: 'ei tulevaisuuteen siirtynyttä taukoa');
  });

  // Aiempien versioiden oikeat varmuuskopiot (tehty kunkin version omalla exportZip-koodilla).
  final old = Directory('test/fixtures/old_backups');
  for (final f
      in old.existsSync()
          ? (old.listSync().whereType<File>().toList()..sort((x, y) => x.path.compareTo(y.path)))
          : <File>[]) {
    final v = p.basenameWithoutExtension(f.path);
    test('Vanha varmuuskopio $v palautuu uuteen asennukseen', () async {
      _fresh(b);
      final r = readZip(f.readAsBytesSync());
      expect(r.workouts, isNotEmpty);
      expect(r.settingsMd, isNotNull);
      final n = await applyImport(r);
      expect(n, r.workouts.length);
      // Asetukset luetaan ennen treenihistoriaa: oma liike ja sen kategoria tulevat asetuksista, eivät historiasta.
      expect(settings.customExercises, contains('Oma veto'), reason: 'oma liike asetuksista');
      expect(settings.customCategory['Oma veto'], 'Selkä');
      expect(settings.customMeasure['Oma veto'], Measure.seconds);
      expect(settings.injuries, ['niska']);
      await store.reload();
      expect(store.workouts.length, r.workouts.length);
      final hasGpx = readZip(f.readAsBytesSync()).workouts.any((w) => w.routeGpx != null);
      if (hasGpx) expect(Directory(p.join(b.path, '2026')).listSync().any((x) => x.path.endsWith('.gpx')), isTrue);
      expect(settings.program, isNotNull, reason: 'ohjelma palautui');
      final sets = store.workouts.expand((w) => w.exercises).expand((e) => e.sets).length;
      expect(sets, greaterThan(0));
    });
  }
}

// asetukset.md ennen 0.5.5:ttä: omien liikkeiden kategoriat kirjoitettiin mittaustapojen, vammojen ja taukojen
// perään, jolloin ne luettiin väärään osioon ja omat liikkeet katosivat.
void settingsOrderTests() {
  test('asetukset.md: omat liikkeet säilyvät mittaustapojen, vammojen ja taukojen kanssa', () {
    final s = Settings()
      ..customExercises = ['Oma veto', 'Oma punnerrus']
      ..customCategory = {'Oma veto': 'Selkä'}
      ..customMeasure = {'Oma veto': Measure.seconds}
      ..injuries = ['niska']
      ..pauses = [Pause(DateTime(2026, 11, 1), 'loma', DateTime(2026, 11, 5))];
    final back = Settings()..applyMarkdown(s.settingsToMarkdown());
    expect(back.customExercises, ['Oma veto', 'Oma punnerrus']);
    expect(back.customCategory, {'Oma veto': 'Selkä'});
    expect(back.customMeasure, {'Oma veto': Measure.seconds});
    expect(back.injuries, ['niska']);
    expect(back.pauses.single.end, DateTime(2026, 11, 5));
  });

  test('Vanhan version asetukset.md (kategoriat lopussa) luetaan oikein', () {
    const old =
        '---\nname: Testi\n---\n\n## Omat liikkeet\n\n## Mittaustavat\n- Oma veto: sekunnit\n\n'
        '## Tauot\n- 2026-11-01 – 2026-11-05 loma\n\n### Selkä\n- Oma veto\n\n### Omat liikkeet\n- Oma punnerrus\n';
    final s = Settings()..applyMarkdown(old);
    expect(s.customExercises, ['Oma veto', 'Oma punnerrus']);
    expect(s.customCategory['Oma veto'], 'Selkä');
    expect(s.pauses, hasLength(1));
  });

  test('Kadonneet omat liikkeet palautuvat treenihistoriasta', () async {
    final dir = Directory.systemTemp.createTempSync('gievra-hist');
    SharedPreferences.setMockInitialValues({});
    _fresh(dir);
    await store.save(
      Workout(date: DateTime(2026, 11, 3), title: 'Treeni')
        ..exercises.add(ExerciseEntry('Kadonnut liike', [SetEntry(20, 10)]))
        ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)])),
    );
    settings.customExercises = [];
    await store.reload();
    expect(settings.customExercises, ['Kadonnut liike']);
    _fresh(Directory.systemTemp);
    settings.folder = null;
    dir.deleteSync(recursive: true);
  });
}
