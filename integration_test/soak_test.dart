// Pitkä rasitustesti oikealla laitteella tai työpöydällä (Windows, Linux, Android):
//   flutter test integration_test/soak_test.dart -d windows \
//     --dart-define=SOAK_SECONDS=900 --dart-define=FITNOTES=C:\polku\FitNotes_Backup.fitnotes
// Kierros: FitNotes-tuonti, varmuuskopion vienti ja palautus, treenien ja liikunnan tallennus ja poisto,
// päänäkymien piirto. Muisti (RSS) mitataan joka kierroksella; lopussa verrataan alkua ja loppua.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/theme.dart';
import 'package:treenipaivakirja/ui/activity.dart';
import 'package:treenipaivakirja/ui/body_screen.dart';
import 'package:treenipaivakirja/ui/new_workout.dart';
import 'package:treenipaivakirja/ui/running_screen.dart';
import 'package:treenipaivakirja/ui/workout.dart';
import 'package:treenipaivakirja/ui/home.dart';
import 'package:treenipaivakirja/ui/import_export.dart';
import 'package:treenipaivakirja/ui/program_screen.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';

const _seconds = int.fromEnvironment('SOAK_SECONDS', defaultValue: 60);
const _fitnotes = String.fromEnvironment('FITNOTES');

final _times = <String, List<int>>{}; // näkymä -> piirtoajat (ms), hidastumisen seuraamiseen

