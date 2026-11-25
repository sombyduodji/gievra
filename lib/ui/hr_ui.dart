import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../app_state.dart';
import '../body.dart';
import '../effort.dart' show hrEffort;
import '../heart_rate.dart';
import '../health.dart';
import '../sports.dart' show sportOf;
import '../share_text.dart' show thousands;
import '../hr_calc.dart';
import '../models.dart';
import '../l10n.dart';
import '../theme.dart';
import 'widgets.dart';

/// Syke treenin aikana: "❤️ 142". Näkyy vain, kun sykevyö on valittu ja treeni kerää sykettä. Yhdistettäessä
/// "…", ilman ihokontaktia tai tuoretta lukemaa "–".
class HrChip extends StatelessWidget {
  final double fontSize;
  const HrChip({super.key, this.fontSize = 15});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: hr,
    builder: (context, _) {
      if (hr.address == null || !hr.recording) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final v = hr.bpm;
      final text = v != null && hr.contact != false
          ? '$v'
          : hr.state == HrState.connecting
          ? '…'
          : '–';
      return Tooltip(
        message: hr.name ?? t('Sykevyö'),
        child: Container(
          key: const ValueKey('hrChip'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Sami.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite, size: fontSize, color: v != null ? Sami.red : cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Asetukset → Keho ja laitteet → Sykevyö: haku, valinta, nykyinen syke ja akku, unohda.
class HrScreen extends StatefulWidget {
  const HrScreen({super.key});
  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> {
  @override
  void initState() {
    super.initState();
    // Valittu vyö: yhteys auki tällä sivulla, jotta syke ja akku näkyvät (testi ennen treeniä).
    if (hr.address != null) hr.begin(_key);
  }

  static const _key = 'settings';

  @override
  void dispose() {
    hr.stopScan();
    hr.end(_key);
    super.dispose();
  }

  String _profileText() => hrProfileSummary();

  String? _errorText() => switch (hr.error) {
    'permission' when hr.locationPermission => t('Sijaintilupa tarvitaan sykevyön hakuun (Android 11 ja vanhemmat).'),
    'permission' => t('Bluetooth-lupa tarvitaan sykevyön hakuun.'),
    'off' => t('Bluetooth on pois päältä.'),
    'noHeartRate' => t('Laite ei lähetä sykettä.'),
    null => null,
    _ => t('Haku ei onnistunut: {0}', [hr.error!]),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 13, color: cs.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: BarTitle(Text(t('Sykevyö'))), bottom: samiBarBand),
      body: ListenableBuilder(
        listenable: hr,
        builder: (context, _) {
          final err = _errorText();
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              Text(
                t(
                  'Sykevyö tai -anturi Bluetoothilla (esim. Polar H10, Polar Verity Sense, Garmin HRM). Syke näkyy '
                  'treenin aikana, ja keskisyke ja maksimi tallentuvat treeniin.',
                ),
                style: sub,
              ),
              const SizedBox(height: 16),
              if (hr.address != null) ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.favorite, color: hr.bpm != null ? Sami.red : cs.onSurfaceVariant, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(hr.name ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              Text(
                                [
                                  switch (hr.state) {
                                    HrState.connected => t('Yhdistetty'),
                                    HrState.connecting => t('Yhdistetään…'),
                                    HrState.none => t('Ei yhteyttä'),
                                  },
                                  if (hr.battery != null) t('akku {0} %', [hr.battery!]),
                                ].join(' · '),
                                style: sub,
                              ),
                              if (hr.contact == false)
                                Text(t('Ei ihokontaktia: kostuta vyön elektrodit.'), style: TextStyle(color: cs.error)),
                            ],
                          ),
                        ),
                        Text(
                          hr.bpm == null ? '–' : '${hr.bpm}',
                          key: const ValueKey('hrNow'),
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  key: const ValueKey('hrProfile'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: Text(t('Kalorit sykkeestä')),
                  subtitle: Text(_profileText(), style: sub),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    await askHrProfile(context);
                    if (mounted) setState(() {});
                  },
                ),
                // Oma maksimisyke (jos tiedossa): alueet, käyrän asteikko ja kalorit.
                ListTile(
                  key: const ValueKey('maxHr'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.speed),
                  title: Text(t('Maksimisyke')),
                  subtitle: Text(
                    settings.maxHr != null
                        ? t('{0} · oma mittaus', [settings.maxHr!])
                        : hrProfile() == null
                        ? t('arvio iästä, kun syntymävuosi on annettu')
                        : t('{0} · arvio iästä (208 − 0,7 × ikä)', [hrProfile()!.maxHr(DateTime.now())]),
                    style: sub,
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final v = await askNumber(
                      context,
                      t('Oma maksimisyke (0 = arvio iästä)'),
                      (settings.maxHr ?? hrProfile()?.maxHr(DateTime.now()) ?? 185).toDouble(),
                      decimals: false,
                    );
                    if (v == null) return;
                    settings.setMaxHr(v < 120 ? null : v.round());
                    if (mounted) setState(() {});
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => showZoneInfo(context),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: Text(t('Mitä sykealueet tarkoittavat?')),
                  ),
                ),
                // Palautus sykkeen mukaan: ajastin odottaa sykkeen laskua palautumisrajan alle.
                SwitchListTile(
                  key: const ValueKey('restByHr'),
                  contentPadding: EdgeInsets.zero,
                  value: settings.restByHr,
                  onChanged: (v) => setState(() => settings.setRestByHr(v)),
                  title: Text(t('Palautus sykkeen mukaan')),
                  subtitle: Text(
                    t(
                      'Sarjan jälkeen ajastin odottaa, kunnes syke laskee palautumisrajan alle, ja ilmoittaa '
                      'silloin. Jos palautuminen kestää yli 5 min, saat muistutuksen. Ilman sykettä käytetään '
                      'tavallisia palautusaikoja.',
                    ),
                  ),
                ),
                // Palautuminen sarjojen välillä ja kalorien oma korjaus.
                _Stepper(
                  key: const ValueKey('hrRecoveryPct'),
                  title: t('Palautunut sarjojen välillä'),
                  value: settings.hrRecoveryPct,
                  text: (v) {
                    final m = hrProfile()?.maxHr(DateTime.now());
                    return m == null
                        ? t('alle {0} % maksimisykkeestä', [v])
                        : t('alle {0} % maksimista ({1})', [v, (m * v / 100).round()]);
                  },
                  step: 5,
                  min: 40,
                  max: 80,
                  onChanged: (v) => setState(() => settings.setHrRecovery(v)),
                ),
                _Stepper(
                  key: const ValueKey('kcalAdjust'),
                  title: t('Kalorien korjaus'),
                  value: settings.kcalAdjustPct,
                  text: (v) => v == 0 ? t('ei korjausta (tutkimuksen arvo)') : t('{0} %', [v > 0 ? '+$v' : '$v']),
                  step: 1,
                  min: -10,
                  max: 10,
                  onChanged: (v) => setState(() => settings.setKcalAdjust(v)),
                ),
                Text(
                  t(
                    'Korjaa vain, jos tiedät kulutuksesi paremmin (esim. laboratoriomittaus tai pitkä seuranta). '
                    'Laskenta on yksilöllisesti noin ±15–20 % tarkka.',
                  ),
                  style: sub,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: hr.forget,
                    icon: const Icon(Icons.link_off),
                    label: Text(t('Unohda vyö')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: hr.scanning ? hr.stopScan : hr.scan,
                icon: hr.scanning
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bluetooth_searching),
                label: Text(hr.scanning ? t('Lopeta haku') : t('Etsi sykevyö')),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err, style: TextStyle(color: cs.error)),
                ),
              // Lupa kiellettiin: Android ei ehkä kysy uudelleen, joten ohjataan sovelluksen lupiin.
              if (hr.error == 'permission')
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('hrPermissionSettings'),
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(t('Avaa sovelluksen luvat')),
                  ),
                ),
              if (hr.scanEmpty && !hr.scanning && hr.found.isEmpty)
                Padding(
                  key: const ValueKey('hrScanEmpty'),
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    t(
                      'Vyötä ei löytynyt. Pue vyö ja kostuta elektrodit, jotta se herää, sulje valmistajan sovellus '
                      'ja etsi uudelleen.',
                    ),
                    style: TextStyle(color: cs.error),
                  ),
                ),
              if (hr.scanning || hr.found.isNotEmpty) ...[
                const SizedBox(height: 12),
                SectionLabel(t('Löytyneet')),
                if (hr.found.isEmpty) Text(t('Etsitään… Pue vyö ja kostuta elektrodit, jotta se herää.'), style: sub),
                for (final d in hr.found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.monitor_heart_outlined),
                    title: Text(d.name),
                    subtitle: Text(d.address, style: sub),
                    trailing: d.address == hr.address ? Icon(Icons.check, color: greenText(context)) : null,
                    onTap: () async {
                      await hr.choose(d);
                      // Kaloreihin tarvittavat tiedot heti vyön käyttöönotossa (olemassa olevat ehdotetaan).
                      if (hrProfile() == null && context.mounted) await askHrProfile(context);
                    },
                  ),
              ],
              const SizedBox(height: 20),
              Text(
                t(
                  'Vinkki: jos vyötä ei löydy, sulje valmistajan sovellus (esim. Polar Flow tai Polar Beat), koska vyö '
                  'voi olla yhteydessä vain yhteen sovellukseen kerrallaan. Polar-vyöhön voi myös kytkeä kaksi '
                  'yhtäaikaista yhteyttä valmistajan sovelluksesta.',
                ),
                style: sub,
              ),
              const SizedBox(height: 8),
              Text(t('Vyö muistetaan vain tällä puhelimella. Sykkeitä ei lähetetä minnekään.'), style: sub),
            ],
          );
        },
      ),
    );
  }
}

