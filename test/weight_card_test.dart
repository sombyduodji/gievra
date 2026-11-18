import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/home.dart';

// Etusivun painokortti katoaa heti tallennuksen jälkeen (ei vasta näkymää vaihdettaessa).
void main() {
  testWidgets('aamupaino etusivun kysymyksenä (ei ikkunaa); kortti vain asetuksella Painon kehitys etusivulla', (
    t,
  ) async {
    final dir = Directory.systemTemp.createTempSync('paino');
    settings
      ..folder = dir.path
      ..bodyTracker = true
      ..introDone = true
      ..weightOnHome = false
      ..bodySkipped = null
      ..body = BodyLog();
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: Column(children: [MorningWeightCard(), WeightTodayCard()])),
        ),
      ),
    );
    // Ilman asetusta ei korttia etusivulla (käyttäjä 17.11.).
    expect(find.byKey(const ValueKey('weightCard')), findsNothing);
    // Kysymys näkyy etusivulla, ei ponnahdusikkunana (käyttäjä 18.11.).
    expect(find.byKey(const ValueKey('morningWeight')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // Väärä arvo: virhe, ei tallennu.
    await t.enterText(find.byKey(const ValueKey('morningWeightField')), '5');
    await t.tap(find.byKey(const ValueKey('morningWeightSave')));
    await t.pump();
    expect(find.text('Anna paino 20–400 kg.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('morningWeightField')), '-82.4'); // miinus suodattuu, piste käy
    await t.tap(find.byKey(const ValueKey('morningWeightSave')));
    await t.tap(find.byKey(const ValueKey('morningWeightSave'))); // tuplanapautus
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(settings.body.weights[dateOnly(DateTime.now())], 82.4);
    // Punnittu: kysymys poistuu.
    expect(find.byKey(const ValueKey('morningWeight')), findsNothing);
    // Ei tänään: piilottaa tältä päivältä.
    settings.body = BodyLog();
    settings.setWeightOnHome(false); // ilmoittaa muutoksesta
    await t.pump();
    expect(find.byKey(const ValueKey('morningWeight')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('morningWeightSkip')));
    await t.pump();
    expect(settings.bodySkipped, isoDate(dateOnly(DateTime.now())));
    expect(find.byKey(const ValueKey('morningWeight')), findsNothing);
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
