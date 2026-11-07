import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/models.dart';

void main() {
  setUp(() => settings.customMeasure = {});

  test('Lankku sekunteina, Farmer walk edestakaisin, kyykky toistoina', () {
    expect(measureOf('Lankku'), Measure.seconds);
    expect(measureOf('Farmer walk'), Measure.trips);
    expect(measureOf('Takakyykky'), Measure.reps);
    final w = Workout(
      date: DateTime(2026, 11, 6),
      exercises: [
        ExerciseEntry('Lankku', [SetEntry(0, 45), SetEntry(10, 30, rir: 1)]),
        ExerciseEntry('Farmer walk', [SetEntry(48, 2)]),
        ExerciseEntry('Askelkyykkykävely', [SetEntry(20, 24)]),
        ExerciseEntry('Takakyykky', [SetEntry(100, 5)]),
      ],
    );
    final md = workoutToMarkdown(w);
    expect(md, contains('## Lankku\n1. 45 s\n2. 10 kg × 30 s RIR 1-2\n'));
    expect(md, contains('## Farmer walk\n1. 48 kg × 2 edestakaisin\n'));
    expect(md, contains('## Askelkyykkykävely\n1. 20 kg × 24 askelta\n'));
    expect(md, contains('## Takakyykky\n1. 100 kg × 5\n'));
    expect(workoutToMarkdown(parseWorkout(md)), md);
  });

  test('Käyttäjän valitsema mittaustapa tallentuu asetuksiin', () {
    settings.customMeasure = {'Askelkyykkykävely': Measure.trips, 'Oma kantoliike': Measure.meters};
    expect(measureOf('Askelkyykkykävely'), Measure.trips);
    final r = Settings()..applyMarkdown(settings.settingsToMarkdown());
    expect(r.customMeasure, {'Askelkyykkykävely': Measure.trips, 'Oma kantoliike': Measure.meters});
    expect(fmtSet('Oma kantoliike', SetEntry(32, 40)), '32 kg × 40 m');
  });
}
