import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sports.dart';
import 'package:treenipaivakirja/ui/activity.dart';

// Käsin syötetty epäuskottava nopeus (1 km ajassa 0:10) kysytään ennen tallennusta. Keksityt treenit.
void main() {
  test('Rajat lajeittain', () {
    expect(implausibleSpeed('Kävely', 1, 10), isTrue); // 360 km/h
    expect(implausibleSpeed('Kävely', 5, 3600), isFalse);
    expect(implausibleSpeed('Juoksu', 10, 40 * 60), isFalse); // 15 km/h
    expect(implausibleSpeed('Juoksu', 10, 10 * 60), isTrue); // 60 km/h
    expect(implausibleSpeed('Pyöräily', 40, 3600), isFalse);
    expect(implausibleSpeed('Uinti', 1, 60), isTrue); // 60 km/h
    expect(implausibleSpeed('Muu liikunta', 50, 3600), isFalse);
    expect(implausibleSpeed('Kävely', 0, 10), isFalse);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
  });

  testWidgets('Muokkaa palaa muokkaukseen, Tallenna silti jatkaa tallennukseen', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('gievra-nopeus');
    settings.folder = dir.path;
    addTearDown(() {
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    final w = Workout(date: DateTime(2026, 11, 10), title: 'Kävely', activity: 'Kävely', session: 3)
      ..distanceKm = 1
      ..seconds = 10
      ..minutes = 1;
    await tester.pumpWidget(MaterialApp(home: ActivityScreen(workout: w)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('finishActivity')));
    await tester.pumpAndSettle();
    expect(find.text('Tarkista matka ja aika'), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('360 km/h')), findsOneWidget);
    await tester.tap(find.text('Muokkaa'));
    await tester.pumpAndSettle();
    expect(find.text('Tarkista matka ja aika'), findsNothing);
    expect(store.workouts, isEmpty);
    await tester.tap(find.byKey(const ValueKey('finishActivity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tallenna silti'));
    await tester.pumpAndSettle();
    expect(find.text('Tarkista matka ja aika'), findsNothing);
    expect(find.text('Miltä tuntui?'), findsOneWidget, reason: 'tallennus jatkuu fiiliskyselyyn');
  });
}
