import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/effort.dart';
import 'package:treenipaivakirja/hr_calc.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/finish_sheet.dart';
import 'package:treenipaivakirja/ui/widgets.dart' show feelingSkipped;
import 'package:treenipaivakirja/ui/workout.dart' show SavedScreen;
import 'package:treenipaivakirja/ui/activity.dart' show ActivityScreen;

import 'test_fonts.dart';

// Treeni valmis -ikkuna (mockup 8 ja 9): rasituksen arvio, fiilis, salin nostot ja "Mikä tuntui raskaalta?".
// Keksityt treenit.
void main() {
  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };
  final day = DateTime(2026, 11, 10);

  setUpAll(() async {
    await loadRoboto();
  });
  setUp(() {
    settings
      ..birthYear = 1985
      ..sex = 'nainen'
      ..body = BodyLog(heightCm: 168, weights: {DateTime(2026, 11, 1): 66.0});
  });
  tearDown(() {
    settings
      ..birthYear = null
      ..sex = null
      ..body = BodyLog();
    store.workouts = [];
    debugSetCatalog('fi', const {});
  });

  HrSeries hrSeries(int bpm, int seconds) => HrSeries(DateTime(2026, 11, 10, 9), 5, List.filled(seconds ~/ 5, bpm));
  Workout walk({double km = 3, int sec = 1800, HrSeries? s}) =>
      Workout(date: day, title: 'Kävely', activity: 'Kävely', distanceKm: km)
        ..seconds = sec
        ..hrSeries = s;
  Workout gym() => Workout(date: day, title: 'Koko keho B', session: 2)
    ..minutes = 60
    ..exercises.addAll([
      ExerciseEntry('Takakyykky', [SetEntry(85, 5), SetEntry(85, 5, pr: true)]),
      ExerciseEntry('Penkkipunnerrus', [SetEntry(60, 8)]),
    ]);

  group('Rasituksen arvio', () {
    // Maksimi 208 − 0,7 × 41 = 179.
    test('sykkeestä: alle 64 % kevyt, alle 77 % reipas, muuten kova; vain jos syke vähintään puolelta', () {
      expect(estimateEffort(walk(), series: hrSeries(105, 1800), maxHr: 179), ('kevyt', EffortSource.heartRate));
      expect(estimateEffort(walk(), series: hrSeries(125, 1800), maxHr: 179), ('reipas', EffortSource.heartRate));
      expect(estimateEffort(walk(), series: hrSeries(150, 1800), maxHr: 179), ('kova', EffortSource.heartRate));
      // Syke vain 10 %: vauhdista (3 km / 30 min = 6 km/h).
      expect(estimateEffort(walk(), series: hrSeries(150, 180), maxHr: 179), ('reipas', EffortSource.pace));
    });
    test('vauhdista: kävely 4 ja 6,5 km/h rajoina, juoksu 8 km/h; muut lajit ei arviota', () {
      expect(estimateEffort(walk(km: 1.5)), ('kevyt', EffortSource.pace));
      expect(estimateEffort(walk(km: 3.5)), ('kova', EffortSource.pace));
      final run = Workout(date: day, title: 'Juoksu', activity: 'Juoksu', distanceKm: 5)..seconds = 1800;
      expect(estimateEffort(run), ('kova', EffortSource.pace));
      expect(estimateEffort(Workout(date: day, title: 'Jooga', activity: 'Jooga')..seconds = 1800), isNull);
    });
  });

  test('Salin nostot: ennätykset ja suurin painonnousu edelliseen', () {
    final prev = Workout(date: DateTime(2026, 11, 7), title: 'Koko keho B')
      ..exercises.addAll([
        ExerciseEntry('Takakyykky', [SetEntry(80, 5)]),
        ExerciseEntry('Penkkipunnerrus', [SetEntry(57.5, 8)]),
      ]);
    final (prs, best) = gymHighlights(gym(), [prev]);
    expect(prs, 1);
    expect(best, ('Takakyykky', 5.0));
  });

  Future<FinishResult?> open(
    WidgetTester tester,
    Workout w, {
    bool askIntensity = false,
    bool heavyStep = false,
    double width = 412,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FinishResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showFinishSheet(context, w: w, askIntensity: askIntensity, heavyStep: heavyStep);
                },
                child: const Text('avaa'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Kävely sykkeellä: Reipas esivalittu (arvio sykkeestä), kasvon napautus palauttaa fiiliksen', (
    tester,
  ) async {
    late FinishResult? r;
    final w = walk(s: hrSeries(125, 1800));
    tester.view.physicalSize = const Size(412 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => r = await showFinishSheet(context, w: w, askIntensity: true),
              child: const Text('avaa'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Giitu! Kävely tehty'), findsOneWidget);
    expect(find.text('✦ arvio sykkeestä'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('face_4')));
    await tester.pumpAndSettle();
    expect((r!.feeling, r!.intensity), (4, 'reipas'));
  });

  testWidgets('Rasituksen vaihto piilottaa arvion; Ohita palauttaa ohituksen ja valitun rasituksen', (tester) async {
    late FinishResult? r;
    final w = walk();
    tester.view.physicalSize = const Size(412 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => r = await showFinishSheet(context, w: w, askIntensity: true),
              child: const Text('avaa'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    expect(find.text('✦ arvio vauhdista'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('effort_kova')));
    await tester.pump();
    expect(find.byKey(const ValueKey('effortEstimate')), findsNothing);
    await tester.tap(find.text('Ohita'));
    await tester.pumpAndSettle();
    expect((r!.feeling, r!.intensity), (feelingSkipped, 'kova'));
  });

  testWidgets('Sali: nostot ylhäällä; Tahmea avaa liikkeet samaan ikkunaan, valinnat tallentuvat', (tester) async {
    late FinishResult? r;
    final w = gym();
    store.workouts = [
      Workout(date: DateTime(2026, 11, 7), title: 'Koko keho B')
        ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(80, 5)])),
    ];
    tester.view.physicalSize = const Size(412 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => r = await showFinishSheet(context, w: w, heavyStep: true),
              child: const Text('avaa'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    expect(find.text('🏆 1 ennätys!'), findsOneWidget);
    expect(find.text('⬆ Takakyykky +5 kg'), findsOneWidget);
    expect(find.text('Rasitus'), findsNothing, reason: 'salissa ei rasitusta');
    await tester.tap(find.byKey(const ValueKey('face_2')));
    await tester.pumpAndSettle();
    expect(find.text('Mikä tuntui raskaalta?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('heavy_Takakyykky')));
    await tester.tap(find.text('väsynyt'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('heavyDone')));
    await tester.tap(find.byKey(const ValueKey('heavyDone')));
    await tester.pumpAndSettle();
    expect(r!.feeling, 2);
    expect(w.tooHeavy, {'Takakyykky'});
    expect(w.moveFeeling['Takakyykky'], 1);
    expect(w.dayReasons, {'väsynyt'});
  });

  testWidgets('Yhteenveto: fiilisrivillä liian raskaiksi merkityt liikkeet', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final w = gym()
      ..feeling = 2
      ..tooHeavy.add('Takakyykky');
    await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w)));
    await tester.pump();
    expect(find.text('Liian raskas: Takakyykky'), findsOneWidget);
  });

  testWidgets('Tallennettu liikunta: rasitus ja fiilis samalla uudella ulkoasulla, valinta vaihtuu', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final w = walk()
      ..intensity = 'reipas'
      ..feeling = 4;
    store.workouts = [w];
    await tester.pumpWidget(MaterialApp(home: ActivityScreen(workout: w)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(EffortScale), findsOneWidget);
    expect(find.byType(FaceRow), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing, reason: 'vanha rasitusvalinta poissa');
    // Rasitus ja fiilis samassa kortissa, peräkkäin.
    final card = find.byType(EffortFeelingCard);
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(EffortScale)), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(FaceRow)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // Teksti ei katkea: kaikki kielet, kapea ja leveä puhelin, tavallinen ja iso teksti.
  for (final lang in ['fi', 'en', 'se']) {
    for (final (width, scale) in [(360.0, 1.0), (360.0, 1.3), (412.0, 1.0), (412.0, 1.3), (412.0, 2.0)]) {
      for (final kind in ['kävely', 'sali raskas']) {
        testWidgets('$lang ${width.round()} dp ${(scale * 100).round()} %: $kind', (tester) async {
          debugSetCatalog(lang, lang == 'fi' ? const {} : po[lang]!);
          final w = kind == 'kävely' ? walk(s: hrSeries(125, 1800)) : gym();
          await open(
            tester,
            w,
            askIntensity: kind == 'kävely',
            heavyStep: kind != 'kävely',
            width: width,
            scale: scale,
          );
          if (kind != 'kävely') {
            await tester.tap(find.byKey(const ValueKey('face_1')));
            await tester.pumpAndSettle();
          }
          final sheet = tester.renderObject<RenderBox>(find.byKey(const ValueKey('finishSheet')));
          void walkTree(RenderObject o) {
            if (o is RenderParagraph) {
              expect(o.didExceedMaxLines, isFalse, reason: o.text.toPlainText());
              // Yksikään sana ei katkea kesken: jokainen sana mahtuu kappaleen leveyteen (laatat, otsikot).
              final style = (o.text as TextSpan).style;
              for (final word in o.text.toPlainText().split(RegExp(r'\s+'))) {
                if (word.isEmpty) continue;
                final tp = TextPainter(
                  text: TextSpan(text: word, style: style),
                  textDirection: TextDirection.ltr,
                  textScaler: o.textScaler,
                )..layout();
                expect(tp.width, lessThanOrEqualTo(o.size.width + 1), reason: 'sana katkeaa: $word');
              }
            }
            if (o is RenderFittedBox && o.child != null && o.child!.hasSize && o.hasSize) {
              final c = o.child!.size;
              final f = [o.size.width / c.width, o.size.height / c.height, 1.0].reduce((a, b) => a < b ? a : b);
              final txt = <String>[];
              void collect(RenderObject x) {
                if (x is RenderParagraph) txt.add(x.text.toPlainText());
                x.visitChildren(collect);
              }

              collect(o);
              expect(f, greaterThanOrEqualTo(scale >= 2 ? .6 : .75), reason: 'pienenee liikaa: ${txt.join()}');
            }
            o.visitChildren(walkTree);
          }

          walkTree(sheet);
          expect(tester.takeException(), isNull);
          debugSetCatalog('fi', const {});
        });
      }
    }
  }
}
