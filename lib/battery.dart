import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_state.dart';

// Akunsäästö: saako Gievra toimia taustalla. Muuten puhelin (etenkin Samsung) voi pysäyttää sovelluksen näytön
// ollessa pois päältä: palautuksen ilmoitus myöhästyy, eikä sykevyön lukemia saada. Treenin aikana käynnissä oleva
// treeni-ilmoitus pitää sovelluksen hereillä; tämä asetus varmistaa sen kaikilla puhelimilla.
// Android-puoli: MainActivity.kt ("fi.somby.gievra/power").

class BatteryHelp extends ChangeNotifier with WidgetsBindingObserver {
  static const _ch = MethodChannel('fi.somby.gievra/power');

  /// Sallittu toimia taustalla (null = ei tiedetä, esim. verkkoversio tai testit).
  bool? exempt;

  /// Samsung: lisäohje nukkuvista sovelluksista.
  bool samsung = false;

  static bool get supported => !kIsWeb && !isDemo && defaultTargetPlatform == TargetPlatform.android;

  Future<void> refresh() async {
    if (!supported) return;
    try {
      final m = await _ch.invokeMapMethod<String, Object?>('status');
      final e = m?['exempt'] as bool?, s = m?['samsung'] == true;
      if (e != exempt || s != samsung) {
        exempt = e;
        samsung = s;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Androidin oma kysymys "Sallitaanko taustalla?"; false, jos se ei aukea (silloin sovelluksen asetukset).
  Future<bool> request() async {
    try {
      return await _ch.invokeMethod<bool>('request') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod('appSettings');
    } catch (_) {}
  }

  /// Palattaessa asetuksista tila päivittyy.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}

final battery = BatteryHelp();
