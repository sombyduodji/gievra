import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/share_text.dart';
import 'package:treenipaivakirja/sync/sync_engine.dart';

void main() {
  test('Liikunta .md:ssä edestakaisin, vauhti lasketaan', () {
    final w = Workout(
      date: DateTime(2026, 11, 7),
      title: 'Juoksu',
      activity: 'Juoksu',
      minutes: 45,
      distanceKm: 8.2,
      intensity: 'reipas',
      feeling: 4,
      session: 2,
    );
    expect(w.pace, '5:29 /km');
    final md = workoutToMarkdown(w);
    expect(md, contains('activity: Juoksu'));
    expect(md, contains('- Juoksu: 45 min, 8,2 km, 5:29 /km, reipas'));
    final r = parseWorkout(md);
    expect(
      (r.activity, r.minutes, r.distanceKm, r.intensity, r.session, r.exercises.length),
      ('Juoksu', 45, 8.2, 'reipas', 2, 0),
    );
    expect(r.isEmpty, isFalse);
    expect(shareText(r), contains('Juoksu 7.11.2026'));
    expect(shareText(r), contains('5:29 /km'));
  });

  test('Useampi treeni samana päivänä: omat tiedostot, synkronointi ja tallennus', () async {
    expect(workoutPath(DateTime(2026, 11, 7)), '2026/2026-11-07.md');
    expect(workoutPath(DateTime(2026, 11, 7), 2), '2026/2026-11-07-2.md');
    expect(sessionFromName('2026-11-07-2.md'), 2);
    expect(sessionFromName('2026-11-07.md'), 1);
    expect(isSyncable('2026/2026-11-07-2.md'), isTrue);
    expect(dateOfPath('2026/2026-11-07-3.md'), DateTime(2026, 11, 7));

    final dir = await Directory.systemTemp.createTemp('sessiot');
    settings.folder = dir.path;
    store.workouts = [];
    final gym = Workout(
      date: DateTime(2026, 11, 7),
      title: 'Koko keho A',
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(100, 5)]),
      ],
    );
    await store.save(gym);
    expect(store.nextSession(DateTime(2026, 11, 7)), 2);
    await store.save(
      Workout(date: DateTime(2026, 11, 7), session: 2, title: 'Salibandy', activity: 'Salibandy', minutes: 90),
    );
    expect(File('${dir.path}/2026/2026-11-07-2.md').existsSync(), isTrue);
    await store.reload();
    final day = store.onDay(DateTime(2026, 11, 7));
    expect(day.map((w) => w.title), ['Koko keho A', 'Salibandy']);
    await store.delete(DateTime(2026, 11, 7), 2);
    expect(store.onDay(DateTime(2026, 11, 7)).length, 1);
    settings.folder = null;
    await dir.delete(recursive: true);
  });

  test('Salitreenin jakoteksti', () {
    final w = Workout(
      date: DateTime(2026, 11, 7),
      title: 'Jalat',
      minutes: 55,
      feeling: 5,
      exercises: [
        ExerciseEntry('Takakyykky', [SetEntry(100, 5), SetEntry(110, 3, pr: true)]),
      ],
    );
    final t = shareText(w);
    expect(t, contains('💪 Jalat 7.11.2026'));
    expect(t, contains('Takakyykky: 2 sarjaa, paras 110 kg × 3 🏆'));
    expect(t, contains('Fiilis: 🤩 Loistava'));
    expect(thousands(3820), '3820');
    expect(thousands(12500), '12\u00a0500');
    expect(thousands(950), '950');
    expect(thousands(1234567), '1\u00a0234\u00a0567');
  });

  test('Kellon tiedot .md:ssä ja jaossa; kellon kesto merkitään', () {
    final w = Workout(
      date: DateTime(2026, 11, 7),
      title: 'Juoksu',
      activity: 'Juoksu',
      minutes: 52,
      distanceKm: 9,
      kcal: 610,
      hrAvg: 148,
      hrMax: 181,
      watchTime: true,
    );
    final md = workoutToMarkdown(w);
    expect(md, contains('duration: 52 min (kello)'));
    expect(md, contains('kcal: 610'));
    final r = parseWorkout(md);
    expect((r.minutes, r.kcal, r.hrAvg, r.hrMax, r.watchTime), (52, 610, 148, 181, true));
    expect(shareText(r), contains('❤️ syke 148/181 · 610 kcal'));
    expect(parseWorkout('---\ndate: 2026-11-07\nduration: 40 min\n---\n').watchTime, isFalse);
  });
}
