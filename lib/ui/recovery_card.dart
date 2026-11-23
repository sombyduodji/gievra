import 'package:flutter/material.dart';

import '../app_state.dart';
import '../heart_rate.dart' show hrProfile;
import '../home_extras.dart';
import '../l10n.dart';
import '../models.dart';
import '../recovery.dart';
import '../session_compare.dart' show fmtDuration;
import '../sleep.dart';
import '../theme.dart';
import 'home_extras_ui.dart' show NightHrData, NightMetricsCard, hrvHint, nightHrNights;
import 'sleep_stages_ui.dart';
import 'tile_trend.dart';

// Palautuminen-kortti (käyttäjä 18.11., vaihtoehto A): ruudut, joiden vasen reuna on saamen vihreä, keltainen tai
// punainen; keltaisessa ja punaisessa ⚠, jota napauttamalla näkee, mitä poikkeama voi tarkoittaa ja mitä tehdä.
// Ei tilasirua eikä selitystekstejä kortissa: ohjeet ? -painikkeen takana. Yösyke on yksi ruutu muiden joukossa.

class RecTile {
  final String key, label, value, sub;
  final IconData icon;
  final TileState state;
  const RecTile(this.key, this.label, this.icon, this.value, this.sub, this.state);
}

Color tileColor(BuildContext context, TileState s) => switch (s) {
  TileState.green => Theme.of(context).brightness == Brightness.dark ? Sami.greenLight : Sami.green,
  TileState.yellow => Sami.yellow,
  TileState.red => Sami.red,
  TileState.none => Theme.of(context).colorScheme.outlineVariant,
};

/// Kortin ruudut nykyisistä tiedoista ([now] testeille).
List<RecTile> recoveryTiles(DateTime now) {
  final today = dateOnly(now);
  final tiles = <RecTile>[];
  // Käyttäjän järjestyksessä (Asetukset → Etusivu → Palautumisen ruudut, 18.11.).
  for (final k in settings.recoveryOrder) {
    if (!settings.nightTiles.contains(k)) continue;
    switch (k) {
      case 'nighthr':
        final n = nightHr(nightHrNights(), now);
        if (n == null) continue;
        tiles.add(
          RecTile(
            'nighthr',
            t('Yösyke'),
            Icons.favorite_border,
            '${n.last}',
            n.base == null ? t('tav. viikon jälkeen') : t('tav. {0}', [n.base!.round()]),
            nightHrState(n),
          ),
        );
      case 'hrv' || 'rr' || 'spo2' || 'temp':
        if (!settings.homeCardOn('night')) continue;
        final s = metricStat(sleepData.metrics, k, now);
        if (s == null) continue;
        final st = metricState(k, s, sleepData.metrics, now);
        tiles.add(
          RecTile(
            k,
            NightMetricsCard.label(k),
            NightMetricsCard.icon(k),
            NightMetricsCard.value(k, s.last),
            st == TileState.none
                ? t('vertailu 2 viikon jälkeen')
                : t('tav. {0}', [NightMetricsCard.value(k, metricUsual(k, s)!)]),
            st,
          ),
        );
      case 'sleep':
        if (!sleepData.enabled) continue;
        final s = sleepStats(sleepData.nights, today, goal: Duration(minutes: settings.sleepGoal));
        if (s.last == null) continue;
        tiles.add(
          RecTile(
            'sleep',
            t('Uni'),
            Icons.bedtime_outlined,
            fmtDuration(s.last!.asleep.inMinutes),
            s.usual == null ? '' : t('tav. {0}', [fmtDuration(s.usual!.inMinutes)]),
            sleepTileState(s),
          ),
        );
      case 'load':
        final l = trainingLoad(store.workouts, today, maxHr: hrProfile()?.maxHr(now));
        if (l == null) continue;
        tiles.add(
          RecTile(
            'load',
            t('Kuormitus'),
            Icons.fitness_center,
            switch (l.$1) {
              TrainLoad.light => t('Kevyt'),
              TrainLoad.normal => t('Tavallinen'),
              TrainLoad.hard => t('Kova'),
            },
            t('7 pv vs. 4 vk'),
            loadTileState(l.$1),
          ),
        );
    }
  }
  return tiles;
}

/// Ruudun nimi ja kuvake asetuksiin.
(String, IconData) recoveryTileName(String k) => switch (k) {
  'nighthr' => (t('Yösyke'), Icons.favorite_border),
  'sleep' => (t('Uni'), Icons.bedtime_outlined),
  'load' => (t('Kuormitus'), Icons.fitness_center),
  _ => (NightMetricsCard.label(k), NightMetricsCard.icon(k)),
};

