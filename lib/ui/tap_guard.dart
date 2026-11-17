import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lyhyt napautussuoja näkymän tai ikkunan vaihtuessa (käyttäjä 15.11.). Tupla- tai kolmoisnapautuksen
/// ylimääräiset napautukset osuivat ennen juuri avautuneeseen tai alta paljastuneeseen näkymään: *Hylkää* avasi
/// alla olevasta listasta tallennetun treenin, ja *Tee ohjelma* ohitti kyselyn ensimmäisen sivun.
///
/// Navigaattorin tarkkailija merkitsee vaihdon hetken, ja [TapGuard] nielee kosketukset [duration] ajan.
/// Ei ajastimia: aika luetaan kosketuksen hetkellä.
class NavTapGuard extends NavigatorObserver {
  /// Testeissä pois (napautukset heti näkymän vaihdon jälkeen); oma testi asettaa keston.
  static Duration duration = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
      ? Duration.zero
      : const Duration(milliseconds: 300);
  static DateTime Function() clock = DateTime.now;
  static DateTime? _changed;

  /// Testejä varten: edellisen testin näkymänvaihto ei saa niellä seuraavan testin ensimmäistä napautusta.
  @visibleForTesting
  static void debugReset() => _changed = null;

  /// Onko näkymä vaihtunut juuri (kosketukset niellään)?
  static bool get active {
    final c = _changed;
    if (c == null || duration <= Duration.zero) return false;
    final d = clock().difference(c);
    // Kello siirtyi taaksepäin (verkkoaika, käsin): ei suojaa, ettei sovellus niele kaikkia kosketuksia (yötesti 16.11.).
    return d >= Duration.zero && d < duration;
  }

  void _mark() => _changed = clock();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _mark(); // sovelluksen ensimmäinen näkymä ei tarvitse suojaa
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _mark();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _mark();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _mark();
}

/// Koko sovelluksen ympärille (MaterialApp.builder): nielee kosketukset, kun [NavTapGuard.active].
class TapGuard extends SingleChildRenderObjectWidget {
  const TapGuard({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTapGuard();
}

class _RenderTapGuard extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Kuten AbsorbPointer: osuma tähän, ei lapsiin.
    if (NavTapGuard.active) return size.contains(position);
    return super.hitTest(result, position: position);
  }
}
