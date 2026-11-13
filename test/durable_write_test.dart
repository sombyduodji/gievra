import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/durable_write.dart';

// Treenitiedostot kirjoitetaan väliaikaistiedoston kautta: ei tyhjää tiedostoa, jos virta katkeaa kesken.
void main() {
  test('Korvaa vanhan sisällön kokonaan eikä jätä väliaikaistiedostoa', () async {
    final dir = Directory.systemTemp.createTempSync('gievra-kesto');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/2026-11-12-9.md');
    await f.writeAsString('vanha, pidempi sisältö');
    await writeDurable(f, '---\ndate: 2026-11-12\n---\n');
    expect(f.readAsStringSync(), '---\ndate: 2026-11-12\n---\n');
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['2026-11-12-9.md']);
    await writeDurableBytes(f, [65, 66]);
    expect(f.readAsStringSync(), 'AB');
  });

  test('Päällekkäiset tallennukset samaan tiedostoon eivät kaadu eivätkä sekoitu', () async {
    final dir = Directory.systemTemp.createTempSync('gievra-rinn');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/2026-11-12.md');
    final texts = [for (var i = 0; i < 20; i++) 'versio $i ' * 200];
    await Future.wait([for (final x in texts) writeDurable(f, x)]);
    expect(texts, contains(f.readAsStringSync()));
    expect(dir.listSync(), hasLength(1), reason: 'ei jääneitä väliaikaistiedostoja');
  });
}
