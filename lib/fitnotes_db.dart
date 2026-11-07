// FitNotes-varmuuskopion (SQLite) luku ja kirjoitus. Vain natiivialustoilla (dart:ffi); verkossa fitnotes_db_stub.dart.
import 'dart:io';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import 'app_state.dart';
import 'exercises.dart';
import 'fitnotes_template.dart';
import 'body.dart';
import 'import_export.dart';
import 'models.dart';

/// Lukee FitNotes-varmuuskopion. [translate]: tunnetut liikkeet suomeksi.
ImportResult readFitnotes(String dbPath, {bool translate = true}) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final rows = db.select('''
      SELECT t.date AS date, e.name AS name, c.name AS cat, t.metric_weight AS kg, t.reps AS reps,
             t.distance AS dist, t.duration_seconds AS secs, t.is_personal_record AS pr
      FROM training_log t
      JOIN exercise e ON e._id = t.exercise_id
      LEFT JOIN Category c ON c._id = e.category_id
      ORDER BY t.date, t._id''');

    // Askelkyykky, jossa toistoja on aina 1–2 painon kanssa, on kirjattu edestakaisina kävelyinä.
    final maxReps = <String, int>{};
    for (final r in rows) {
      final n = (r['name'] as String).trim();
      maxReps[n] = math.max(maxReps[n] ?? 0, r['reps'] as int);
    }
    final measures = <String, Measure>{};
    String rename(String orig) {
      final walk =
          RegExp(r'lunge|askelkyykky', caseSensitive: false).hasMatch(orig) &&
          !RegExp(r'bulgar|split', caseSensitive: false).hasMatch(orig) &&
          (maxReps[orig] ?? 0) <= 2;
      if (walk) {
        final n = translate ? 'Askelkyykkykävely' : orig;
        measures[n] = Measure.trips;
        return n;
      }
      return translate ? (fitnotesNames[orig] ?? orig) : orig;
    }

    final byDate = <String, Workout>{};
    final newEx = <String, String>{};
    var sets = 0, cardio = 0;
    for (final r in rows) {
      final date = r['date'] as String;
      final w = byDate[date] ??= Workout(date: DateTime.parse(date));
      final orig = (r['name'] as String).trim();
      final name = rename(orig);
      final kg = (r['kg'] as num).toDouble();
      final reps = r['reps'] as int;
      final dist = (r['dist'] as num?) ?? 0;
      final secs = (r['secs'] as int?) ?? 0;

      final timed = (measures[name] ?? measureOf(name)) == Measure.seconds;
      if (timed && reps == 0 && secs > 0) {
        var e = w.exercises.where((x) => x.name == name).firstOrNull;
        if (e == null) w.exercises.add(e = ExerciseEntry(name));
        e.sets.add(SetEntry(kg, secs));
        sets++;
        continue;
      }
      if (reps == 0 && (dist > 0 || secs > 0)) {
        // Kardio- ja aikasarjat muistiinpanoihin (sarjamuoto on paino × toistot).
        final parts = [if (dist > 0) 'matka $dist', if (secs > 0) 'aika ${mmss(secs)}'];
        w.notes = '${w.notes}${w.notes.isEmpty ? '' : '\n'}- $name: ${parts.join(', ')}';
        cardio++;
        continue;
      }
      var e = w.exercises.where((x) => x.name == name).firstOrNull;
      if (e == null) w.exercises.add(e = ExerciseEntry(name));
      e.sets.add(SetEntry(kg, reps, pr: (r['pr'] as int? ?? 0) != 0));
      sets++;
      if (categoryOf(name) == null && !newEx.containsKey(name)) {
        newEx[name] = fitnotesCategories[r['cat']] ?? ownCategory;
      }
    }

    // Kehonpaino (mittaukset tai vanhempi BodyWeight-taulu): kaikki punnitukset kehonpaino.md:hen ja
    // treenipäivinä myös treenin tietoihin. Saman päivän useasta punnituksesta otetaan ensimmäinen.
    var bw = 0;
    final weighIns = <DateTime, double>{};
    void addBw(String date, num v) {
      final kg = parseWeight(v.toString());
      final day = DateTime.tryParse(date.substring(0, 10));
      if (kg == null || day == null) return;
      weighIns.putIfAbsent(dateOnly(day), () => kg);
      final w = byDate[date.substring(0, 10)];
      if (w != null && w.bodyweight == null) {
        w.bodyweight = v.toDouble();
        bw++;
      }
    }

    try {
      for (final r in db.select('''
          SELECT r.date AS date, r.value AS v FROM MeasurementRecord r
          JOIN Measurement m ON m._id = r.measurement_id
          WHERE lower(m.name) = 'bodyweight' ORDER BY r.date, r.time''')) {
        addBw(r['date'] as String, r['v'] as num);
      }
    } on SqliteException catch (_) {}
    try {
      for (final r in db.select('SELECT date, body_weight_metric AS v FROM BodyWeight')) {
        addBw(r['date'] as String, r['v'] as num);
      }
    } on SqliteException catch (_) {}

    // Treenikommentit.
    try {
      for (final r in db.select('SELECT date, comment FROM WorkoutComment ORDER BY _id')) {
        final w = byDate[(r['date'] as String).substring(0, 10)];
        final c = (r['comment'] as String).trim();
        if (w != null && c.isNotEmpty) w.notes = w.notes.isEmpty ? c : '$c\n${w.notes}';
      }
    } on SqliteException catch (_) {}

    for (final w in byDate.values) {
      w.title = autoTitle(w);
    }
    final list = byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return ImportResult(
      source: 'FitNotes',
      workouts: list,
      newExercises: newEx,
      sets: sets,
      bodyweights: bw,
      cardioNotes: cardio,
      measures: measures,
      bodyMd: weighIns.isEmpty ? null : bodyToMarkdown(BodyLog(weights: weighIns)),
    );
  } finally {
    db.close();
  }
}

