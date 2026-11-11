import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/import_export.dart';

// Tuonnin yhteenveto: varmuuskopion vammatila kysytään, kun yhdistetään käytössä olevaan päiväkirjaan.
// Keksityt tiedot.
void main() {
  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    debugSetCatalog('fi', const {});
    store.workouts = [];
    settings.injuries = [];
  });

  ImportResult backup(List<String> injuries) => ImportResult(
    source: 'Gievra',
    workouts: [Workout(date: DateTime(2026, 11, 3), title: 'Koko keho A')],
    settingsMd: '## Vammat\n${injuries.map((i) => '- $i').join('\n')}\n',
  );

  Future<void> open(WidgetTester tester, ImportResult r) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    // Testifontti (Ahem) on leveämpi kuin oikea: yhteenvedon aikaväli-rivi ei mahdu (ei liity vammatilaan).
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    await tester.pumpWidget(MaterialApp(home: ImportExportScreen()));
    await tester.pump();
    (tester.state(find.byType(ImportExportScreen)) as dynamic).previewForTest(r);
    await tester.pumpAndSettle();
  }

  for (final l in ['fi', 'en', 'se']) {
    testWidgets('Vammatilan valinta yhteenvedossa ($l): oletuksena pois, vain uudet alueet', (tester) async {
      debugSetCatalog(l, l == 'fi' ? const {} : po[l]!, english: po['en']);
      store.workouts = [Workout(date: DateTime(2026, 10, 1), title: 'Oma')];
      settings.injuries = ['ranne'];
      await open(tester, backup(['polvi_kierukka_ristiside', 'ranne']));
      final box = find.widgetWithText(CheckboxListTile, t('Ota vammatila käyttöön'));
      expect(box, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(box).value, isFalse);
      // Lyhyt nimi, ei jo valittua rannetta.
      final sub = t('Varmuuskopiossa: {0}. Valitse vain, jos vaiva on yhä ajankohtainen.', [
        l == 'en' ? 'Knee' : 'Polvi',
      ]);
      expect(find.text(sub), findsOneWidget);
      await tester.tap(box);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(box).value, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Ei valintaa uuteen puhelimeen eikä, kun alueet ovat jo valittuna', (tester) async {
    await open(tester, backup(['polvi_etu']));
    expect(find.text('Ota vammatila käyttöön'), findsNothing, reason: 'tyhjä päiväkirja: palautetaan sellaisinaan');
    Navigator.of(tester.element(find.text('Peruuta'))).pop();
    await tester.pumpAndSettle();
    store.workouts = [Workout(date: DateTime(2026, 10, 1), title: 'Oma')];
    settings.injuries = ['polvi_etu'];
    await open(tester, backup(['polvi_etu']));
    expect(find.text('Ota vammatila käyttöön'), findsNothing);
  });
}
