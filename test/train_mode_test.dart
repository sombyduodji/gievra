import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/main.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sports.dart';
import 'package:treenipaivakirja/stats.dart';

void main() {
  test('Vanha sports-asetus -> treenitila; mode voittaa', () {
    final s = Settings()..applyMarkdown('---\nname: A\nsports: true\n---\n');
    expect(s.trainMode, 'both');
    expect(s.sports, isTrue);
    final g = Settings()..applyMarkdown('---\nname: A\nsports: false\n---\n');
    expect(g.trainMode, 'gym');
    final c = Settings()..applyMarkdown('---\nname: A\nsports: true\nmode: cardio\n---\n');
    expect(c.trainMode, 'cardio');
    final md = c.settingsToMarkdown();
    expect(md, contains('mode: cardio'));
    expect(md, contains('sports: true')); // vanhemmat versiot näkevät liikunnan
    expect((Settings()..applyMarkdown(md)).trainMode, 'cardio');
  });

  testWidgets('Etusivu: Molemmat-tilassa Sali / Kestävyys -valinta, muuten ei', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => d.toString().contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    settings
      ..name = 'Testi'
      ..introDone = true
      ..program = null
      ..trainMode = 'both'
      ..homeView = 'gym';
    store.workouts = [
      Workout(date: DateTime.now(), title: 'Juoksu', activity: 'Juoksu', distanceKm: 6, seconds: 1800, minutes: 30),
    ];
    await tester.pumpWidget(const TreeniApp());
    await tester.pump();
    expect(find.text('Kestävyys'), findsOneWidget);
    expect(find.text('Lisää lenkki'), findsNothing);
    await tester.tap(find.text('Kestävyys'));
    await tester.pump();
    expect(settings.homeView, 'cardio');
    expect(find.text('Lisää lenkki'), findsOneWidget);
    expect(find.text('6 km'), findsOneWidget); // tämän viikon kilometrit
    // Pelkkä sali: ei valintaa, vanha etusivu.
    settings.setTrainMode('gym');
    await tester.pump();
    expect(find.text('Kestävyys'), findsNothing);
    expect(find.text('Lisää lenkki'), findsNothing);
    // Pelkkä kestävyys: ei valintaa, kestävyysnäkymä.
    settings.setTrainMode('cardio');
    await tester.pump();
    expect(find.text('Kestävyys'), findsNothing);
    expect(find.text('Lisää lenkki'), findsOneWidget);
    settings.trainMode = 'gym';
    store.workouts = [];
  });

  test('Lajit käyttömäärän mukaan', () {
    final order = sportsByUse(['Kävely', 'Pyöräily', 'Kävely', null, 'Pyöräily', 'Kävely']).map((s) => s.name);
    expect(order.take(3), ['Kävely', 'Pyöräily', 'Juoksu']); // käyttämättömät alkuperäisessä järjestyksessä
  });

  test('kooste: kaikki, sali ja kestävyys erikseen; viikoittaiset määrät', () {
    final mon = DateTime(2026, 11, 2);
    final ws = [
      Workout(
        date: mon,
        title: 'Koko keho A',
        exercises: [
          ExerciseEntry('Takakyykky', [SetEntry(100, 5)]),
        ],
      )..minutes = 60,
      Workout(date: mon, session: 2, title: 'Juoksu', activity: 'Juoksu')
        ..seconds = 1800
        ..distanceKm = 5
        ..hrAvg = 140,
      Workout(date: DateTime(2026, 11, 4), title: 'Pyöräily', activity: 'Pyöräily')..minutes = 45,
    ];
    final all = recap(ws, mon, DateTime(2026, 11, 9));
    expect((all.gym, all.activities, all.minutes, all.gymMinutes, all.cardioMinutes), (1, 2, 135, 60, 75));
    expect(all.sports['Juoksu']!.km, 5);
    expect(all.hrAvg, 140);
    expect(recap(ws, mon, DateTime(2026, 11, 9), kind: 'gym').sessions, 1);
    expect(recap(ws, mon, DateTime(2026, 11, 9), kind: 'cardio').sessions, 2);
    final weeks = weeklyCounts(ws, DateTime(2026, 11, 7));
    expect(weeks.length, 12);
    expect((weeks.last.$2, weeks.last.$3), (1, 2));
  });
}
