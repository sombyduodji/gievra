import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/widgets.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Keksitty treeni (ei oikeita tietoja).
Workout _done() => Workout(
  date: DateTime(2026, 11, 7),
  title: 'Koko keho A',
  exercises: [
    ExerciseEntry('Takakyykky', [SetEntry(60, 8), SetEntry(80, 6)]),
  ],
)..minutes = 52;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Valmis treeni avautuu lukutilaan; napautus kysyy ennen muokkausta', (tester) async {
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: _done())));
    await tester.pump();
    expect(find.byType(LockButton), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Treeni valmis!'), findsNothing);

    // Napautus liikkeeseen: kysymys, Peruuta pitää lukutilan.
    await tester.tap(find.text('Takakyykky'));
    await tester.pumpAndSettle();
    expect(find.text('Muokataanko tallennettua treeniä?'), findsOneWidget);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(find.byType(LockButton), findsOneWidget);

    // Muokkaa: lukutila pois, liikkeen lisäys ja Treeni valmis näkyvät.
    await tester.tap(find.text('Takakyykky'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Muokkaa'));
    await tester.pumpAndSettle();
    expect(find.byType(LockButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Treeni valmis!'), findsOneWidget);
  });

  testWidgets('Keskeneräinen treeni ei ole lukittu', (tester) async {
    final w = _done()..minutes = null;
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: w)));
    await tester.pump();
    expect(find.byType(LockButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
