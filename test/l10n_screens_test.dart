import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/custom_merge.dart';
import 'package:treenipaivakirja/exercise_names_en.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/sami_material.dart';
import 'package:treenipaivakirja/theme.dart';
import 'package:treenipaivakirja/ui/drawer.dart';
import 'package:treenipaivakirja/ui/injury_screen.dart';
import 'package:treenipaivakirja/ui/intro.dart';
import 'package:treenipaivakirja/ui/program_screen.dart';
import 'package:treenipaivakirja/ui/program_template.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/ui/body_screen.dart';
import 'package:treenipaivakirja/ui/bug_report.dart';
import 'package:treenipaivakirja/ui/health_import.dart';
import 'package:treenipaivakirja/ui/health_sheet.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/import_export.dart';
import 'package:treenipaivakirja/ui/new_workout.dart';
import 'package:treenipaivakirja/ui/picker.dart';
import 'package:treenipaivakirja/ui/maxes_editor.dart';
import 'package:treenipaivakirja/ui/programs_screen.dart';
import 'package:treenipaivakirja/ui/running_screen.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';
import 'package:treenipaivakirja/ui/workout.dart';
import 'package:treenipaivakirja/ui/widgets.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';

// Käännöstarkistus näkymittäin: englanniksi ja saameksi näkyvissä ei saa olla suomenkielistä tekstiä.
// Tunnistus: (1) teksti on .po-tiedoston suomenkielinen alkuteksti, jolla on eri käännös, (2) siinä on ä tai ö
// (eivät kuulu englantiin eivätkä pohjoissaameen). Sallittu: sovelluksen nimi, kielivalitsimen kielet, saamessa
// liikkeiden nimet (suomeksi tai englanniksi valinnan mukaan).
late Set<String> _fiKeys;

/// Tarkoituksella suomeksi jätetyt (käännös = alkuteksti), esim. vammatilan ohjeet saameksi.
late Set<String> _keep;
final _exercises = builtinExercises().toSet();
const _allowed = ['Treenipäiväkirja', 'Kieli · Giella', 'Suomi', 'Käypä hoito'];

List<String> _texts(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final s = (e.widget as RichText).text.toPlainText().trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

List<String> _finnish(WidgetTester tester, String lang) {
  final bad = <String>{};
  for (final s in _texts(tester)) {
    if (_allowed.any(s.contains)) continue;
    if (_keep.any((k) => k.length > 3 && s.contains(k))) continue;
    if (lang == 'se' && _exercises.any((x) => s.contains(x))) continue;
    final parts = [s, ...s.split(RegExp(r',\s*|:\s*|\s·\s|\n'))].map((x) => x.trim()).where((x) => x.length > 2);
    // Englanniksi liikkeiden nimet aina englanniksi: suomenkielinen liikenimi (jolla on eri englanninkielinen nimi).
    final fiExercise = lang == 'en' && parts.any((x) => (exerciseEnglish[x] ?? x) != x);
    if (fiExercise || parts.any(_fiKeys.contains) || RegExp('[äöÄÖ]').hasMatch(s)) bad.add(s);
  }
  return bad.toList();
}

Future<void> _app(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(_TApp(home: home));
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text).hitTestable();
  if (f.evaluate().isEmpty) {
    await tester.dragUntilVisible(find.text(text).first, find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(text).hitTestable().first);
  await tester.pumpAndSettle();
}

// Valinnainen kuvakaappaus jokaisesta tarkistetusta näkymästä (värien ja asettelun vertailuun):
// GIEVRA_SHOTS=<kansio> GIEVRA_THEME=dark|light flutter test test/l10n_screens_test.dart
final _shots = Platform.environment['GIEVRA_SHOTS'];
final ThemeData? _shotTheme = switch (Platform.environment['GIEVRA_THEME']) {
  'dark' => _withFallback(buildTheme(Brightness.dark)),
  'light' => _withFallback(buildTheme(Brightness.light)),
  _ => null,
};
ThemeData _withFallback(ThemeData t) =>
    t.copyWith(textTheme: t.textTheme.apply(fontFamilyFallback: const ['DejaVu', 'Emoji']));

/// Sovellus testissä: kuvakaappauksissa sovelluksen oma teema.
class _TApp extends StatelessWidget {
  final Widget home;
  const _TApp({required this.home});
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    // Flutterin omat tekstit kuten sovelluksessa: käyttöliittymän kielellä (saame omana kerroksenaan).
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _shotTheme,
      locale: flutterLocale(uiLang),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: home,
    ),
  );
}

