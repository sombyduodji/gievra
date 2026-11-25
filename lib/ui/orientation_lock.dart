import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Salitreeni vain pystyssä (käyttäjä 18.11.): vaakasuunnassa palautusajastimen kortti peitti sarjan kirjauksen.
// Puhelimissa koko sovellus pystyssä (käyttäjä 24.11.: vaakasuunnassa esim. Tilastoista näkyi vain kortin otsikko);
// tabletit ja avattu taittopuhelin (lyhyempi sivu vähintään 600 dp) kääntyvät edelleen, paitsi salitreenissä.
// Laskuri, jos treeninäkymiä on pinossa useampi.

int _locks = 0;
bool _phone = false;

/// Puhelin: näytön lyhyempi sivu alle tämän (dp). Materialin raja puhelimen ja tabletin välillä.
const phoneMaxShortSide = 600.0;

/// Testeille: viimeksi asetetut suunnat.
List<DeviceOrientation>? debugLastOrientations;

void _apply() {
  final o = _phone || _locks > 0 ? const [DeviceOrientation.portraitUp] : const <DeviceOrientation>[];
  if (debugLastOrientations != null && _same(debugLastOrientations!, o)) return;
  debugLastOrientations = o;
  SystemChrome.setPreferredOrientations(o);
}

bool _same(List<DeviceOrientation> a, List<DeviceOrientation> b) =>
    a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

void lockPortrait() {
  _locks++;
  _apply();
}

void unlockPortrait() {
  if (_locks == 0) return;
  _locks--;
  _apply();
}

/// Onko laite puhelin (lyhyempi sivu alle [phoneMaxShortSide] dp).
bool isPhoneSize(Size logical) => logical.shortestSide < phoneMaxShortSide;

/// Päivittää puhelinlukituksen näytön koon mukaan (käynnistys ja koon muutos, esim. taittopuhelimen avaus).
void updatePhoneLock(Size logical) {
  if (logical.isEmpty) return;
  _phone = isPhoneSize(logical);
  _apply();
}

/// Käynnistyksessä: lukitus heti ja uudelleen aina, kun näytön koko muuttuu.
void initOrientationLock() {
  final b = WidgetsBinding.instance;
  void check() {
    final views = b.platformDispatcher.views;
    if (views.isEmpty) return;
    final v = views.first;
    updatePhoneLock(v.physicalSize / v.devicePixelRatio);
  }

  check();
  b.addObserver(_SizeObserver(check));
}

class _SizeObserver with WidgetsBindingObserver {
  final VoidCallback onChange;
  _SizeObserver(this.onChange);
  @override
  void didChangeMetrics() => onChange();
}

/// Testeille: palauttaa alkutilan.
@visibleForTesting
void debugResetOrientationLock() {
  _locks = 0;
  _phone = false;
  debugLastOrientations = null;
}
