import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sleep.dart';

// Myöhäinen kova treeni (käyttäjä 18.11.): oman tavallisen nukkumaanmenon mukaan, vain kun yö jäi lyhyeksi.
// Keksityt yöt ja treenit.
void main() {
  final today = DateTime(2026, 11, 18);
  // 30 yötä: nukkumaan 23.15, herätys 6.45, uni 7 h 20 min.
  Map<DateTime, SleepNight> base() => {
    for (var i = 1; i <= 30; i++)
      addDays(today, -i): SleepNight(
        addDays(today, -i),
        DateTime(today.year, today.month, today.day - i - 1, 23, 15),
        DateTime(today.year, today.month, today.day - i, 6, 45),
        const Duration(hours: 7, minutes: 20),
      ),
  };
  SleepNight lastNight(Duration asleep) =>
      SleepNight(today, DateTime(2026, 11, 17, 23, 40), DateTime(2026, 11, 18, 6, 30), asleep);
  Workout hardRun(int h, int m, {String intensity = 'kova'}) => Workout(date: DateTime(2026, 11, 17), title: 'Juoksu')
    ..activity = 'Juoksu'
    ..intensity = intensity
    ..started = DateTime(2026, 11, 17, h, m)
    ..seconds = 50 * 60;

  test('kova treeni päättyi 35 min ennen tavallista nukkumaanmenoa ja yö jäi lyhyeksi: vihje', () {
    final nights = {...base(), today: lastNight(const Duration(hours: 6, minutes: 5))};
    final s = sleepStats(nights, today);
    expect(usualBedMinutes(nights, today), 11 * 60 + 15);
    final l = lateHardWorkout(s, nights, [hardRun(21, 50)])!; // päättyi 22.40
    expect(l.minutesBefore, 35);
    expect(l.asleep, const Duration(hours: 6, minutes: 5));
  });

  test('ei vihjettä: hyvä yö, aikainen treeni, kevyt treeni tai liian vähän öitä', () {
    final good = {...base(), today: lastNight(const Duration(hours: 7, minutes: 10))};
    expect(lateHardWorkout(sleepStats(good, today), good, [hardRun(21, 50)]), isNull);
    final bad = {...base(), today: lastNight(const Duration(hours: 6))};
    final s = sleepStats(bad, today);
    expect(lateHardWorkout(s, bad, [hardRun(19, 0)]), isNull, reason: 'päättyi 19.50, kauan ennen');
    expect(lateHardWorkout(s, bad, [hardRun(21, 50, intensity: 'kevyt')]), isNull);
    final few = {
      for (final e in bad.entries)
        if (e.key.isAfter(addDays(today, -12))) e.key: e.value,
    };
    expect(lateHardWorkout(sleepStats(few, today), few, [hardRun(21, 50)]), isNull);
  });

  test('salitreeni on kova, kun vähintään 3 työsarjaa 0–1 toiston varalla', () {
    final w = Workout(date: today, title: 'Treeni')
      ..exercises.add(
        ExerciseEntry('Takakyykky', [SetEntry(60, 5)..rir = 0, SetEntry(80, 5)..rir = 1, SetEntry(80, 5)..rir = 0]),
      );
    expect(hardWorkout(w), isTrue);
    w.exercises.first.sets.last.rir = 3;
    expect(hardWorkout(w), isFalse);
  });
}
