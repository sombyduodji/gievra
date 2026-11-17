import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/home.dart';

// Etusivun painokortti katoaa heti tallennuksen jälkeen (ei vasta näkymää vaihdettaessa).
void main() {
  testWidgets('aamupaino kysytään kerran päivässä; kortti vain asetuksella Painon kehitys etusivulla', (t) async {
    final dir = Directory.systemTemp.createTempSync('paino');
    settings
      ..folder = dir.path
      ..bodyTracker = true
      ..introDone = true
      ..weightOnHome = false
      ..bodySkipped = null
      ..body = BodyLog();
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Column(
              children: [
                TextButton(onPressed: () => askDailyWeight(c), child: const Text('avaa')),
                const WeightTodayCard(),
              ],
            ),
          ),
        ),
      ),
    );
    // Ilman asetusta ei korttia etusivulla (käyttäjä 17.11.).
    expect(find.byKey(const ValueKey('weightCard')), findsNothing);
    // Päivän ensimmäinen avaus kysyy painon.
    await t.tap(find.text('avaa'));
    await t.pumpAndSettle();
    expect(find.text('Aamupaino'), findsOneWidget);
    await t.enterText(find.byType(TextField), '-82.4'); // miinus suodattuu, piste käy
    await t.tap(find.text('OK'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(settings.body.weights[dateOnly(DateTime.now())], 82.4);
    // Punnittu: ei kysytä uudelleen.
    await t.tap(find.text('avaa'));
    await t.pumpAndSettle();
    expect(find.text('Aamupaino'), findsNothing);
    // Ei punnitusta, ikkuna suljetaan: ohitus tälle päivälle, ei kysytä toista kertaa.
    settings.body = BodyLog();
    await t.tap(find.text('avaa'));
    await t.pumpAndSettle();
    expect(find.text('Aamupaino'), findsOneWidget);
    await t.tapAt(const Offset(5, 5)); // ikkunan ulkopuolelle
    await t.pumpAndSettle();
    expect(settings.bodySkipped, isoDate(dateOnly(DateTime.now())));
    await t.tap(find.text('avaa'));
    await t.pumpAndSettle();
    expect(find.text('Aamupaino'), findsNothing);
    // Asetuksella kortti näkyy: viimeisin paino.
    await t.runAsync(() => settings.setWeight(dateOnly(DateTime.now()), 81.0));
    settings.setWeightOnHome(true);
    await t.pump();
    expect(find.byKey(const ValueKey('weightCard')), findsOneWidget);
    expect(find.text('81 kg'), findsOneWidget);
    settings
      ..folder = null
      ..bodyTracker = false
      ..weightOnHome = false
      ..bodySkipped = null;
    // Windows pitää juuri kirjoitetun tiedoston hetken lukittuna: odotetaan, eikä siivous saa kaataa testiä.
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException catch (_) {}
    });
  });
}
