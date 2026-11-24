import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/insights.dart';
import 'package:treenipaivakirja/models.dart';

// Ennätykset (käyttäjä 23.11.): painavin nosto (todellinen ennätys) ja arvioitu maksimi nyt. Keksityt treenit.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final today = DateTime(2026, 11, 23);
  Workout w(int daysAgo, List<SetEntry> sets) => Workout(
    date: addDays(today, -daysAgo),
    title: 'A',
    exercises: [ExerciseEntry('Takakyykky', sets)],
  );

  test('painavin nosto millä tahansa toistomäärällä, lämmittely ei laske', () {
    final ws = [
      w(70, [SetEntry(110, 1)]),
      w(10, [SetEntry(100, 8), SetEntry(120, 1)..warmup = true]),
    ];
    final h = heaviestLift(ws, 'Takakyykky')!;
    expect((h.kg, h.reps), (110, 1));
    expect(
      heaviestLift([
        w(5, [SetEntry(90, 15)]),
      ], 'Takakyykky')!.reps,
      15,
      reason: 'yli 12 toistoakin',
    );
  });

  test('tasapelissä enemmän toistoja, sitten aiempi kerta', () {
    final ws = [
      w(30, [SetEntry(100, 3)]),
      w(10, [SetEntry(100, 3)]),
      w(5, [SetEntry(100, 2)]),
    ];
    expect(heaviestLift(ws, 'Takakyykky')!.date, addDays(today, -30));
  });

  test('arvio nyt 8 viikolta; muuten viimeisin kerta', () {
    final ws = [
      w(100, [SetEntry(120, 5)]),
      w(20, [SetEntry(100, 5)]),
    ];
    final now = currentE1rm(ws, 'Takakyykky', today)!;
    expect(now.recent, isTrue);
    expect(now.lift.e1rm.round(), 117);
    expect(bestLift(ws, 'Takakyykky')!.e1rm, 140, reason: 'kaikkien aikojen arvio näkyy erikseen');
    final old = currentE1rm(
      [
        w(100, [SetEntry(120, 5)]),
      ],
      'Takakyykky',
      today,
    )!;
    expect((old.recent, old.lift.kg), (false, 120));
    expect(currentE1rm(const [], 'Takakyykky', today), isNull);
  });

  // Yötesti 24.11.: sama tulos joka kerta (50 × 10) sai "uusi"-merkin ja viimeisimmän päivän, kun treenilista oli
  // uusin ensin. Ennätyksen päivä on ensimmäinen kerta; arvio nyt näyttää viimeisimmän.
  test('tasapelissä ennätys aiemmalta kerralta, arvio nyt viimeisimmältä, järjestyksestä riippumatta', () {
    final ws = [
      w(3, [SetEntry(50, 10)]),
      w(30, [SetEntry(50, 10)]),
      w(90, [SetEntry(50, 10)]),
    ];
    for (final list in [ws, ws.reversed.toList()]) {
      expect(bestLift(list, 'Takakyykky')!.date, addDays(today, -90));
      expect(bestLift(list, 'Takakyykky', since: addDays(today, -40))!.date, addDays(today, -30));
      expect(currentE1rm(list, 'Takakyykky', today)!.lift.date, addDays(today, -3));
    }
  });
}
