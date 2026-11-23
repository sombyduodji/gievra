import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/csv_export.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';

// Yötesti 21.11.: oudot syötteet uusissa kentissä (Mikä painoi, muistiinpanot, rasitus). Keksityt tiedot.
void main() {
  tearDown(() => debugSetCatalog('fi', const {}));

  test('Muistiinpanot, joissa Markdown-otsikoita ja ---, säilyvät tallennuksessa sellaisinaan', () {
    const notes = 'testi ---\n## Liikunta\n- Sali: 99:99\nfeeling: 5\n---\n# otsikko';
    final w = Workout(date: DateTime(2026, 11, 20), title: 'Koripallo', activity: 'Koripallo', session: 2)
      ..seconds = 69
      ..minutes = 1
      ..feeling = 2
      ..dayReasons = ['stressi']
      ..notes = notes;
    final back = parseWorkout(workoutToMarkdown(w));
    expect(back.notes, notes);
    expect((back.feeling, back.seconds, back.activity), (2, 69, 'Koripallo'));
    expect(back.dayReasons, ['stressi']);
  });

  test('Käsin muokattu day_feeling: kaava ja erottimet eivät riko CSV:tä', () {
    debugSetCatalog('fi', const {});
    final w = parseWorkout(
      '---\ndate: 2026-11-20\ntitle: Kävely\nsession: 1\nactivity: Kävely\nduration: 30 min\nfeeling: 1\n'
      'day_feeling: =HYPERLINK("http://x"), väsynyt; "lainaus"\ntags: [treeni]\n---\n\n# Kävely 2026-11-20\n',
    );
    expect(w.dayReasons, ['=HYPERLINK("http://x")', 'väsynyt; "lainaus"']);
    final d = DateTime(2026, 11, 20);
    final txt = buildCsvExport(
      [w],
      BodyLog(),
      CsvExportOptions(from: d, to: d),
    ).firstWhere((f) => f.name.startsWith('liikunta')).text;
    final lines = txt.trim().split('\n');
    expect(lines.length, 3, reason: 'kommenttirivi, otsikko ja yksi rivi');
    expect(txt, isNot(contains(';=HYPERLINK')), reason: 'kaava ei ala solun alusta');
    expect(txt, contains("'=HYPERLINK"));
  });

  test('Valtava muistiinpano (100 000 merkkiä) säilyy', () {
    final long = List.filled(2000, 'pitkä sana ' * 4).join('\n').trim();
    final w = Workout(date: DateTime(2026, 11, 20), title: 'Treeni')..notes = long;
    expect(parseWorkout(workoutToMarkdown(w)).notes, long);
  });
}
