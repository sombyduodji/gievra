import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'ui/import_export.dart';

/// Sovelluksen navigaattori: avatut tiedostot tarvitsevat kontekstin tuontinäkymälle.
final appNavigator = GlobalKey<NavigatorState>();
final appMessenger = GlobalKey<ScaffoldMessengerState>();

const _channel = MethodChannel('fi.somby.gievra/open');

/// Avatun tiedoston tuontinäkymän reitin nimi.
const openedRouteName = 'opened-import';
Route<void>? _openedRoute;

/// Avattu tai jaettu tiedosto: nimi ja sisältö, tai liian suuri (tuontinäkymä ilmoittaa).
class OpenedFile {
  const OpenedFile(this.name, this.bytes, {this.size = 0, this.tooLarge = false});
  final String name;
  final Uint8List bytes;
  final int size;
  final bool tooLarge;
}

/// Kanavan viesti (MainActivity.fileFromIntent) tiedostoksi; väliaikainen kopio poistetaan luettaessa.
Future<OpenedFile?> openedFromMessage(Object? arg) async {
  if (arg is! Map) return null;
  final text = arg['text'];
  if (text is String) return OpenedFile('', Uint8List.fromList(utf8.encode(text)));
  final path = arg['path'];
  if (path is! String) return null;
  final f = File(path);
  try {
    final name = (arg['name'] as String?) ?? '';
    if (arg['tooLarge'] == true) return OpenedFile(name, Uint8List(0), size: await f.length(), tooLarge: true);
    return OpenedFile(name, await f.readAsBytes());
  } on FileSystemException {
    return null;
  } finally {
    if (await f.exists()) await f.delete();
  }
}

/// Android: "Avaa sovelluksella" / "Jaa → Gievra". Kun sovellus on valmis (nimi annettu), avataan tuontinäkymä,
/// joka tunnistaa tiedoston kuten Tuo tiedosto -painike (FitNotes, varmuuskopio, Garmin, .md, ohjelmapohja).
void listenOpenedFiles() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'open') unawaited(_show(call.arguments));
  });
  unawaited(() async {
    await _show(await _channel.invokeMethod<Object?>('initial'));
  }());
}

Future<void> _show(Object? message) => showOpened(message);

/// Testeille julkinen: avaa tuontinäkymän kanavan viestistä.
Future<void> showOpened(Object? message) async {
  final file = await openedFromMessage(message);
  if (file == null) return;
  // Odotetaan, että aloitusnäkymä (nimi) on ohi ja navigaattori on olemassa.
  for (var i = 0; i < 600; i++) {
    final nav = appNavigator.currentState;
    if (nav != null && nav.mounted && settings.onboarded) {
      // Uusi avattu tiedosto korvaa edellisen avatun tuontinäkymän ja sen päällä olevat (esikatselu, dialogi), ettei
      // Takaisin-painikkeen takana ole vanhoja näkymiä.
      final prev = _openedRoute;
      if (prev != null && prev.isActive) {
        nav.popUntil((r) => r == prev);
        nav.pop();
      }
      final route = _openedRoute = MaterialPageRoute<void>(
        settings: const RouteSettings(name: openedRouteName),
        builder: (_) => ImportExportScreen(opened: file),
      );
      await nav.push(route);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
