import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/maps/elevation.dart';
import 'package:treenipaivakirja/ui/elevation_chart.dart';

// Korkeuskaavion kilometrivauhdit: viimeisen vajaan kilometrin teksti pysyy kaavion sisällä. Keksitty reitti.
void main() {
  testWidgets('Viimeisen vajaan kilometrin vauhti ei mene oikean reunan yli', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    // 3,2 km: kolme täyttä kilometriä ja 200 m.
    const profile = ElevationProfile(
      [(0, 20), (1600, 35), (3200, 25)],
      15,
      10,
      1,
      splits: [(0, 1000, 330), (1000, 1000, 340), (2000, 1000, 335), (3000, 200, 75)],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ElevationCard(profile))),
      ),
    );
    // Kaavio täyttää leveyden reunuksia (16 px) lukuun ottamatta.
    final right = tester.getSize(find.byType(Scaffold)).width - 16;
    final last = find.text('6:15');
    expect(last, findsOneWidget);
    final r = tester.getRect(last);
    expect(r.right, lessThanOrEqualTo(right + 0.5));
    // Edellisen kilometrin teksti (keskitetty) jää riittävän kauas.
    expect(r.center.dx - tester.getRect(find.text('5:35')).center.dx, greaterThanOrEqualTo(34));
    expect(tester.takeException(), isNull);
  });
}
