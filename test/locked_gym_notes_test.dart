import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/widgets.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Tallennetun salitreenin muistiinpanot ovat muokattavissa ilman "Muokataanko?"-kysymystä (yötesti 27.11. Nothing:
// kysymyksen jälkeen kenttä ei saanut fokusta ja lista hyppäsi). Muistiinpanon pituusraja ja numeroiden sidonta.
// Keksityt tiedot.
Workout _done() => Workout(
  date: DateTime(2026, 11, 7),
  title: 'Koko keho A',
  exercises: [
    ExerciseEntry('Takakyykky', [SetEntry(60, 8)]),
  ],
)..minutes = 52;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Lukitun salitreenin muistiinpanot: ei kysymystä, kenttä saa fokuksen, lukitus pysyy', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: WorkoutScreen(workout: _done())));
    await tester.pump();
    expect(find.byType(LockButton), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notes')));
    await tester.pumpAndSettle();
    expect(find.text('Muokataanko tallennettua treeniä?'), findsNothing);
    final editable = find.descendant(of: find.byKey(const ValueKey('notes')), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.enterText(find.byKey(const ValueKey('notes')), 'polvi ok');
    await tester.pump();
    expect(find.text('polvi ok'), findsOneWidget);
    // Muu sisältö pysyy lukittuna.
    expect(find.byType(LockButton), findsOneWidget);
    await tester.tap(find.text('Takakyykky'));
    await tester.pumpAndSettle();
    expect(find.text('Muokataanko tallennettua treeniä?'), findsOneWidget);
  });

  test('Muistiinpanon raja: vanha pidempi teksti ei saa rajaa', () {
    expect(notesLimit('lyhyt'), notesMaxLength);
    expect(notesLimit('x' * (notesMaxLength + 1)), isNull);
  });

  test('bindNumbers: väli ja varaus eivät katkea', () {
    expect(bindNumbers('3 × 6–10 · varaa 2–3'), '3\u00A0×\u00A06–\u206010\u00A0· varaa\u00A02–\u20603');
  });
}
