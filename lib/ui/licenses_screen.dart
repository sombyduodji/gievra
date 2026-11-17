import 'package:flutter/material.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../maps/elevation.dart' show elevAttribution, copernicusAttribution;
import '../theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Avoimen lähdekoodin osat selkokielellä: mitä kukin tekee ja millä lisenssillä.
/// Täydet lisenssitekstit Flutterin omalla sivulla (vaatimus: tekstit pitää näyttää sovelluksessa).
class LicensesScreen extends StatelessWidget {
  final String version;
  const LicensesScreen({super.key, required this.version});

  static List<(String, String, String)> get _parts => [
    (t('Flutter ja Dart'), t('Sovelluksen pohja: käyttöliittymä, piirtäminen, perustoiminnot'), 'BSD-3'),
    ('intl', t('Suomenkieliset päivämäärät ja kuukausien nimet'), 'BSD-3'),
    (t('path, path_provider'), t('Treenikansion ja tiedostopolkujen käsittely'), 'BSD-3'),
    ('shared_preferences', t('Laitteen omat asetukset (esim. treenikansion sijainti)'), 'BSD-3'),
    ('file_picker', t('Kansion ja tuotavien tiedostojen valinta'), 'MIT'),
    ('permission_handler', t('Tiedostojen käyttöluvan pyytäminen synkatulle kansiolle'), 'MIT'),
    ('archive', t('Varmuuskopion zip-tiedoston teko ja purku'), 'MIT'),
    ('sqlite3', t('FitNotes-varmuuskopion luku ja vienti (SQLite-tietokanta)'), 'MIT, SQLite: public domain'),
    ('share_plus', t('Treenin jakaminen viesteihin ja muihin sovelluksiin'), 'BSD-3'),
    ('url_launcher', t('Linkit ja sähköposti (palaute, tuki)'), 'BSD-3'),
    ('package_info_plus', t('Versionumero Tietoa-ikkunaan'), 'BSD-3'),
    ('crypto', t('Tarkistesummat: tunnistaa, onko tiedosto muuttunut (tulevaa synkronointia varten)'), 'BSD-3'),
    ('http', t('Tuleva Google Drive -synkronointi (ei vielä käytössä)'), 'BSD-3'),
    ('flutter_map', t('Reittikartta ja karttapakettien näyttö'), 'BSD-3'),
    ('vector_map_tiles, vector_tile_renderer', t('Offline-vektorikartan piirto'), 'BSD-3'),
    ('vector_tile', t('Karttapakettien luku'), 'MIT'),
    ('latlong2', t('Koordinaatit ja matkat reitillä'), 'Apache 2.0'),
    (
      'AndroidX Core, Health Connect client',
      t('Ilmoitukset sekä Health Connectin syke, askeleet ja harjoitukset'),
      'Apache 2.0',
    ),
    ('Kotlin coroutines', t('Health Connect -haut taustasäikeessä'), 'Apache 2.0'),
    if (isDemo) ('Noto Sans, Noto Color Emoji', t('Verkkoversion fontit ja emojit omalta palvelimelta'), 'SIL OFL 1.1'),
    if (isDemo) ('Roboto', t('Verkkoversion perusfontti'), 'Apache 2.0'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: BarTitle(Text(t('Avoin lähdekoodi'))), bottom: samiBarBand),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SizedBox(height: 12),
          Text(
            t(
              'Gievra on tehty avoimen lähdekoodin osista. Ne ovat ohjelmointikirjastoja, eivät '
              'erillisiä sovelluksia: ne eivät lähetä tietoja minnekään eivätkä käytä laitteen tehoa '
              'taustalla. Lisenssit sallivat maksuttoman käytön; ehtona on, että lisenssitekstit '
              'näytetään.',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t(
              'Gievra itse on vapaa ohjelma: GNU GPL v3.0. Lähdekoodia saa käyttää, muokata ja jakaa, '
              'kunhan muokatut versiot jaetaan samalla lisenssillä.',
            ),
            style: sub,
          ),
          SectionLabel(t('Osat ja mihin niitä käytetään')),
          for (final (name, what, lic) in _parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(what, style: sub),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(lic, style: sub),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            t(
              'BSD-3 ja MIT ovat lyhyitä, sallivia lisenssejä: käyttö on vapaata, kun tekijöiden '
              'tekijänoikeusmerkintä säilyy. Lisäksi mukana on näiden osien omia apukirjastoja, jotka '
              'näkyvät täysissä teksteissä.',
            ),
            style: sub,
          ),
          // Aineistojen lisenssit vaativat lähteen mainitsemisen (OSM: ODbL, Maanmittauslaitos: CC BY 4.0).
          SectionLabel(t('Kartta- ja korkeustiedot')),
          for (final (name, what, lic) in [
            ('© OpenStreetMap contributors', t('Karttapakettien tiedot (tiet, polut, paikat)'), 'ODbL 1.0'),
            ('Protomaps basemap', t('Kartan tyyli (vaalea ja tumma)'), 'CC0'),
            (elevAttribution, t('Nousut ja korkeusprofiili Suomessa'), 'CC BY 4.0'),
            ('Copernicus DEM GLO-30', '$copernicusAttribution.', t('muualla')),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(what, style: sub),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(lic, style: sub),
                ],
              ),
            ),
          // Laskentakaavat (käyttäjä 17.11.: lähteet ja käyttöehdot tarkistettu; yhtälöt ja luvut eivät ole
          // tekijänoikeuden suojaamia, Compendium sallii käytön lähteen mainiten: pacompendium.com).
          SectionLabel(t('Laskentakaavat')),
          for (final (name, what) in [
            ('Ludlow & Weyand 2016, J Appl Physiol 120:481–494', t('Kävelyn kalorit vauhdista ja pituudesta')),
            ('Keytel et al. 2005, J Sports Sci 23:289–297', t('Muiden kestävyyslajien kalorit sykkeestä')),
            ('ACSM: Guidelines for Exercise Testing and Prescription', t('Juoksun kalorit matkasta ja ajasta')),
            (
              'Herrmann et al. 2024, Adult Compendium of Physical Activities (pacompendium.com)',
              t('Salitreenin MET-arvot'),
            ),
            ('Mifflin, St Jeor et al. 1990, Am J Clin Nutr 51:241–247', t('Lepoaineenvaihdunta')),
            ('Tanaka et al. 2001, J Am Coll Cardiol 37:153–156', t('Maksimisykkeen arvio iästä')),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(what, style: sub),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            t('Palautusajastimen äänet, kuvakkeet ja liikkeiden animaatiot ovat Gievran omaa työtä (GPL v3.0).'),
            style: sub,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: AppInfo.fullName,
              applicationVersion: version,
              applicationIcon: const AppLogo(size: 48),
            ),
            icon: const Icon(Icons.description_outlined),
            label: Text(t('Näytä täydet lisenssitekstit')),
          ),
        ],
      ),
    );
  }
}
