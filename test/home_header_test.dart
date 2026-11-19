import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/widgets.dart';

// Etusivun yläpalkki (käyttäjä 18.11.): saamenkielinen tervehdys ilman nimeä, päivä saameksi ja suomeksi suluissa.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings
      ..started = true
      ..introDone = true;
  });

  for (final (scale, width) in [(1.0, 400.0), (2.0, 360.0)]) {
    testWidgets('ei nimeä, päivä kahdella rivillä; ei ylivuotoa (fontti $scale, $width dp)', (tester) async {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
            child: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      final now = DateTime.now();
      expect(find.text(seGreeting(now)), findsOneWidget);
      expect(find.textContaining('Testi'), findsNothing, reason: 'nimi pois otsikosta');
      expect(find.text('${seWeekdays[now.weekday - 1]} ${now.day}.${now.month}.'), findsOneWidget);
      expect(find.text('(${fiWeekdays[now.weekday - 1]})'), findsOneWidget);
      final a = tester.getTopLeft(find.text('${seWeekdays[now.weekday - 1]} ${now.day}.${now.month}.')).dx;
      final b = tester.getTopLeft(find.text('(${fiWeekdays[now.weekday - 1]})')).dx;
      expect(a, b, reason: 'suomi alkaa samasta kohdasta kuin saame');
      expect(tester.takeException(), isNull);
    });
  }
}
