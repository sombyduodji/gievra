import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/watch.dart';

// Kellon tietojen käsin syöttö: mahdoton syke ei mene läpi (yötesti 21.11., Nothing: keskisyke 999 näytti
// "Rasitus: kova, 558 % maksimisykkeestä"). 0 tyhjentää edelleen. Keksityt tiedot.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Keskisyke 999 hylätään, 150 ja 0 käyvät', (tester) async {
    final w = Workout(date: DateTime(2026, 11, 20), title: 'Koripallo', activity: 'Koripallo', session: 2)
      ..seconds = 3600;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WatchCard(w: w, onChanged: () {}),
        ),
      ),
    );
    Future<void> enter(String v) async {
      await tester.tap(find.text('keskisyke'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), v);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    await enter('999');
    expect(find.text('Sallittu 0–250'), findsOneWidget, reason: 'ikkuna jää auki ja kertoo rajat');
    expect(w.hrAvg, isNull);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    await enter('150');
    expect(w.hrAvg, 150);
    await enter('0');
    expect(w.hrAvg, isNull);
  });
}