Future<void> _loadShotFonts() async {
  // Kuvakaappaus päästää näkymän oikeat taustatehtävät käyntiin (esim. tiedostolistat): väliaikainen kansio.
  final tmp = Directory.systemTemp.createTempSync('gievra-shots').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp,
  );
  final root = '${Platform.environment['HOME']}/sdk/flutter/bin/cache/artifacts/material_fonts';
  for (final (family, files) in [
    ('Roboto', ['$root/Roboto-Regular.ttf', '$root/Roboto-Medium.ttf', '$root/Roboto-Bold.ttf']),
    ('MaterialIcons', ['$root/MaterialIcons-Regular.otf']),
    ('DejaVu', ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']),
    ('Emoji', ['/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf']),
  ]) {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(File(f).readAsBytesSync().buffer.asByteData()));
    }
    await l.load();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final f = find.byType(RepaintBoundary).first;
  if (f.evaluate().isEmpty) return;
  await tester.runAsync(() async {
    final img = await captureImage(f.evaluate().first);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(_shots!).createSync(recursive: true);
    File('$_shots/${name.replaceAll(RegExp(r'[^A-Za-z0-9äöÄÖ_-]+'), '_')}.png')
        .writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  // Suomi mukana asettelun vuoksi (pitkät sanat, ylivuodot): kielitarkistus vain englanniksi ja saameksi.
  for (final lang in ['fi', 'en', 'se']) {
    group(lang, () {
      final found = <String, List<String>>{};
      Future<void> check(WidgetTester tester, String where) async {
        if (_shots != null) await _capture(tester, '$lang-$where');
        final b = lang == 'fi' ? const <String>[] : _finnish(tester, lang);
        if (b.isNotEmpty) found[where] = b;
        expect(b, isEmpty, reason: 'suomenkielistä tekstiä näkymässä "$where" ($lang)');
      }

      setUpAll(() async {
        TestWidgetsFlutterBinding.ensureInitialized();
        if (_shots != null) await _loadShotFonts();
        await setUiLang(lang);
        final po = lang == 'fi' ? '' : await rootBundle.loadString('assets/l10n/$lang.po');
        final cat = parsePo(po);
        // Myös isolla alkukirjaimella (esim. "Sekunnit"), kun käännös on eri myös pienillä kirjaimilla.
        _fiKeys = {
          for (final e in cat.entries)
            if (e.value.isNotEmpty && e.value.toLowerCase() != e.key.toLowerCase()) ...[
              e.key,
              if (e.key.isNotEmpty) '${e.key[0].toUpperCase()}${e.key.substring(1)}',
            ],
        };
        _keep = {
          for (final e in cat.entries)
            if (e.value == e.key) e.key,
        };
      });
      tearDownAll(() {
        // ignore: avoid_print
        for (final e in found.entries) {
          // ignore: avoid_print
          print('[$lang] ${e.key}:\n  ${e.value.map((s) => s.replaceAll('\n', ' ')).join('\n  ')}');
        }
      });

      // Ohjelmakysely: jokainen tavoite, kokemus, väline, päivämäärä, kesto ja toistoalue loppuun asti.
      final goalsUi = ['Voimanosto', 'Lihaskasvu', 'Rasvanpoltto', 'Yleiskunto', 'Mennään fiiliksellä'];
      final expSubs = [
        'Isot liikkeet tutuiksi, paino nousee nopeasti',
        'Nousu hidastunut, tarvitset rakennetta',
        'Enemmän volyymia ja säännölliset kevennykset',
      ];
      final runs = <(String, String?, String?, String?, String?)>[
        for (final g in goalsUi) (g, null, null, null, null),
        for (final e in expSubs) ('Lihaskasvu', e, null, null, null),
        ('Yleiskunto', null, '2', '45 min', 'Raskaampi'),
        ('Rasvanpoltto', null, '4', '75 min', 'Kevyempi'),
        ('Lihaskasvu', null, '5', '90 min', 'Suositus'),
        ('Voimanosto', null, '6', '60 min', 'Raskaampi'),
      ];
      for (final (goal, exp, days, minutes, reps) in runs) {
        testWidgets('Ohjelmakysely: $goal ${exp ?? ''} ${days ?? ''} ${minutes ?? ''} ${reps ?? ''}', (tester) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);
          settings
            ..program = null
            ..injuries = [];
          await _app(tester, const IntroScreen());
          await check(tester, 'kysely 1');
          await _tapText(tester, t('Vastaan kysymyksiin itse'));
          for (var step = 2; step <= 12; step++) {
            await check(tester, 'kysely $step ($goal)');
            if (step == 2) await _tapText(tester, t(goal));
            if (step == 3 && exp != null) await _tapText(tester, t(exp));
            if (days != null && find.text(days).hitTestable().evaluate().isNotEmpty && step >= 5) {
              await _tapText(tester, days);
              if (minutes != null) await _tapText(tester, minutes);
              if (reps != null) await _tapText(tester, t(reps));
            }
            final next = find.text(t('Seuraava')).hitTestable();
            if (next.evaluate().isEmpty) break;
            await tester.tap(next.first);
            await tester.pumpAndSettle();
          }
          await check(tester, 'kysely: yhteenveto ($goal ${days ?? ''})');
        });
      }

      testWidgets('Ohjelma vammojen kanssa ja ohjelmasivu', (tester) async {
        tester.view.physicalSize = const Size(1080, 4000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        for (final goal in ['voimanosto', 'lihaskasvu', 'kunto']) {
          final ids = [for (final r in injuryRegions) r.id];
          settings.program = generateProgram(
            goal: goal,
            experience: 'keski',
            days: 3,
            minutes: 60,
            injuries: ids.take(4).toList(),
          );
          settings.injuries = ids.take(4).toList();
          await _app(tester, const ProgramScreen());
          await check(tester, 'ohjelmasivu ($goal, vammoja)');
        }
      });

      // Suomeksi luotu ohjelma (päivien nimet tallentuvat suomeksi), käyttöliittymä vaihdettu: kaikki tavoitteet,
      // kokemustasot, päivämäärät ja kahvakuulaohjelmat uuden treenin valinnassa ja ohjelmasivulla.
      testWidgets('Suomeksi luotu ohjelma: uusi treeni ja ohjelmasivu', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        settings.injuries = [];
        final cases = <(String, String, int, String?)>[
          for (final g in ['voimanosto', 'lihaskasvu', 'rasvanpoltto', 'kunto'])
            for (final e in ['aloittelija', 'keski'])
              for (final d in [2, 3, 4, 5, 6]) (g, e, d, null),
          for (final k in kbFocuses.keys) ('kunto', 'keski', 3, k),
        ];
        for (final (g, e, d, kb) in cases) {
          settings.program = generateProgram(
            goal: g,
            experience: e,
            days: d,
            minutes: 60,
            injuries: const [],
            equipment: kb == null ? const {} : const {'kahvakuula'},
            kbFocus: kb,
          );
          final where = '$g $e $d pv${kb == null ? '' : ' kahvakuula $kb'}';
          await tester.pumpWidget(_TApp(home: NewWorkoutScreen(date: DateTime(2026, 11, 9))));
          await tester.pump(const Duration(milliseconds: 300));
          await check(tester, 'uusi treeni: $where');
          await _app(tester, const ProgramScreen());
          await check(tester, 'ohjelmasivu: $where');
        }
        settings.program = null;
      });

      testWidgets('Etusivu ja tilastot treenien kanssa', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        final now = DateTime.now();
        store.workouts = [
          Workout(date: DateTime(now.year, now.month, now.day), title: 'Koko keho A')
            ..exercises.addAll([
              ExerciseEntry('Takakyykky', [SetEntry(100, 5)]),
              ExerciseEntry('Penkkipunnerrus', [SetEntry(80, 5)]),
              ExerciseEntry('Kulmasoutu', [SetEntry(70, 8)]),
            ]),
          Workout(
            date: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
            title: 'Juoksu',
            activity: 'Juoksu',
            minutes: 30,
            distanceKm: 5,
          ),
        ];
        await tester.pumpWidget(const _TApp(home: HomeScreen()));
        await tester.pump(const Duration(seconds: 1));
        await check(tester, 'etusivu treenien kanssa');
        await tester.pumpWidget(const _TApp(home: StatsScreen()));
        await tester.pump(const Duration(seconds: 1));
        await check(tester, 'tilastot treenien kanssa');
        store.workouts = [];
      });

      testWidgets('Suomeksi tehty ohjelmapohja (.gmd) avataan toisella kielellä', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        // Pohja tehdään suomeksi (tiedostomuoto on aina sama), avataan testattavalla kielellä.
        final p = generateProgram(
          goal: 'voimanosto',
          experience: 'keski',
          days: 4,
          minutes: 60,
          injuries: [injuryRegions.first.id],
        );
        final md = programToTemplate(p, author: 'Testi');
        await tester.pumpWidget(
          _TApp(
            home: Builder(
              builder: (c) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => importTemplate(c, text: md, activate: false),
                    child: const Text('x'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('x'));
        await tester.pumpAndSettle();
        await check(tester, 'ohjelmapohjan esikatselu');
        settings.program = parseProgram(md);
        await _app(tester, const ProgramScreen());
        await check(tester, 'pohjasta otettu ohjelma');
        await tester.pumpWidget(_TApp(home: NewWorkoutScreen(date: DateTime(2026, 11, 10))));
        await tester.pump(const Duration(milliseconds: 300));
        await check(tester, 'pohjasta otettu ohjelma: uusi treeni');
        settings.program = null;
      });

      // Vältettävän liikkeen rivi kertoo vamman nimen (ei liikkeen): käännetään vammana.
      testWidgets('Liikkeen valinta ja sarjan kirjaus: vältettävä liike vammatilassa', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        settings.injuries = [for (final r in injuryRegions) r.id];
        await _app(tester, const ExercisePickerScreen());
        expect(find.textContaining('⚠️'), findsWidgets, reason: 'vältettäviä liikkeitä näkyy');
        await check(tester, 'liikkeen valinta, kaikki vammat');
        settings.injuries = ['nivus_lahentaja'];
        await tester.pumpWidget(
          _TApp(
            home: SetLoggerScreen(
              date: DateTime(2026, 11, 10),
              entry: ExerciseEntry('Sumomaastaveto', [SetEntry(100, 5)]),
              onChanged: () async {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        // Liikevinkit saameksi tarkoituksella suomeksi (vammatilan ohjeiden kieli): suljetaan, tarkistetaan varoitus.
        await tester.tap(find.byIcon(Icons.play_circle_outline).first);
        await tester.pumpAndSettle();
        expect(find.textContaining('⚠️'), findsWidgets);
        await check(tester, 'sarjan kirjaus, vältettävä liike');
        settings.injuries = [];
      });

      testWidgets('Sarjan kirjaus: vinkit, vammavaroitus, mittaustapa ja ohjelman liikkeen muokkaus', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        settings.injuries = ['alaselka'];
        for (final ex in ['Maastaveto', 'Lankku', 'Good morning']) {
          await tester.pumpWidget(
            _TApp(
              home: SetLoggerScreen(
                date: DateTime(2026, 11, 10),
                entry: ExerciseEntry(ex, [SetEntry(100, 5)]),
                onChanged: () async {},
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final tips = find.byIcon(Icons.play_circle_outline);
          if (tips.evaluate().isNotEmpty && find.text(t('Kokeellinen ohje')).evaluate().isNotEmpty) {
            await tester.tap(tips.first);
            await tester.pumpAndSettle();
          }
          await check(tester, 'sarjan kirjaus: $ex');
          await tester.tap(find.byIcon(Icons.straighten));
          await tester.pumpAndSettle();
          await check(tester, 'mittaustapa: $ex');
        }
        settings.injuries = [];
        settings.program = generateProgram(
          goal: 'lihaskasvu',
          experience: 'keski',
          days: 3,
          minutes: 60,
          injuries: const [],
        );
        await _app(tester, const ProgramScreen());
        await tester.tap(find.byType(ExName).first);
        await tester.pumpAndSettle();
        await check(tester, 'ohjelman liikkeen muokkaus');
        final chip = find.byType(ChoiceChip);
        if (chip.evaluate().isNotEmpty) {
          await tester.tap(chip.first);
          await tester.pumpAndSettle();
          await check(tester, 'liikkeen vaihdon esikatselu');
        }
        settings.program = null;
      });

      testWidgets('Vienti luettavaksi tai taulukkoon: valintaikkuna', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        final now = DateTime.now();
        store.workouts = [
          Workout(date: DateTime(now.year, now.month, now.day), title: 'Koko keho A')
            ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)])),
        ];
        await _app(tester, const ImportExportScreen());
        await check(tester, 'tuonti ja vienti');
        await tester.tap(find.byIcon(Icons.table_chart_outlined));
        await tester.pumpAndSettle();
        await check(tester, 'vienti CSV: valinnat');
        await tester.tap(find.text(t('Kaikki')).last);
        await tester.pumpAndSettle();
        await check(tester, 'vienti CSV: kaikki');
        store.workouts = [];
      });

      testWidgets('Vammatila: kaikki alueet valittuina', (tester) async {
        tester.view.physicalSize = const Size(1080, 8000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await _app(tester, InjuryScreen(initial: [for (final r in injuryRegions) r.id]));
        await check(tester, 'vammatila');
      });

      final day = DateTime(2026, 11, 9);
      final screens = <String, Widget Function()>{
        'etusivu': () => const HomeScreen(),
        'tilastot': () => const StatsScreen(),
        'uusi treeni': () => NewWorkoutScreen(date: day),
        'salitreeni': () => WorkoutScreen(
          workout: Workout(date: day, title: 'Treeni')
            ..exercises.addAll([
              ExerciseEntry('Takakyykky', [SetEntry(100, 5)]),
              ExerciseEntry('Penkkipunnerrus', [SetEntry(80, 5)]),
            ]),
        ),
        'liikunta: juoksu': () => ActivityScreen(
          workout: Workout(date: day, title: 'Juoksu', activity: 'Juoksu'),
        ),
        'liikunta: jooga': () => ActivityScreen(
          workout: Workout(date: day, title: 'Jooga', activity: 'Jooga'),
        ),
        'juoksun kehitys': () => const RunningScreen(),
        'kehonpaino': () => const BodyScreen(),
        'tuonti ja varmuuskopio': () => const ImportExportScreen(),
        'ilmoita ongelmasta': () => const BugReportScreen(),
        'ohjelmat': () => const ProgramsScreen(),
        'ennätykset': () => const MaxesScreen(),
        'ennätysten syöttö': () => Scaffold(
          body: ListView(
            children: [
              MaxesEditor(maxes: {'Takakyykky': 100, 'Penkkipunnerrus': 80, 'Maastaveto': 120}, onChanged: () {}),
            ],
          ),
        ),
        'health connect -tuonti': () => const HealthImportScreen(),
      };
      for (final MapEntry(key: name, value: make) in screens.entries) {
        testWidgets('Näkymä: $name', (tester) async {
          tester.view.physicalSize = const Size(1080, 6000);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);
          settings.program = null;
          await tester.pumpWidget(_TApp(home: make()));
          await tester.pump(const Duration(seconds: 1));
          await check(tester, name);
        });
      }

      testWidgets('Treenin valikko ja Muokkaa kestoa: kysymys, ikkuna, kellotaulu ja kalenteri', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.6;
        addTearDown(tester.view.reset);
        settings.watch = false;
        final w = Workout(date: DateTime(2026, 11, 7), title: 'Koko keho A')
          ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(60, 8)]))
          ..minutes = 52
          ..started = DateTime(2026, 11, 7, 17, 30);
        await tester.pumpWidget(_TApp(home: WorkoutScreen(workout: w)));
        await tester.pump();
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await check(tester, 'treenin valikko');
        await tester.tap(find.text(t('Muokkaa kestoa')));
        await tester.pumpAndSettle();
        await check(tester, 'muokataanko tallennettua');
        await tester.tap(find.widgetWithText(FilledButton, t('Muokkaa')));
        await tester.pumpAndSettle();
        await check(tester, 'muokkaa kestoa');
        await tester.tap(find.byIcon(Icons.schedule));
        await tester.pumpAndSettle();
        await check(tester, 'kellotaulu');
        await tester.tap(find.widgetWithText(TextButton, t('Peruuta')).last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, t('Peruuta')).last);
        await tester.pumpAndSettle();
        // Kalenteri (sama kuin uuden treenin päivän valinnassa).
        await tester.pumpWidget(
          _TApp(
            home: Builder(
              builder: (c) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => pickDate(
                      c,
                      initial: DateTime(2026, 11, 10),
                      first: DateTime(2000),
                      last: DateTime(2026, 12, 31),
                    ),
                    child: const Text('x'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('x'));
        await tester.pumpAndSettle();
        await check(tester, 'kalenteri');
      });

      testWidgets('Health Connect: kävelyn askeleet (Oura vai kaikki lähteet) ja pelkät askeleet', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.6;
        addTearDown(tester.view.reset);
        const ch = MethodChannel('fi.somby.gievra/health');
        final st = DateTime(2026, 11, 10, 17);
        Map<String, Object?> c(String kind) => {
          'kind': kind,
          'start': st.millisecondsSinceEpoch,
          'end': st.add(const Duration(minutes: 40)).millisecondsSinceEpoch,
          'title': kind == 'session' ? 'Walking' : null,
          'type': 79,
          'app': kind == 'session' ? 'Oura' : '',
          'steps': 4560,
          'ownSteps': kind == 'session' ? 1230 : null,
          'allSteps': 4560,
        };
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null),
        );
        for (final kind in ['session', 'steps']) {
          await tester.pumpWidget(const SizedBox()); // edellinen ikkuna kiinni
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            ch,
            (call) async => switch (call.method) {
              'status' => 'available',
              'granted' => true,
              'candidates' => [c(kind)],
              _ => null,
            },
          );
          final w = Workout(date: DateTime(2026, 11, 10), title: 'Kävely', activity: 'Kävely')
            ..minutes = 40
            ..started = st;
          await tester.pumpWidget(
            _TApp(
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: TextButton(onPressed: () => showHealthSheet(ctx, w), child: const Text('x')),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('x'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(t('Tarkista')));
          await tester.pumpAndSettle();
          await check(tester, 'health connect askeleet $kind');
        }
      });

      testWidgets('Valikko ja asetukset auki', (tester) async {
        tester.view.physicalSize = const Size(1080, 9000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const _TApp(
            home: Scaffold(drawer: AppDrawer(), body: SizedBox()),
          ),
        );
        final state = tester.state<ScaffoldState>(find.byType(Scaffold));
        state.openDrawer();
        await tester.pumpAndSettle();
        await tester.tap(find.text(t('Asetukset')));
        await tester.pumpAndSettle();
        await check(tester, 'valikko ja asetukset');
      });

      testWidgets('Ilmoita ongelmasta: jokainen ongelmatyyppi ja sen vinkki', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const _TApp(home: BugReportScreen()));
        await tester.pump(const Duration(seconds: 1));
        final types = [
          'Tuonti ei onnistu',
          'Vienti tai varmuuskopio ei onnistu',
          'Ohjelma tai ehdotus näyttää väärältä',
          'Sovellus kaatuu tai jumittuu',
          'GPS, kartat tai korkeustiedot',
          'Health Connect -tuonti',
          'Käännösvirhe tai väärä kieli',
          'Muu ongelma tai ehdotus',
        ];
        for (final x in types) {
          await tester.tap(find.textContaining(t(x)));
          await tester.pump();
          await check(tester, 'ilmoita ongelmasta: $x');
        }
        expect(find.byIcon(Icons.lightbulb_outline), findsNothing, reason: 'Muu: ei vinkkiä');
      });

      testWidgets('Lähetä palautetta', (tester) async {
        await _app(
          tester,
          Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () => showFeedback(c), child: const Text('x')),
              ),
            ),
          ),
        );
        await tester.tap(find.text('x'));
        await tester.pumpAndSettle();
        await check(tester, 'palaute');
      });

      testWidgets('Tauko: sairas tai loma', (tester) async {
        settings.program = null;
        await _app(
          tester,
          Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () => showPauseDialog(c), child: const Text('x')),
              ),
            ),
          ),
        );
        await tester.tap(find.text('x'));
        await tester.pumpAndSettle();
        await check(tester, 'tauko');
      });
    });
  }
}
