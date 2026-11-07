import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/body.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';

// Kehonpainon seuranta: kehonpaino.md, syötteet, painoindeksi, tuonti ja vienti. Arvot keksittyjä.
void main() {
  tearDown(() => debugSetCatalog('fi', const {}));

  test('Syöte: pilkku ja piste käyvät, negatiiviset ja mahdottomat hylätään', () {
    expect(parseWeight('82,4'), 82.4);
    expect(parseWeight('82.4'), 82.4);
    expect(parseWeight(' 82 kg'), 82);
    expect(parseWeight('82,45'), 82.5); // yksi desimaali
    for (final bad in ['-82', '−82', '0', '5', '1000', '', 'abc', '8..2']) {
      expect(parseWeight(bad), isNull, reason: bad);
    }
    expect(parseHeight('180'), 180);
    expect(parseHeight('180 cm'), 180);
    expect(parseHeight('-180'), isNull);
    expect(parseHeight('18'), isNull);
    expect(bmi(82.4, 180), 25.4);
  });

  test('kehonpaino.md: kirjoitus ja luku, rikkinäiset rivit ohitetaan', () {
    final b = BodyLog(heightCm: 180, weights: {DateTime(2026, 11, 7): 82.4, DateTime(2026, 11, 4): 82.8});
    final md = bodyToMarkdown(b);
    expect(md, contains('height: 180 cm'));
    expect(md, contains('- 2026-11-07: 82,4 kg'));
    expect(md.indexOf('2026-11-07'), lessThan(md.indexOf('2026-11-04'))); // uusin ensin
    final back = parseBody(md);
    expect(back.heightCm, 180);
    expect(back.weights, b.weights);
    final hand = parseBody(
      '---\nheight: abc\n---\n- 2026-11-01: 83.1 kg\n- 2026-11-02: -80 kg\n- huono rivi\n* 2026-11-03: 82,9\n',
    );
    expect(hand.heightCm, isNull);
    expect(hand.weights, {DateTime(2026, 11, 1): 83.1, DateTime(2026, 11, 3): 82.9});
  });

  test('Näyttö: englanniksi piste, tiedostossa aina pilkku', () {
    debugSetCatalog('en', const {});
    expect(fmtNum(82.4), '82.4');
    expect(bodyToMarkdown(BodyLog(weights: {DateTime(2026, 11, 7): 82.4})), contains('82,4 kg'));
  });

  test('Painosarja: punnitukset ja treeneihin tuodut kehonpainot, punnitus voittaa', () {
    final b = BodyLog(weights: {DateTime(2026, 10, 1): 96.0});
    final ws = [
      Workout(date: DateTime(2026, 10, 1), title: 'X', bodyweight: 96.5),
      Workout(date: DateTime(2026, 9, 1), title: 'X', bodyweight: 97.5),
      Workout(date: DateTime(2026, 9, 2), title: 'X'),
    ];
    expect(weightSeries(b, ws), [(DateTime(2026, 9, 1), 97.5), (DateTime(2026, 10, 1), 96.0)]);
  });

  test('Tuonti: zip ja .md-tiedostot tuovat kehonpaino.md:n; yhdistäminen ei ylikirjoita', () {
    final body = bodyToMarkdown(BodyLog(heightCm: 175, weights: {DateTime(2026, 11, 1): 70.0}));
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('Treenit/kehonpaino.md', utf8.encode(body)))
      ..addFile(ArchiveFile.bytes('Treenit/asetukset.md', utf8.encode('---\nname: Testi\nbody_tracker: true\n---\n')))
      ..addFile(ArchiveFile.bytes('Treenit/2026/2026-11-01.md', utf8.encode('---\ndate: 2026-11-01\ntitle: X\n---\n')));
    final r = readZip(ZipEncoder().encodeBytes(archive));
    expect(r.workouts.length, 1); // kehonpaino.md ei ole treeni
    expect(parseBody(r.bodyMd!).weights.length, 1);
    expect((Settings()..applyMarkdown(r.settingsMd!)).bodyTracker, isTrue);
    expect(readMdFiles({'kehonpaino.md': body, '2026-11-02.md': '---\ndate: 2026-11-02\n---\n'}).bodyMd, body);

    final current = BodyLog(heightCm: 180, weights: {DateTime(2026, 11, 1): 82.0});
    final merged = mergeBody(current, parseBody(body));
    expect(merged.heightCm, 180);
    expect(merged.weights[DateTime(2026, 11, 1)], 82.0);
    final merged2 = mergeBody(BodyLog(), parseBody(body));
    expect((merged2.heightCm, merged2.weights.length), (175, 1));
  });

  test('Asetus body_tracker kulkee asetukset.md:ssä', () {
    final s = Settings()..bodyTracker = true;
    expect((Settings()..applyMarkdown(s.settingsToMarkdown())).bodyTracker, isTrue);
    expect((Settings()..applyMarkdown('---\nname: X\n---\n')).bodyTracker, isFalse); // vanha tiedosto: pois
  });
}