/// Treenin syke: käyrä (ylös ja alas), aika sykealueilla ja tietojen lähde. Näkyy, kun treenissä on sykevyön
/// käyrä (hr_series).
/// Rasitus sykkeestä (käyttäjä 20.11.): ei kysytä, vaan näytetään syke-kortissa, kun liikunnassa on sykettä ja
/// maksimisyke tiedetään. Ilman sykettä riviä ei ole. Alla minuutit viikon reippaan liikunnan tavoitteeseen.
class HrEffortRow extends StatelessWidget {
  final Workout w;
  final int? maxHr;
  const HrEffortRow(this.w, {super.key, this.maxHr});

  static const _labels = {'kevyt': 'Kevyt', 'reipas': 'Reipas', 'kova': 'Kova'};

  @override
  Widget build(BuildContext context) {
    if (w.activity == null) return const SizedBox.shrink();
    final e = hrEffort(w, maxHr ?? hrProfile()?.maxHr(w.date) ?? maxHrFor(w.date));
    if (e == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final i = ['kevyt', 'reipas', 'kova'].indexOf(e.level);
    final (bg, fg) = dark
        ? const [
            (Color(0xFF12301F), Color(0xFF5BD08A)),
            (Color(0xFF3A2F14), Color(0xFFF2C060)),
            (Color(0xFF3B1A18), Color(0xFFFF8378)),
          ][i]
        : const [
            (Color(0xFFE3F3E9), Color(0xFF007229)),
            (Color(0xFFFFF4D6), Color(0xFF7A5C00)),
            (Color(0xFFFBE6E4), Color(0xFFC0261B)),
          ][i];
    final weekMin = ((e.moderateSec + 2 * e.vigorousSec) / 60).round();
    return Padding(
      key: const ValueKey('hrEffort'),
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                Text(
                  t('Rasitus: {0}', [t(_labels[e.level]!).toLowerCase()]),
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                ),
                Text(t('{0} % maksimisykkeestä', [e.pct]), style: TextStyle(color: fg, fontSize: 13)),
              ],
            ),
            Text(
              weekMin > 0
                  ? t('Laskettu sykkeestä · {0} min viikon reippaaseen liikuntaan', [weekMin])
                  : t('Laskettu sykkeestä · kevyt liikunta ei kerrytä viikon reippaita minuutteja'),
              style: TextStyle(color: fg, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class HrDetails extends StatelessWidget {
  final Workout w;

  /// Treenin yhteenveto (käyttäjä 20.11.): matala käyrä ilman sykealueita, jotta kaikki mahtuu yhdelle ruudulle.
  final bool compact;
  const HrDetails(this.w, {super.key, this.compact = false});

  static const zoneColors = [Color(0xFF9E9E9E), Color(0xFF2E7DD7), Color(0xFF2BA6A6), Color(0xFFE6A23C), Sami.red];

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: settings, builder: (context, _) => _card(context)); // tiedot lisätty → alueet

  Widget _card(BuildContext context) {
    final s = w.hrSeries;
    if (s == null || s.readingCount < 2) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final p = hrProfile();
    // Alueisiin riittää maksimisyke (oma tai arvio syntymävuodesta); kaloreihin tarvitaan koko profiili.
    final measured = settings.maxHr != null;
    final maxHr =
        p?.maxHr(s.start) ??
        settings.maxHr ??
        (settings.birthYear == null ? null : (208 - 0.7 * (s.start.year - settings.birthYear!)).round());
    final watch = w.hrSource == 'kello';
    final zones = maxHr == null ? null : zoneSeconds(s, maxHr);
    // Alle 50 %:n aika (lämmittely, rauhallinen alku): muuten alueiden summa jäi mitattua lyhyemmäksi ja näytti
    // puuttuvalta sykkeeltä (kaverin kävely 14.11.: alueissa 17:40, mitattu 23:45).
    final below = zones == null ? 0 : s.readingCount * s.interval - zones.fold<int>(0, (a, b) => a + b);
    // Aluerivien sarakkeet kasvavat tekstikoon mukana: kiinteä leveys katkoi ajan ("15:0/0") ja alueen nimen
    // järjestelmän fontilla 2,0 (yötesti 15.11., Samsung/emulaattori).
    final textScale = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(1.0, 2.0).toDouble();
    final chipW = 124 * textScale.clamp(1.0, 1.3).toDouble();
    final timeW = 56 * textScale.clamp(1.0, 1.6).toDouble();
    final top = zones == null ? 1 : math.max(below, zones.reduce((a, b) => a > b ? a : b));
    final dur = w.durationSec ?? s.length.inSeconds;
    final cover = (s.coverage(dur) * 100).round();
    String mmss(int sec) => sec >= 3600 ? fmtDurationSec(sec) : '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
    return Card(
      key: const ValueKey('hrDetails'),
      margin: EdgeInsets.only(top: compact ? 8 : 12),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: Sami.red, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t('Syke'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Flexible(
                  child: Text(
                    t('ka {0} · max {1}', [w.hrAvg ?? s.avg ?? '–', w.hrMax ?? s.max ?? '–']),
                    textAlign: TextAlign.end,
                    style: sub,
                  ),
                ),
              ],
            ),
            HrEffortRow(w, maxHr: maxHr),
            const SizedBox(height: 8),
            Semantics(
              label: '${t('Syke')}: ${t('ka {0} · max {1}', [w.hrAvg ?? s.avg ?? '–', w.hrMax ?? s.max ?? '–'])}',
              excludeSemantics: true,
              child: SizedBox(
                height: compact ? 64 : 120,
                width: double.infinity,
                child: CustomPaint(
                  painter: _HrCurve(
                    s,
                    maxHr,
                    // Treenin oma aikajana: puuttuva syke näkyy tyhjänä (ennen 100 s venyi koko leveydelle ja näytti
                    // koko lenkiltä). Alku treenin alusta, jos se tiedetään.
                    offsetSec: w.started == null ? 0 : math.max(0, s.start.difference(w.started!).inSeconds),
                    spanSec: math.max(
                      dur,
                      s.length.inSeconds +
                          (w.started == null ? 0 : math.max(0, s.start.difference(w.started!).inSeconds)),
                    ),
                    cs.outlineVariant,
                    // Sovelluksen oma fontti (myös suurella tekstillä samassa suhteessa).
                    DefaultTextStyle.of(context).style
                        .copyWith(fontSize: MediaQuery.textScalerOf(context).scale(10), color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            if (!compact && zones != null && zones.any((z) => z > 0)) ...[
              const SizedBox(height: 10),
              for (var i = 4; i >= 0; i--)
                if (zones[i] > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: chipW,
                          // Alueen nimi värillisenä merkkinä: väri sama kuin palkissa ja käyrän taustassa.
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: _zoneBg[i], borderRadius: BorderRadius.circular(99)),
                              child: Text(
                                t('{0} {1}', [i + 1, t(zoneNames[i])]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _zoneFg[i]),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ExcludeSemantics(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: zones[i] / top,
                                minHeight: 8,
                                color: _zoneLine[i],
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: timeW,
                          child: Text(mmss(zones[i]), textAlign: TextAlign.end, softWrap: false, style: sub),
                        ),
                      ],
                    ),
                  ),
              if (below > 0)
                Padding(
                  key: const ValueKey('hrBelowZones'),
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: chipW,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: cs.outlineVariant),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            // Ei katkaista ("…"): saameksi pitkä, pienennetään tarvittaessa.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                t('Alle alueiden'),
                                maxLines: 1,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ExcludeSemantics(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: below / top,
                              minHeight: 8,
                              color: cs.outline,
                              backgroundColor: cs.surfaceContainerHighest,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: timeW,
                        child: Text(mmss(below), textAlign: TextAlign.end, softWrap: false, style: sub),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      measured
                          ? t('Alueet % maksimisykkeestä {0} (oma mittaus).', [maxHr!])
                          : t('Alueet % maksimisykkeestä {0} (arvio iästä).', [maxHr!]),
                      style: sub,
                    ),
                  ),
                  IconButton(
                    tooltip: t('Mitä sykealueet tarkoittavat?'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showZoneInfo(context),
                    icon: const Icon(Icons.info_outline, size: 18),
                  ),
                ],
              ),
            ],
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(
                [
                  // Kellon käyrä Health Connectista (15.11.: ennen luki aina "Sykevyö").
                  if (watch)
                    (w.healthSource ?? '').isEmpty ? 'Health Connect' : 'Health Connect · ${w.healthSource}'
                  else if (cover >= 90)
                    t('Sykevyö')
                  else
                    t('Sykevyö, {0} % treenistä', [cover]),
                  if (w.kcalSource == 'syke' && w.kcal != null)
                    w.activity == null
                        ? t('kalorit: MET sykkeen mukaan (Compendium 2024)')
                        : t('kalorit sykkeestä (Keytel 2005)'),
                  if (w.kcalSource == 'nopeus' && w.kcal != null)
                    w.activity == 'Kävely'
                        ? t('kalorit kävelyvauhdista (Ludlow & Weyand 2016)')
                        : t('kalorit matkasta ja ajasta (ACSM)'),
                  // Kokonaiskulutus ja aktiiviset (käyttäjä 17.11.): ero kävelymattoon ja kelloihin selittyy tällä.
                  if (w.kcal != null && hrProfile() != null) t('aktiiviset kalorit = kokonaiskulutus − lepokulutus'),
                ].join(' · '),
                style: sub,
              ),
              // Kävely sykevyöllä (käyttäjä 18.11.): kalorit vauhdista, mutta sykkeestä laskettu arvio näkyy vertailuksi
              // ja merkitään epäluotettavaksi (Keytel 2005 on tehty reippaalle liikunnalle; hitaassa kävelyssä noin
              // 1,5–3-kertainen: 49 min keskisykkeellä 93 sykkeestä 360 kcal, vauhdista noin 150).
              if (!watch && p != null && w.kcalSource == 'nopeus' && w.activity == 'Kävely' && w.kcal != null)
                Builder(
                  builder: (context) {
                    final fromHr = p.kcalEnduranceFor(s, w.durationSec);
                    if (fromHr <= w.kcal! * 1.15) return const SizedBox.shrink();
                    return Padding(
                      key: const ValueKey('walkHrKcal'),
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        t(
                          'Sykevyöstä laskettuna {0} kcal: ei luotettava kävelyssä. Sykkeeseen perustuva kaava on tehty '
                          'reippaalle liikunnalle ja yliarvioi hidasta kävelyä, joten kalorit lasketaan vauhdista.',
                          [fromHr],
                        ),
                        style: sub,
                      ),
                    );
                  },
                ),
            ],
            // Vyö lakkasi lähettämästä kesken treenin: todennäköisin syy on puhelimen akunsäästö (näyttö lukittuna).
            if (cover < 50 && !watch)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t(
                    'Syke katkesi kesken treenin. Jos puhelin oli taskussa näyttö lukittuna, salli Gievralle toiminta '
                    'taustalla (akunsäästö voi katkaista vyön yhteyden) ja kostuta elektrodit.',
                  ),
                  style: sub.copyWith(color: cs.error),
                ),
              ),
            // Puuttuvat tiedot kysytään suoraan kortista (käyttäjä 15.11.: kellon syke ilman omia tietoja).
            if (!compact && ((watch && maxHr == null) || (!watch && p == null)))
              Row(
                children: [
                  Expanded(
                    child: Text(
                      watch
                          ? t('Sykealueisiin tarvitaan syntymävuosi.')
                          : t('Kaloreihin ja sykealueisiin tarvitaan syntymävuosi, sukupuoli, pituus ja paino.'),
                      style: sub,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('hrProfileAdd'),
                    onPressed: () => askHrProfile(context),
                    child: Text(t('Lisää tiedot')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Sykekäyrä: viiva, aukot (ei lukemaa) katkaisevat sen. Asteikko 50 → oma maksimisyke, merkit omien alueiden
/// rajoilla, alueet himmeinä vyöhykkeinä. Ilman profiilia kiinteä 50–200.
class _HrCurve extends CustomPainter {
  final HrSeries s;
  final int? maxHr;
  final Color grid;
  final TextStyle label;
  final int offsetSec, spanSec;
  _HrCurve(this.s, this.maxHr, this.grid, this.label, {this.offsetSec = 0, int? spanSec})
    : spanSec = spanSec ?? s.length.inSeconds;

  static const low = 50;

  @override
  void paint(Canvas canvas, Size size) {
    // Yläraja: oma maksimisyke (arvio iästä tai itse mitattu); jos tämä treeni meni yli, vain tämä kuva venyy.
    // Ilman profiilia kiinteä 50–200 (250, jos yli 200).
    final peak = s.max ?? 0;
    final top = maxHr == null ? (peak > 200 ? 250 : 200) : math.max(maxHr!, ((peak + 4) ~/ 5) * 5);
    final labelW = label.fontSize! * 2.8;
    final w = size.width - labelW;
    double y(int v) => size.height - (v.clamp(low, top) - low) / (top - low) * size.height;
    // Sykealueet himmeinä vyöhykkeinä käyrän takana (50–60 … 90–100 % maksimista).
    if (maxHr case final m?) {
      for (var z = 0; z < 5; z++) {
        final a = (m * (.5 + z * .1)).round(), b = (m * (.6 + z * .1)).round();
        canvas.drawRect(
          Rect.fromLTRB(labelW, y(b), size.width, y(a)),
          Paint()..color = _zoneLine[z].withValues(alpha: .13),
        );
      }
    }
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // Merkit omien alueiden rajoilla (50, 60 … 100 % maksimista), ilman profiilia 50/80/120/160/200.
    final marks = maxHr == null
        ? [50, 80, 120, 160, 200, if (top > 200) 240]
        : [low, for (var p = 5; p <= 10; p++) (maxHr! * p / 10).round()];
    // Alhaalta ylös; teksti, joka osuisi edelliseen (suuri tekstikoko, 179/161 päällekkäin), jätetään pois.
    var lastTop = double.infinity;
    for (final v in marks) {
      final yy = y(v);
      canvas.drawLine(Offset(labelW, yy), Offset(size.width, yy), g);
      final tp = TextPainter(
        text: TextSpan(text: '$v', style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      final ty = (yy - tp.height / 2).clamp(0, size.height - tp.height).toDouble();
      if (ty + tp.height > lastTop) continue;
      lastTop = ty;
      tp.paint(canvas, Offset(labelW - tp.width - 4, ty));
    }
    final pen = Paint()
      ..color = Sami.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final n = s.values.length;
    final span = math.max(spanSec, (n - 1) * s.interval);
    Path? path;
    for (var i = 0; i < n; i++) {
      final v = s.values[i];
      final x = labelW + (span <= 0 ? 0.0 : (offsetSec + i * s.interval) / span * w).clamp(0.0, w);
      if (v <= 0) {
        if (path != null) canvas.drawPath(path, pen);
        path = null;
        continue;
      }
      path == null ? (path = Path()..moveTo(x, y(v))) : path.lineTo(x, y(v));
    }
    if (path != null) canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_HrCurve o) =>
      o.s != s || o.maxHr != maxHr || o.label != label || o.offsetSec != offsetSec || o.spanSec != spanSec;
}

/// Omat tiedot lyhyesti (asetusrivit): mitä on annettu ja maksimisyke (oma tai arvio iästä).
String hrProfileSummary() {
  final now = DateTime.now();
  final y = settings.birthYear, kg = settings.body.sorted.lastOrNull?.$2, h = settings.body.heightCm;
  if (y == null && settings.maxHr == null) return t('Lisää syntymävuosi, sukupuoli, pituus ja paino');
  final max = settings.maxHr ?? (208 - 0.7 * (now.year - y!)).round();
  return [
    if (y != null) t('{0} v', [now.year - y]),
    if (settings.sex != null) settings.sex == 'mies' ? t('mies') : t('nainen'),
    if (h != null) '$h cm',
    if (kg != null) '${fmtNum(kg)} kg',
    t('maksimisyke n. {0}', [max]),
  ].join(' · ');
}

/// Kalorilaskennan perustiedot sykevyötä varten: syntymävuosi, sukupuoli, pituus ja paino. Olemassa olevat tiedot
/// (kehonpainon seuranta) ehdotetaan valmiiksi. Palauttaa true, kun tallennettiin.
Future<bool> askHrProfile(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ProfileSheet(),
    ) ==
    true;

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final _year = TextEditingController(text: settings.birthYear?.toString() ?? '');
  late final _height = TextEditingController(text: settings.body.heightCm?.toString() ?? '');
  late final _weight = TextEditingController(
    text: settings.body.sorted.lastOrNull == null ? '' : fmtNum(settings.body.sorted.last.$2),
  );
  late String? _sex = settings.sex;
  late final _max = TextEditingController(text: settings.maxHr?.toString() ?? '');

  @override
  void dispose() {
    _max.dispose();
    _year.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  int? get _y {
    final y = int.tryParse(_year.text.trim());
    final now = DateTime.now().year;
    return y != null && y >= now - 100 && y <= now - 10 ? y : null;
  }

  int? get _h => parseHeight(_height.text);
  int? get _m {
    final v = int.tryParse(_max.text.trim());
    return v != null && v >= 120 && v <= 230 ? v : null;
  }

  double? get _w => parseWeight(_weight.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    // Syntymävuosi riittää sykealueisiin; muut kaloreihin (valinnaiset, käyttäjä 15.11.: kellon syke ilman vyötä).
    // Virheellinen pituus tai paino estää tallennuksen kuten maksimisyke (yötesti 25.11.: virhe näkyi, mutta Tallenna
    // sulki arkin ja jätti arvon hiljaa pois).
    final ok =
        _y != null &&
        (_max.text.trim().isEmpty || _m != null) &&
        (_height.text.trim().isEmpty || _h != null) &&
        (_weight.text.trim().isEmpty || _w != null);
    InputDecoration dec(String label, String? suffix) =>
        InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder());
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('Sykealueet ja kalorit'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              t(
                'Sykealueisiin riittää syntymävuosi. Kalorit sykkeestä lasketaan tutkituilla menetelmillä, joihin '
                'tarvitaan myös sukupuoli, pituus ja paino. Tiedot tallentuvat vain asetuksiisi.',
              ),
              style: sub,
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('birthYear'),
              controller: _year,
              keyboardType: TextInputType.number,
              // Tallenna on pois käytöstä väärällä vuodella: näytetään sallittu väli (kuten maksimisykkeessä).
              decoration: dec(t('Syntymävuosi'), null).copyWith(
                errorText: _year.text.trim().isNotEmpty && _y == null
                    ? '${DateTime.now().year - 100}–${DateTime.now().year - 10}'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              segments: [
                ButtonSegment(value: 'nainen', label: Text(t('Nainen'))),
                ButtonSegment(value: 'mies', label: Text(t('Mies'))),
              ],
              selected: {?_sex},
              onSelectionChanged: (s) => setState(() => _sex = s.firstOrNull),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t('Laskentayhtälöt on tehty erikseen naisille ja miehille.'), style: sub),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('heightCm'),
                    controller: _height,
                    keyboardType: TextInputType.number,
                    // Rajojen ulkopuolinen arvo näkyy virheenä (yötesti 24.11.), ei hiljaa ohitettuna.
                    decoration: dec(
                      t('Pituus'),
                      'cm',
                    ).copyWith(errorText: _height.text.trim().isNotEmpty && _h == null ? '100–250' : null),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('weightKg'),
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: dec(
                      t('Paino nyt'),
                      'kg',
                    ).copyWith(errorText: _weight.text.trim().isNotEmpty && _w == null ? '20–400' : null),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('maxHrField'),
              controller: _max,
              keyboardType: TextInputType.number,
              decoration: dec(t('Oma maksimisyke'), t('lyöntiä/min')).copyWith(
                helperText: t('Valinnainen: jos et ole mitannut, maksimi arvioidaan iästä.'),
                helperMaxLines: 3,
                errorText: _max.text.trim().isNotEmpty && _m == null ? '120–230' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: !ok
                  ? null
                  : () async {
                      await settings.setProfile(birthYear: _y!, sex: _sex, heightCm: _h, weightKg: _w, maxHr: _m);
                      if (context.mounted) Navigator.pop(context, true);
                    },
              child: Text(t('Tallenna')),
            ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Ei nyt'))),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Syke treenin aikana: tila (yhdistetään, ei kontaktia, yhteys katkesi), alueen väri ja nimi, minikäyrä.

/// Alueen väri (1–5) ja tekstin väri sen päällä.
const _zoneBg = [Color(0xFFF1EFE8), Color(0xFFE6F1FB), Color(0xFFFAEEDA), Color(0xFFFAECE7), Color(0xFFFCEBEB)];
const _zoneFg = [Color(0xFF444441), Color(0xFF0C447C), Color(0xFF633806), Color(0xFF712B13), Color(0xFF791F1F)];
const _zoneLine = [Color(0xFF888780), Color(0xFF378ADD), Color(0xFFEF9F27), Color(0xFFD85A30), Color(0xFFE24B4A)];

/// Viimeisten minuuttien minikäyrä (näkyy, miten syke nousee sarjassa ja laskee tauolla).
class HrSparkline extends StatelessWidget {
  final Color color;
  final double height;
  const HrSparkline({super.key, required this.color, this.height = 32});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(painter: _Spark(List.of(hr.recent), color, hr.now())),
  );
}

class _Spark extends CustomPainter {
  final List<(DateTime, int)> pts;
  final Color color;
  final DateTime now;
  _Spark(this.pts, this.color, this.now);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    const span = 180; // s
    final lo = pts.map((e) => e.$2).reduce((a, b) => a < b ? a : b) - 5;
    final hi = pts.map((e) => e.$2).reduce((a, b) => a > b ? a : b) + 5;
    final path = Path();
    for (final (i, (t, v)) in pts.indexed) {
      final x = size.width * (1 - now.difference(t).inMilliseconds / 1000 / span).clamp(0.0, 1.0);
      final y = size.height - (v - lo) / (hi - lo) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Spark o) => true;
}

/// Salitreenin sykenauha yläpalkin alla: iso luku, alue värillä ja nimellä, minikäyrä ja viiden alueen palkki.
class HrLiveStrip extends StatelessWidget {
  const HrLiveStrip({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: hr,
    builder: (context, _) {
      if (hr.address == null || !hr.recording) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final status = hrStatusText();
      final v = status == null ? hr.bpm : null;
      final maxHr = hrProfile()?.maxHr(DateTime.now());
      final z = v == null || maxHr == null ? null : zoneOf(v, maxHr);
      final bg = z == null ? cs.surfaceContainer : _zoneBg[z];
      final fg = z == null ? cs.onSurface : _zoneFg[z];
      // Arvio kaloreista tähän asti (sali: Compendiumin MET sykkeen mukaan).
      final key = hr.currentKey;
      final so = key == null ? null : hr.peek(key);
      final p = hrProfile();
      // Puuttuvat lukemat (nollat käyrässä) sekunteina.
      final missingSec = so?.series?.missingSec ?? 0;
      final kcal = p == null || so?.series == null
          ? null
          : key!.startsWith('gym')
          ? p.kcalGym(so!.series!, so.series!.length.inMinutes)
          : p.kcalEndurance(so!.series!);
      return Padding(
        key: const ValueKey('hrStrip'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(Icons.favorite, color: v == null ? cs.onSurfaceVariant : Sami.red, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v == null ? '–' : '$v',
                          key: const ValueKey('hrStripBpm'),
                          style: TextStyle(fontSize: 30, height: 1.05, fontWeight: FontWeight.w800, color: fg),
                        ),
                        Text(
                          status ??
                              (z == null
                                  ? (maxHr == null ? t('lyöntiä/min') : t('alle alueiden'))
                                  : t('Alue {0} · {1}', [z + 1, t(zoneNames[z])])),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: status != null ? cs.error : fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(width: 110, child: HrSparkline(color: Sami.red, height: 30)),
                      if (kcal != null && kcal > 0)
                        Text(
                          '≈ $kcal kcal',
                          key: const ValueKey('hrStripKcal'),
                          style: TextStyle(fontSize: 12, color: fg),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Vyön akku vähissä: vaihda paristo ennen kuin syke katoaa kesken treenin.
            if (hr.batteryLow)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.battery_alert, size: 16, color: cs.error),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        t('Sykevyön akku vähissä ({0} %)', [hr.battery!]),
                        key: const ValueKey('hrBatteryLow'),
                        style: TextStyle(fontSize: 12, color: cs.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            // Syke puuttui jo kesken treenin (vyö katkesi, ei ihokontaktia): kerrotaan heti, ei vasta jälkikäteen.
            if (missingSec >= 30)
              Padding(
                key: const ValueKey('hrGapBanner'),
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t(
                            'Syke puuttui {0} tässä treenissä. Jos vyö katkeaa usein: kostuta elektrodit ja salli Gievran '
                            'toiminta taustalla.',
                            [fmtDurationSec(missingSec)],
                          ),
                          style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (maxHr != null) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: _zoneLine[i].withValues(alpha: z == i ? 1 : .3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Palautuspalkin syke: luku, suunta viimeisen minuutin aikana ja valmius seuraavaan sarjaan.
class HrRecovery extends StatelessWidget {
  const HrRecovery({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: hr,
    builder: (context, _) {
      if (hr.address == null || !hr.recording) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final status = hrStatusText();
      final v = status == null ? hr.bpm : null;
      final target = hr.recoveryBpm(DateTime.now());
      final trend = hr.trend;
      final ready = v != null && target != null && v <= target;
      return Padding(
        key: const ValueKey('hrRecovery'),
        padding: const EdgeInsets.only(top: 6, right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, color: Sami.red, size: 18),
                const SizedBox(width: 6),
                Text(v == null ? '–' : '$v', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (trend != null && v != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    trend < -2 ? Icons.arrow_downward : (trend > 2 ? Icons.arrow_upward : Icons.arrow_forward),
                    size: 16,
                    color: trend < -2 ? greenText(context) : cs.onSurfaceVariant,
                  ),
                ],
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    status ??
                        (trend == null
                            ? ''
                            : trend < 0
                            ? t('laskee · {0} / 60 s', [trend])
                            : t('nousee · +{0} / 60 s', [trend])),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: status != null ? cs.error : cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            if (v != null && target != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ready
                    ? Text(
                        t('✓ Palautunut: valmis seuraavaan sarjaan'),
                        key: const ValueKey('hrReady'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: greenText(context)),
                      )
                    : Text(
                        t('Palautunut, kun syke alle {0}', [target]),
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
              ),
          ],
        ),
      );
    },
  );
}

/// Kävely, juoksu ja muut liikunnat: iso sykerengas alueen värillä, alue ja % maksimista, käyrä tähän asti,
/// keskisyke, maksimi ja kalorit tähän asti.
class HrRing extends StatelessWidget {
  final String sessionKey;
  const HrRing({super.key, required this.sessionKey});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: hr,
    builder: (context, _) {
      if (hr.address == null || !hr.recording) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
      final status = hrStatusText();
      final v = status == null ? hr.bpm : null;
      final p = hrProfile();
      final now = DateTime.now();
      final maxHr = p?.maxHr(now);
      final z = v == null || maxHr == null ? null : zoneOf(v, maxHr);
      final ring = z == null ? cs.outlineVariant : _zoneLine[z];
      final so = hr.peek(sessionKey);
      final kcal = p == null || so?.series == null ? null : p.kcalEndurance(so!.series!);
      return Padding(
        key: const ValueKey('hrRing'),
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 7),
              ),
              padding: const EdgeInsets.all(12),
              // Luku ja otsikko pienenevät tarvittaessa (suuri teksti), eivät valu renkaan yli.
              child: FittedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v == null ? '–' : '$v',
                      key: const ValueKey('hrRingBpm'),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1),
                    ),
                    Text(t('syke'), style: sub),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              status ??
                  (z == null
                      ? (maxHr == null ? t('Lisää tiedot sykevyön asetuksiin: alueet ja kalorit') : t('alle alueiden'))
                      : t('Alue {0} · {1} · {2} %', [z + 1, t(zoneNames[z]), (v! / maxHr! * 100).round()])),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: status != null ? cs.error : (z == null ? cs.onSurfaceVariant : _zoneFg[z]),
              ),
            ),
            const SizedBox(height: 6),
            const SizedBox(
              width: double.infinity,
              child: HrSparkline(color: Sami.red, height: 34),
            ),
            if (so != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  children: [
                    Text(t('ka {0}', [so.avg]), style: sub),
                    Text(t('max {0}', [so.max]), style: sub),
                    if (kcal != null && kcal > 0) Text('≈ $kcal kcal', key: const ValueKey('hrRingKcal'), style: sub),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Arvon säätö − / +: otsikko, nykyinen arvo tekstinä.
class _Stepper extends StatelessWidget {
  final String title;
  final int value, step, min, max;
  final String Function(int) text;
  final ValueChanged<int> onChanged;
  const _Stepper({
    super.key,
    required this.title,
    required this.value,
    required this.text,
    required this.step,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final sub = TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                Text(text(value), style: sub),
              ],
            ),
          ),
          IconButton.filledTonal(
            // Ruudunlukija sanoo, mitä säädetään (yötesti 20.11.: pelkkä "−" / "+").
            tooltip: t('Vähennä: {0}', [title]),
            onPressed: value - step < min ? null : () => onChanged(value - step),
            icon: const Icon(Icons.remove),
          ),
          IconButton.filledTonal(
            tooltip: t('Lisää: {0}', [title]),
            onPressed: value + step > max ? null : () => onChanged(value + step),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Sykevyöllä tallennettu kävely tai muu askellaji: etsii samaan aikaan tallennetun Health Connect -harjoituksen
/// (esim. kävelymatto) ja tarjoaa sen askeleet ja matkan. Sykevyön syke ja kalorit pysyvät. Jos laite ei ole vielä
/// synkronoinut, "Hae uudelleen".
class PadMatch extends StatefulWidget {
  final Workout w;
  final Future<void> Function() onApplied;

  /// Testejä varten: ehdokkaiden haku (muuten Health Connect).
  final Future<List<HealthCandidate>> Function(DateTime start, DateTime end)? fetch;
  const PadMatch({super.key, required this.w, required this.onApplied, this.fetch});

  static bool wanted(Workout w) =>
      w.hrSource == 'sykevyö' && (sportOf(w.activity)?.steps ?? false) && w.steps == null && w.started != null;

  @override
  State<PadMatch> createState() => _PadMatchState();
}

class _PadMatchState extends State<PadMatch> {
  HealthCandidate? _found;
  bool _busy = false, _searched = false, _done = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final w = widget.w;
    setState(() => _busy = true);
    try {
      final start = w.started!, end = start.add(Duration(seconds: w.durationSec ?? 3600));
      final all = await (widget.fetch ?? HealthConnect.candidates)(
        start.subtract(const Duration(minutes: 30)),
        end.add(const Duration(minutes: 30)),
      );
      final ranked = rankCandidates(w, [
        for (final c in all)
          if (c.session && (c.steps ?? 0) > 0) c,
      ], others: store.workouts);
      _found = ranked.firstOrNull;
    } catch (_) {
      _found = null;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _searched = true;
      });
    }
  }

  Future<void> _apply() async {
    final c = _found!;
    // Askeleet ja matka laitteesta; syke ja kalorit sykevyöstä (ei korvata).
    applyCandidate(widget.w, c, steps: true);
    if ((c.meters ?? 0) > 0 && widget.w.distanceKm == null) widget.w.distanceKm = (c.meters! / 10).round() / 100;
    await widget.onApplied();
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final c = _found;
    return Card(
      key: const ValueKey('padMatch'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_walk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c != null ? t('Kävelyn tiedot löytyivät') : t('Kävelymaton tai kellon askeleet'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              c != null
                  ? [
                      if (c.app.isNotEmpty) c.app,
                      t('{0} askelta', [thousands(c.steps!)]),
                      if ((c.meters ?? 0) > 0) '${fmtNum((c.meters! / 10).round() / 100)} km',
                    ].join(' · ')
                  : _busy
                  ? t('Etsitään Health Connectista…')
                  : t('Ei vielä löytynyt. Laite voi synkronoida muutaman minuutin viiveellä.'),
              style: c != null ? null : sub,
            ),
            if (c != null) Text(t('Syke ja kalorit pysyvät sykevyöstä.'), style: sub),
            Align(
              alignment: Alignment.centerRight,
              child: c != null
                  ? FilledButton(onPressed: _apply, child: Text(t('Lisää askeleet ja matka')))
                  : TextButton.icon(
                      onPressed: _busy || !_searched ? null : _search,
                      icon: const Icon(Icons.refresh),
                      label: Text(t('Hae uudelleen')),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sykealueiden käyttö (selitys).
// l10n: data
const zoneUses = [
  'Hyvin kevyt: lämmittely, jäähdyttely ja palauttava liikunta.',
  'Kevyt peruskestävyys: pystyt puhumaan kokonaisin lausein. Suurin osa kestävyysharjoittelusta kannattaa tehdä tällä.',
  'Reipas tasainen kestävyys: puhuminen onnistuu lyhyin lausein.',
  'Kynnys: lähellä maitohappokynnystä, jonka yläpuolella väsymys kasvaa nopeasti. Kova, mutta kestettävissä noin 20–60 min.',
  'Maksimi: lyhyet kovat vedot ja intervallit, kestää vain minuutteja.',
];

/// Sykealueiden selitys: nimi, % maksimista, oma sykeväli ja mihin aluetta käytetään.
Future<void> showZoneInfo(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) {
    final m = hrProfile()?.maxHr(DateTime.now());
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('Sykealueet'), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              t('Alueet lasketaan prosentteina maksimisykkeestä. Mitä tarkempi maksimisyke, sitä osuvammat alueet.'),
            ),
            const SizedBox(height: 12),
            for (var i = 4; i >= 0; i--)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: _zoneBg[i], borderRadius: BorderRadius.circular(99)),
                          child: Text(
                            t('{0} {1}', [i + 1, t(zoneNames[i])]),
                            style: TextStyle(fontWeight: FontWeight.w700, color: _zoneFg[i]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          m == null
                              ? '${50 + i * 10}–${60 + i * 10} %'
                              : '${50 + i * 10}–${60 + i * 10} % · ${(m * (50 + i * 10) / 100).round()}–${(m * (60 + i * 10) / 100).round()}',
                          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(t(zoneUses[i])),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  },
);