/// Asetukset → Etusivu → Palautumisen ruudut: päälle/pois ja järjestys vetämällä (käyttäjä 18.11.).
class RecoveryTilesSettings extends StatelessWidget {
  const RecoveryTilesSettings({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(t('Palautumisen ruudut'))),
        body: const RecoveryTilesSettings(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: settings, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final night = settings.homeCardOn('night');
    return ListView(
      key: const ValueKey('recoveryTilesSettings'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(t('Valitse näytettävät ruudut ja vedä ne haluamaasi järjestykseen.'), style: sub),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            final o = [...settings.recoveryOrder];
            o.insert(b, o.removeAt(a));
            settings.setRecoveryOrder(o);
          },
          children: [
            for (final (i, k) in settings.recoveryOrder.indexed)
              Builder(
                key: ValueKey('recTileRow_$k'),
                builder: (context) {
                  final (name, icon) = recoveryTileName(k);
                  final needsNight = const {'hrv', 'rr', 'spo2', 'temp'}.contains(k) && !night;
                  final needsSleep = k == 'sleep' && !sleepData.enabled;
                  return ListTile(
                    contentPadding: const EdgeInsets.only(left: 4, right: 16),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_indicator)),
                    ),
                    title: Row(
                      children: [
                        Icon(icon, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Flexible(child: Text(name)),
                      ],
                    ),
                    subtitle: needsNight
                        ? Text(t('Vaatii yöarvot (kytkin Asetukset → Etusivu).'), style: sub)
                        : needsSleep
                        ? Text(t('Vaatii Uni-kortin tai yöarvot.'), style: sub)
                        : null,
                    trailing: Semantics(
                      label: name,
                      child: Switch(
                        key: ValueKey('recTileSwitch_$k'),
                        value: settings.nightTiles.contains(k),
                        onChanged: (v) => settings.setNightTile(k, v),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class RecoveryCard extends StatelessWidget {
  const RecoveryCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([NightHrData.nights, sleepData, settings, store]),
    builder: (context, _) {
      final now = DateTime.now();
      final tiles = recoveryTiles(now);
      if (tiles.isEmpty) {
        if (!settings.homeCardOn('night')) return const SizedBox.shrink();
        return _shell(
          context,
          Text(
            sleepData.loading
                ? t('Haetaan yöarvoja Health Connectista…')
                : t('Ei yöarvoja. Kortti näyttää ne, kun kello tai sormus kirjaa ne Health Connectiin.'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
      }
      final reds = tiles
          .where((x) => const {'nighthr', 'hrv', 'rr', 'temp'}.contains(x.key) && x.state == TileState.red)
          .length;
      return _shell(
        context,
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, tile) in tiles.indexed)
                  SizedBox(
                    // Pariton määrä: viimeinen ruutu koko leveydeltä.
                    width: tiles.length.isOdd && i == tiles.length - 1 ? c.maxWidth : w,
                    child: _Tile(tile: tile, reds: reds, now: now),
                  ),
              ],
            );
          },
        ),
      );
    },
  );

  Widget _shell(BuildContext context, Widget body) => Card(
    key: const ValueKey('nightHrCard'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 14), // oikealla ruutujen oma reunus
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Semantics(
              header: true,
              child: Text(t('Palautuminen'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          Padding(padding: const EdgeInsets.only(right: 12), child: body),
        ],
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  final RecTile tile;
  final int reds;
  final DateTime now;
  const _Tile({required this.tile, required this.reds, required this.now});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = tileColor(context, tile.state);
    final warn = tile.state == TileState.yellow || tile.state == TileState.red;
    final warnColor = tile.state == TileState.red ? redText(context) : yellowText(context);
    // Vaihtoehto A (käyttäjä 18.11.): pyöristetty ruutu neutraalilla pinnalla (ei teeman ruskeaa), tilan väri
    // lyhyenä pyöristettynä palkkina ruudun sisällä.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final body = Container(
      key: ValueKey('nightTile_${tile.key}'),
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: .07) : Colors.black.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              margin: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tile.label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), maxLines: 2),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(tile.value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                  if (tile.sub.isNotEmpty)
                    Text(tile.sub, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), maxLines: 2),
                ],
              ),
            ),
            if (warn)
              Align(
                alignment: Alignment.topRight,
                child: Icon(Icons.warning_amber_rounded, size: 20, color: warnColor),
              ),
          ],
        ),
      ),
    );
    // Jokainen ruutu avaa käyrän (19.11.); poikkeavassa myös neuvon.
    return Semantics(
      button: true,
      label: warn
          ? '${tile.label} ${tile.value}, ${tile.sub}, ${t('poikkeaa tavallisesta')}'
          : '${tile.label} ${tile.value}, ${tile.sub}',
      onTap: () => showTileAdvice(context, tile, reds, now),
      excludeSemantics: true,
      child: GestureDetector(onTap: () => showTileAdvice(context, tile, reds, now), child: body),
    );
  }
}

