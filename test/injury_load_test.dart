import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/progression.dart';

// Keksitty historia (ei oikeita tietoja).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    store.workouts = [];
    settings.injuries = [];
  });

  test('Vammatila keventää ehdotetun kuorman 30 % (alaspäin askeleeseen); ilman vammaa ennallaan', () {
    store.workouts = [
      Workout(
        date: DateTime(2026, 11, 10),
        title: 'Treeni',
        exercises: [
          ExerciseEntry('Maastaveto', [SetEntry(100, 5, rir: 2), SetEntry(100, 5, rir: 2)]),
        ],
      )..minutes = 40,
    ];
    final day = DateTime(2026, 11, 16);
    final base = suggestNext('Maastaveto', day)!;
    expect(base.kg, greaterThanOrEqualTo(100));
    settings.injuries = ['alaselka'];
    final hurt = suggestNext('Maastaveto', day)!;
    expect(hurt.kg, lessThanOrEqualTo(base.kg * .7 + 1e-9));
    expect(hurt.kg, greaterThan(base.kg * .7 - 5));
    expect(hurt.reps, base.reps);
    expect(hurt.reason, contains('Vammatila'));
    // Vamma, joka ei koske liikettä: ei kevennystä.
    settings.injuries = ['ranne'];
    expect(suggestNext('Maastaveto', day)!.kg, base.kg);
  });
}
