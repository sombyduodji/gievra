import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/home_layout.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart';
import 'package:treenipaivakirja/ui/recovery_stats.dart';

// Tilastot → Palautuminen ja uni (käyttäjä 18.11.): kehitys ajan mittaan, vain kun ominaisuus on käytössä.
// Keksityt yöt.
void main() {
  final today = dateOnly(DateTime.now());

  test('viikkokeskiarvot ja 4 viikon muutos', () {
    final d = {for (var i = 0; i < 56; i++) addDays(today, -i): i < 28 ? 40.0 : 36.0};
    final (now, before) = fourWeekChange(d, today)!;
    expect(now, 40);
    expect(before, 36);
    final w = weeklyAverages(d, today);
    expect(w.length, 12);
    expect(w.last, 40);
    expect(fourWeekChange({today: 1}, today), isNull);
  });

  testWidgets('näkyy vain, kun Palautuminen, Uni tai yöarvot on käytössä; HRV:n nousu vihreänä', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    settings.homeHidden = {...homeCardsOffByDefault};
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: RecoveryTrendsSection())),
      ),
    );
    expect(find.byKey(const ValueKey('recoveryTrends')), findsNothing, reason: 'ei käytössä');
    NightHrData.debugNights = {for (var i = 0; i < 56; i++) addDays(today, -i): i < 28 ? 50 : 54};
    sleepData.metrics
      ..clear()
      ..addAll({for (var i = 0; i < 56; i++) addDays(today, -i): NightMetrics(hrv: i < 28 ? 42 : 36)});
    settings.homeHidden = {'sleep'}; // Palautuminen ja yöarvot päällä
    await tester.pump();
    expect(find.byKey(const ValueKey('recoveryTrends')), findsOneWidget);
    expect(find.byKey(const ValueKey('trend_nighthr')), findsOneWidget);
    expect(find.byKey(const ValueKey('trend_hrv')), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget, reason: 'HRV nousi');
    expect(find.byIcon(Icons.trending_down), findsOneWidget, reason: 'yösyke laski');
    expect(tester.takeException(), isNull);
    settings.homeHidden = {...homeCardsOffByDefault};
    NightHrData.debugNights = const {};
    sleepData.metrics.clear();
  });
}