/// Kirjoittaa treenit FitNotes-varmuuskopioksi [path]:iin (tietokantaversio 22).
/// Suomennetut liikkeet palautetaan FitNotesin englanninkielisiin nimiin.
/// Kehonpaino -> mittaukset, muistiinpanot ja lämmittely -> treenikommentti. Palauttaa sarjojen määrän.
int writeFitnotes(String path, List<Workout> workouts) {
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  final db = sqlite3.open(path);
  var sets = 0;
  try {
    db.execute('BEGIN');
    for (final sql in fitnotesSchema) {
      db.execute(sql);
    }
    db.execute('PRAGMA user_version = $fitnotesUserVersion');
    final cats = {for (final r in db.select('SELECT _id, name FROM Category')) r['name'] as String: r['_id'] as int};
    final bwId = db.select("SELECT _id FROM Measurement WHERE name = 'Bodyweight'").first['_id'] as int;
    final english = <String, String>{};
    for (final e in fitnotesNames.entries) {
      english.putIfAbsent(e.value, () => e.key);
    }
    final exIds = <String, int>{};
    final insEx = db.prepare(
      'INSERT INTO exercise (name, category_id, exercise_type_id, weight_unit_id) VALUES (?, ?, 0, 0)',
    );
    final insLog = db.prepare(
      'INSERT INTO training_log (exercise_id, date, metric_weight, reps, unit, '
      'is_personal_record, is_complete) VALUES (?, ?, ?, ?, 0, ?, 1)',
    );
    final insTime = db.prepare(
      'INSERT INTO training_log (exercise_id, date, metric_weight, reps, unit, '
      'is_personal_record, is_complete, duration_seconds) VALUES (?, ?, ?, 0, 0, ?, 1, ?)',
    );
    final insBw = db.prepare(
      "INSERT INTO MeasurementRecord (measurement_id, date, time, value, comment) VALUES (?, ?, '12:00:00', ?, NULL)",
    );
    final insCom = db.prepare('INSERT INTO WorkoutComment (date, comment) VALUES (?, ?)');
    try {
      for (final w in [...workouts]..sort((a, b) => a.date.compareTo(b.date))) {
        final date = isoDate(w.date);
        for (final e in w.exercises) {
          if (e.sets.isEmpty) continue;
          final name = english[e.name] ?? e.name;
          final id = exIds[name] ??= () {
            insEx.execute([name, cats[fitnotesCategoryFor(e.name)] ?? cats['Full']]);
            if (measureOf(e.name) == Measure.seconds) {
              db.execute('UPDATE exercise SET exercise_type_id = 3 WHERE _id = ?', [db.lastInsertRowId]);
            }
            return db.lastInsertRowId;
          }();
          final timed = measureOf(e.name) == Measure.seconds;
          for (final s in e.sets) {
            if (timed) {
              insTime.execute([id, date, s.kg, s.pr ? 1 : 0, s.reps]);
            } else {
              insLog.execute([id, date, s.kg, s.reps, s.pr ? 1 : 0]);
            }
            sets++;
          }
        }
        if (w.bodyweight != null) insBw.execute([bwId, date, w.bodyweight]);
        final comment = [
          if (w.warmup != null) 'Lämmittely: ${w.warmup!.equipment} ${w.warmup!.minutes} min',
          if (w.notes.trim().isNotEmpty) w.notes.trim(),
        ].join('\n');
        if (comment.isNotEmpty) insCom.execute([date, comment]);
      }
    } finally {
      insEx.close();
      insLog.close();
      insTime.close();
      insBw.close();
      insCom.close();
    }
    db.execute('COMMIT');
  } finally {
    db.close();
  }
  return sets;
}
