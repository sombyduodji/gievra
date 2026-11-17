import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/ui/drawer.dart' show MoreScreen;

// Lisää-välilehden otsikko vaihtuu kielen mukana (tarkistus 17.11.: englanniksi vaihdon jälkeen otsikko jäi "Lisää").
void main() {
  testWidgets('kielen vaihto päivittää Lisää-välilehden otsikon', (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => tester.runAsync(() => settings.setLang('fi')));
    await tester.runAsync(() => settings.setLang('fi'));
    await tester.pumpWidget(const MaterialApp(home: MoreScreen()));
    expect(find.text('Lisää'), findsOneWidget);
    await tester.runAsync(() => settings.setLang('en'));
    await tester.pump();
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Lisää'), findsNothing);
  });
}
