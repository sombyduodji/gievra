import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sami_material.dart';
import 'package:treenipaivakirja/session_compare.dart' show fmtDuration;
import 'package:treenipaivakirja/ui/watch.dart';
import 'package:treenipaivakirja/ui/widgets.dart';
import 'package:treenipaivakirja/ui/workout.dart';

// Muokkaa kestoa: käsin asetettu kesto, sama arvo kellon tiedoissa, valintaikkunat kaikilla kielillä.
// Keksitty treeni (ei oikeita tietoja).
Workout _done() => Workout(
  date: DateTime(2026, 11, 7),
  title: 'Koko keho A',
  exercises: [
    ExerciseEntry('Takakyykky', [SetEntry(60, 8), SetEntry(80, 6)]),
  ],
)..minutes = 52;

Widget _app(Widget home, String lang) => MaterialApp(
  locale: flutterLocale(lang),
  supportedLocales: appSupportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  home: home,
);

void main() {
  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };
  void lang(String l) => debugSetCatalog(l, l == 'fi' ? const {} : po[l]!, english: po['en']);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings.watch = false;
  });
  tearDown(() {
    lang('fi');
    settings.watch = false;
  });

  test('Käsin asetettu kesto tallentuu merkinnällä ja säilyy; kello ja käsin eivät sekoitu', () {
    final w = _done()
      ..minutes = 75
      ..manualTime = true
      ..started = DateTime(2026, 11, 7, 17, 30);
    final md = workoutToMarkdown(w);
    expect(md, contains('duration: 75 min (käsin)'));
    final r = parseWorkout(md);
    expect((r.minutes, r.manualTime, r.watchTime, r.fixedTime), (75, true, false, true));
    expect(r.started, DateTime(2026, 11, 7, 17, 30));
    // Kello voittaa merkinnässä; vanhat tiedostot ilman merkintää ennallaan.
    expect(workoutToMarkdown(r..watchTime = true), contains('duration: 75 min (kello)'));
    final old = parseWorkout('---\ndate: 2026-11-07\nduration: 40 min\n---\n');
    expect((old.minutes, old.manualTime, old.watchTime, old.fixedTime), (40, false, false, false));
  });

  for (final l in ['fi', 'en', 'se']) {
    testWidgets('Muokkaa kestoa ($l): kysyy ensin, asettaa keston ja aloitusajan', (tester) async {
      lang(l);
      final w = _done();
      await tester.pumpWidget(_app(WorkoutScreen(workout: w), l));
      await tester.pump();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('Muokkaa kestoa')));
      await tester.pumpAndSettle();
      // Valmis treeni: sama kysymys kuin muissa muokkauksissa.
      expect(find.text(t('Muokataanko tallennettua treeniä?')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, t('Muokkaa')));
      await tester.pumpAndSettle();
      expect(find.text(t('Muokkaa kestoa')), findsOneWidget);
      expect(find.text(t('ei tiedossa')), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '75');
      await tester.pump();
      // Aloitusaika kellotaululta: otsikko ja painikkeet käyttöliittymän kielellä.
      await tester.tap(find.text(t('ei tiedossa')));
      await tester.pumpAndSettle();
      expect(find.text(t('Aloitusaika')), findsNWidgets(2));
      expect(find.text(t('Peruuta')), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, 'OK').last);
      await tester.pumpAndSettle();
      expect(find.textContaining(t('Päättyi klo {0}', ['']).trim()), findsOneWidget);
      await tester.tap(find.text(t('Tallenna')));
      await tester.pumpAndSettle();
      expect((w.minutes, w.manualTime, w.watchTime), (75, true, false));
      expect(w.started, isNotNull);
      expect(find.textContaining(t('kesto {0}', [fmtDuration(75)])), findsOneWidget);
    });
  }

  testWidgets('Kellon tiedot päällä: ei valikossa, kesto muutetaan kellon ruudusta (sama arvo)', (tester) async {
    settings.watch = true;
    final w = _done(); // kesto ajastimesta (ei kellosta)
    await tester.pumpWidget(_app(WorkoutScreen(workout: w), 'fi'));
    await tester.pump();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Muokkaa kestoa'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    // Kellon ruutu näyttää saman keston, vaikka se tuli ajastimesta.
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: WatchCard(w: w, withDuration: true, onChanged: () {}),
        ),
        'fi',
      ),
    );
    expect(find.text('52 min'), findsOneWidget);
    await tester.tap(find.text('52 min'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '64');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect((w.minutes, w.watchTime, w.manualTime), (64, true, false));
  });

  for (final (l, month, help) in [
    ('fi', 'marraskuu 2026', 'Valitse päivä'),
    ('en', 'November 2026', 'Choose a date'),
    ('se', 'skábmamánnu 2026', 'Vállje beaivvi'),
  ]) {
    testWidgets('Kalenteri käyttöliittymän kielellä ($l)', (tester) async {
      lang(l);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) => TextButton(
              onPressed: () =>
                  pickDate(c, initial: DateTime(2026, 11, 10), first: DateTime(2000), last: DateTime(2026, 12, 31)),
              child: const Text('x'),
            ),
          ),
          l,
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();
      expect(find.text(help), findsOneWidget);
      expect(find.text(month), findsOneWidget);
      expect(find.text(t('Peruuta')), findsOneWidget);
      // Saameksi Flutterin omat vihjeet saameksi (ei suomeksi).
      if (l == 'se') expect(find.byTooltip('Boahtte mánnu'), findsOneWidget);
    });
  }
}
