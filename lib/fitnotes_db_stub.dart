// Verkkoversio: FitNotes-tietokantaa (SQLite) ei voi lukea selaimessa.
import 'import_export.dart';
import 'models.dart';

ImportResult readFitnotes(String dbPath, {bool translate = true}) =>
    throw UnsupportedError('FitNotes-tuonti toimii vain sovelluksessa');

int writeFitnotes(String path, List<Workout> workouts) =>
    throw UnsupportedError('FitNotes-vienti toimii vain sovelluksessa');
