import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/custom_merge.dart';
import 'package:treenipaivakirja/exercise_names_en.dart';
import 'package:treenipaivakirja/injuries.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/drawer.dart';
import 'package:treenipaivakirja/ui/injury_screen.dart';
import 'package:treenipaivakirja/ui/intro.dart';
import 'package:treenipaivakirja/ui/program_screen.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/ui/body_screen.dart';
import 'package:treenipaivakirja/ui/bug_report.dart';
import 'package:treenipaivakirja/ui/health_import.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/import_export.dart';
import 'package:treenipaivakirja/ui/new_workout.dart';
import 'package:treenipaivakirja/ui/maxes_editor.dart';
import 'package:treenipaivakirja/ui/programs_screen.dart';
import 'package:treenipaivakirja/ui/running_screen.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';
import 'package:treenipaivakirja/ui/workout.dart';

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
  await tester.pumpWidget(MaterialApp(home: home));
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

void main() {
  for (final lang in ['en', 'se']) {
    group(lang, () {
      final found = <String, List<String>>{};
      void check(WidgetTester tester, String where) {
        final b = _finnish(tester, lang);
        if (b.isNotEmpty) found[where] = b;
        expect(b, isEmpty, reason: 'suomenkielistä tekstiä näkymässä "$where" ($lang)');
      }

      setUpAll(() async {
        TestWidgetsFlutterBinding.ensureInitialized();
        await setUiLang(lang);
        final po = await rootBundle.loadString('assets/l10n/$lang.po');
        final cat = parsePo(po);
        _fiKeys = {
          for (final e in cat.entries)
            if (e.value.isNotEmpty && e.value != e.key) e.key,
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
          check(tester, 'kysely 1');
          await _tapText(tester, t('Vastaan kysymyksiin itse'));
          for (var step = 2; step <= 12; step++) {
            check(tester, 'kysely $step ($goal)');
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
          check(tester, 'kysely: yhteenveto ($goal ${days ?? ''})');
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
          check(tester, 'ohjelmasivu ($goal, vammoja)');
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
          await tester.pumpWidget(MaterialApp(home: NewWorkoutScreen(date: DateTime(2026, 11, 9))));
          await tester.pump(const Duration(milliseconds: 300));
          check(tester, 'uusi treeni: $where');
          await _app(tester, const ProgramScreen());
          check(tester, 'ohjelmasivu: $where');
        }
        settings.program = null;
      });

      testWidgets('Vammatila: kaikki alueet valittuina', (tester) async {
        tester.view.physicalSize = const Size(1080, 8000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await _app(tester, InjuryScreen(initial: [for (final r in injuryRegions) r.id]));
        check(tester, 'vammatila');
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
        'health connect -tuonti': () => const HealthImportScreen(),
      };
      for (final MapEntry(key: name, value: make) in screens.entries) {
        testWidgets('Näkymä: $name', (tester) async {
          tester.view.physicalSize = const Size(1080, 6000);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);
          settings.program = null;
          await tester.pumpWidget(MaterialApp(home: make()));
          await tester.pump(const Duration(seconds: 1));
          check(tester, name);
        });
      }

      testWidgets('Valikko ja asetukset auki', (tester) async {
        tester.view.physicalSize = const Size(1080, 9000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(drawer: AppDrawer(), body: SizedBox()),
          ),
        );
        final state = tester.state<ScaffoldState>(find.byType(Scaffold));
        state.openDrawer();
        await tester.pumpAndSettle();
        await tester.tap(find.text(t('Asetukset')));
        await tester.pumpAndSettle();
        check(tester, 'valikko ja asetukset');
      });

      testWidgets('Ilmoita ongelmasta: jokainen ongelmatyyppi ja sen vinkki', (tester) async {
        tester.view.physicalSize = const Size(1080, 6000);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const MaterialApp(home: BugReportScreen()));
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
          check(tester, 'ilmoita ongelmasta: $x');
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
        check(tester, 'palaute');
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
        check(tester, 'tauko');
      });
    });
  }
}
