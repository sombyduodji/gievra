import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/import_export.dart';

// Tuonnin rajat: valtava tiedosto tai zip-pommi ei kaada sovellusta, mutta oikeat (isotkin) varmuuskopiot mahtuvat.
void main() {
  test('Zip-pommi: 101 Mt nollia (pakattuna ~0,1 Mt) hylätään ennen purkua', () {
    final zip = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.bytes('Treenit/2026/reitti.gpx', Uint8List(101 * 1024 * 1024))),
    );
    expect(zip.length, lessThan(1024 * 1024));
    expect(() => readZip(zip), throwsA(isA<FormatException>()));
  });

  test('Yhteensä yli 1 Gt purettuna hylätään; vuosien reitit (2000 × 0,5 Mt) mahtuvat', () {
    Archive many(int n, int size) {
      final a = Archive();
      for (var i = 0; i < n; i++) {
        a.addFile(ArchiveFile('r$i.gpx', size, const []));
      }
      return a;
    }

    expect(() => checkZipLimits(many(2000, 512 * 1024)), returnsNormally);
    expect(() => checkZipLimits(many(11, 100 * 1024 * 1024)), throwsA(isA<FormatException>()));
  });

  test('Valittu tiedosto: 500 Mt käy, yli ei', () {
    expect(() => checkImportSize(500 * 1024 * 1024), returnsNormally);
    expect(() => checkImportSize(500 * 1024 * 1024 + 1), throwsA(isA<FormatException>()));
  });
}
