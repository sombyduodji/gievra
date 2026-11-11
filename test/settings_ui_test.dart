import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/main.dart';

void main() {
  testWidgets('Asetukset näyttävät uuden valinnan heti (painon lisäys, teema)', (tester) async {
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
    Future<void> group(String name) async {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pumpAndSettle();
    }

    await group('Harjoittelu');

    Set<T> selected<T>() => tester.widget<SegmentedButton<T>>(find.byType(SegmentedButton<T>)).selected;
    expect(selected<double>(), {2.5});
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<double>), matching: find.text('5')));
    await tester.pumpAndSettle();
    expect(settings.weightStep, 5);
    expect(selected<double>(), {5});
    await back();
    await group('Yleiset');

    await tester.tap(find.text('Tumma'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(selected<ThemeMode>(), {ThemeMode.dark});

    await back();
    // Palautusajat: +15 s näkyy heti (const-lapsi kuuntelee itse).
    await group('Palautusajastin');
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

  testWidgets('Nimen muokkaus: peruutus, tallennus ja Enter; dialogi sulkeutuu ilman virheitä', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    settings.name = 'Testi';
    settings.introDone = true;
    await tester.pumpWidget(const TreeniApp());
    await tester.pump();
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asetukset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yleiset'));
    await tester.pumpAndSettle();
    Future<void> open() async {
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(find.text('Miksi sinua kutsutaan?'), findsOneWidget);
    }

    await open();
    await tester.enterText(find.byType(TextField), 'Ei tallennu');
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(settings.name, 'Testi');
    await open();
    expect(find.widgetWithText(TextField, 'Testi'), findsOneWidget, reason: 'nykyinen nimi valmiina');
    await tester.enterText(find.byType(TextField), 'Ánde');
    await tester.tap(find.text('Tallenna'));
    await tester.pumpAndSettle();
    expect(settings.name, 'Ánde');
    await open();
    await tester.enterText(find.byType(TextField), 'Biret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(settings.name, 'Biret');
    expect(find.text('Miksi sinua kutsutaan?'), findsNothing);
    expect(tester.takeException(), isNull);
    settings.name = 'Testi';
  });

  testWidgets('Tallennus: kansion haku ei käynnisty uudelleen, kun muu asetus muuttuu', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings.name = 'Testi';
    settings.introDone = true;
    await tester.pumpWidget(const TreeniApp());
    await tester.pump();
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asetukset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tallennus'));
    await tester.pumpAndSettle();
    expect(find.text('Treenikansio (.md)'), findsOneWidget);
    Object? future() => (tester.widget(find.byWidgetPredicate((w) => w is FutureBuilder).last) as FutureBuilder).future;
    final before = future();
    settings.setWeightStep(settings.weightStep == 5 ? 2.5 : 5);
    await tester.pump();
    expect(identical(future(), before), isTrue);
  });
}
