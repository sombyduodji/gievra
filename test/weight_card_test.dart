import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/home.dart';

// Etusivun painokortti katoaa heti tallennuksen jälkeen (ei vasta näkymää vaihdettaessa).
void main() {
  testWidgets('aamupainopainike: dialogi, ja rivi katoaa heti merkinnän ja ohituksen jälkeen', (t) async {
    final dir = Directory.systemTemp.createTempSync('paino');
    settings
      ..folder = dir.path
      ..bodyTracker = true
      ..bodySkipped = null
      ..body = BodyLog();
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: WeightTodayCard())));
    expect(find.byType(TextField), findsNothing); // vain painike, ei syöttökenttää etusivulla
    await t.tap(find.text('Merkitse aamupaino'));
    await t.pumpAndSettle();
    expect(find.text('Aamupaino'), findsOneWidget);
    await t.enterText(find.byType(TextField), '-82.4'); // miinus suodattuu, piste käy
    await t.tap(find.text('OK'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.text('Merkitse aamupaino'), findsNothing);
    expect(settings.body.weights[dateOnly(DateTime.now())], 82.4);

    settings.body = BodyLog();
    settings.notifyListeners();
    await t.pump();
    expect(find.text('Merkitse aamupaino'), findsOneWidget);
    await t.tap(find.text('Ohita'));
    await t.pump();
    expect(find.text('Merkitse aamupaino'), findsNothing);
    settings
      ..folder = null
      ..bodyTracker = false
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
