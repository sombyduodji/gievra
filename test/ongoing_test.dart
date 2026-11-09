import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ongoing.dart';

// Käynnissä olevan treenin ilmoitus: mitä näytetään milloinkin. Keksityt treenit.
void main() {
  final now = DateTime(2026, 11, 9, 12, 0);
  Workout gym({DateTime? started, bool sets = true, int? minutes, DateTime? date}) => Workout(
    date: date ?? now,
    title: 'Koko keho A',
    started: started ?? now.subtract(const Duration(minutes: 42)),
    minutes: minutes,
    exercises: [
      ExerciseEntry('Takakyykky', sets ? [SetEntry(100, 5)] : []),
    ],
  );

  tearDown(() {
    Ongoing.activity = null;
    Ongoing.gps = null;
  });

  test('Salitreeni käynnissä: tämän päivän, sarjoja, ei valmis, alle 5 h', () {
    final w = gym();
    final c = Ongoing.current([w], now)!;
    expect(c.$1, 'Salitreeni käynnissä');
    expect(c.$2, w.started);
    expect(c.$3, isFalse);
    expect(Ongoing.current([gym(sets: false)], now), isNull, reason: 'ei vielä sarjoja');
    expect(Ongoing.current([gym(minutes: 55)], now), isNull, reason: 'Treeni valmis!');
    expect(Ongoing.current([gym(started: now.subtract(const Duration(hours: 6)))], now), isNull, reason: 'unohtunut');
    expect(Ongoing.current([gym(date: DateTime(2026, 11, 8))], now), isNull, reason: 'eilinen');
    final saved = gym()..feeling = 4;
    expect(Ongoing.current([saved], now), isNull, reason: 'fiilis = merkitty valmiiksi');
  });

  test('Liikunnan ajanotto ennen salia; tauolla kello pysähtyy', () {
    Ongoing.activity = OngoingActivity('Kävely', since: now.subtract(const Duration(minutes: 12)));
    var c = Ongoing.current([gym()], now)!;
    expect(c.$1, 'Kävely käynnissä');
    expect(c.$2, now.subtract(const Duration(minutes: 12)));
    Ongoing.activity = const OngoingActivity('Kävely', elapsed: Duration(minutes: 12, seconds: 31));
    c = Ongoing.current([], now)!;
    expect(c.$3, isTrue);
    expect(c.$4, 'tauolla · 12:31');
    Ongoing.activity = null;
    expect(Ongoing.current([], now), isNull);
  });

  test('Yksi ilmoitus: GPS-lenkki ohittaa ajanoton ja salitreenin; signaalia odottaessa ei kelloa', () {
    Ongoing.activity = OngoingActivity('Kävely', since: now.subtract(const Duration(minutes: 3)));
    Ongoing.gps = const OngoingActivity('Juoksu', note: 'Etsitään GPS-signaalia…');
    var c = Ongoing.current([gym()], now)!;
    expect((c.$1, c.$3, c.$4), ('Juoksu käynnissä', true, 'Etsitään GPS-signaalia…'));
    Ongoing.gps = OngoingActivity('Juoksu', since: now.subtract(const Duration(minutes: 20)));
    c = Ongoing.current([gym()], now)!;
    expect((c.$1, c.$2, c.$3), ('Juoksu käynnissä', now.subtract(const Duration(minutes: 20)), false));
    Ongoing.gps = null;
    Ongoing.activity = null;
    expect(Ongoing.current([gym()], now)!.$1, 'Salitreeni käynnissä', reason: 'lenkin jälkeen sali palaa');
  });

  test('Asetus: oletus päällä, tallentuu', () {
    expect(Settings().ongoingNote, isTrue);
    final s = Settings()..ongoingNote = false;
    expect((Settings()..applyMarkdown(s.settingsToMarkdown())).ongoingNote, isFalse);
  });
}
