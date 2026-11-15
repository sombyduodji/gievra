import 'dart:io';

import 'package:flutter/services.dart';

/// Flutterin Material-fonttien kansio (Roboto, MaterialIcons). Haetaan testiajurin (flutter_tester) sijainnista
/// ja FLUTTER_ROOT-muuttujasta, ei kotikansiosta: GitHubin koonnissa Flutter on eri paikassa, ja kovakoodattu
/// ~/sdk/flutter kaatoi kolme testiä (sivuston päivitys ei mennyt läpi 0.6.6–0.6.7.1).
String? materialFontsDir() {
  final candidates = [
    if (Platform.environment['FLUTTER_ROOT'] case final r?) '$r/bin/cache/artifacts/material_fonts',
    // .../flutter/bin/cache/artifacts/engine/linux-x64/flutter_tester
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
    '${Platform.environment['HOME']}/sdk/flutter/bin/cache/artifacts/material_fonts',
  ];
  for (final c in candidates) {
    if (File('$c/Roboto-Regular.ttf').existsSync()) return c;
  }
  return null;
}

/// Lataa Roboto-fontin testiin (tekstin oikeat leveydet). Jos fontteja ei löydy, testi jatkaa oletusfontilla.
Future<void> loadRoboto() async {
  final root = materialFontsDir();
  if (root == null) return;
  final l = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    l.addFont(Future.value(File('$root/$f').readAsBytesSync().buffer.asByteData()));
  }
  await l.load();
}
