import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/gps_filter.dart' show TrackPoint;
import 'package:treenipaivakirja/gpx.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart' show Target;
import 'package:treenipaivakirja/rest.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';
import 'package:treenipaivakirja/ui/workout.dart' show SavedScreen;
import 'package:treenipaivakirja/weekly_activity.dart';

// Viikon WHO-tavoite, toistuvien vammaohjeiden yhdistäminen, seuraava sarja palautuspalkissa ja juoksun
// yhteenveto ilman tuplavauhtia. Keksityt luvut.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.workouts = [];
    settings
      ..program = null
      ..pauses = []
      ..restTimer = false;
    debugSetCatalog('fi', const {});
  });

  test('Toistuvat vammaohjeet: sisältyvä ohje pois, sama ohje kerran, erilaiset jäävät', () {
    expect(mergeInjuryNotes(['käytä vetoremmejä, kevennä', 'vetoremmit']), ['käytä vetoremmejä, kevennä']);
    expect(mergeInjuryNotes(['vetoremmit', 'käytä vetoremmejä, kevennä']), ['käytä vetoremmejä, kevennä']);
    expect(mergeInjuryNotes(['syvyys kivuttomaan', 'syvyys kivuttomaan']), ['syvyys kivuttomaan']);
    expect(mergeInjuryNotes(['kevennä selvästi', 'niska neutraalina']), ['kevennä selvästi', 'niska neutraalina']);
    // Oikealla aineistolla: kaikki vamma-alueet päällä, maastavedon "vetoremmit" yhdistyy.
    final all = injuryStatus('Maastaveto', [for (final r in injuryRegions) r.id]).modify;
    expect(all.where((m) => m == 'vetoremmit'), isEmpty);
    expect(all.toSet().length, all.length);
    // Lyhyet sanat, numerot ja kiellot lasketaan: mitään ei pudoteta väärin.
    expect(mergeInjuryNotes(['Tempo 3-1-1', '5 s']), ['Tempo 3-1-1', '5 s']);
    expect(mergeInjuryNotes(['Ei kyykkyä', 'Kyykky kevyesti']), ['Ei kyykkyä', 'Kyykky kevyesti']);
    expect(mergeInjuryNotes(['ote 1,5 × hartialeveys', 'ote 1,2 × hartialeveys']).length, 2);
    expect(mergeInjuryNotes(['', 'kevennä']), ['', 'kevennä']);
    // Vanhaan ohjelmaan tallennettu yhdistetty ohje: toisto poistuu näytettäessä.
    expect(trNote('käytä vetoremmejä, kevennä · vetoremmit'), 'käytä vetoremmejä, kevennä');
  });

  test('Viikon liikunta: rasitus, kävelyn vauhti ja askeltiheys, lihaskuntopäivät, vain tämä viikko', () {
    final mon = DateTime(2026, 11, 9); // maanantai
    Workout act(int day, String sport, int min, {String? intensity, double? km, int? steps}) =>
        Workout(
            date: mon.add(Duration(days: day)),
            title: sport,
            activity: sport,
          )
          ..minutes = min
          ..intensity = intensity
          ..distanceKm = km
          ..steps = steps;
    final ws = [
      act(0, 'Juoksu', 30, intensity: 'kova'), // 60
      act(1, 'Kävely', 60, km: 5), // 5 km/h: reipas 60
      act(2, 'Kävely', 120, km: 4), // 2 km/h: kevyt
      act(3, 'Kävely', 20, steps: 2200), // 110/min: reipas 20
      act(4, 'Jooga', 45), // kevyt
      act(5, 'Koripallo', 30, intensity: 'kevyt'), // valittu rasitus voittaa
      act(-1, 'Juoksu', 90, intensity: 'kova'), // edellinen viikko
      Workout(
        date: mon,
        exercises: [
          ExerciseEntry('Kyykky', [SetEntry(60, 5)]),
        ],
      ),
      Workout(
        date: mon.add(const Duration(days: 2)),
        exercises: [
          ExerciseEntry('Penkki', [SetEntry(40, 8)]),
        ],
      ),
      Workout(
        date: mon.add(const Duration(days: 4)),
        exercises: [
          ExerciseEntry('Penkki', [SetEntry(20, 10, warmup: true)]),
        ],
      ),
    ];
    final a = weekActivity(ws, DateTime(2026, 11, 15)); // sunnuntai, sama viikko
    expect(a.vigorous, 30);
    expect(a.moderate, 80);
    expect(a.moderateEq, 140);
    expect(a.light, 120 + 45 + 30);
    expect(a.strengthDays, 2, reason: 'pelkkä lämmittely ei ole lihaskuntopäivä');
    expect(a.minutesMet, isFalse);
    expect(a.strengthMet, isTrue);
    // Kesäaikaan siirtymisen viikko (su 29.3.2026): seuraavan maanantain treeni ei kuulu tähän viikkoon.
    final dst = weekActivity([
      act(0, 'Juoksu', 30, intensity: 'reipas')..date = DateTime(2026, 3, 30),
    ], DateTime(2026, 3, 27));
    expect(dst.moderate, 0);
  });

  testWidgets('Palautuspalkki näyttää seuraavan sarjan ja päivittyy, kun painoa muutetaan', (tester) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    settings.restTimer = true;
    addTearDown(() {
      rest.stop();
      settings.restTimer = false;
    });
    final e = ExerciseEntry('Penkkipunnerrus');
    await tester.pumpWidget(
      MaterialApp(
        home: SetLoggerScreen(
          date: DateTime(2026, 11, 12),
          entry: e,
          target: Target(3, 8, 8, '1–2', 120, '3 × 8'),
          onChanged: () async {},
        ),
      ),
    );
    await tester.pump();
    final ok = find.text('Muutama');
    await tester.ensureVisible(ok);
    await tester.tap(ok);
    await tester.pump();
    expect(rest.running, isTrue);
    expect(find.textContaining('Seuraava sarja 2/3:'), findsOneWidget);
    final first = rest.next!;
    // Paino + : palkki seuraa heti.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(rest.next, isNot(first));
    // Kaksi sarjaa lisää: tavoite täynnä.
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(ok);
      await tester.tap(ok);
      await tester.pump();
    }
    expect(find.text('Tavoitteen sarjat tehty ✓'), findsOneWidget);
    // Näkymästä poistuttaessa viimeisin rivi jää palkkiin tekstinä.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(rest.nextFn, isNull);
    expect(rest.next, 'Tavoitteen sarjat tehty ✓');
    rest.stop();
  });

  testWidgets('Toisen liikkeen palautus: palkki näyttää avatun liikkeen ensimmäisen sarjan nimen kera', (tester) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    rest.start(120, 'Takakyykky');
    await tester.pumpWidget(
      MaterialApp(
        home: SetLoggerScreen(
          date: DateTime(2026, 11, 12),
          entry: ExerciseEntry('Penkkipunnerrus'),
          onChanged: () async {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(rest.next, startsWith('Penkkipunnerrus · Seuraava'));
    expect(find.textContaining('Penkkipunnerrus · Seuraava'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    rest.stop();
  });

  testWidgets('Askelpituus: matka / askeleet tiedostossa, vanhoille lasketaan, epäuskottava jätetään pois', (
    tester,
  ) async {
    final w = Workout(date: DateTime(2026, 11, 7), title: 'Kävely', activity: 'Kävely')
      ..seconds = 2400
      ..minutes = 40
      ..distanceKm = 3.2
      ..steps = 4100;
    expect(w.strideM!, closeTo(0.78, 0.005));
    final md = workoutToMarkdown(w);
    expect(md, contains('stride: 0,78 m'));
    final back = parseWorkout(md);
    expect(back.steps, 4100);
    expect(back.strideM, closeTo(0.78, 0.005));
    // Koko päivän askeleet lyhyelle lenkille: 0,1 m ei ole askel.
    expect((w.copy()..steps = 32000).strideM, isNull);
    expect((w.copy()..steps = null).strideM, isNull);
    // Vanha tiedosto ilman stride-riviä ei muutu tallennettaessa, mutta askelpituus lasketaan silti.
    final old = parseWorkout(md.replaceFirst(RegExp(r'stride: .*\n'), ''));
    expect(old.strideM, closeTo(0.78, 0.005));
    expect(workoutToMarkdown(old), isNot(contains('stride:')));
    // Ensin tallennettu ilman askeleita (GPS-kävely), askeleet myöhemmin Health Connectista: rivi kirjoitetaan.
    final first = parseWorkout(workoutToMarkdown(w.copy()..steps = null));
    expect(first.strideLine, isTrue);
    first.steps = 4100;
    expect(workoutToMarkdown(first), contains('stride: 0,78 m'));
    // Vain liikunnan tiedoissa, ei yhteenvedossa (harvoin tarvittu luku).
    await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w)));
    await tester.pump();
    expect(find.text('askelpituus'), findsNothing);
  });

  testWidgets('Vanha GPS-kävely: askelpituus näkyy liikunnan tiedoissa', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final t0 = DateTime.utc(2026, 11, 4, 8);
    final gpx = routeToGpx([
      [TrackPoint(t0, 62.0, 25.0), TrackPoint(t0.add(const Duration(minutes: 40)), 62.0, 25.06)],
    ], name: 'testi');
    // Vanha tiedosto: reitti, matka ja askeleet, ei stride-riviä.
    final w = parseWorkout(
      '---\ndate: 2026-11-04\ntitle: Kävely\nactivity: Kävely\ndistance: 3,2 km\nduration: 40 min\n'
      'time: 40:00\nsteps: 4100\n---\n',
    )..routeGpx = gpx;
    await tester.pumpWidget(MaterialApp(home: ActivityScreen(workout: w)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('askelpituus'), findsOneWidget);
    expect(find.textContaining('0,78'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Juoksun yhteenveto: vauhti vain kerran', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final w = Workout(date: DateTime(2026, 11, 7), title: 'Juoksu', activity: 'Juoksu')
      ..minutes = 30
      ..seconds = 1800
      ..distanceKm = 5;
    await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w)));
    await tester.pump();
    expect(find.textContaining('6:00'), findsOneWidget);
    expect(find.text('Juoksun kehitys'), findsOneWidget);
  });
}
