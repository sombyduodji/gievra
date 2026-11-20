import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/drawer.dart' show NotificationsBlockedTile;

void main() {
  testWidgets('Ilmoitukset estetty -rivi näkyy vain ilman lupaa', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NotificationsBlockedTile(check: () async => false)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notificationsBlocked')), findsOneWidget);
    expect(find.text('Ilmoitukset estetty'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationsBlockedTile(key: UniqueKey(), check: () async => true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notificationsBlocked')), findsNothing);
  });
}