Future<void> _show(WidgetTester t, Widget w, [String? name]) async {
  final sw = Stopwatch()..start();
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      locale: const Locale('fi'),
      supportedLocales: const [Locale('fi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: w,
    ),
  );
  // Animaatiot toistuvat (liikeanimaatiot), joten ei pumpAndSettle: piirretään 2 s verran ruutuja.
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  (_times[name ?? w.runtimeType.toString()] ??= []).add(sw.elapsedMilliseconds);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Rasitustesti: tuonti, vienti, tallennus ja näkymät, muisti ei kasva', (t) async {
    await initializeDateFormatting('fi');
    final dir = await Directory.systemTemp.createTemp('gievra-soak');
    final log = File('${Directory.systemTemp.path}${Platform.pathSeparator}gievra-soak-mem.csv')
      ..writeAsStringSync('kierros,sekunnit,rss_mt,treenit\n');
    settings.folder = dir.path;
    settings.name = 'Testi';
    settings.introDone = true;
    settings.sports = true;
    store.workouts = [];
    final rss = <int>[];
    final watch = Stopwatch()..start();
    var round = 0;
    while (watch.elapsed.inSeconds < _seconds) {
      round++;
      // 1. FitNotes-tuonti (oikea varmuuskopio, jos annettu) tai keinotekoinen historia.
      if (_fitnotes.isNotEmpty) {
        final r = readFitnotes(_fitnotes);
        await applyImport(r);
      } else {
        await store.saveMany([
          for (var i = 0; i < 200; i++)
            Workout(
              date: addDays(DateTime(2025, 1, 1), i * 2),
              title: 'Koko keho A',
              feeling: 1 + i % 5,
              exercises: [
                ExerciseEntry('Takakyykky', [SetEntry(100.0 + i % 20, 5), SetEntry(100, 5)]),
              ],
            ),
        ]);
      }
      await store.reload();
      final n = store.workouts.length;
      expect(n, greaterThan(100));

      // 2. Varmuuskopio: vienti ja luku takaisin, sama määrä treenejä.
      final zip = await exportZip();
      final back = readZip(zip);
      expect(back.workouts.length, n);

      // 3. Treeni, toinen treeni samalle päivälle ja liikunta, sitten poisto.
      final day = DateTime(2030, 1, 1 + round % 28);
      await store.save(
        Workout(
          date: day,
          title: 'Rasitus',
          feeling: 4,
          exercises: [
            ExerciseEntry('Penkkipunnerrus', [SetEntry(80, 5)]),
          ],
        ),
      );
      await store.save(Workout(date: day, session: 2, title: 'Juoksu', activity: 'Juoksu', minutes: 30, distanceKm: 5));
      expect(store.onDay(day).length, 2);
      await store.delete(day, 2);
      await store.delete(day);
      expect(store.onDay(day), isEmpty);

      // 3b. Kehonpaino: punnitukset, varmuuskopio ja tuonti takaisin (ei kaksoiskappaleita).
      settings.bodyTracker = true;
      await settings.setBody(
        BodyLog(
          heightCm: 180,
          weights: {for (var i = 0; i < 60; i++) addDays(DateTime(2026, 1, 1), i * 3): 90 - i * .1},
        ),
      );
      final zip2 = await exportZip();
      final back2 = readZip(zip2);
      expect(parseBody(back2.bodyMd!).weights.length, 60);
      await applyImport(back2);
      expect(settings.body.weights.length, 60);
      expect(weightSeries(settings.body, store.workouts), isNotEmpty);

      // Kieli vaihtuu kierroksittain (suomi, englanti, saame), samoin sali- ja kestävyysnäkymä.
      await setUiLang(const ['fi', 'en', 'se'][round % 3]);
      settings.trainMode = 'both';
      settings.homeView = round.isEven ? 'gym' : 'cardio';

      // 4. Ohjelma ja näkymät.
      await settings.setProgram(
        generateProgram(goal: 'lihaskasvu', experience: 'keski', days: 3, minutes: 60, injuries: const []),
      );
      await _show(t, const HomeScreen(), 'HomeScreen-${settings.homeView}');
      await _show(t, const StatsScreen());
      await _show(t, const StatsScreen(kind: 'cardio'), 'StatsScreen-cardio');
      await _show(t, const ProgramScreen());
      await _show(t, const ImportExportScreen());
      await _show(t, const BodyScreen());
      await _show(t, const RunningScreen());
      await _show(t, NewWorkoutScreen(date: day, gymOnly: true));
      await _show(
        t,
        WorkoutScreen(
          workout: Workout(
            date: day,
            title: settings.program!.plan.first.display,
            programDay: settings.program!.plan.first.name,
          ),
          planDay: settings.program!.plan.first,
        ),
      );
      await _show(
        t,
        ActivityScreen(
          workout: Workout(date: day, activity: 'Salibandy'),
        ),
      );
      await t.pumpWidget(const SizedBox());

      // 5. Puhdas pöytä seuraavalle kierrokselle.
      await dir.delete(recursive: true);
      await dir.create();
      store.workouts = [];

      final mb = ProcessInfo.currentRss ~/ (1024 * 1024);
      rss.add(mb);
      log.writeAsStringSync('$round,${watch.elapsed.inSeconds},$mb,$n\n', mode: FileMode.append);
      // ignore: avoid_print
      print('SOAK kierros $round ${watch.elapsed.inSeconds}s rss=${mb}Mt treenit=$n kieli=$uiLang');
    }
    // Muistivuodon tarkistus: 3 viimeisen kierroksen keskiarvo vs. kierrokset 3–5 (lämpeneminen ohi).
    if (rss.length >= 8) {
      double avg(Iterable<int> x) => x.reduce((a, b) => a + b) / x.length;
      final early = avg(rss.sublist(2, 5)), late = avg(rss.sublist(rss.length - 3));
      // ignore: avoid_print
      print('KIERROKSIA $round, RSS alussa ${early.round()} Mt, lopussa ${late.round()} Mt, loki ${log.path}');
      for (final e in _times.entries) {
        final v = e.value;
        final first = v.take(3).reduce((a, b) => a + b) / 3, last = v.skip(v.length - 3).reduce((a, b) => a + b) / 3;
        // ignore: avoid_print
        print(
          'SOAK aika ${e.key}: alussa ${first.round()} ms, lopussa ${last.round()} ms, max ${v.reduce((a, b) => a > b ? a : b)} ms',
        );
      }
      expect(late, lessThan(early * 1.25 + 30), reason: 'muisti kasvoi: $rss');
    }
    // Tyhjä näkymä ja hetki aikaa, ettei logon kuvan purku jää kesken ikkunan sulkeutuessa
    // (Windows: "No Impeller context is available" testin lopussa).
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    await dir.delete(recursive: true);
    // ignore: avoid_print
    print('SOAK VALMIS');
  }, timeout: const Timeout(Duration(minutes: 90)));
}
