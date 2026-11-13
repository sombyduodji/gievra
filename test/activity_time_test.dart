import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/ui/sport_picker.dart';
import 'package:treenipaivakirja/ui/widgets.dart' show pickSport;
import 'package:treenipaivakirja/ui/workout.dart' show SavedScreen;

// Liikunnan lajivalinta (haku, viimeksi, ruudukko) ja ajan kirjaus (Ajanotto / Syötä aika). Keksityt treenit.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
  });

  Future<Workout> open(WidgetTester tester, {String? sport}) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final w = Workout(date: DateTime(now.year, now.month, now.day), title: 'Liikunta', activity: sport, session: 9);
    await tester.pumpWidget(MaterialApp(home: ActivityScreen(workout: w)));
    await tester.pump();
    return w;
  }

  testWidgets('Lajivalinta: viimeksi tehdyt, ryhmät kuusi ensin, haku', (tester) async {
    store.workouts = [
      Workout(date: DateTime(2026, 11, 1), title: 'Koripallo', activity: 'Koripallo'),
      Workout(date: DateTime(2026, 11, 3), title: 'Uinti', activity: 'Uinti'),
    ];
    final w = await open(tester);
    expect(find.byType(SportPicker), findsOneWidget);
    expect(find.text('Viimeksi'.toUpperCase()), findsOneWidget);
    // Viimeksi: uusin ensin.
    final uinti = tester.getTopLeft(find.text('Uinti').first);
    final kori = tester.getTopLeft(find.text('Koripallo').first);
    expect(uinti.dy, kori.dy);
    expect(uinti.dx, lessThan(kori.dx));
    expect(find.textContaining('Näytä kaikki'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'lumik');
    await tester.pump();
    expect(find.text('Lumikenkäily'), findsOneWidget);
    expect(find.text('Uinti'), findsNothing);
    await tester.tap(find.text('Lumikenkäily'));
    await tester.pump();
    expect(w.activity, 'Lumikenkäily');
  });

  testWidgets('Ajanotto: aloita, lopeta, alku ja loppu näkyvät; Syötä aika näyttää keston', (tester) async {
    final w = await open(tester, sport: 'Koripallo');
    expect(find.text('Ajanotto'), findsOneWidget);
    expect(find.text('Syötä aika'), findsOneWidget);
    await tester.tap(find.text('Aloita'));
    await tester.pump();
    expect(w.started, isNotNull);
    expect(find.text('Lopeta'), findsOneWidget);
    expect(find.textContaining('alkoi'), findsOneWidget);
    await tester.tap(find.text('Lopeta'));
    await tester.pump();
    expect(find.text('ALKOI'), findsOneWidget);
    expect(find.text('LOPPUI'), findsOneWidget);
    expect(find.text('Jatka ajanottoa'), findsOneWidget);
    expect(w.minutes, 1, reason: 'alle minuutti → 1 min');
    await tester.tap(find.text('Syötä aika'));
    await tester.pump();
    expect(find.text('KESTO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Syötä aika: alkuaika ja kesto antavat loppuajan', (tester) async {
    final w = await open(tester, sport: 'Koripallo');
    await tester.tap(find.text('Syötä aika'));
    await tester.pump();
    expect(find.text('ei tiedossa'), findsNWidgets(2), reason: 'ei alkua → ei loppua');
    final d = w.date;
    // Alku asetetaan (kuten kellotaululta): loppu = alku + kesto.
    w.started = DateTime(d.year, d.month, d.day, 17);
    w.minutes = 45;
    await tester.tap(find.byIcon(Icons.add).first); // kesto 50 min
    await tester.pump();
    expect(find.text('17.00'), findsOneWidget);
    expect(find.text('17.50'), findsOneWidget);
  });

  testWidgets('Matkalaji: aloitus GPS / Ajanotto / Syötä itse; edellinen saman lajin kirjaus näkyy', (tester) async {
    ActivityScreen.debugGps = true;
    addTearDown(() => ActivityScreen.debugGps = null);
    store.workouts = [
      Workout(date: DateTime(2026, 11, 3), title: 'Kävely', activity: 'Kävely')
        ..distanceKm = 4.2
        ..minutes = 48,
    ];
    await open(tester, sport: 'Kävely');
    expect(find.text('Aloita GPS:llä'), findsOneWidget);
    expect(find.byKey(const ValueKey('startWatch')), findsOneWidget);
    expect(find.byKey(const ValueKey('startManual')), findsOneWidget);
    expect(find.textContaining('4,2 km'), findsOneWidget);
    expect(find.text('Treeni valmis!'), findsNothing, reason: 'ei vielä kirjaustapaa');
    await tester.tap(find.byKey(const ValueKey('startWatch')));
    await tester.pump();
    expect(find.text('Aloita'), findsOneWidget, reason: 'ajanotto valmiina');
    expect(find.text('Treeni valmis!'), findsOneWidget);
    await tester.tap(find.text('Syötä aika'));
    await tester.pump();
    expect(find.text('AIKA'), findsOneWidget, reason: 'matkalajissa tarkka aika');
    expect(find.text('MATKA'), findsOneWidget);
  });

  testWidgets('Syötä itse suoraan aloituksesta; uusi liikunta: ei fiilistä eikä kellon tietoja sivulla', (
    tester,
  ) async {
    ActivityScreen.debugGps = true;
    settings.watch = true;
    addTearDown(() {
      ActivityScreen.debugGps = null;
      settings.watch = false;
    });
    await open(tester, sport: 'Juoksu');
    await tester.tap(find.byKey(const ValueKey('startManual')));
    await tester.pump();
    expect(find.text('AIKA'), findsOneWidget);
    expect(find.text('MILTÄ TUNTUI?'), findsNothing);
    expect(find.text('KELLON TIEDOT'), findsNothing);
  });

  testWidgets('Treeni valmis alareunassa; fiilis ponnahdusikkunassa ennen yhteenvetoa', (tester) async {
    final dir = Directory.systemTemp.createTempSync('gievra-liikunta');
    settings.folder = dir.path;
    addTearDown(() {
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    final w = await open(tester, sport: 'Koripallo');
    final finish = tester.getRect(find.text('Treeni valmis!'));
    expect(finish.bottom, greaterThan(4000 / 2.7 - 80));
    // Ajanottoa ei aloitettu: ilmoitus, Syötä aika vaihtaa käsin syöttöön (ei oletuskestoa huomaamatta).
    await tester.tap(find.text('Treeni valmis!'));
    await tester.pumpAndSettle();
    expect(find.text('Ajanottoa ei ole aloitettu'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Syötä aika'));
    await tester.pumpAndSettle();
    expect(find.text('KESTO'), findsOneWidget);
    await tester.tap(find.text('Treeni valmis!'));
    for (var k = 0; k < 20 && find.text('Miltä tuntui?').evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('Miltä tuntui?'), findsOneWidget);
    await tester.tap(find.text('Loistava'));
    for (var k = 0; k < 20 && find.byType(SavedScreen).evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(w.feeling, 5);
    expect(find.byType(SavedScreen), findsOneWidget);
  });

  testWidgets('Yhteenveto: otsikko, vain täytetyt luvut, fiilis rivinä, kellon tiedot -painike, toiminnot alhaalla', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    settings.watch = true;
    addTearDown(() => settings.watch = false);
    final w = Workout(date: DateTime(2026, 11, 7), title: 'Koripallo', activity: 'Koripallo')
      ..minutes = 45
      ..intensity = 'reipas'
      ..feeling = 5
      ..started = DateTime(2026, 11, 7, 18, 2);
    await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w)));
    await tester.pump();
    expect(find.text('Giitu! Koripallo tehty'), findsOneWidget);
    expect(find.textContaining('18.02–18.47'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('–'), findsNothing, reason: 'ei tyhjiä ruutuja');
    expect(find.text('Fiilis: loistava'), findsOneWidget);
    expect(find.byKey(const ValueKey('fetchWatch')), findsOneWidget);
    expect(find.text('Valmis'), findsOneWidget);
    expect(find.text('Tiedosto'), findsOneWidget);
    // Kellon tiedot paneelissa; arvot näkyvät sen jälkeen lukuina.
    w.kcal = 410;
    w.hrAvg = 131;
    await tester.pumpWidget(
      MaterialApp(
        home: SavedScreen(workout: w, key: UniqueKey()),
      ),
    );
    await tester.pump();
    expect(find.text('🔥 410'), findsOneWidget);
    expect(find.text('❤️ 131'), findsOneWidget);
    expect(find.byKey(const ValueKey('fetchWatch')), findsNothing);
    await tester.tap(find.text('Tiedosto'));
    await tester.pumpAndSettle();
    expect(find.text('Tallennettu tiedosto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mikä laji tämä on? käyttää samaa lajivalintaa: haku ja ruudut; Ohita palauttaa null', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    String? got = 'ei vielä';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await pickSport(context, '4032 askelta ilman harjoitusta.'),
            child: const Text('avaa'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    expect(find.text('Mikä laji tämä on?'), findsOneWidget);
    expect(find.byType(SportPicker), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'kävel');
    await tester.pump();
    await tester.tap(find.text('Kävely'));
    await tester.pumpAndSettle();
    expect(got, 'Kävely');
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ohita, älä tuo'));
    await tester.pumpAndSettle();
    expect(got, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fiiliskysely: takaisin peruu lopetuksen (ei tallennusta), Ohita tallentaa ilman fiilistä', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('gievra-takaisin');
    settings.folder = dir.path;
    addTearDown(() {
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    final w = await open(tester, sport: 'Jooga');
    await tester.tap(find.text('Syötä aika'));
    await tester.pump();
    await tester.tap(find.text('Treeni valmis!'));
    await tester.pumpAndSettle();
    expect(find.text('Miltä tuntui?'), findsOneWidget);
    // Takaisin: kysely sulkeutuu, ollaan yhä kirjauksessa, mitään ei tallennettu.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Miltä tuntui?'), findsNothing);
    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(store.workouts.where((x) => x.activity == 'Jooga'), isEmpty);
    // Ohita: tallentuu ilman fiilistä.
    await tester.tap(find.text('Treeni valmis!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ohita'));
    for (var k = 0; k < 20 && find.byType(SavedScreen).evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SavedScreen), findsOneWidget);
    expect(w.feeling, isNull);
  });

  testWidgets('Takaisin tallentamattomalla kirjauksella kysyy: Peruuta jää, Hylkää poistuu', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final w = Workout(date: DateTime(now.year, now.month, now.day), title: 'Jooga', activity: 'Jooga', session: 9);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: w))),
            child: const Text('avaa'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    // Muuttamaton: takaisin poistuu suoraan.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsNothing);
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Syötä aika'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Tallennetaanko liikunta?'), findsOneWidget);
    await tester.tap(find.text('Peruuta'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hylkää'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsNothing);
  });

  testWidgets('Yön yli: loppu ennen alkua tarkoittaa seuraavaa päivää; kesto pysyy järkevänä', (tester) async {
    final w = await open(tester, sport: 'Jooga');
    await tester.tap(find.text('Syötä aika'));
    await tester.pump();
    final d = w.date;
    var pick = const TimeOfDay(hour: 23, minute: 30);
    ActivityScreen.debugPickTime = () => pick;
    addTearDown(() => ActivityScreen.debugPickTime = null);
    await tester.tap(find.text('ei tiedossa').first);
    await tester.pump();
    expect(w.started, DateTime(d.year, d.month, d.day, 23, 30));
    pick = const TimeOfDay(hour: 0, minute: 10);
    await tester.tap(find.byIcon(Icons.schedule).last);
    await tester.pump();
    expect(w.minutes, 40, reason: '23.30 → 00.10 = 40 min');
    expect(find.text('00.10'), findsOneWidget);
  });

  testWidgets('Käynnissä olevaa ajanottoa ei vaihdeta Syötä aika -tilaan; valinta näkyy', (tester) async {
    await open(tester, sport: 'Jooga');
    await tester.tap(find.text('Aloita'));
    await tester.pump();
    await tester.tap(find.text('Syötä aika'));
    await tester.pump();
    expect(find.text('Lopeta ajanotto ensin.'), findsOneWidget);
    expect(find.text('Lopeta'), findsOneWidget, reason: 'ajanotto yhä näkyvissä');
    await tester.tap(find.text('Lopeta'));
    await tester.pump();
  });

  testWidgets('Uusi liikunta: rasitus ja fiilis samassa kyselyssä lopussa, ei sivulla', (tester) async {
    final dir = Directory.systemTemp.createTempSync('gievra-rasitus');
    settings.folder = dir.path;
    addTearDown(() {
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    final w = await open(tester, sport: 'Koripallo');
    expect(find.text('RASITUS'), findsNothing, reason: 'kysytään lopussa');
    await tester.tap(find.text('Syötä aika'));
    await tester.pump();
    await tester.tap(find.text('Treeni valmis!'));
    await tester.pumpAndSettle();
    expect(find.text('Rasitus'), findsOneWidget);
    expect(find.text('Miltä tuntui?'), findsOneWidget);
    await tester.tap(find.textContaining('Reipas'));
    await tester.pump();
    await tester.tap(find.text('Hyvä'));
    for (var k = 0; k < 20 && find.byType(SavedScreen).evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect((w.intensity, w.feeling), ('reipas', 4));
    expect(find.byType(SavedScreen), findsOneWidget);
  });
}
