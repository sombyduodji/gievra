import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/time_zone.dart';
import 'package:treenipaivakirja/ui/widgets.dart';

void main() {
  test('DayWatch ilmoittaa päivän ja tervehdyksen jakson vaihtuessa, ei muuten', () {
    var now = DateTime(2026, 11, 16, 23, 30);
    final w = DayWatch(now: () => now);
    var n = 0;
    w.addListener(() => n++);
    now = DateTime(2026, 11, 16, 23, 59);
    expect(w.check(), isFalse);
    now = DateTime(2026, 11, 17, 0, 0, 5); // päivä vaihtui, jakso sama (yö)
    expect(w.check(), isTrue);
    now = DateTime(2026, 11, 17, 4, 59);
    expect(w.check(), isFalse);
    now = DateTime(2026, 11, 17, 6, 40); // aamu: tervehdys vaihtuu
    expect(w.check(), isTrue);
    expect(w.check(), isFalse);
    expect(n, 2);
  });

  test('jaksot vastaavat tervehdyksen rajoja', () {
    for (var h = 0; h < 24; h++) {
      final a = seGreeting(DateTime(2026, 1, 1, h)), b = seGreeting(DateTime(2026, 1, 1, (h + 1) % 24));
      expect(DayWatch.slot(h) != DayWatch.slot((h + 1) % 24), a != b, reason: 'tunti $h');
    }
  });

  test('päivän vaihtuminen pyytää näkymät rakentumaan uudelleen', () {
    var n = 0;
    void l() => n++;
    settings.addListener(l);
    settings.dayChanged();
    settings.removeListener(l);
    expect(n, 1);
  });
}
