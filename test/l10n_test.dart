import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/exercise_names_en.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';

void main() {
  final po = parsePo(File('assets/l10n/se.po').readAsStringSync());

  tearDown(() => debugSetCatalog('fi', const {}));

  test('.po-tiedosto lukeutuu ja sisältää käännöksiä', () {
    expect(po.length, greaterThan(400));
    expect(po['Tallenna'], 'Vurke');
  });

  test('paikkamerkit {0}, {1}… ovat samat alkutekstissä ja käännöksessä', () {
    final re = RegExp(r'\{\d+\}');
    for (final e in po.entries) {
      final a = re.allMatches(e.key).map((m) => m[0]).toSet();
      final b = re.allMatches(e.value).map((m) => m[0]).toSet();
      expect(b, a, reason: e.key);
    }
  });

  test('t() kääntää, täyttää muuttujat ja palaa suomeen, jos käännös puuttuu', () {
    debugSetCatalog('se', po);
    expect(t('Tallenna'), 'Vurke');
    expect(t('Versio {0}', ['0.1.1']), 'Veršuvdna 0.1.1');
    expect(t('Tätä ei ole käännetty'), 'Tätä ei ole käännetty');
    debugSetCatalog('fi', const {});
    expect(t('Tallenna'), 'Tallenna');
  });

  test('saamenkielinen käyttöliittymä ei muuta .md-tiedostoja: tiedostomuoto ja liikkeet suomeksi', () {
    final w = Workout(date: DateTime(2026, 11, 7), title: 'Voima A')
      ..feeling = 4
      ..exercises.add(ExerciseEntry('Takakyykky', [SetEntry(100, 5)]));
    final fi = workoutToMarkdown(w);
    debugSetCatalog('se', po);
    final se = workoutToMarkdown(w);
    expect(se, fi);
    expect(se, contains('feeling: 4 🙂 Hyvä'));
    expect(se, contains('## Takakyykky'));
    // Liikkeiden mittaustavat tallentuvat suomeksi, vaikka näkyvät saameksi.
    expect(Measure.reps.label, 'toistot');
  });

  test('jokaisella liikkeellä on englanninkielinen nimi ja haku löytää sillä', () {
    for (final e in exerciseCatalog.values.expand((x) => x)) {
      expect(exerciseEnglish[e], isNotNull, reason: e);
    }
    expect(matchesSearch('Takakyykky', 'barbell squat'), isTrue);
    expect(matchesSearch('Tuplakahvakuulapystypunnerrus', 'double kettlebell'), isTrue);
  });

  test('tuplakahvakuula: paino per kuula, volyymiin molemmat', () {
    expect(loadMultiplier('Tuplakahvakuulasoutu'), 2);
    expect(loadMultiplier('Kahvakuulasoutu'), 1);
  });
}
