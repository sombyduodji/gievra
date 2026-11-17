import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/health_update.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/workout.dart';
import 'package:treenipaivakirja/ui/hc_update.dart';

// Keksityt arvot (ei oikeita tietoja).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, 0, 10).isAfter(now)
      ? now.subtract(const Duration(hours: 2))
      : DateTime(now.year, now.month, now.day, 0, 10);
  Workout gym() => Workout(
    date: DateTime(start.year, start.month, start.day),
    title: 'Koko keho B',
    started: start,
    exercises: [
      ExerciseEntry('Takakyykky', [SetEntry(60, 8)]),
    ],
  )..seconds = 48 * 60;
  HealthCandidate cand({int? kcal = 290}) => HealthCandidate(
    session: true,
    start: start.subtract(const Duration(minutes: 2)),
    end: start.add(const Duration(minutes: 51)),
    app: 'Oura',
    hrAvg: 112,
    hrMax: 150,
    kcal: kcal,
  );

  test('Erot: puuttuva syke ja kalorit valmiiksi valittuina, kesto oletuksena pois', () {
    final ch = hcChanges(gym(), cand());
    expect(ch.map((c) => c.field), [HcField.hr, HcField.kcal, HcField.duration]);
    expect(ch.where((c) => c.preselect).map((c) => c.field), [HcField.hr, HcField.kcal]);
  });

  test('Sykevyöllä kirjattu syke ei ole valmiiksi valittu; päivitys vain valituille ja kumoa palauttaa', () {
    final w = gym()
      ..hrAvg = 118
      ..hrMax = 160
      ..hrSource = 'sykevyö';
    final ch = hcChanges(w, cand());
    expect(ch.firstWhere((c) => c.field == HcField.hr).preselect, isFalse);
    final snap = HcSnapshot(w);
    applyHcChanges(w, cand(), {HcField.kcal});
    expect(w.hrAvg, 118);
    expect(w.kcal, 290);
    expect(w.kcalSource, 'kello');
    snap.restore(w);
    expect(w.kcal, isNull);
    expect(w.healthSource, isNull);
  });

  test('Ei eroja: ei mitään uutta', () {
    final w = gym();
    applyHcChanges(w, cand(), {HcField.hr, HcField.kcal});
    expect(hcChanges(w, cand()).where((c) => c.preselect), isEmpty);
  });

  testWidgets('Tallennettu treeni: Uutta tietoa -rivi, lista ja Päivitä 2 tietoa; rivi katoaa', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('gievra-hc');
    settings.folder = dir.path;
    HcUpdateRow.debugFetch = (a, b) async => [cand()];
    addTearDown(() {
      HcUpdateRow.debugFetch = null;
      settings.folder = null;
      store.workouts = [];
      dir.deleteSync(recursive: true);
    });
    final w = gym()..minutes = 48;
    store.workouts = [w];
    await tester.pumpWidget(MaterialApp(home: SavedScreen(workout: w, history: true)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Uutta tietoa: syke, kalorit'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hcUpdateRow')));
    await tester.pumpAndSettle();
    expect(find.text('Päivitä 2 tietoa'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hcApply')));
    for (var k = 0; k < 30 && find.textContaining('Päivitetty').evaluate().isEmpty; k++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(w.hrAvg, 112);
    expect(w.kcal, 290);
    expect(w.seconds, 48 * 60, reason: 'kesto ei valittu');
    expect(find.textContaining('Päivitetty: syke, kalorit'), findsOneWidget);
    expect(find.text('Uutta tietoa: syke, kalorit'), findsNothing);
    // Kumoa-ilmoitus katoaa itsestään (ennen jäi ruudulle, kunnes napautettiin; käyttäjä 17.11.).
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.textContaining('Päivitetty'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
