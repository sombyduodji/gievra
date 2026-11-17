import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/sami_material.dart';

// Saame: Flutterin omat tekstit (myös ruudunlukijan lukemat) eivät jää suomeksi.
void main() {
  testWidgets('Saamen Material-tekstit: ponnahdusikkunan tausta, järjestely, aikavalitsin, lisenssit', (tester) async {
    late MaterialLocalizations l;
    late WidgetsLocalizations w;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('se'),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (c) {
            l = MaterialLocalizations.of(c);
            w = WidgetsLocalizations.of(c);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(l.modalBarrierDismissLabel, 'Gidde', reason: 'ennen "Ohita"');
    expect(w.reorderItemUp, 'Sirdde bajás', reason: 'ruudunlukijan järjestelyteksti');
    expect(w.noResultsFound, 'Ii gávdnon mihkkege');
    expect(l.timePickerHourLabel, 'Diibmu');
    expect(l.licensesPackageDetailText(3), '3 liseanssa');
    expect(l.remainingTextFieldCharacterCount(1), '1 mearka báhcá');
    expect(l.dateRangeStartDateSemanticLabel('1.1.2026'), 'Álgobeaivi 1.1.2026');
    expect(l.tabLabel(tabIndex: 2, tabCount: 3), 'Siidu 2 / 3');
    // Suomenkielisiä Flutterin tekstejä ei jää näkyviin (näppäimistön näppäimiä lukuun ottamatta).
    final fi = ['Ohita', 'Siirrä', 'Tallenna', 'Jatka', 'Tänään', 'Valitse', 'Lisenssit', 'sivu'];
    final shown = [
      l.modalBarrierDismissLabel,
      w.reorderItemDown,
      w.selectAllButtonLabel,
      l.saveButtonLabel,
      l.continueButtonLabel,
      l.currentDateLabel,
      l.timePickerHourModeAnnouncement,
      l.licensesPageTitle,
      l.nextPageTooltip,
      l.scrimOnTapHint('x'),
      l.dialogLabel,
      l.alertDialogLabel,
      l.popupMenuLabel,
      l.bottomSheetLabel,
    ];
    for (final s in shown) {
      for (final w in fi) {
        expect(s.contains(w), isFalse, reason: '"$s" sisältää suomea ($w)');
      }
    }
  });
}
