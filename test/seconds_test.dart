import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/csv_export.dart';
import 'package:treenipaivakirja/share_text.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/session_compare.dart';
import 'package:treenipaivakirja/stats.dart';
import 'package:treenipaivakirja/weekly_activity.dart';

// Jokainen sekunti lasketaan kaikissa lajeissa: tarkka aika tallentuu, ja summat pyöristetään vasta lopuksi.
// Keksityt liikunnat.
void main() {
  final day = DateTime(2026, 11, 11); // keskiviikko

  Workout act(String sport, {int? seconds, int? minutes, String? intensity}) =>
      Workout(date: day, title: sport, activity: sport)
        ..seconds = seconds
        ..minutes = minutes ?? (seconds == null ? null : (seconds / 60).round())
        ..intensity = intensity;

  test('Kooste: sekunnit yhteen, pyöristys vasta summasta', () {
    // 4 × 40 s koripalloa: ennen 4 × 1 min = 4 min (tai 4 × 0), nyt 160 s ≈ 3 min.
    final ws = [for (var i = 0; i < 4; i++) act('Koripallo', seconds: 40)];
    final r = recap(ws, DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    expect(r.seconds, 160);
    expect(r.minutes, 3);
    expect(r.cardioMinutes, 3);
    expect(r.sports['Koripallo']!.minutes, 3);
  });

  test('Vanha tiedosto ilman tarkkaa aikaa: minuutit kuten ennen', () {
    final w = parseWorkout('---\ndate: 2026-11-11\ntitle: Jooga\nactivity: Jooga\nduration: 45 min\n---\n');
    expect((w.seconds, w.minutes, workoutSeconds(w), workoutMinutes(w)), (null, 45, 2700, 45));
    expect(durationText(w), fmtDuration(45));
  });

  test('Tarkka aika tallentuu ja luetaan takaisin kaikissa lajeissa (myös muut kuin matkalajit)', () {
    final w = act('Koripallo', seconds: 16);
    final back = parseWorkout(workoutToMarkdown(w));
    expect(back.seconds, 16);
    expect(durationText(back), fmtDurationSec(16));
  });

  test('WHO-viikko: reippaat 30 s pätkät lasketaan yhteen', () {
    final ws = [for (var i = 0; i < 6; i++) act('Juoksu', seconds: 30, intensity: 'reipas')];
    final a = weekActivity(ws, day);
    expect(a.moderate, 3, reason: '6 × 30 s = 3 min (ennen 6 × pyöristys)');
  });

  test('Tiedosto: lyhyt liikunta "duration: 1 min" + "time: 0:16"; vanhempi versio näkee 1 min, tämä 0:16', () {
    final w = act('Koripallo', seconds: 16)..minutes = minutesFromSeconds(16);
    final md = workoutToMarkdown(w);
    expect(md, contains('duration: 1 min'));
    expect(md, contains('time: 0:16'));
    // Vanhempi versio, joka ei lue "time:" muissa kuin matkalajeissa: vain minuutit.
    final old = parseWorkout(md.replaceAll(RegExp(r'^time: .*\n', multiLine: true), ''));
    expect((old.seconds, old.minutes, durationText(old)), (null, 1, fmtDuration(1)));
    // Tämä versio: tarkka aika.
    final now = parseWorkout(md);
    expect((now.seconds, workoutSeconds(now), durationText(now)), (16, 16, fmtDurationSec(16)));
  });

  test('minutesFromSeconds: pyöristys, vähintään 1 kun aikaa on', () {
    expect([0, 1, 16, 29, 30, 89, 90, 3600].map(minutesFromSeconds).toList(), [0, 1, 1, 1, 1, 1, 2, 60]);
  });

  test('CSV-vienti ja jakoteksti näyttävät tarkan ajan', () {
    final w = act('Koripallo', seconds: 41)..minutes = minutesFromSeconds(41);
    final csv = buildCsvExport([w], BodyLog(), CsvExportOptions(from: DateTime(2026), to: DateTime(2027)));
    expect(csv.single.text, contains(';0:41;'));
    expect(shareText(w), contains(fmtDurationSec(41)));
    expect(shareText(w), isNot(contains('1 min')));
  });

  test('Vanha liikunta (vain minuutit) toimii ennallaan kaikkialla', () {
    final w = parseWorkout(
      '---\ndate: 2026-11-11\ntitle: Jooga\nactivity: Jooga\nduration: 45 min\nintensity: reipas\n---\n',
    );
    expect(shareText(w), contains(fmtDuration(45)));
    final csv = buildCsvExport([w], BodyLog(), CsvExportOptions(from: DateTime(2026), to: DateTime(2027)));
    expect(csv.single.text, contains(';45:00;'));
    expect(recap([w], DateTime(2026, 11, 1), DateTime(2026, 12, 1)).minutes, 45);
    expect(weekActivity([w], day).moderate, 45);
  });
}
