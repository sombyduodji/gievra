import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/main.dart';
import 'package:treenipaivakirja/models.dart';

void main() {
  test('Vanha sports-asetus -> treenitila; mode voittaa', () {
    final s = Settings()..applyMarkdown('---\nname: A\nsports: true\n---\n');
    expect(s.trainMode, 'both');
    expect(s.sports, isTrue);
    final g = Settings()..applyMarkdown('---\nname: A\nsports: false\n---\n');
    expect(g.trainMode, 'gym');
    final c = Settings()..applyMarkdown('---\nname: A\nsports: true\nmode: cardio\n---\n');
    expect(c.trainMode, 'cardio');
    final md = c.settingsToMarkdown();
    expect(md, contains('mode: cardio'));
    expect(md, contains('sports: true')); // vanhemmat versiot näkevät liikunnan
    expect((Settings()..applyMarkdown(md)).trainMode, 'cardio');
  });

  testWidgets('Etusivu: Molemmat-tilassa Sali / Kestävyys -valinta, muuten ei', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    settings
      ..name = 'Testi'
      ..introDone = true
      ..program = null
      ..trainMode = 'both'
      ..homeView = 'gym';
    store.workouts = [
      Workout(date: DateTime.now(), title: 'Juoksu', activity: 'Juoksu', distanceKm: 6, seconds: 1800, minutes: 30),
    ];
    await tester.pumpWidget(const TreeniApp());
    await tester.pump();
    expect(find.text('Kestävyys'), findsOneWidget);
    expect(find.text('Lisää lenkki'), findsNothing);
    await tester.tap(find.text('Kestävyys'));
    await tester.pump();
    expect(settings.homeView, 'cardio');
    expect(find.text('Lisää lenkki'), findsOneWidget);
    expect(find.text('6 km'), findsOneWidget); // tämän viikon kilometrit
    // Pelkkä sali: ei valintaa, vanha etusivu.
    settings.setTrainMode('gym');
    await tester.pump();
    expect(find.text('Kestävyys'), findsNothing);
    expect(find.text('Lisää lenkki'), findsNothing);
    // Pelkkä kestävyys: ei valintaa, kestävyysnäkymä.
    settings.setTrainMode('cardio');
    await tester.pump();
    expect(find.text('Kestävyys'), findsNothing);
    expect(find.text('Lisää lenkki'), findsOneWidget);
    settings.trainMode = 'gym';
    store.workouts = [];
  });
}
