import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'ui/program_template.dart';

/// Sovelluksen navigaattori: avatut tiedostot (ohjelmapohja .gmd) tarvitsevat kontekstin dialogille.
final appNavigator = GlobalKey<NavigatorState>();
final appMessenger = GlobalKey<ScaffoldMessengerState>();

const _channel = MethodChannel('fi.somby.gievra/open');

/// Android: "Avaa sovelluksella" / "Jaa → Gievra". Kun sovellus on valmis (nimi annettu), näytetään tuonti.
void listenOpenedFiles() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'open' && call.arguments is String) unawaited(_show(call.arguments as String));
  });
  unawaited(() async {
    final text = await _channel.invokeMethod<String>('initial');
    if (text != null) await _show(text);
  }());
}

Future<void> _show(String text) async {
  // Odotetaan, että aloitusnäkymä (nimi) on ohi ja navigaattori on olemassa.
  for (var i = 0; i < 600; i++) {
    final ctx = appNavigator.currentContext;
    if (ctx != null && ctx.mounted && (settings.name?.isNotEmpty ?? false)) {
      await importTemplate(ctx, text: text);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
