import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ongoing.dart';
import 'package:treenipaivakirja/rest.dart';

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

  test('Elävä ilmoitus: taustakuva lajin mukaan', () {
    expect(Ongoing.kindOf(null, gym: true), 'gym');
    expect(Ongoing.kindOf('Juoksu'), 'run');
    expect(Ongoing.kindOf('Kävely'), 'walk');
    expect(Ongoing.kindOf('Sauvakävely'), 'walk');
    expect(Ongoing.kindOf('Uinti'), 'other');
    expect(Ongoing.kindOf(null), 'other');
  });

  test('Elävä ilmoitus: sali näyttää liikkeen ja sarjat, GPS matkan ja vauhdin, ilman vyötä ei sykettä', () {
    var l = Ongoing.live([gym()], now);
    expect(l['kind'], 'gym');
    expect(l['line'], 'Takakyykky · 1 sarja');
    expect(l.containsKey('line2'), isFalse, reason: 'yksi liike: ei toistoa');
    expect(l.containsKey('hr'), isFalse, reason: 'sykevyötä ei valittu');
    Ongoing.gps = OngoingActivity('Juoksu', since: now.subtract(const Duration(minutes: 20)));
    Ongoing.gpsLine = () => '3,24 km · 6:10 /km';
    l = Ongoing.live([gym()], now);
    expect(l['kind'], 'run');
    expect(l['line'], '3,24 km · 6:10 /km');
    expect(l.containsKey('line2'), isFalse);
    Ongoing.gpsLine = null;
  });

  test('Elävä ilmoitus: palautus käynnissä, sitten "tauko ohi" kunnes seuraava sarja alkaa', () {
    var t0 = DateTime(2026, 11, 9, 12, 0);
    RestTimer.clock = () => t0;
    addTearDown(() {
      rest.stop();
      RestTimer.clock = DateTime.now;
    });
    rest.start(90, 'Takakyykky');
    var l = Ongoing.live([gym()], now);
    expect(l['line'], 'Palautus');
    expect(l['restEnd'], isNotNull);
    t0 = t0.add(const Duration(seconds: 90));
    rest.tick();
    l = Ongoing.live([gym()], now);
    expect(l['line'], '✓ Tauko ohi');
    expect(l.containsKey('restEnd'), isFalse);
    rest.start(90, 'Takakyykky');
    expect(Ongoing.live([gym()], now)['line'], 'Palautus');
  });
}
