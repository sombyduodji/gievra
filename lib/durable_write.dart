import 'dart:io';
import 'dart:math';

// Kestävä kirjoitus: ensin väliaikaistiedostoon, levylle asti (flush), sitten nimen vaihto. Virran katketessa
// kesken jää vanha tiedosto tai uusi kokonaisena, ei tyhjää tai puolikasta treenitiedostoa.

var _seq = 0;
final _rnd = Random();

/// Oma väliaikaistiedosto jokaiselle kirjoitukselle: päällekkäiset tallennukset eivät sekoitu.
File _tmpFor(File f) => File(
  '${f.parent.path}${Platform.pathSeparator}.${f.uri.pathSegments.last}.$pid-${_seq++}-${_rnd.nextInt(1 << 30)}.tmp',
);

/// Kirjoittaa [text] tiedostoon [f] turvallisesti.
Future<void> writeDurable(File f, String text) async {
  final tmp = _tmpFor(f);
  try {
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
  } catch (_) {
    if (await tmp.exists()) await tmp.delete();
    rethrow;
  }
}

/// Sama tavuille.
Future<void> writeDurableBytes(File f, List<int> bytes) async {
  final tmp = _tmpFor(f);
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  } catch (_) {
    if (await tmp.exists()) await tmp.delete();
    rethrow;
  }
}
