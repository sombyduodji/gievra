import 'package:flutter/services.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/l10n.dart';

// Sovelluksen omat virheviestit (fi()-merkintä) näkyvät käyttäjän kielellä; muut sellaisinaan.
void main() {
  final en = parsePo(File('assets/l10n/en.po').readAsStringSync());
  tearDown(() => debugSetCatalog('fi', const {}));

  test('Virheviestit englanniksi, myös muuttujan kanssa', () {
    debugSetCatalog('en', en, english: en);
    expect(errorText(FormatException(fi('tarkiste ei täsmää'))), "checksum doesn't match");
    expect(errorText(FormatException(fi('maakoodi ei kelpaa: {0}', ['xx']))), 'invalid country code: xx');
    expect(errorText(Exception('Drive 500: x')), 'Drive 500: x', reason: 'vieras virhe sellaisenaan');
    // Yötesti 18.11.: PlatformException ilman luokan nimeä ja koodia.
    expect(
      errorText(PlatformException(code: 'already_active', message: 'File picker is already active')),
      'File picker is already active',
    );
    expect(errorText(const HttpException('HTTP 404')), 'HTTP 404');
  });

  test('Suomeksi ennallaan', () {
    expect(errorText(FormatException(fi('tarkiste ei täsmää'))), 'tarkiste ei täsmää');
  });
}
