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

  testWidgets('Päivän toisen treenin poisto: kysymys nimeää oikean tiedoston, ensimmäinen säilyy', (tester) async {
    final d = dateOnly(DateTime.now());
    final first = Workout(
      date: d,
      title: 'Koko keho A',
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(60, 8)]),
      ],
    );
    final second = Workout(
      date: d,
      session: 2,
      title: 'Koko keho B',
      exercises: [
        ExerciseEntry('Maastaveto', [SetEntry(20, 10, warmup: true)]),
      ],
    );
    await tester.runAsync(() async {
      await store.save(first);
      await store.save(second);
    });
    final f1 = File('${dir.path}/${store.fileName(d)}'), f2 = File('${dir.path}/${store.fileName(d, 2)}');
    expect(f2.existsSync(), isTrue);
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: second)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poista treeni'));
    await tester.pumpAndSettle();
    // Ennen kysymys nimesi aina päivän ensimmäisen tiedoston (vvvv-kk-pp.md).
    expect(find.text('Tiedosto ${isoDate(d)}-2.md poistetaan.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Poista'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(f2.existsSync(), isFalse);
    expect(f1.existsSync(), isTrue);
  });
}
