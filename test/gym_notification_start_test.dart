import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ongoing.dart';

// Salitreenin ilmoitus heti alusta (käyttäjä 17.11. salilla: lämmittelyn aikana ei ilmoitusta, vaikka syke kulki).
void main() {
  final now = DateTime(2026, 11, 17, 15, 30);
  final day = DateTime(2026, 11, 17);
  tearDown(() => Ongoing.openGym = null);

  test('tallessa oleva treeni, jossa vain lämmittely, on käynnissä', () {
    final w = Workout(date: day, title: 'Koko keho A')
      ..started = DateTime(2026, 11, 17, 15, 20)
      ..warmup = Warmup('Venyttely', 10);
    expect(Ongoing.gymInProgress([w], now), same(w));
    expect(Ongoing.current([w], now)?.$1, 'Salitreeni käynnissä');
  });

  test('auki oleva uusi treeni ilman sarjoja näkyy; valmis tai suljettu ei', () {
    final w = Workout(date: day, title: 'Koko keho A')..started = DateTime(2026, 11, 17, 15, 25);
    expect(Ongoing.current([], now), isNull);
    Ongoing.openGym = w;
    expect(Ongoing.gymNow([], now), same(w));
    expect(Ongoing.current([], now)?.$2, w.started);
    w.minutes = 40; // Treeni valmis!
    expect(Ongoing.gymNow([], now), isNull);
    w.minutes = null;
    expect(Ongoing.gymNow([], DateTime(2026, 11, 17, 21)), isNull, reason: 'yli 5 h');
    Ongoing.openGym = null;
    expect(Ongoing.current([], now), isNull);
  });
}
