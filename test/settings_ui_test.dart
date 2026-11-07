import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/main.dart';

void main() {
  testWidgets('Asetusvalikko näyttää uuden valinnan heti (painon lisäys, teema)', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Testifontti (Ahem) on leveämpi kuin oikea: kielivalinnan rivi ei mahdu kapeaan valikkoon.
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    settings.name = 'Testi';
    settings.introDone = true;
    settings.weightStep = 2.5;
    settings.themeMode = ThemeMode.system;
    await tester.pumpWidget(const TreeniApp());
    await tester.pump();
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asetukset'));
    await tester.pumpAndSettle();

    Set<T> selected<T>() => tester.widget<SegmentedButton<T>>(find.byType(SegmentedButton<T>)).selected;
    expect(selected<double>(), {2.5});
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<double>), matching: find.text('5')));
    await tester.pumpAndSettle();
    expect(settings.weightStep, 5);
    expect(selected<double>(), {5});

    await tester.tap(find.text('Tumma'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(selected<ThemeMode>(), {ThemeMode.dark});

    // Palautusajat: +15 s näkyy heti (const-lapsi kuuntelee itse).
    settings.restAdjust = [0, 0, 0];
    settings.setRestTimer(true);
    await tester.pumpAndSettle();
    expect(find.text('3:00'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    expect(settings.restAdjust, [0, 0, 15]);
    expect(find.text('3:15'), findsOneWidget);
    settings.setRestTimer(false);
    settings.restAdjust = [0, 0, 0];
  });
}
