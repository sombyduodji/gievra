import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';

void main() {
  test('strictDate hyväksyy vain olemassa olevan päivän', () {
    expect(strictDate('2026-11-17'), DateTime(2026, 11, 17));
    expect(strictDate('2024-02-29'), DateTime(2024, 2, 29));
    expect(strictDate('2026-13-45'), isNull); // DateTime.parse antaisi 14.2.2027
    expect(strictDate('2026-02-30'), isNull);
    expect(strictDate('roskaa'), isNull);
  });

  test('mahdoton päivä tiedostonimessä ja otsakkeessa: treeniä ei lueta tulevaisuuteen', () {
    const text = '---\ndate: 2026-13-45\ntitle: Mahdoton\n---\n## Penkkipunnerrus\n1. 50 kg × 5\n';
    expect(() => parseWorkout(text, fallbackDate: strictDate('2026-13-45')), throwsFormatException);
    // Otsakkeen päivä kelvollinen: nimen mahdoton päivä ei haittaa.
    final w = parseWorkout(text.replaceFirst('2026-13-45', '2026-11-13'), fallbackDate: strictDate('2026-13-45'));
    expect(w.date, DateTime(2026, 11, 13));
  });
}
