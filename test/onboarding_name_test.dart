import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';

// Nimi on valinnainen: sen tyhjentäminen asetuksista ei saa viedä takaisin aloitussivulle, vaikka asetukset olisi
// tehty ennen 0.6.6:ta (aloitus tunnistettiin silloin vain nimestä, started puuttuu tiedostosta).
void main() {
  test('vanhat asetukset: nimen tyhjennys säilyttää aloituksen käydyksi, myös tallennuksen jälkeen', () {
    final old = Settings()..applyMarkdown('---\nname: Testi\n---\n');
    final s = Settings()..applyMarkdown(old.settingsToMarkdown());
    expect(s.started, isFalse, reason: 'vanha tiedosto: started puuttuu');
    expect(s.onboarded, isTrue);
    s.setName('');
    expect(s.name, '');
    expect(s.onboarded, isTrue);
    expect((Settings()..applyMarkdown(s.settingsToMarkdown())).onboarded, isTrue);
  });

  test('aloittamaton: nimen asetus ei yksin merkitse aloitusta käydyksi', () {
    final s = Settings()..setName('');
    expect(s.onboarded, isFalse);
  });
}
