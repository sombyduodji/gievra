import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/rest.dart';

void main() {
  test('Vapaa treeni: raskas moninivelliike pidempi, eristävä ja kevyt lyhyempi', () {
    expect(restSeconds('Takakyykky', SetEntry(100, 5)), 180);
    expect(restSeconds('Takakyykky', SetEntry(110, 2), best: 120), 240); // yli 90 % maksimista
    expect(restSeconds('Takakyykky', SetEntry(80, 10)), 120);
    expect(restSeconds('Hauiskääntö', SetEntry(14, 10)), 90);
    expect(restSeconds('Hauiskääntö', SetEntry(10, 15)), 60);
    expect(restSeconds('Takakyykky', SetEntry(60, 5, warmup: true)), 45); // työpaino tuntematon: kevyt
  });

  test('Ei varaa: +30 s; kevennysviikko lyhentää', () {
    expect(restSeconds('Takakyykky', SetEntry(80, 10, rir: 0)), 150);
    expect(restSeconds('Takakyykky', SetEntry(80, 10), deload: true), 90);
  });

  test('Ohjelman tauko voittaa; ohjelman kevennysviikko lyhentää', () {
    final t = Target(3, 5, 5, '2', 240, 'Viikko 1');
    expect(restSeconds('Hauiskääntö', SetEntry(14, 5), target: t), 240);
    final d = Target(2, 5, 5, '3–4', 240, 'Kevennys', loadFactor: .9);
    expect(restSeconds('Takakyykky', SetEntry(90, 5), target: d), 180);
  });

  test('Lämmittely: kevyet lyhyesti, työpainoa lähestyvät pidempään', () {
    expect(restSeconds('Takakyykky', SetEntry(40, 5, warmup: true), work: 120), 45);
    expect(restSeconds('Takakyykky', SetEntry(80, 3, warmup: true), work: 120), 60);
    expect(restSeconds('Takakyykky', SetEntry(100, 2, warmup: true), work: 120), 90);
  });

  test('Oma säätö kuormaluokittain ja tallennus asetuksiin', () {
    expect(loadClass(SetEntry(100, 3)), 2);
    expect(loadClass(SetEntry(60, 8)), 1);
    expect(loadClass(SetEntry(40, 15)), 0);
    expect(loadClass(SetEntry(100, 8), best: 110), 2); // yli 85 % maksimista
    settings.restAdjust = [0, 0, 0];
    settings.adjustRest(2, 15);
    settings.adjustRest(2, 15);
    settings.adjustRest(0, -15);
    expect(restSeconds('Takakyykky', SetEntry(100, 5)), 210);
    expect(restSeconds('Hauiskääntö', SetEntry(10, 15)), 45);
    final md = settings.settingsToMarkdown();
    expect(md, contains('rest_adjust: -15, 0, 30'));
    settings.restAdjust = [0, 0, 0];
    settings.applyMarkdown(md);
    expect(settings.restAdjust, [-15, 0, 30]);
    settings.adjustRest(2, null);
    settings.adjustRest(0, null);
    expect(settings.restAdjust, [0, 0, 0]);
  });

  test('Oletukset ohjelmasta: luokan yleisin tauko', () {
    final p = parseProgram('''---
start: 2026-11-02
goal: voimanosto
days: 2
---

# Ohjelma

## Voima A
- Takakyykky | 5 × 3–5 | varaa 2 | tauko 4 min | KK
- Penkkipunnerrus | 4 × 3–5 | varaa 2 | tauko 4 min | KP
- Kulmasoutu | 3 × 8–10 | varaa 2 | tauko 2,5 min | VVE
- Hauiskääntö | 3 × 12–15 | varaa 1 | tauko 1 min | HAU
''');
    expect(restDefaults(p), [60, 150, 240]);
    expect(restDefaults(), [60, 120, 180]);
  });

  test('Ajastin: −15 s / +15 s ja ohitus', () {
    final r = RestTimer();
    r.start(90, 'Takakyykky');
    expect(r.running, isTrue);
    expect(r.remaining, inInclusiveRange(89, 90));
    r.adjust(15);
    expect(r.remaining, inInclusiveRange(104, 105));
    r.stop();
    expect(r.running, isFalse);
    expect(r.remaining, 0);
  });
}
