import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/save_verified.dart';

// Varmuuskopion vienti poistaa automaattiset kopiot vasta, kun tiedosto on luettu takaisin ja se täsmää.
void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tallennus'));
  tearDown(() async => dir.delete(recursive: true));

  test('Takaisinluku: sama sisältö täsmää; puuttuva, lyhyempi tai muuttunut ei', () async {
    final bytes = Uint8List.fromList(List.generate(70000, (i) => i % 251));
    final f = File('${dir.path}/a.zip');
    expect(await sameBytes(f, bytes), isFalse, reason: 'tiedostoa ei ole');
    await f.writeAsBytes(bytes);
    expect(await sameBytes(f, bytes), isTrue);
    await f.writeAsBytes(bytes.sublist(0, 69999));
    expect(await sameBytes(f, bytes), isFalse, reason: 'katkennut kirjoitus');
    final changed = Uint8List.fromList(bytes)..[123] ^= 1;
    await f.writeAsBytes(changed);
    expect(await sameBytes(f, bytes), isFalse, reason: 'sisältö eri');
  });
}
