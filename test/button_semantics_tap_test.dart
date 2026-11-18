import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/ui/kcal_card.dart';
import 'package:treenipaivakirja/ui/start_panels.dart';

// Yötesti 18.11.: painikkeet, joiden Semantics(excludeSemantics: true) korvaa lapsen (InkWell), tarvitsevat oman
// napautustoiminnon. Ilman sitä Androidin saavutettavuuspuussa clickable=false (uiautomator, Samsung): TalkBackin
// kaksoisnapautus ei osunut Sali/Liikunta-painikkeisiin eikä alapalkin välilehtiin.
void main() {
  setUpAll(() {
    final tmp = Directory.systemTemp.createTempSync('gievra-sem').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp,
    );
  });

  testWidgets('Sali | Liikunta -painikkeilla on napautustoiminto saavutettavuuspuussa', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final handle = tester.ensureSemantics();
    store.workouts = [];
    settings.trainMode = 'both';
    addTearDown(() => settings.trainMode = 'gym');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StartSplitButton())));
    final nodes = [
      for (final k in ['homeStartGym', 'homeStartActivity']) tester.getSemantics(find.byKey(ValueKey(k))),
    ];
    expect(nodes.map((n) => n.label.split(',').first), ['Sali', 'Liikunta']);
    for (final n in nodes) {
      expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: n.label);
    }
    handle.dispose();
  });

  testWidgets('kalorirenkaan napautus (kellon tiedot) on saavutettavuuspuussa', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KcalRing(total: 420, active: 300, onTap: () => taps++)),
      ),
    );
    final n = tester.getSemantics(find.byKey(const ValueKey('kcalRing')));
    expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(find.byKey(const ValueKey('kcalRing')));
    expect(taps, 1);
    handle.dispose();
  });
}
