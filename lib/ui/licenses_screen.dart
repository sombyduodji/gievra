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
    ('crypto', t('Karttapakettien tarkistussummat'), 'BSD-3'),
    ('http', t('Karttojen ja korkeustietojen lataus'), 'BSD-3'),
    ('flutter_map', t('Reittikartta ja karttapakettien näyttö'), 'BSD-3'),
    ('vector_map_tiles, vector_tile_renderer', t('Offline-vektorikartan piirto'), 'BSD-3'),
    ('vector_tile', t('Karttapakettien luku'), 'MIT'),
    ('latlong2', t('Koordinaatit ja matkat reitillä'), 'Apache 2.0'),
    (
      'AndroidX Core, Health Connect client',
      t('Ilmoitukset sekä Health Connectin syke, askeleet, harjoitukset, uni ja yöarvot'),
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
            // Uni- ja Palautuminen-kortit (17.11.): vain vihjeitä, omaan tasoon verraten.
            ('Watson et al. 2015 (AASM, SRS), Sleep 38:843–844', t('Uni: aikuisille 7 tuntia tai enemmän')),
            ('Craven et al. 2022, Sports Medicine', t('Uni: lyhyen yön vaikutus suorituskykyyn')),
            ('Windred et al. 2024, Sleep', t('Uni: säännöllisyys')),
            (
              'Huang et al. 2020, JACC 75:991–999; Fischer et al. 2021, Sleep 44:zsab103',
              t('Uni: säännöllisyyden rajat (30 ja 90 min) ja 14 yön jakso'),
            ),
            (
              'Mah et al. 2011, Sleep 34:943–950; Cunha et al. 2023, Sports Med Open, doi 10.1186/s40798-023-00599-z',
              t('Uni: unen pidentäminen ja päiväunet urheilijoilla'),
            ),
            ('Baron et al. 2017, J Clin Sleep Med 13:351–354', t('Uni: unenseurannan aiheuttama stressi (ortosomnia)')),
            (
              'Mishra et al. 2020, Nat Biomed Eng 4:1208–1220; Radin et al. 2020, Lancet Digital Health',
              t('Yön alin syke verrattuna omaan 28 päivän tasoon'),
            ),
            // Yöarvot-kortti (17.11.): kaikki avoimia (CC BY) paitsi Plews 2012.
            (
              'Plews et al. 2012, Eur J Appl Physiol 112:3729–3741; Buchheit 2014, Front Physiol 5:73',
              t('Yöarvot: HRV:n 7 yön keskiarvo ja oma vaihteluväli'),
            ),
            (
              'Javaloyes et al. 2019, IJSPP 14:23–32; Düking et al. 2021, J Sci Med Sport; Stanley et al. 2013, Sports Med',
              t('Yöarvot: HRV-ohjattu treeni ja palautuminen kovan treenin jälkeen'),
            ),
            ('Cao et al. 2022, J Med Internet Res 24:e27487', t('Yöarvot: sormuksen yösyke ja HRV verrattuna EKG:hen')),
            (
              'Altini & Plews 2021, Sensors 21:7932; Pietilä et al. 2018, JMIR Ment Health 5:e23',
              t('Yöarvot: alkoholin, sairauden ja treenin vaikutus HRV:hen ja sykkeeseen'),
            ),
            ('Natarajan et al. 2021, npj Digit Med 4:136', t('Yöarvot: hengitystiheys')),
            (
              'Smarr et al. 2020, Sci Rep 10:21640; Mason et al. 2022, Sci Rep 12:3463',
              t('Yöarvot: ihon lämpötila ja useamman arvon yhdistelmä'),
            ),
            (
              'Shapiro et al. 2023, npj Digit Med 6:134; Khosla et al. 2018 (AASM), J Clin Sleep Med 14:877–880',
              t('Yöarvot: happisaturaatio ja kuluttajalaitteiden rajat'),
            ),
            ('Walsh et al. 2021, Br J Sports Med 55:356–368', t('Uni: urheilijan uni ja oma unitavoite')),
            ('Stutz et al. 2019, Sports Med 49:269–287', t('Uni: kova treeni alle tunti ennen nukkumaanmenoa')),
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
