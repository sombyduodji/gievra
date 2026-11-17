import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';

// Keksityt treenit (ei oikeita tietoja).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => store.workouts = []);

  testWidgets('Tilastojen välilehdet: Viikko, Kehitys, Ennätykset ja Kalenteri; ennätys arvioituna maksimina', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    store.workouts = [
      Workout(
        date: d,
        title: 'Koko keho A',
        exercises: [
          ExerciseEntry('Takakyykky', [SetEntry(100, 5), SetEntry(90, 8)]),
        ],
      )..minutes = 50,
      Workout(
        date: d.subtract(const Duration(days: 60)),
        title: 'Koko keho A',
        exercises: [
          ExerciseEntry('Takakyykky', [SetEntry(80, 5)]),
        ],
      )..minutes = 45,
    ];
    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    await tester.pumpAndSettle();
    for (final l in ['Viikko', 'Kehitys', 'Ennätykset', 'Kalenteri']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    // Viikko: tämän viikon treeni ja sarjat.
    expect(find.text('Tämä viikko'), findsOneWidget);
    expect(find.text('Koko keho A'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // sarjaa
    // Edellinen viikko ja takaisin.
    await tester.tap(find.byKey(const ValueKey('weekPrev')));
    await tester.pumpAndSettle();
    expect(find.text('Ei treenejä tällä viikolla.'), findsOneWidget);

    // Ennätykset: paras arvio 100 × 5 → 117 kg (Epley), uusi-merkki; napautus näyttää kerrat.
    await tester.tap(find.text('Ennätykset'));
    await tester.pumpAndSettle();
    expect(find.text('117 kg'), findsOneWidget);
    expect(find.text('uusi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('record_Takakyykky')));
    await tester.pumpAndSettle();
    expect(find.text('Paras sarja joka kerralta'), findsOneWidget);
    expect(find.text('🏆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
