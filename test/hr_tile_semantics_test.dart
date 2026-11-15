import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/heart_rate.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/drawer.dart';

import 'heart_rate_test.dart' show FakeHr;

// TalkBack: Asetukset → Keho ja laitteet → Sykevyö -rivi on oma painikkeensa, ei koko listan kokoinen alue,
// jonka sisällä viereiset kytkimet ovat (yötesti 13.–14.11).
void main() {
  testWidgets('Sykevyö-rivin semanttinen alue on vain rivi', (tester) async {
    debugSetCatalog('fi', const {});
    hrDeviceMemory = {};
    hr.source = FakeHr();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final h = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.text('Keho ja laitteet'));
    await tester.pumpAndSettle();
    final n = tester.getSemantics(find.byKey(const ValueKey('hrTile')));
    expect(n.label, startsWith('Sykevyö'));
    expect(n.rect.height, lessThan(150), reason: 'rivi, ei koko lista: ${n.rect}');
    expect(n.hasChildren, isFalse, reason: 'ei muita rivejä sisällä');
    h.dispose();
  });
}