/// Neuvo ruudulle: (otsikko, mitä se voi tarkoittaa, mitä tehdä, raja ja lähde).
(String, String, String, String) tileAdvice(RecTile tile, DateTime now) {
  final red = tile.state == TileState.red;
  return switch (tile.key) {
    'nighthr' when red => (
      t('Yösyke selvästi koholla'),
      t('Sairastuminen alkamassa, kova rasitus, alkoholi, stressi tai huono uni.'),
      t('Kevyempi tai kohtuullinen treeni tänään, liiku silti. Jos olo on kipeä tai kuumeinen, lepää.'),
      t('Raja: 5 lyöntiä yli oman tason (3 yön keskiarvo vs. 28 yön mediaani; Mishra 2020, Quer 2020). Ei diagnoosi.'),
    ),
    'nighthr' => (
      t('Yösyke hieman koholla'),
      t('Usein huono uni, stressi, alkoholi tai edellisen päivän rasitus.'),
      t('Treenin voi tehdä, mutta jätä enemmän varaa. Seuraa huomenna.'),
      t('Raja: 3 lyöntiä yli oman tason.'),
    ),
    'hrv' when red => (
      t('HRV kaksi päivää matalana'),
      hrvHint(now),
      '',
      t('Raja: 7 yön keskiarvo alle oman vaihteluvälin kahtena päivänä peräkkäin (Plews 2012, Javaloyes 2019).'),
    ),
    'hrv' => (
      t('HRV tavallista matalampi'),
      t('Yksittäinen matala jakso johtuu usein lyhyestä yöstä, alkoholista tai kovasta treenistä.'),
      t('Seuraa huomenna; yksi päivä ei vielä vaadi muutoksia.'),
      t('Raja: 7 yön keskiarvo alle oman vaihteluvälin (Plews 2012).'),
    ),
    'rr' when red => (
      t('Hengitys selvästi tavallista tiheämpää'),
      t('Hengitystiheyden nousu on tutkimuksissa ollut yksi varhaisista sairastumisen merkeistä.'),
      t('Kevyt päivä tai lepo, jos olo on huono. Jos samalla on hengenahdistusta, ota yhteys lääkäriin.'),
      t('Raja: +3 /min tai +2 /min kahtena yönä peräkkäin (Natarajan 2021).'),
    ),
    'rr' => (
      t('Hengitys hieman tavallista tiheämpää'),
      t('Voi johtua rasituksesta, stressistä tai alkavasta flunssasta.'),
      t('Seuraa huomenna.'),
      t('Raja: 1,5 /min yli oman tason.'),
    ),
    'temp' when red => (
      t('Ihon lämpötila koholla'),
      t(
        'Lämmön nousu ennen oireita on tutkimuksissa ollut yleinen sairastumisen merkki, mutta myös lämmin '
        'makuuhuone, alkoholi tai kuukautiskierto nostavat sitä.',
      ),
      t('Jos olo on kipeä tai kuumeinen, lepää. Muuten kevyempi päivä ja seuraa.'),
      t('Raja: +0,5 °C omasta tasosta (Smarr 2020, Mason 2022). Ei diagnoosi.'),
    ),
    'temp' => (
      t('Ihon lämpötila hieman koholla'),
      t('Lämmin makuuhuone, alkoholi, myöhäinen treeni tai kuukautiskierto voivat nostaa sitä.'),
      t('Seuraa huomenna.'),
      t('Raja: +0,3 °C omasta tasosta.'),
    ),
    'spo2' when red => (
      t('Happisaturaatio tavallista matalampi'),
      t('Kellon tai sormuksen lukema on suuntaa-antava.'),
      t('Jos se toistuu ja olet väsynyt tai kuorsaat, kysy lääkäriltä.'),
      t('Raja: 2 alle oman tason kolmena yönä tai alle 92 % (Shapiro 2023; AASM). Ei diagnoosi.'),
    ),
    'spo2' => (
      t('Happisaturaatio hieman tavallista matalampi'),
      t('Yksittäinen yö voi johtua sormuksen asennosta tai liikkeestä unessa.'),
      t('Seuraa.'),
      t('Raja: 1 prosenttiyksikkö alle oman tason.'),
    ),
    'sleep' when red => (
      t('Lyhyt yö (6 h tai alle)'),
      t('Suorituskyky voi olla heikompi, eniten illalla ja taitoa vaativissa liikkeissä.'),
      t('Jätä enemmän varaa. Aiempi nukkumaanmeno tai lyhyt päiväuni voi auttaa.'),
      t('Craven 2022, Mah 2011.'),
    ),
    'sleep' => (
      t('Uni jäi tavallista lyhyemmäksi'),
      t('Lyhyt yö laskee usein HRV:tä ja nostaa yösykettä seuraavana päivänä.'),
      t('Treenin voi tehdä; jätä enemmän varaa. Aiempi nukkumaanmeno tai lyhyt päiväuni voi auttaa.'),
      t('Raja: 45 min alle oman tavallisen.'),
    ),
    _ => (
      t('Kuormitus tavallista kovempi'),
      t('Viimeisen viikon treenimäärä kertaa rasitus on yli 1,3-kertainen 4 viikon keskiarvoon.'),
      t('Jos olo on väsynyt, kevennä muutamaksi päiväksi. Kuormituksen nostaminen vähitellen on turvallisinta.'),
      t('Gabbett 2016. Suhteen yhteys vammoihin on kiistelty (Impellizzeri 2020), joten tämä on vain taustatietoa.'),
    ),
  };
}

