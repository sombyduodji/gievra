import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Keskeneräisen salitreenin poisto ⋮-valikosta: ennen sivulta poistuminen (dispose) tallensi treenin
// uudelleen, ja poistettu treeni palasi etusivulle. Keksitty treeni.
void main() {
  late Directory dir;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('gievra-del');
    settings.folder = dir.path;
  });
  tearDown(() {
    settings.folder = null;
    store.workouts = [];
    dir.deleteSync(recursive: true);
  });

  testWidgets('Poistettu treeni ei palaa, kun sivulta poistutaan', (tester) async {
    final w = Workout(
      date: dateOnly(DateTime.now()),
      title: 'Koko keho B',
      exercises: [
        ExerciseEntry('Maastaveto', [SetEntry(20, 10, warmup: true)]),
      ],
    );
    final file = File('${dir.path}/${store.fileName(w.date)}');
    await tester.runAsync(() => store.save(w));
    expect(file.existsSync(), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutScreen(workout: w))),
            child: const Text('avaa'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poista treeni'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Poista'));
    for (var i = 0; i < 10 && find.byType(WorkoutScreen).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsNothing);
    // Annetaan mahdolliselle dispose-tallennukselle aikaa valmistua.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(store.onDay(w.date), isEmpty, reason: 'ei treeniä muistissa');
    expect(file.existsSync(), isFalse, reason: 'dispose ei saa tallentaa poistettua treeniä');
  });
}
