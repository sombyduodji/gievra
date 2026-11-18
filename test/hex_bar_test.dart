import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/plates.dart';
import 'package:treenipaivakirja/ui/plate_sheet.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';

// Hex barin paino (käyttäjä 18.11.): asetus, levylaskuri ja kirjauksen alkupaino. Keksityt painot.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    settings
      ..program = null
      ..plates = [...defaultPlates]
      ..barKg = defaultBarKg
      ..hexBarKg = null
      ..restTimer = false;
    debugSetCatalog('fi', const {});
  });
  tearDown(() {
    settings
      ..hexBarKg = null
      ..exerciseBars = {};
  });

  test('asetus tiedostoon ja takaisin; puuttuva = ei asetettu', () {
    settings.hexBarKg = 22;
    expect(settings.settingsToMarkdown(), contains('hex_bar: 22'));
    settings.hexBarKg = null;
    settings.applyMarkdown('---\nhex_bar: 27,5\n---\n');
    expect(settings.hexBarKg, 27.5);
    settings.hexBarKg = null;
    expect(settings.settingsToMarkdown(), isNot(contains('hex_bar')));
    expect(isHexBar('Farmer walk hex barilla'), isTrue);
    expect(isBarbell('Farmer walk hex barilla'), isFalse);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SetLoggerScreen(
          date: DateTime(2026, 11, 12),
          entry: ExerciseEntry('Farmer walk hex barilla', null),
          onChanged: () async {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('ilman painoa: alkaa 0 kg:sta, ei levylaskuria, linkki asetukseen', (tester) async {
    await open(tester);
    expect(find.byType(PlateLine), findsNothing);
    expect(find.byKey(const ValueKey('hexBarSet')), findsOneWidget);
  });

  testWidgets('paino asetettu: alkaa tangon painosta ja levylaskuri laskee siitä', (tester) async {
    settings.hexBarKg = 25;
    await open(tester);
    expect(find.byType(PlateLine), findsOneWidget);
    expect(find.text('Pelkkä tanko'), findsOneWidget);
    expect(find.byKey(const ValueKey('hexBarSet')), findsNothing);
    final (ps, rest) = platesPerSide(65, 25, defaultPlates);
    expect(ps, [20.0]);
    expect(rest, 0);
  });

  test('liikekohtainen tanko: tiedostoon ja takaisin, oletus ilman; ei muuta kirjattua treeniä', () {
    settings.exerciseBars = {'Ranteen koukistus tangolla': 10, 'Farmer walk hex barilla': 27.5};
    final md = settings.settingsToMarkdown();
    expect(md, contains('exercise_bars: Ranteen koukistus tangolla=10; Farmer walk hex barilla=27,5'));
    settings.exerciseBars = {};
    settings.applyMarkdown(
      '---\nexercise_bars: Ranteen koukistus tangolla=10; roska; X=-3; Farmer walk hex barilla=27,5\n---\n',
    );
    expect(settings.exerciseBars, {'Ranteen koukistus tangolla': 10.0, 'Farmer walk hex barilla': 27.5});
    expect(barFor('Ranteen koukistus tangolla'), 10);
    expect(barFor('Takakyykky'), defaultBarKg, reason: 'muut liikkeet käyttävät oletusta');
    expect(barFor('Farmer walk hex barilla', hex: true), 27.5, reason: 'liikkeen oma ohittaa puuttuvan oletuksen');
    // Kirjattu treeni on sama tangosta riippumatta (sarjat ovat kokonaispainoja).
    final w = Workout(date: DateTime(2026, 11, 12), title: 'Treeni')
      ..exercises.add(ExerciseEntry('Ranteen koukistus tangolla', [SetEntry(25, 12)]));
    final before = workoutToMarkdown(w);
    settings.setExerciseBar('Ranteen koukistus tangolla', 15);
    expect(workoutToMarkdown(w), before);
    settings.setExerciseBar('Ranteen koukistus tangolla', null);
    expect(settings.exerciseBars.containsKey('Ranteen koukistus tangolla'), isFalse);
  });

  testWidgets('levyrivi laskee liikkeen omasta tangosta', (tester) async {
    settings.exerciseBars = {'Ranteen koukistus tangolla': 10};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlateLine(kg: 10, exercise: 'Ranteen koukistus tangolla')),
      ),
    );
    expect(find.text('Pelkkä tanko'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PlateLine(kg: 10))));
    expect(find.textContaining('Kevyempi kuin tanko'), findsOneWidget, reason: 'oletustanko 20 kg');
  });
}
