import 'package:flutter/material.dart';

// "Uutta tässä versiossa": vain uudet ominaisuudet (ei korjauksia), näytetään kerran päivityksen jälkeen.
// Lisää uuden version kohdat listan alkuun; tekstit suomeksi (käännökset .po-tiedostoissa).

class NewFeature {
  final String version;
  final IconData icon;
  final String title, text;
  const NewFeature(this.version, this.icon, this.title, this.text);
}

// l10n: data
const whatsNew = <NewFeature>[
  NewFeature(
    '0.6.3',
    Icons.fitness_center,
    'Levylaskuri',
    'Tankoliikkeissä painon alla näkyy levyt puolta kohden. Napauta: kuva tangosta ja omat levyt.',
  ),
  NewFeature(
    '0.6.3',
    Icons.percent,
    'Prosenttia maksimista',
    'Sarjan kirjauksen %-painike näyttää painot 50–95 % arvioidusta maksimista. Ohjelmassa painon voi antaa prosentteina.',
  ),
  NewFeature(
    '0.6.3',
    Icons.link,
    'Supersarjat ja kiertoharjoittelu',
    'Liikkeet vuorotellen, tauko vasta kierroksen jälkeen. Ohjelmassa liikkeen kohdalla Supersarja A–D, treenissä ⋮ → Supersarjat.',
  ),
  NewFeature(
    '0.6.3',
    Icons.trending_down,
    'Pudotus- ja AMRAP-sarjat',
    'Sarjan tyyppi tallennuspainikkeiden yläpuolella: pudotus (kevyempi paino heti perään) tai AMRAP (niin monta toistoa kuin jaksat).',
  ),
  NewFeature(
    '0.6.3',
    Icons.timer_outlined,
    'Ajastin aikaliikkeisiin',
    'Lankku ja muut sekunteina mitattavat liikkeet: Aloita ajastin laskee alas ja ilmoittaa äänellä.',
  ),
  NewFeature(
    '0.6.3',
    Icons.auto_graph,
    'Tarkemmat painoehdotukset',
    'Tankoliikkeissä paino nousee 5 tai 10 kg ja toistot palaavat alueelle; toistoja ei lisätä loputtomiin. Kahvakuulalla seuraava kuula vasta, kun sillä onnistuu tarpeeksi toistoja.',
  ),
];

/// Versioiden vertailu numeroina: 0.6.10 > 0.6.9, 0.6 < 0.6.1.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Uudet ominaisuudet, joita ei ole vielä näytetty: version [seen] jälkeen, enintään nykyinen [current].
List<NewFeature> unseenFeatures(String current, String seen) => [
  for (final f in whatsNew)
    if (compareVersions(f.version, seen) > 0 && compareVersions(f.version, current) <= 0) f,
];

/// Uusimman version ominaisuudet, joka on enintään [current] (Tietoa-näkymän "Uutta tässä versiossa").
List<NewFeature> latestFeatures(String current) {
  final shown = whatsNew.where((f) => compareVersions(f.version, current) <= 0).toList();
  if (shown.isEmpty) return const [];
  final v = shown.first.version;
  return shown.where((f) => f.version == v).toList();
}
