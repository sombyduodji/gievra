# Verkkoversion fontit

Flutter-verkkoversio hakisi nämä oletuksena Googlen palvelimelta (fonts.gstatic.com). Gievra tarjoaa ne
itse, jotta verkkoversio toimii ilman yhteyttä Googleen (web/flutter_bootstrap.js: fontFallbackBaseUrl).
Tiedostot ovat Googlen alkuperäisiä, muuttamattomia woff2-tiedostoja (fonts.gstatic.com/s/<polku>).

| Fontti | Kansio | Lisenssi |
|---|---|---|
| Roboto | roboto/ | Apache License 2.0 (Apache-2.0.txt) |
| Noto Sans | notosans/ | SIL Open Font License 1.1 (OFL.txt) |
| Noto Sans Symbols, Symbols 2, Math | notosanssymbols/, notosanssymbols2/, notosansmath/ | SIL Open Font License 1.1 (OFL.txt) |
| Noto Color Emoji | notocoloremoji/ | SIL Open Font License 1.1 (OFL.txt) |

Copyright: Noto-fontit © Google Inc. / The Noto Project Authors; Roboto © Google Inc.
Muut kirjoitusjärjestelmät (esim. kiina, japani) puuttuvat tarkoituksella: niitä ei tarvita sovelluksessa.
