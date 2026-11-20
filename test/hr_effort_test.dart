import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/effort.dart';
import 'package:treenipaivakirja/hr_calc.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/weekly_activity.dart';

// Rasitus sykkeestä (käyttäjä 20.11.). Keksityt tiedot.
void main() {
  final day = DateTime(2026, 11, 18);
  Workout walk({int sec = 3600, HrSeries? s, int? avg, String? intensity, double? km}) =>
      Workout(date: day, title: 'Kävely', activity: 'Kävely', session: 1)
        ..seconds = sec
        ..hrSeries = s
        ..hrAvg = avg
        ..distanceKm = km
        ..intensity = intensity;
  // Puolet ajasta 100 (kevyt, 56 % maksimista 180), puolet 125 (reipas, 69 %).
  HrSeries split(int sec) =>
      HrSeries(DateTime(2026, 11, 18, 9), 5, [...List.filled(sec ~/ 10, 100), ...List.filled(sec ~/ 10, 125)]);

  test('Ei sykettä tai maksimisykettä: ei rasitusta', () {
    expect(hrEffort(walk(), 180), isNull);
    expect(hrEffort(walk(avg: 120), null), isNull);
  });

  test('Pelkkä keskisyke: koko kesto samalla tasolla', () {
    final e = hrEffort(walk(avg: 125), 180)!;
    expect((e.level, e.pct, e.lightSec, e.moderateSec, e.vigorousSec), ('reipas', 69, 0, 3600, 0));
    expect(hrEffort(walk(avg: 150), 180)!.level, 'kova');
    expect(hrEffort(walk(avg: 100), 180)!.level, 'kevyt');
  });

  test('Sykekäyrä: ajat tasoittain koko kestoon skaalattuna', () {
    final e = hrEffort(walk(s: split(3600)), 180)!;
    expect(e.fromCurve, isTrue);
    expect((e.lightSec, e.moderateSec, e.vigorousSec), (1800, 1800, 0));
    expect(e.level, 'kevyt', reason: 'keskisyke 112,5 = 63 %');
  });

  test('Viikon minuutit: syke ohittaa vanhan rasitusvalinnan; ilman sykettä vanha valinta säilyy', () {
    weeklyMaxHr = (_) => 180;
    addTearDown(() => weeklyMaxHr = null);
    // Sykkeellinen: 30 min reipasta (käyrästä), vaikka tiedostossa "kova".
    final a = periodActivity([walk(s: split(3600), intensity: 'kova')], day, day.add(const Duration(days: 1)));
    expect((a.moderate, a.vigorous, a.light), (30, 0, 30));
    // Ilman sykettä: vanha valinta (taaksepäin yhteensopiva).
    final b = periodActivity([walk(intensity: 'reipas')], day, day.add(const Duration(days: 1)));
    expect(b.moderateEq, 60);
    // Ei sykettä eikä valintaa: kävelyvauhti (3 km/h = kevyt).
    final c = periodActivity([walk(km: 3)], day, day.add(const Duration(days: 1)));
    expect((c.light, c.moderateEq), (60, 0));
  });

  test('Vanha rasitus säilyy tiedostossa (luku ja kirjoitus)', () {
    final w = walk(intensity: 'reipas', avg: 120);
    final back = parseWorkout(workoutToMarkdown(w));
    expect(back.intensity, 'reipas');
  });
}
