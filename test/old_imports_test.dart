import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/stats.dart';

// Aiempien versioiden tuonnit: test/fixtures/old_imports/<versio>/ sisältää .md-tiedostot, jotka 0.1.0 ja 0.1.10
// kirjoittivat FitNotes- ja Garmin-tuonnista (keksityt arvot, samat kuin import_test.dart ja garmin_test.dart).
// Nykyinen versio lukee ne tilastoihin ja kirjoittaa ne takaisin täsmälleen samoina.
Map<String, String> _files(String version) {
  final dir = Directory('test/fixtures/old_imports/$version');
  return {
    for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md')))
      f.path.substring(dir.path.length + 1): f.readAsStringSync(),
  };
}

void main() {
  for (final v in ['v0.1.0', 'v0.1.10']) {
    test('$v: tuodut treenit näkyvät koosteessa ja tiedostot pysyvät samoina', () {
      final files = _files(v);
      final r = readMdFiles(files);
      expect(r.workouts.length, files.length);
      for (final w in r.workouts) {
        final path = files.keys.firstWhere((k) => k.endsWith('${isoDate(w.date)}.md'));
        expect(workoutToMarkdown(w), files[path], reason: path);
      }
      final all = recap(r.workouts, DateTime(2000), DateTime(2100));
      // FitNotes: kaksi salitreeniä, toisena päivänä myös kävely muistiinpanoissa (20 min).
      expect(all.gym, 2);
      expect(all.sets, 4);
      expect(all.sports['Muu liikunta']?.minutes, 20);
      if (v == 'v0.1.10') {
        // Garmin (0.1.8 alkaen): kaksi juoksua ja uinti, voimaharjoittelu ohitettu.
        expect(all.activities, 4);
        expect(all.sports['Juoksu']!.count, 2);
        expect(all.sports['Juoksu']!.km, 17);
        expect(all.sports['Uinti']!.km, 1.5);
        expect(all.minutes, 20 + 90 + 40 + 35);
      } else {
        expect(all.activities, 1);
      }
      expect(monthlyCounts(r.workouts, DateTime(2026, 10, 31), months: 12).last, (DateTime(2026, 10), 2, 1));
    });
  }
}
