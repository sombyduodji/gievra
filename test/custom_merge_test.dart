import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/custom_merge.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';

void main() {
  final builtin = builtinExercises().toList();

  test('Uudet valmiit liikkeet ovat luettelossa, ohjeineen ja liikemalleineen', () {
    const n = 'Rintatuettu kulmasoutu käsipainoilla';
    expect(builtin, contains(n));
    expect(slotOf(n), 'VVE');
    expect(matchesSearch(n, 'chest supported'), isTrue);
    expect(matchesSearch('Käsipainopystypunnerrus', 'pystypunnerrus käsipainoilla'), isTrue);
  });

  test('Sama nimi (kirjainkoko, välit, viivat) yhdistetään kysymättä', () {
    final m = findMoveMatches(['rintatuettu  kulmasoutu-käsipainoilla'], builtin);
    expect(m.single.builtin, 'Rintatuettu kulmasoutu käsipainoilla');
    expect(m.single.identical, isTrue);
  });

  test('Samankaltaisesta kysytään: hakusana, englanninkielinen nimi, taivutusmuoto', () {
    final m = findMoveMatches([
      'Pystypunnerrus käsipainoilla',
      'Chest-Supported Dumbbell Row',
      'Rintatuettu käsipainosoutu',
    ], builtin);
    expect(
      {for (final x in m) x.custom: (x.builtin, x.identical)},
      {
        'Pystypunnerrus käsipainoilla': ('Käsipainopystypunnerrus', false),
        'Chest-Supported Dumbbell Row': ('Rintatuettu kulmasoutu käsipainoilla', false),
        'Rintatuettu käsipainosoutu': ('Rintatuettu kulmasoutu käsipainoilla', false),
      },
    );
  });

  test('Eri liikkeitä ei ehdoteta, eikä hylättyä paria kysytä uudelleen', () {
    expect(findMoveMatches(['Mummon kottikärryt', 'Hauiskääntö kahvakuulalla'], builtin), isEmpty);
    expect(
      findMoveMatches(
        ['Pystypunnerrus käsipainoilla'],
        builtin,
        declined: {'Pystypunnerrus käsipainoilla|Käsipainopystypunnerrus'},
      ),
      isEmpty,
    );
  });

  test('Yhdistäminen siirtää treenit, ohjelman ja ennätykset, oma liike poistuu', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('gievra-yhdistys');
    settings.folder = dir.path;
    store.workouts = [];
    settings.customExercises = ['Pystypunnerrus käsipainoilla'];
    final w1 = Workout(
      date: DateTime(2026, 11, 1),
      exercises: [
        ExerciseEntry('Pystypunnerrus käsipainoilla', [SetEntry(16, 10)]),
      ],
    )..moveFeeling = {'Pystypunnerrus käsipainoilla': 4};
    final w2 = Workout(
      date: DateTime(2026, 11, 3),
      exercises: [
        ExerciseEntry('Käsipainopystypunnerrus', [SetEntry(14, 12)]),
        ExerciseEntry('Pystypunnerrus käsipainoilla', [SetEntry(16, 8)]),
      ],
    );
    await store.save(w1);
    await store.save(w2);
    final p = generateProgram(goal: 'voima', experience: 'keski', days: 3, minutes: 60, injuries: const [])
      ..maxes = {'Pystypunnerrus käsipainoilla': 40};
    p.plan.first.items.first.exercise = 'Pystypunnerrus käsipainoilla';
    await settings.setProgram(p);

    final n = await mergeMove(
      const MoveMatch('Pystypunnerrus käsipainoilla', 'Käsipainopystypunnerrus', identical: false),
    );
    expect(n, 2);
    await store.reload();
    final a = store.onDay(DateTime(2026, 11, 1)).single;
    expect(a.exercises.single.name, 'Käsipainopystypunnerrus');
    expect(a.moveFeeling, {'Käsipainopystypunnerrus': 4});
    final b = store.onDay(DateTime(2026, 11, 3)).single;
    expect(b.exercises.single.sets.length, 2); // sarjat yhdistyivät samaan liikkeeseen
    expect(settings.program!.plan.first.items.first.exercise, 'Käsipainopystypunnerrus');
    expect(settings.program!.maxes, {'Käsipainopystypunnerrus': 40});
    expect(settings.customExercises, isEmpty);
    settings.folder = null;
    dir.deleteSync(recursive: true);
  });
}
