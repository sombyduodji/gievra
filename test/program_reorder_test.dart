import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/program_view.dart';

// Käyttäjä 16.11.: ohjelman liikkeiden järjestys ilman poistoa ja uudelleen lisäystä (vetämällä tai Siirrä ylös / alas).
void main() {
  Program program() => Program(
    goal: 'voima',
    experience: 'keski',
    days: 1,
    minutes: 60,
    start: DateTime(2026, 11, 2),
    deloadEvery: 0,
    plan: [
      PlanDay('Koko keho A', [
        PlanItem('Penkkipunnerrus', 'VTY', 3, 5, 5, '1–2', 180),
        PlanItem('Takakyykky', 'KY', 3, 5, 5, '1–2', 180),
        PlanItem('Hauiskääntö tangolla', 'HA', 2, 10, 15, '0–2', 90),
      ]),
    ],
  );
  List<String> names(Program p) => [for (final i in p.plan.first.items) i.exercise];

  Future<void> pump(WidgetTester tester, Program p, VoidCallback changed) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ProgramView(program: p, header: 'Ohjelma', onChanged: () => setState(changed)),
          ),
        ),
      ),
    );
  }

  testWidgets('Siirrä alas ja ylös liikkeen ikkunasta', (tester) async {
    final p = program();
    var n = 0;
    await pump(tester, p, () => n++);
    await tester.scrollUntilVisible(find.text('Penkkipunnerrus'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Penkkipunnerrus').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Siirrä alas'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byTooltip('Siirrä alas'));
    await tester.pump();
    expect(names(p), ['Takakyykky', 'Penkkipunnerrus', 'Hauiskääntö tangolla']);
    await tester.tap(find.byTooltip('Siirrä alas'));
    await tester.pump();
    expect(names(p).last, 'Penkkipunnerrus');
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_downward)).onPressed,
      isNull,
      reason: 'viimeinen: ei alemmas',
    );
    await tester.tap(find.byTooltip('Siirrä ylös'));
    await tester.pump();
    await tester.tap(find.text('Valmis'));
    await tester.pumpAndSettle();
    expect(names(p), ['Takakyykky', 'Penkkipunnerrus', 'Hauiskääntö tangolla']);
    expect(n, greaterThan(0), reason: 'muutos tallennetaan');
  });

  testWidgets('Vetämällä kahvasta', (tester) async {
    final p = program();
    await pump(tester, p, () {});
    await tester.scrollUntilVisible(find.text('Hauiskääntö tangolla'), 300, scrollable: find.byType(Scrollable).first);
    final handles = find.byIcon(Icons.drag_indicator);
    expect(handles, findsNWidgets(3));
    final g = await tester.startGesture(tester.getCenter(handles.at(2)));
    await tester.pump();
    for (var k = 0; k < 10; k++) {
      await g.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(names(p).first, 'Hauiskääntö tangolla');
  });

  testWidgets('Päivän lisäys ja poisto; treenipäiviä viikossa seuraa (käyttäjä 16.11.)', (tester) async {
    final p = program();
    await pump(tester, p, () {});
    expect(find.byTooltip('Poista päivä'), findsNothing, reason: 'viimeistä päivää ei voi poistaa');
    await tester.scrollUntilVisible(find.text('Lisää päivä'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Lisää päivä'));
    await tester.pumpAndSettle();
    expect(p.plan.length, 2);
    expect(p.days, 2, reason: 'päiviä oli yhtä monta kuin treenipäiviä viikossa');
    expect(p.plan.last.items, isEmpty);
    expect(p.plan.last.uiName, 'Päivä 2');
    final del = find.byTooltip('Poista päivä');
    expect(del, findsNWidgets(2));
    await tester.tap(del.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(p.plan.length, 2);
    await tester.tap(del.first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Poista'));
    await tester.pumpAndSettle();
    expect(p.plan.single.uiName, 'Päivä 2');
    expect(p.days, 1);
  });
}
