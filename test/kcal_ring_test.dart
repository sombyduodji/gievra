import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/kcal_card.dart';

// Kalorit renkaana (käyttäjä 17.11., luonnos A): kokonaiskulutus keskellä, aktiiviset ja lepokulutus vieressä.
void main() {
  testWidgets('rengas: kokonaiskulutus, aktiiviset ja lepokulutus; suuri teksti ja kapea näyttö ilman ylivuotoa', (
    tester,
  ) async {
    for (final (width, scale) in [(360.0, 1.0), (320.0, 2.0)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SizedBox(width: width - 32, child: const KcalRing(total: 1254, active: 1005)),
            ),
          ),
        ),
      );
      expect(find.text('1254'), findsOneWidget);
      expect(find.text('1005 aktiivisia'), findsOneWidget);
      expect(find.text('249 lepokulutusta'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'leveys $width, teksti $scale×');
    }
  });

  testWidgets('aktiiviset suurempi kuin kokonaiskulutus (käsin kirjattu): lepo ei negatiivinen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KcalRing(total: 100, active: 120))));
    expect(find.text('0 lepokulutusta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
