import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/csv_export.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/bug_report.dart' show reportHrKeys;

// Kellon (Health Connect) sykekäyrä kulkee kaikkialle kuten sykevyön: .md-tiedosto, .md-tuonti, varmuuskopio ja
// palautus, CSV-vienti ja vikailmoituksen terveystietoliite (15.11.). Harva kello (60 s) ja tiheä (5 s). Keksityt.
void main() {
  final day = DateTime(2026, 3, 5);
  Workout watchWorkout(int interval, int n) {
    final t0 = DateTime(2026, 3, 5, 17, 46, 3);
    final w = Workout(date: day, title: 'Treeni', session: 2)
      ..started = DateTime(2026, 3, 5, 17, 46)
      ..minutes = 72
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)]));
    applyCandidate(
      w,
      HealthCandidate(
        session: true,
        start: t0,
        end: t0.add(const Duration(minutes: 72)),
        app: 'Health Sync',
        hrAvg: 115,
        hrMax: 138,
        kcal: 552,
        hrSamples: [for (var i = 0; i < n; i++) (t0.add(Duration(seconds: interval * i)), 100 + i % 38)],
      ),
    );
    return w;
  }

  for (final (interval, n) in [(5, 864), (60, 72)]) {
    group('kello $interval s', () {
      final w = watchWorkout(interval, n);
      final md = workoutToMarkdown(w);

      test('.md: käyrä, lähde ja välitiedot säilyvät', () {
        expect(md, contains('hr_series: $interval 17:46:03 '));
        final back = parseWorkout(md);
        expect(back.hrSeries!.interval, interval);
        expect(back.hrSeries!.readingCount, n);
        expect(back.hrSource, 'kello');
        expect(back.hrAvg, 115);
        expect(back.kcal, 552);
      });

      test('.md-tuonti ja varmuuskopion palautus (zip)', () {
        final fromMd = readMdBytes({'2026-03-05-2.md': utf8.encode(md)}).workouts.single;
        expect(fromMd.hrSeries!.encode(), w.hrSeries!.encode());
        final zip = Archive()..addFile(ArchiveFile.bytes('Treenit/2026/2026-03-05-2.md', utf8.encode(md)));
        final restored = readZip(ZipEncoder().encode(zip)).workouts.single;
        expect(restored.hrSeries!.encode(), w.hrSeries!.encode());
        expect(restored.hrSource, 'kello');
      });

      test('CSV: syke.csv lukema kerrallaan oikeaan kellonaikaan, lähde Älykello', () {
        final files = {
          for (final f in buildCsvExport([w], BodyLog(), CsvExportOptions(from: DateTime(2000), to: DateTime(2030))))
            f.name: f.text,
        };
        final rows = files['syke.csv']!.trim().split('\n');
        expect(rows.length, n + 2, reason: 'tunnisterivi, otsikko ja lukemat');
        expect(rows[1], 'Päivä;Treeni;Kellonaika;Syke');
        expect(rows[2], '2026-03-05;Treeni;17:46:03;100');
        final t2 = DateTime(2026, 3, 5, 17, 46, 3).add(Duration(seconds: interval));
        expect(
          rows[3],
          startsWith('2026-03-05;Treeni;${t2.hour}:${t2.minute}:${t2.second.toString().padLeft(2, '0')};'),
        );
        expect(files['salitreenit.csv'], contains('Älykello'));
      });

      test('vikailmoitus: käyrä ja lähde terveystietoliitteeseen (oletuksena pois)', () {
        final hrLines = md.split('\n').where((l) => reportHrKeys.any((k) => l.startsWith('$k:'))).toList();
        expect(hrLines.map((l) => l.split(':').first), containsAll(['hr_series', 'hr_source', 'hr_avg', 'kcal']));
      });
    });
  }
}
