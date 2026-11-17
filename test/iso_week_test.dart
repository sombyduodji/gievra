import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/running.dart';

// ISO-viikko ja juoksuryhmien rajat kesäajan yli (koodikatselmus 17.11.: kesäajan viikot yhtä pienempinä 2026).
// Aja myös TZ=Europe/Helsinki: flutter test -ympäristössä paikallinen aikavyöhyke ratkaisee.
void main() {
  test('ISO-viikko oikein ympäri vuoden (myös kesäaika, 1.1. torstai)', () {
    expect(isoWeek(DateTime(2026, 1, 1)), 1);
    expect(isoWeek(DateTime(2026, 3, 30)), 14);
    expect(isoWeek(DateTime(2026, 6, 15)), 25);
    expect(isoWeek(DateTime(2026, 11, 17)), 47);
    expect(isoWeek(DateTime(2026, 12, 31)), 53);
    expect(isoWeek(DateTime(2027, 1, 3)), 53);
    expect(isoWeek(DateTime(2027, 1, 4)), 1);
    expect(isoWeek(DateTime(2025, 12, 29)), 1);
    // Joka päivä kahden vuoden ajan: maanantaina +1 (tai uusi vuosi), muuten sama.
    for (var d = DateTime(2025, 1, 1); d.isBefore(DateTime(2027, 1, 1)); d = addDays(d, 1)) {
      final prev = isoWeek(addDays(d, -1));
      if (d.weekday == DateTime.monday) {
        expect(isoWeek(d) == prev + 1 || isoWeek(d) == 1, isTrue, reason: '$d');
      } else {
        expect(isoWeek(d), prev, reason: '$d');
      }
    }
  });

  test('juoksuryhmät: 28 päivän raja kalenteripäivinä', () {
    final today = DateTime(2026, 11, 17);
    Workout run(DateTime d, double km) => Workout(date: d, title: 'Juoksu', activity: 'Juoksu')
      ..distanceKm = km
      ..seconds = (km * 360).round();
    // Raja 20.10. (kesäaika päättyi 25.10.): 20.10. kuuluu uusiin.
    final ws = [
      run(DateTime(2026, 10, 20), 4),
      run(DateTime(2026, 11, 10), 4),
      run(DateTime(2026, 10, 1), 4),
      run(DateTime(2026, 9, 25), 4),
    ];
    final g = runGroups(ws, today).single;
    expect((g.runs, g.prevRuns), (2, 2));
  });
}
