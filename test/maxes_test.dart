import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/maxes_editor.dart';
import 'package:treenipaivakirja/ui/program_screen.dart';

void main() {
  testWidgets('Muokkaa ennätyksiä: muutos tallentuu ohjelmaan, ohjelma muuten ennallaan', (tester) async {
    final dir = Directory.systemTemp.createTempSync('gievra-maksimit');
    settings.folder = dir.path;
    final p = generateProgram(goal: 'voima', experience: 'keski', days: 3, minutes: 60, injuries: const [])
      ..maxes = {'Takakyykky': 100, 'Penkkipunnerrus': 80};
    await tester.runAsync(() => settings.setProgram(p));
    final days = p.plan.map((d) => d.name).toList();

    await tester.pumpWidget(const MaterialApp(home: MaxesScreen()));
    expect(find.text('100 kg'), findsOneWidget);
    // Takakyykky 100 -> 105
    await tester.tap(find.text('Takakyykky'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '105');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // Penkkipunnerrus pois
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(find.text('105 kg'), findsOneWidget);
    await tester.tap(find.text('Tallenna ✓'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(settings.program!.maxes, {'Takakyykky': 105});
    expect(settings.program!.plan.map((d) => d.name).toList(), days);
    // Tiedostoon kirjoitettava muoto (kirjoitus itse on testattu muualla).
    final md = programToMarkdown(settings.program!);
    expect(md, contains('Takakyykky=105'));
    expect(md, isNot(contains('Penkkipunnerrus=')));
    settings.folder = null;
    dir.deleteSync(recursive: true);
  });

  testWidgets('Ohjelma ja tavoitteet: Muokkaa ennätyksiä avaa ennätysnäkymän', (tester) async {
    final dir = Directory.systemTemp.createTempSync('gievra-maksimit2');
    settings.folder = dir.path;
    final p = generateProgram(goal: 'voima', experience: 'keski', days: 3, minutes: 60, injuries: const [])
      ..maxes = {'Takakyykky': 100};
    await tester.runAsync(() => settings.setProgram(p));
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ProgramScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Muokkaa ennätyksiä'), 300);
    await tester.tap(find.text('Muokkaa ennätyksiä'));
    await tester.pumpAndSettle();
    expect(find.byType(MaxesScreen), findsOneWidget);
    expect(find.text('100 kg'), findsOneWidget);
    settings.folder = null;
    dir.deleteSync(recursive: true);
  });
}