/// Ruudun paneeli (käyttäjä 19.11., vaihtoehto C): arvo käyränä 30 päivältä tai 12 viikolta; keltaisessa ja
/// punaisessa ruudussa lisäksi mitä poikkeama voi tarkoittaa ja mitä tehdä.
Future<void> showTileAdvice(BuildContext context, RecTile tile, int reds, DateTime now) {
  final warn = tile.state == TileState.yellow || tile.state == TileState.red;
  final (title, means, todo, src) = warn ? tileAdvice(tile, now) : (tile.label, '', '', '');
  final physio = const {'nighthr', 'hrv', 'rr', 'temp'}.contains(tile.key);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final sub = TextStyle(fontSize: 13, color: cs.onSurfaceVariant);
      Widget sec(String h, String body) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(h, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body),
          ],
        ),
      );
      return SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('tileAdvice'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    warn ? Icons.warning_amber_rounded : tile.icon,
                    color: warn ? (tile.state == TileState.red ? redText(ctx) : yellowText(ctx)) : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: 4),
              Text(tile.sub.isEmpty ? tile.value : '${tile.value} · ${tile.sub}', style: sub),
              // Univaiheet viime yöltä (käyttäjä 23.11.), vain näyttö.
              if (tile.key == 'sleep' && sleepStats(sleepData.nights, dateOnly(now)).last != null)
                SleepStagesBox(night: sleepStats(sleepData.nights, dateOnly(now)).last!),
              TileTrend(tileKey: tile.key, state: tile.state, now: now),
              if (warn) ...[
                if (physio && reds >= 2 && tile.state == TileState.red)
                  sec(t('Useampi arvo punaisella'), t('Kevyt päivä tai lepo on hyvä ajatus.')),
                sec(t('Mitä se voi tarkoittaa'), means),
                if (todo.isNotEmpty) sec(t('Mitä tehdä'), todo),
                const SizedBox(height: 10),
                Text(src, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Etusivun ohjeen Palautuminen-osio (käyttäjä 18.11.: selitykset etusivun ? -ohjeeseen, ei korttiin).
class RecoveryHelpSection extends StatelessWidget {
  const RecoveryHelpSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 13, color: cs.onSurfaceVariant);
    Widget legend(TileState s, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 5, height: 18, color: tileColor(context, s)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: sub)),
        ],
      ),
    );
    return Padding(
      key: const ValueKey('recoveryHelpSection'),
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Palautuminen'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          legend(TileState.green, t('Vihreä: omalla tasollasi')),
          legend(TileState.yellow, t('Keltainen: hieman poikkeava, seuraa')),
          legend(TileState.red, t('Punainen: selvästi poikkeava')),
          legend(TileState.none, t('Harmaa: vertailu, kun öitä on tarpeeksi')),
          const SizedBox(height: 4),
          Text(t('Napauta ⚠-ruutua: näet, mitä poikkeama voi tarkoittaa ja mitä tehdä.'), style: sub),
          const SizedBox(height: 4),
          Text(
            t(
              'Yön arvoja verrataan omaan tasoosi, kun öitä on tarpeeksi (yösyke viikko, muut 2 viikkoa). Jos kaksi '
              'tai useampi yösyke-, HRV-, hengitys- tai lämpöarvo on punainen, kevyt päivä tai lepo on hyvä ajatus. '
              'Uni on viime yö verrattuna tavalliseen. Kuormitus on viimeisen viikon treeni verrattuna 4 viikon '
              'keskiarvoon. Vain vihjeitä, ei diagnoosia.',
            ),
            style: sub,
          ),
          const SizedBox(height: 4),
          Text(t('Lähteet: Lisää → Tietoa. Kehitys ajan mittaan: Tilastot.'), style: sub),
          TextButton.icon(
            key: const ValueKey('recoveryChooseTiles'),
            icon: const Icon(Icons.tune, size: 18),
            label: Text(t('Valitse ruudut')),
            onPressed: () => RecoveryTilesSettings.open(context),
          ),
        ],
      ),
    );
  }
}
