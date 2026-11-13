import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';

/// Pieni FitNotes-tietokanta samalla skeemalla kuin oikeassa varmuuskopiossa.
String makeFitnotesDb(Directory dir) {
  final path = '${dir.path}/test.fitnotes';
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE Category(_id INTEGER PRIMARY KEY, name TEXT NOT NULL, colour INTEGER, sort_order INTEGER);
    CREATE TABLE exercise(_id INTEGER PRIMARY KEY, name TEXT NOT NULL, category_id INTEGER NOT NULL,
      exercise_type_id INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE training_log(_id INTEGER PRIMARY KEY, exercise_id INTEGER NOT NULL, date DATE NOT NULL,
      metric_weight INTEGER NOT NULL, reps INTEGER NOT NULL, is_personal_record INTEGER NOT NULL DEFAULT 0,
      distance INTEGER NOT NULL DEFAULT 0, duration_seconds INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE Measurement(_id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE MeasurementRecord(_id INTEGER PRIMARY KEY, measurement_id INTEGER, date TEXT, time TEXT, value REAL);
    INSERT INTO Category VALUES (5,'Back',0,0),(6,'Legs',0,0),(8,'Cardio',0,0);
    INSERT INTO exercise VALUES (1,'Barbell Squat',6,0),(2,'Techogym Pull Down',5,0),(3,'Walking',8,1);
    INSERT INTO training_log(exercise_id,date,metric_weight,reps,is_personal_record,distance,duration_seconds) VALUES
      (1,'2026-10-01',100,5,0,0,0),(1,'2026-10-01',122.5,3,1,0,0),(2,'2026-10-01',50,10,0,0,0),
      (3,'2026-10-03',0,0,0,2000,1200),(2,'2026-10-03',55,8,0,0,0);
    INSERT INTO Measurement VALUES (1,'Bodyweight');
    INSERT INTO MeasurementRecord VALUES (1,1,'2026-10-01','07:00:00',96.5),(2,1,'2026-10-02','07:00:00',96.0);
  ''');
  db.close();
  return path;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('treeni'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('FitNotes: liikkeet suomeksi, ennätykset, kehonpaino, kardio muistiinpanoihin', () {
    final r = readFitnotes(makeFitnotesDb(tmp));
    expect(r.workouts.length, 2);
    expect(r.sets, 4);
    final w = r.workouts.first;
    expect(w.date, DateTime(2026, 10, 1));
    expect(w.exercises.map((e) => e.name), ['Takakyykky', 'Techogym Pull Down']);
    expect(w.exercises.first.sets[1].kg, 122.5);
    expect(w.exercises.first.sets[1].pr, isTrue);
    expect(w.bodyweight, 96.5);
    expect(r.bodyweights, 1); // treenin tietoihin vain treenipäivältä 1.10.
    // Kaikki punnitukset kehonpaino.md:hen, myös päivältä, jolloin ei treenattu.
    expect(parseBody(r.bodyMd!).weights, {DateTime(2026, 10, 1): 96.5, DateTime(2026, 10, 2): 96.0});
    expect(r.newExercises, {'Techogym Pull Down': 'Selkä'});
    expect(r.workouts[1].notes, contains('Walking: matka 2000, aika 20:00'));
    expect(r.cardioNotes, 1);
    // Tulos kirjoittuu ja lukeutuu .md:nä.
    final back = parseWorkout(workoutToMarkdown(w));
    expect(back.bodyweight, 96.5);
    expect(back.exercises.first.sets[1].pr, isTrue);
  });

  test('FitNotes ilman suomennosta säilyttää nimet', () {
    final r = readFitnotes(makeFitnotesDb(tmp), translate: false);
    expect(r.workouts.first.exercises.first.name, 'Barbell Squat');
  });

  test('Asetukset .md edestakaisin', () {
    final s = Settings()
      ..name = 'Elle'
      ..weightStep = 1.25
      ..equipment = [const Equipment('🚴', 'Kuntopyörä'), const Equipment('⭐', 'Airbike')]
      ..customExercises = ['Oma laitesoutu', 'Oma liike']
      ..customCategory = {'Oma laitesoutu': 'Selkä'};
    final md = s.settingsToMarkdown();
    expect(md, contains('### Selkä\n- Oma laitesoutu'));
    final r = Settings()..applyMarkdown(md);
    expect(r.name, 'Elle');
    expect(r.weightStep, 1.25);
    expect(r.equipment.map((e) => '${e.icon} ${e.name}'), ['🚴 Kuntopyörä', '⭐ Airbike']);
    expect(r.customExercises, ['Oma laitesoutu', 'Oma liike']);
    expect(r.customCategory, {'Oma laitesoutu': 'Selkä'});
  });

  test('Käsin kirjoitettu laite ilman kuvaketta', () {
    final r = Settings()..applyMarkdown('# x\n## Lämmittelylaitteet\n- Soutulaite\n');
    expect(r.equipment.single.name, 'Soutulaite');
  });

  test('FitNotes-vienti: punnitukset kehonpaino.md:stä mittauksiksi ja takaisin', () {
    final r = readFitnotes(makeFitnotesDb(tmp));
    final out = '${tmp.path}/bw.fitnotes';
    writeFitnotes(out, r.workouts, weighIns: {DateTime(2026, 3, 1): 81.4, DateTime(2026, 3, 8): 80.9});
    final db = sqlite3.open(out, mode: OpenMode.readOnly);
    expect(db.select('SELECT value FROM MeasurementRecord').map((x) => x['value']), containsAll([81.4, 80.9]));
    db.close();
    final back = readFitnotes(out);
    expect(parseBody(back.bodyMd!).weights[DateTime(2026, 3, 8)], 80.9);
  });

  test('FitNotes-vienti lukeutuu takaisin samana', () {
    final r = readFitnotes(makeFitnotesDb(tmp));
    r.workouts.first.warmup = Warmup('Kuntopyörä', 10);
    final out = '${tmp.path}/out.fitnotes';
    expect(writeFitnotes(out, r.workouts), 4);
    final db = sqlite3.open(out, mode: OpenMode.readOnly);
    expect(db.userVersion, 22);
    expect(db.select("SELECT name FROM exercise ORDER BY _id").map((x) => x['name']), [
      'Barbell Squat',
      'Techogym Pull Down',
    ]);
    db.close();
    final back = readFitnotes(out);
    expect(back.sets, 4);
    expect(back.workouts.first.exercises.first.name, 'Takakyykky');
    expect(back.workouts.first.bodyweight, 96.5);
    expect(back.workouts.first.notes, 'Lämmittely: Kuntopyörä 10 min');
    expect(back.workouts.first.exercises.first.sets[1].pr, isTrue);
  });

  // Oikea varmuuskopio: FITNOTES=/polku/backup.fitnotes flutter test
  final real = Platform.environment['FITNOTES'];
  test('Oikea FitNotes-varmuuskopio', () {
    final r = readFitnotes(real!);
    final out = Directory('${tmp.path}/out')..createSync();
    for (final w in r.workouts) {
      File('${out.path}/${isoDate(w.date)}.md').writeAsStringSync(workoutToMarkdown(w));
    }
    // Kaikki tiedostot lukeutuvat takaisin samoiksi.
    var sets = 0;
    for (final w in r.workouts) {
      final b = parseWorkout(File('${out.path}/${isoDate(w.date)}.md').readAsStringSync());
      expect(workoutToMarkdown(b), workoutToMarkdown(w));
      sets += b.exercises.fold(0, (a, e) => a + e.sets.length);
    }
    expect(sets, r.sets);
    // FitNotes -> .md -> FitNotes -> .md: identtinen.
    writeFitnotes('${tmp.path}/rt.fitnotes', r.workouts);
    final rt = readFitnotes('${tmp.path}/rt.fitnotes');
    expect([for (final w in rt.workouts) workoutToMarkdown(w)], [for (final w in r.workouts) workoutToMarkdown(w)]);
    // ignore: avoid_print
    print(
      '${r.workouts.length} päivää, ${r.sets} sarjaa, ${r.bodyweights} kehonpainoa, '
      '${r.cardioNotes} kardio, ${r.newExercises.length} omaa liikettä',
    );
    // ignore: avoid_print
    print('Esimerkki:\n${workoutToMarkdown(r.workouts.last)}');
    // ignore: avoid_print
    print('Omat: ${r.newExercises}');
  }, skip: real == null ? 'FITNOTES ei asetettu' : false);

  test('FitNotes-tuonti uudelleen: ei kaksoiskappaleita treeneistä eikä punnituksista', () async {
    settings.folder = tmp.path;
    store.workouts = [];
    settings.body = BodyLog();
    final db = makeFitnotesDb(tmp);
    expect(await applyImport(readFitnotes(db)), 2);
    // Punnitus, joka on jo kirjattu Gievraan, ei muutu.
    await settings.setWeight(DateTime(2026, 10, 2), 95.5);
    expect(await applyImport(readFitnotes(db)), 0);
    await store.reload();
    expect(store.workouts.length, 2);
    final files = tmp.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md'));
    expect(files.where((f) => f.path.contains('2026-10-0')).length, 2);
    final body = parseBody(File('${tmp.path}/kehonpaino.md').readAsStringSync());
    expect(body.weights, {DateTime(2026, 10, 1): 96.5, DateTime(2026, 10, 2): 95.5});
    settings.folder = null;
  });
}
