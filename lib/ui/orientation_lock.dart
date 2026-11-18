import 'package:flutter/services.dart';

// Salitreeni vain pystyssä (käyttäjä 18.11.): vaakasuunnassa palautusajastimen kortti peitti sarjan kirjauksen.
// Muut näkymät (tilastot, kaaviot) kääntyvät edelleen. Laskuri, jos treeninäkymiä on pinossa useampi.

int _locks = 0;

/// Testeille: viimeksi asetetut suunnat.
List<DeviceOrientation>? debugLastOrientations;

void _apply(List<DeviceOrientation> o) {
  debugLastOrientations = o;
  SystemChrome.setPreferredOrientations(o);
}

void lockPortrait() {
  if (_locks++ == 0) _apply(const [DeviceOrientation.portraitUp]);
}

void unlockPortrait() {
  if (_locks == 0) return;
  if (--_locks == 0) _apply(const []);
}
