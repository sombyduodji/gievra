import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/anim/cue_lang.dart';
import 'package:treenipaivakirja/anim/cues.dart';
import 'package:treenipaivakirja/anim/cues_en.dart';
import 'package:treenipaivakirja/anim/motions.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/injury_data.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';

void main() {
  final all = {for (final l in exerciseCatalog.values) ...l};

  test('Jokaisella liikkeellä on tekniikkavinkit, ja animaatiot/vinkit viittaavat oikeisiin liikkeisiin', () {
    expect(all.where((e) => !exerciseCues.containsKey(e)), isEmpty);
    expect(exerciseCues.keys.where((e) => !all.contains(e)), isEmpty);
    expect(exerciseMotions.keys.where((e) => !all.contains(e)), isEmpty);
    for (final c in exerciseCues.values.expand((x) => x)) {
      expect(c.length, lessThanOrEqualTo(80), reason: c);
    }
  });

  test('Englanninkieliset vinkit: samat liikkeet ja yhtä monta vinkkiä kuin suomeksi, ei suomea', () {
    expect(exerciseCuesEn.keys.toSet(), exerciseCues.keys.toSet());
    for (final e in exerciseCues.entries) {
      expect(exerciseCuesEn[e.key]!.length, e.value.length, reason: e.key);
    }
    for (final c in exerciseCuesEn.values.expand((x) => x)) {
      expect(c, isNot(matches(RegExp('[äöÄÖ]'))), reason: c);
      expect(c.length, lessThanOrEqualTo(110), reason: c);
    }
  });

  test('Vinkit kielen mukaan: suomi, englanti, saame valinnan mukaan', () {
    const ex = 'Maastaveto';
    debugSetCatalog('fi', const {});
    expect(cuesFor(ex), exerciseCues[ex]);
    debugSetCatalog('en', const {});
    expect(cuesFor(ex), exerciseCuesEn[ex]);
    debugSetCatalog('se', const {});
    healthTextLang = 'fi';
    expect(cuesFor(ex), exerciseCues[ex]);
    healthTextLang = 'en';
    expect(cuesFor(ex), exerciseCuesEn[ex]);
    healthTextLang = 'fi';
    debugSetCatalog('fi', const {});
  });

  test('Slottien ja vammadatan liikkeet ovat luettelossa', () {
    for (final s in slots.values) {
      expect(s.defaults.where((e) => !all.contains(e)), isEmpty, reason: s.name);
    }
    for (final r in injuryRegions) {
      final names = [...r.avoid, ...r.modify.keys, ...r.substitute.keys, ...r.substitute.values, ...r.recommended];
      expect(names.where((e) => !all.contains(e)), isEmpty, reason: r.id);
    }
  });

  test('Sama liike ei toistu samana päivänä', () {
    for (final g in goals.keys) {
      for (final e in experiences.keys) {
        for (var d = 2; d <= 6; d++) {
          for (final inj in [
            <String>[],
            ...injuryRegions.map((r) => [r.id]),
          ]) {
            final p = generateProgram(goal: g, experience: e, days: d, minutes: 90, injuries: inj);
            for (final day in p.plan) {
              final names = day.items.map((i) => i.exercise).toList();
              expect(names.toSet().length, names.length, reason: '$g $e $d ${inj.join()} ${day.name}: $names');
            }
          }
        }
      }
    }
  });

  test('Vanhat nimet luetaan uusilla', () {
    final w = parseWorkout(
      '---\ndate: 2026-11-06\n---\n## Hyperextensio\n1. 10 kg × 12\n## Ojentajadipit\n1. 0 kg × 10\n',
    );
    expect(w.exercises.map((e) => e.name), ['Selän ojennus', 'Penkkidipit']);
  });

  test('Luokittelu lähdetarkistuksen mukaan', () {
    expect(categoryOf('Face pull'), 'Olkapäät');
    expect(categoryOf('Olankohautus'), 'Selkä');
    expect(bodyGroupOf('Rack pull'), BodyGroup.legs);
    expect(bodyGroupOf('Hip thrust'), BodyGroup.legs);
  });
}
