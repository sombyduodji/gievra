import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'picker_guard.dart';

/// Tallennuksen tulos: [saved] = tiedosto kirjoitettiin, [verified] = se luettiin takaisin ja täsmäsi.
typedef SaveOutcome = ({bool saved, bool verified});

/// Tallentaa [bytes] käyttäjän valitsemaan paikkaan ja tarkistaa, että tiedosto on varmasti kirjoitettu (luetaan
/// takaisin ja verrataan). null = käyttäjä perui. Androidissa oma tallennus (Kotlin: SAF + SHA-256), muualla
/// tiedostovalitsin ja takaisinluku polusta.
Future<SaveOutcome?> saveVerified(Uint8List bytes, {required String fileName, required String mime, String? title}) =>
    pickOnce<SaveOutcome?>(() => _saveVerified(bytes, fileName: fileName, mime: mime, title: title));

Future<SaveOutcome?> _saveVerified(
  Uint8List bytes, {
  required String fileName,
  required String mime,
  String? title,
}) async {
  if (Platform.isAndroid) {
    final tmp = File(p.join((await getTemporaryDirectory()).path, 'tallennus-$fileName'));
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      final r = await const MethodChannel('fi.somby.gievra/save')
          .invokeMapMethod<String, bool>('saveVerified', {'path': tmp.path, 'name': fileName, 'mime': mime});
      if (r == null) return null;
      return (saved: r['saved'] ?? false, verified: r['verified'] ?? false);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }
  final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mime, dialogTitle: title);
  if (uri == null) return null;
  return (saved: true, verified: uri.scheme == 'file' && await sameBytes(File(uri.toFilePath()), bytes));
}

/// Onko tiedoston sisältö täsmälleen [bytes]?
Future<bool> sameBytes(File f, Uint8List bytes) async {
  try {
    if (!await f.exists() || await f.length() != bytes.length) return false;
    final back = await f.readAsBytes();
    for (var i = 0; i < bytes.length; i++) {
      if (back[i] != bytes[i]) return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}
