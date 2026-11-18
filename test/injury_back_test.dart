import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/injury_screen.dart';

// Vammatila: Takaisin ruksin jälkeen kysyy (Hylkää / Peruuta / Tallenna); ennen valinta hylättiin hiljaa (yötesti 15.11.).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings.program = null;
  });

  Future<GlobalKey<NavigatorState>> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Text('pohja')));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const InjuryScreen(initial: [])));
    await tester.pumpAndSettle();
    return nav;
  }

  Future<void> tick(WidgetTester tester) async {
    final first = find.byType(Checkbox).first;
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pump();
  }

  testWidgets('Ei muutoksia: Takaisin poistuu kysymättä', (tester) async {
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(InjuryScreen), findsNothing);
  });

  testWidgets('Ruksin jälkeen Takaisin kysyy; Peruuta jää, Hylkää poistuu tallentamatta', (tester) async {
    settings.setInjuries(const []);
    await open(tester);
    await tick(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Tallennetaanko muutokset?'), findsOneWidget);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(find.byType(InjuryScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hylkää'));
    await tester.pumpAndSettle();
    expect(find.byType(InjuryScreen), findsNothing);
    expect(settings.injuries, isEmpty);
  });

  testWidgets('Ruksin jälkeen Takaisin → Tallenna tallentaa valinnan', (tester) async {
    settings.setInjuries(const []);
    await open(tester);
    await tick(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tallenna'));
    await tester.pumpAndSettle();
    expect(find.byType(InjuryScreen), findsNothing);
    expect(settings.injuries, [injuryRegions.first.id]);
  });

  testWidgets('yötesti 18.11.: alueen valintaruudulla on alueen nimi saavutettavuuspuussa', (tester) async {
    final sem = tester.ensureSemantics();
    await open(tester);
    final first = find.byType(Checkbox).first;
    expect(tester.getSemantics(first).getSemanticsData().label, t(injuryRegions.first.name));
    sem.dispose();
  });
}
