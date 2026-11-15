// Verkkoversio: FitNotes-tietokantaa (SQLite) ei voi lukea selaimessa.
import 'import_export.dart';
import 'models.dart';

Future<ImportResult> readFitnotes(String dbPath, {bool translate = true}) async =>
    throw UnsupportedError('FitNotes-tuonti toimii vain sovelluksessa');

Future<int> writeFitnotes(String path, List<Workout> workouts, {Map<DateTime, double> weighIns = const {}}) async =>
    throw UnsupportedError('FitNotes-vienti toimii vain sovelluksessa');
