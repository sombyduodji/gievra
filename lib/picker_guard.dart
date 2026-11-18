// Tiedostovalitsin, tallennusikkuna ja jakaminen yksi kerrallaan (yötesti 18.11.): toinen napautus ennen kuin
// ensimmäinen ikkuna aukesi heitti PlatformExceptionin "already_active" (osassa paikoista käsittelemättömänä
// virheenä lokiin). Toinen kutsu palauttaa null, kuten peruttu valinta.

bool _busy = false;

/// Onko valitsin tai jakaminen jo auki (testeille).
bool get pickerBusy => _busy;

Future<T?> pickOnce<T>(Future<T> Function() f) async {
  if (_busy) return null;
  _busy = true;
  try {
    return await f();
  } finally {
    _busy = false;
  }
}
