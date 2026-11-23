import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';
import 'package:treenipaivakirja/ui/exercise_guide.dart';
import 'package:treenipaivakirja/ui/picker.dart';
import 'package:treenipaivakirja/ui/program_view.dart';

// Käyttäjä 16.11.: olkapään ja selän osat alariveinä, keskivartalo omana rivinä, liikevalitsimessa ohje.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Program program() => Program(
    goal: 'lihaskasvu',
    experience: 'keski',
    days: 1,
    minutes: 60,
    start: DateTime(2026, 11, 2),
    deloadEvery: 0,
    plan: [
      PlanDay('A', [
        PlanItem('Pystypunnerrus', slotOf('Pystypunnerrus'), 3, 6, 10, '1–2', 120),
        PlanItem('Vipunosto sivulle', slotOf('Vipunosto sivulle'), 3, 12, 20, '0–2', 60),
        PlanItem('Kulmasoutu', slotOf('Kulmasoutu'), 4, 8, 12, '1–2', 120),
        PlanItem('Leuanveto', slotOf('Leuanveto'), 3, 6, 10, '1–2', 120),
        PlanItem('Maastaveto', slotOf('Maastaveto'), 2, 5, 5, '1–2', 180),
        PlanItem('Pallof press', slotOf('Pallof press'), 2, 10, 15, '0–2', 60),
      ]),
    ],
  );

  test('osat lasketaan liikemallista', () {
    final st = statsOf(program());
    expect(st.sub['etuolkapää'], 3, reason: 'pystypunnerrus');
    expect(st.sub['sivuolkapää'], 3 + 1.5, reason: 'vipunosto + puolet pystypunnerruksesta');
    expect(st.sub['takaolkapää'], 2, reason: 'puolet soudusta');
    expect(st.sub['yläselkä'], greaterThanOrEqualTo(4), reason: 'soutu täysin');
    expect(st.sub['leveä selkälihas'], 3 + 2, reason: 'leuanveto + puolet soudusta');
    expect(st.sub['alaselkä'], greaterThan(0), reason: 'maastaveto');
    expect(st.weekly['vatsa'], 2, reason: 'Pallof press');
    expect(
      st.weekly.keys.where((k) => k.contains('olkapää') && k != 'olkapää'),
      isEmpty,
      reason: 'pääkartta ennallaan',
    );
  });

  testWidgets('viikon kuorma: alarivit ja keskivartalo näkyvät', (tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: WeeklyLoadCard(program: program())),
        ),
      ),
    );
    for (final x in [
      'etuolkapää',
      'sivuolkapää',
      'takaolkapää',
      'leveä\nselkälihas', // pitkä nimi kahdelle riville
      'yläselkä',
      'alaselkä',
      'keskivartalo',
    ]) {
      expect(find.text(x), findsOneWidget, reason: x);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('viikon kuorma: alariveillä tämän viikon sarjat sinisenä palkkina ja "tehty / suunniteltu" (22.11.)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    Future<void> show(Map<String, double>? done) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklyLoadCard(program: program(), done: done),
          ),
        ),
      ),
    );
    final bars = find.byType(LinearProgressIndicator);
    await show(null);
    final planned = tester.widgetList(bars).length;
    expect(find.text('3'), findsWidgets, reason: 'etuolkapää ilman toteutunutta: vain suunniteltu');
    await show({'olkapää': 2, 'etuolkapää': 6, 'alaselkä': 0.5, 'vatsa': 1});
    expect(find.text('6 / 3'), findsOneWidget, reason: 'etuolkapää');
    expect(find.text('1 / 2'), findsOneWidget, reason: 'keskivartalo');
    expect(find.textContaining(' · '), findsNothing, reason: 'vanha "suunniteltu · tehty" poistui');
    expect(find.text('6 / 3 ✓'), findsNothing, reason: 'alariveillä ei suositusta');
    expect(tester.widgetList(bars).length, planned * 2, reason: 'jokaiselle riville sininen palkki');
    expect(tester.takeException(), isNull);
  });

  testWidgets('liikevalitsin: ▶ avaa ohjeen, josta voi valita liikkeen', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    expect(hasExerciseGuide('Takakyykky'), isTrue);
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await Navigator.of(context)
                    .push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen())),
            child: const Text('avaa'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Näin teet: Takakyykky'));
    for (var k = 0; k < 5; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Valitse tämä liike'), findsOneWidget);
    await tester.tap(find.text('Valitse tämä liike'));
    for (var k = 0; k < 10; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(ExercisePickerScreen), findsNothing, reason: 'valitsin suljettu');
    expect(picked, 'Takakyykky');
  });

  test('oma liike: valitut lihakset tallentuvat ja näkyvät viikon kuormassa; vanha oma liike kategoriasta', () {
    settings.customExercises = [];
    settings.customCategory = {};
    settings.customMuscles = {};
    addTearDown(() {
      settings.customExercises = [];
      settings.customCategory = {};
      settings.customMuscles = {};
      customExerciseMuscles.clear();
    });
    settings.addCustomExercises({'Testisoutu kumilla': 'Selkä', 'Oma rintaliike': 'Rinta'});
    settings.setCustomMuscles('Testisoutu kumilla', ['yläselkä', 'takaolkapää', 'kyynärvarret']);
    final md = settings.settingsToMarkdown();
    expect(md, contains('## Omien liikkeiden lihakset'));
    expect(md, contains('- Testisoutu kumilla: yläselkä, takaolkapää, kyynärvarret'));
    settings.customMuscles = {};
    settings.applyMarkdown(md);
    expect(settings.customMuscles['Testisoutu kumilla'], ['yläselkä', 'takaolkapää', 'kyynärvarret']);
    final load = loadOf('Testisoutu kumilla', slotOf('Testisoutu kumilla'));
    expect(load['yläselkä'], 1);
    expect(load['selkä'], 1, reason: 'osa laskee myös pääpalkkiin');
    expect(load['kyynärvarret'], 1);
    expect(loadOf('Oma rintaliike', '')['rinta'], 1, reason: 'ilman valintaa kategorian mukaan');
  });

  test('pohje, kyynärvarret ja lähentäjät; Kööpenhaminan lähennys ei ole täyttä keskivartaloa', () {
    expect(loadOf('Ranteen koukistus', slotOf('Ranteen koukistus'))['kyynärvarret'], 1);
    expect(loadOf('Vasarakääntö', slotOf('Vasarakääntö'))['kyynärvarret'], .5);
    expect(loadOf('Takakyykky', slotOf('Takakyykky'))['lähentäjät'], .5);
    final cph = loadOf('Kööpenhaminan lähennys', slotOf('Kööpenhaminan lähennys'));
    expect((cph['lähentäjät'], cph['vatsa']), (1, .5));
    expect(loadOf('Pohjenousu seisten', slotOf('Pohjenousu seisten'))['pohje'], 1);
  });
}
