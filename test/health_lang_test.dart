import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/injury_data.dart';
import 'package:treenipaivakirja/l10n.dart';

// Saamenkielinen käyttöliittymä: vammatilan ohjeet suomeksi tai englanniksi asetuksen mukaan.
void main() {
  final r = injuryRegions.first;
  final note = r.modify.values.first;
  setUp(() {
    debugSetCatalog(
      'se',
      {r.name: r.name, note: note, 'Asetukset': 'Heivehusat', 'Varo: {0}': 'Várut: {0}'},
      english: {r.name: 'Shoulder (EN)', note: 'Note (EN)', 'Asetukset': 'Settings'},
    );
  });
  tearDown(() {
    healthTextLang = 'fi';
    debugSetCatalog('fi', const {});
  });

  test('Oletus: vammatilan tekstit suomeksi, muu saameksi', () {
    expect(t(r.name), r.name);
    expect(trNote(note), note);
    expect(t('Asetukset'), 'Heivehusat');
  });

  test('English: vain vammatilan tekstit englanniksi', () {
    healthTextLang = 'en';
    expect(t(r.name), 'Shoulder (EN)');
    expect(trNote(note), 'Note (EN)');
    expect(t('Asetukset'), 'Heivehusat', reason: 'muu käyttöliittymä pysyy saameksi');
    debugSetCatalog('en', {'Asetukset': 'Settings'});
    expect(t('Asetukset'), 'Settings');
  });

  test('Asetus tallentuu', () {
    final s = Settings()..healthLang = 'en';
    expect((Settings()..applyMarkdown(s.settingsToMarkdown())).healthLang, 'en');
    expect(healthTextLang, 'en');
  });
}
