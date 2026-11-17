import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/workout.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/program.dart';

// Keksitty treeni (ei oikeita tietoja).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Vammatila: alaselkä + maastaveto → varoitus ja vaihto tähän treeniin ennen sarjoja', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('gievra-vamma');
    settings.folder = dir.path;
    settings.injuries = ['alaselka'];
    addTearDown(() {
      settings.injuries = [];
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    final w = Workout(date: DateTime(2026, 11, 16), title: 'Treeni');
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: w)));
    await tester.pump();
    // Lisää liike → Maastaveto (käyttäjä lisää itse, ohjelmaa ei ole).
    await tester.tap(find.byKey(const ValueKey('addExercise')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'maastaveto');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maastaveto').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('🩹'), findsOneWidget);
    expect(find.byKey(const ValueKey('injuryPick')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('injuryPick')));
    await tester.pumpAndSettle();
    // Liikevalitsin: haku "lantionnosto".
    await tester.enterText(find.byType(TextField).first, 'lantionnosto');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lantionnosto').first);
    for (var k = 0; k < 10; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(w.exercises.map((e) => e.name), ['Lantionnosto']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Jokainen vamma-alue: merkitty liike näyttää varoituksen ja vaihtopainikkeet sarjanäkymässä', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    addTearDown(() => settings.injuries = []);
    final known = [for (final l in allExercises().values) ...l];
    final missing = <String>[];
    var checked = 0;
    for (final r in injuryRegions) {
      settings.injuries = [r.id];
      // Ensin vältettävä liike, muuten muokattava.
      final x =
          known.where((e) => injuryStatus(e, [r.id]).avoid.isNotEmpty).firstOrNull ??
          known.where((e) => injuryStatus(e, [r.id]).flagged).firstOrNull;
      if (x == null) {
        missing.add('${r.id}: ei yhtään merkittyä liikettä');
        continue;
      }
      final st = injuryStatus(x, [r.id]);
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(r.id),
          home: SetLoggerScreen(
            date: DateTime(2026, 11, 16),
            session: 1,
            entry: ExerciseEntry(x),
            onChanged: () async {},
          ),
        ),
      );
      await tester.pump();
      final warn = st.avoid.isNotEmpty ? '⚠️' : '🩹';
      if (find.textContaining(warn).evaluate().isEmpty) missing.add('${r.id}: $x ilman varoitusta $warn');
      if (find.byKey(const ValueKey('injuryPick')).evaluate().isEmpty) {
        missing.add('${r.id}: $x ilman Valitse muu liike');
      }
      if (st.substitute != null && find.byKey(const ValueKey('injurySwap')).evaluate().isEmpty) {
        missing.add('${r.id}: $x ilman Vaihda-painiketta');
      }
      checked++;
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
    expect(checked, injuryRegions.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Treenilista: vammatilan muistutus ylhäällä ja merkityt ohjelman liikkeet (🩹 / ⚠️)', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    settings.program = generateProgram(goal: 'kunto', experience: 'keski', days: 3, minutes: 60, injuries: const []);
    addTearDown(() {
      settings.program = null;
      settings.injuries = [];
    });
    for (final r in injuryRegions) {
      settings.injuries = [r.id];
      final day = settings.program!.plan
          .map((d) => injuryAdjusted(d, [r.id]))
          .where((d) => d.items.any((i) => injuryStatus(i.exercise, [r.id]).flagged))
          .firstOrNull;
      if (day == null) continue;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(r.id),
          home: WorkoutScreen(
            workout: Workout(date: DateTime(2026, 11, 16), title: day.name),
            planDay: day,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('injuryReminder')), findsOneWidget, reason: r.id);
      expect(
        find.textContaining(RegExp('🩹|⚠️')).evaluate().length,
        greaterThan(1),
        reason: '${r.id}: muistutuksen lisäksi vähintään yksi merkitty liike',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
