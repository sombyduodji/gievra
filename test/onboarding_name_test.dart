import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';

// Nimi poistettu (käyttäjä 19.11.). Ennen 0.6.6 tehdyissä asetuksissa aloitus tunnistettiin vain nimestä (started
// puuttuu tiedostosta): vanha nimi luetaan aloituksen merkiksi, eikä nimeä enää tallenneta.
void main() {
  test('vanha name: merkitsee aloituksen käydyksi, nimeä ei tallenneta', () {
    final s = Settings()..applyMarkdown('---\nname: Testi\n---\n');
    expect(s.onboarded, isTrue);
    final md = s.settingsToMarkdown();
    expect(md, isNot(contains('name:')));
    expect(md, isNot(contains('Testi')));
    expect(md, contains('started: true'));
    expect((Settings()..applyMarkdown(md)).onboarded, isTrue);
  });

  test('tyhjä vanha name: ei merkitse aloitusta', () {
    expect((Settings()..applyMarkdown('---\nname: \n---\n')).onboarded, isFalse);
  });
}
