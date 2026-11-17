import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/heart_rate.dart';
import 'package:treenipaivakirja/hr_calc.dart';
import 'package:treenipaivakirja/models.dart';

// Kävelyn kalorit vauhdista (Ludlow & Weyand 2016) sykkeen sijaan (käyttäjä 17.11.: kävelymatolla 2,5 km/h ja
// syke 97 antoi Keytelin yhtälöllä 525 kcal, kävelymatto noin kolmanneksen siitä). Keksityt henkilöt ja treenit.
void main() {
  // 100 kg, 175 cm, 50 v mies (vuonna 2026).
  const p = HrProfile(birthYear: 1976, male: true, heightCm: 175, weightKg: 100);
  final day = DateTime(2026, 11, 17);

  test('hidas kävely: Ludlow & Weyand -yhtälö omalla lepotasolla (kokonaiskulutus)', () {
    // 2,65 km 1:02:39 (0,70 m/s): lepo 2,57 + 3,85 + 5,97·0,705²/1,75 = 8,11 ml/kg/min → 254 kcal.
    expect(p.kcalWalk(km: 2.65, seconds: 3759, date: day), 254);
    // Reipas kävely 5 km/h, 80 kg, 180 cm, 30 v: 320 kcal tunnissa.
    const q = HrProfile(birthYear: 1996, male: true, heightCm: 180, weightKg: 80);
    expect(q.kcalWalk(km: 5, seconds: 3600, date: day), 320);
  });

  test('vauhti yhtälön alueen ulkopuolella (0,4–1,9 m/s): ei arviota', () {
    expect(p.kcalWalk(km: 0.5, seconds: 3600, date: day), isNull, reason: '0,14 m/s');
    expect(p.kcalWalk(km: 10, seconds: 3600, date: day), isNull, reason: '2,8 m/s = juoksua');
    expect(p.kcalWalk(km: 0, seconds: 3600, date: day), isNull);
  });

  test('vanha sykkeestä laskettu kävely korjataan vauhdista; kellon ja käsin kirjatut säilyvät', () {
    Workout walk({String source = 'syke', String activity = 'Kävely', double? km = 2.65}) =>
        Workout(date: day, title: activity, activity: activity)
          ..seconds = 3759
          ..distanceKm = km
          ..kcal = 525
          ..kcalSource = source;
    final w = walk();
    expect(repairWalkKcal(w, p), isTrue);
    expect((w.kcal, w.kcalSource), (254, 'nopeus'));
    expect(repairWalkKcal(w, p), isFalse, reason: 'kerran');
    expect(repairWalkKcal(walk(source: 'kello'), p), isFalse);
    expect(repairWalkKcal(walk(source: 'käsin'), p), isFalse);
    expect(repairWalkKcal(walk(activity: 'Juoksu'), p), isFalse);
    expect(repairWalkKcal(walk(activity: 'Sauvakävely'), p), isFalse);
    expect(repairWalkKcal(walk(km: null), p), isFalse, reason: 'ilman matkaa syke on ainoa arvio');
    expect(repairWalkKcal(walk(), null), isFalse);
    // Kävely ilman sykevyötä (ei kaloreita): arvio vauhdista (käyttäjä 17.11.).
    final plain = Workout(date: day, title: 'Kävely', activity: 'Kävely')
      ..seconds = 3759
      ..distanceKm = 2.65;
    expect(repairWalkKcal(plain, p), isTrue);
    expect((plain.kcal, plain.kcalSource), (254, 'nopeus'));
    final noKm = Workout(date: day, title: 'Kävely', activity: 'Kävely')..seconds = 3759;
    expect(repairWalkKcal(noKm, p), isFalse);
    expect(noKm.kcal, isNull);
  });

  test('sykevyöllä tallennettu kävely, jonka matka tiedetään: kalorit vauhdista, syke talteen', () {
    final w = Workout(date: day, title: 'Kävely', activity: 'Kävely')
      ..seconds = 3759
      ..distanceKm = 2.65;
    final series = HrSeries(DateTime(2026, 11, 17, 7, 39, 8), 5, List.filled(752, 97));
    expect(walkKcal(w, p), 254);
    expect(p.kcalEndurance(series), greaterThan(500), reason: 'Keytel samalla sykkeellä noin kaksinkertainen');
  });

  test('aktiiviset kalorit = kokonaiskulutus − oma lepokulutus treenin ajalta', () {
    // Lepo 1,284 kcal/min × 62,65 min = 80 → 254 − 80 = 174.
    final w = Workout(date: day, title: 'Kävely', activity: 'Kävely')
      ..seconds = 3759
      ..kcal = 254;
    expect(activeKcal(w, p), 174);
    expect(activeKcal(w, null), isNull, reason: 'ei profiilia');
    expect(activeKcal(Workout(date: day, title: 'Kävely', activity: 'Kävely')..seconds = 3759, p), isNull);
    // Ei koskaan negatiivinen (esim. käsin kirjattu pieni luku).
    expect(
      activeKcal(
        Workout(date: day, title: 'Jooga', activity: 'Jooga')
          ..seconds = 3600
          ..kcal = 10,
        p,
      ),
      0,
    );
  });
}
