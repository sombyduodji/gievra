import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/bug_report.dart';

// Vikailmoituksen liitteet: 3 uusinta treeniä valmiiksi, vanhemmat "Näytä lisää" -erissä valitsemattomina.
// Keksityt treenit väliaikaisessa kansiossa.
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gievra_bug');
    settings.folder = dir.path;
    store.workouts.clear();
    for (var i = 0; i < 15; i++) {
      final d = DateTime(2026, 10, 1 + i);
      final w = Workout(date: d, title: 'Treeni');
      store.workouts.add(w);
      final f = File(p.join(dir.path, workoutPath(d)));
      await f.parent.create(recursive: true);
      await f.writeAsString('# Treeni\n');
    }
  });
  tearDown(() async {
    settings.folder = null;
    store.workouts.clear();
    await dir.delete(recursive: true);
  });

  test('Oletus: 3 uusinta valittuna', () async {
    final a = await defaultReportAttachments();
    expect(a.map((x) => x.$1), ['2026-10-15.md', '2026-10-14.md', '2026-10-13.md']);
    expect(a.every((x) => x.$3), isTrue);
  });

  test('Lisää: seuraavat vanhemmat, valitsemattomina', () async {
    final more = await workoutAttachments(3, 10, on: false);
    expect(more.length, 10);
    expect(more.first.$1, '2026-10-12.md');
    expect(more.last.$1, '2026-10-03.md');
    expect(more.any((x) => x.$3), isFalse);
    expect((await workoutAttachments(13, 10, on: false)).map((x) => x.$1), ['2026-10-02.md', '2026-10-01.md']);
  });
}
