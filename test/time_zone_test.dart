import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/time_zone.dart';

// Aikavyöhykkeen vaihto kesken treenin (päivätesti 14.11.): vaihto huomataan kerran, ja päivä rakennetaan
// uudelleen samasta kalenteripäivästä.
void main() {
  test('Vaihto huomataan kerran; sama vyöhyke ei ilmoita', () {
    var zone = 'EET|120';
    final w = TimeZoneWatch(key: () => zone);
    var n = 0;
    w.addListener(() => n++);
    expect(w.check(), isFalse);
    zone = 'EST|-300';
    expect(w.check(), isTrue);
    expect(w.check(), isFalse);
    expect(n, 1);
  });

  test('rebaseDay säilyttää kalenteripäivän', () {
    final d = DateTime(2026, 11, 14);
    final r = rebaseDay(d);
    expect((r.year, r.month, r.day, r.hour), (2026, 11, 14, 0));
  });
}
