/// Sovelluksen tekijä- ja yhteystiedot (☰-valikon Tietoa / Palaute / Osallistu ja tue).
class AppInfo {
  static const name = 'Gievra'; // pohjoissaamea: vahva
  static const tagline = 'Treenipäiväkirja';

  /// Otsikoissa: "Gievra – Treenipäiväkirja". Kuvakkeen alla ja tiedostonimissä pelkkä Gievra.
  static const fullName = '$name – $tagline';
  static const slogan = 'Sinun treenisi, sinun tiedostosi.';
  static const author = 'Juha Somby';
  static const feedbackEmail = 'treeni@somby.fi';

  /// Julkinen lähdekoodi. null = ei vielä julkaistu (koodi on toistaiseksi vain omassa Forgejossa),
  /// jolloin GitHub-linkit piilotetaan.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const String? github = 'https://github.com/sombyduodji/gievra';
  static String? get issues => github == null ? null : '$github/issues';
  static const coffee = 'https://buymeacoffee.com/sombyduodji';
}

/// Google Drive -synkronoinnin Web-asiakastunnus (Google Cloud Console -> OAuth-asiakas, tyyppi Web).
/// null = synkronointi ei ole käytössä tässä käännöksessä. Ks. docs/google-drive.md.
// ignore: unnecessary_nullable_for_final_variable_declarations
const String? googleWebClientId = null; // asetetaan, kun Drive-synkronointi julkaistaan

/// Google Drive -synkronointi julkaisussa. false = valikossa "tulossa", ei taustasynkronointia.
/// Koodi ja testit ovat valmiina (lib/sync/); kytke päälle, kun ominaisuus julkaistaan.
const bool syncReleased = false;

/// Karttojen lähteet ja lisenssit (ks. tools/map_extract.py). Kartan kulmassa näkyy aina [osm], joka avaa
/// [osmUrl]; Tietoa-ikkunassa on koko lista. Tekijänoikeusmerkintää ei käännetä.
class MapCredits {
  static const osm = '© OpenStreetMap contributors';
  static const osmUrl = 'https://www.openstreetmap.org/copyright';
  static const odblUrl = 'https://opendatacommons.org/licenses/odbl/1-0/';
}
