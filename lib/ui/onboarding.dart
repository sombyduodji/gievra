import 'package:flutter/material.dart';

import '../battery.dart';
import '../daily_steps.dart';
import 'steps_ui.dart' show stepsSupported;

import 'package:flutter/services.dart';

import '../app_state.dart';
import '../body.dart';
import '../models.dart' show dateOnly;
import '../theme.dart';
import 'battery_ui.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Ensimmäinen käynnistys: kysytään, miksi käyttäjää kutsutaan.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _height = TextEditingController(), _weight = TextEditingController();

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  String _mode = settings.trainMode;
  bool _body = false;
  bool _steps = false;

  /// Terveys ja hyvinvointi (käyttäjä 18.11.): pois = vain treenit; askeleita ja kehonpainoa ei kysytä eikä
  /// terveysominaisuuksia oteta käyttöön (kellon ja sykevyön treenitiedot toimivat silti). Kaiken voi kytkeä
  /// myöhemmin asetuksista.
  bool _health = false;
  bool _showErrors = false;
  bool get _heightBad => _height.text.trim().isNotEmpty && parseHeight(_height.text) == null;
  bool get _weightBad => _weight.text.trim().isNotEmpty && parseWeight(_weight.text) == null;

  void _done() {
    if (!_health) {
      _body = false;
      _steps = false;
    }
    // Rajojen ulkopuolinen pituus tai paino (yötesti 24.11.: 999 cm ja 0 kg ohitettiin hiljaa): virhe kenttään,
    // eikä jatketa ennen korjausta tai tyhjennystä.
    if (_health && _body && (_heightBad || _weightBad)) {
      setState(() => _showErrors = true);
      return;
    }
    settings.trainMode = _mode;
    // Kehonpainon seuranta: pituus ja nykyinen paino ovat valinnaisia (voi lisätä myöhemmin asetuksista).
    settings.bodyTracker = _body;
    if (_body) {
      final b = settings.body.copy();
      b.heightCm = parseHeight(_height.text) ?? b.heightCm;
      final kg = parseWeight(_weight.text);
      if (kg != null) b.weights[dateOnly(DateTime.now())] = kg;
      if (!b.isEmpty) settings.setBody(b);
    }
    // Päivän askeleet: Health Connectin lupa kysytään heti (etusivun kortissa on myös Salli-painike).
    if (_steps && stepsSupported) {
      settings.dailySteps = true;
      dailySteps.requestPermission();
    }
    // Pelkkä kestävyys: salin ohjelmakysely ohitetaan (sen voi tehdä myöhemmin valikosta).
    if (_mode == 'cardio') settings.introDone = true;
    markBatteryHintShown(); // aloitus kertoi jo: päivityksen jälkeistä ohjetta ei näytetä
    settings.finishOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final bigText = MediaQuery.textScalerOf(context).scale(14) > 18;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            const Center(child: AppLogo(size: 84)),
            const SizedBox(height: 28),
            // Ohut suora saamen viiva kuten muualla (ulkoasun kohennus 16.11.).
            const SamiBand(height: 4, pattern: false),
            const SizedBox(height: 20),
            const Text('Kieli · Giella', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            const LanguagePicker(),
            const SizedBox(height: 16),
            // Tekstin koko heti alussa: valinta näkyy koko sivulla saman tien (tallentuu nimen kanssa).
            Text(t('Tekstin koko'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: settings,
              builder: (context, _) =>
                  TextSizePicker(value: settings.textSize, onChanged: (v) => settings.setTextSize(v, save: false)),
            ),
            const SizedBox(height: 4),
            Text(
              t('Pieni on tavallinen koko. Voit vaihtaa tätä myöhemmin asetuksista.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text(
              t('Bures!'),
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.light ? const Color(0xFFB07D00) : Sami.yellow,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t('Tervetuloa Gievraan'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              t(
                'Sinun treenisi, sinun tiedostosi: Gievra tallentaa treenit tavallisina .md-tiedostoina '
                'omaan kansioosi. Ei tiliä, ei mainoksia.',
              ),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // Tietosuoja näkyvästi heti alussa (käyttäjä 18.11.).
            Container(
              key: const ValueKey('onbPrivacy'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: greenText(context).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: greenText(context).withValues(alpha: .35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, color: greenText(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t(
                        'Kaikki tiedot pysyvät vain tässä puhelimessa. Gievra ei lähetä eikä synkronoi mitään '
                        'minnekään. Varmuuskopiot ja jakaminen tapahtuvat vain, kun itse teet ne.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Nimeä ei kysytä (käyttäjä 18.11.): etusivun tervehdys on ilman nimeä, eikä nimeä näytetä missään.
            SectionLabel(t('Mitä treenaat?')),
            TrainModePicker(value: _mode, onChanged: (v) => setState(() => _mode = v)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(switch (_mode) {
                'cardio' => t('Juoksu, pyöräily, hiihto ja muut lajit: aika, matka, vauhti ja kehitys.'),
                'both' => t('Etusivulla Sali ja Liikunta vierekkäin. Kalenterissa näkyy kaikki.'),
                _ => t('Salitreenit, treeniohjelma ja voiman kehitys.'),
              }, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('Voit vaihtaa tätä myöhemmin asetuksista.'),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            // Seuranta yhdessä kortissa kytkimin (luonnos aloitus 3): luvat kysytään vasta kytkiessä. Ensin yksi
            // pääkytkin (käyttäjä 18.11.: uusi käyttäjä näkee vain perusasiat): ilman sitä ei kysytä mitään muuta.
            SectionLabel(t('Mitä seurataan?')),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    key: const ValueKey('onbHealth'),
                    secondary: bigText ? null : const Text('❤️', style: TextStyle(fontSize: 22)),
                    title: Text(
                      bigText ? '❤️ ${t('Myös terveys ja hyvinvointi?')}' : t('Myös terveys ja hyvinvointi?'),
                    ),
                    subtitle: Text(
                      t(
                        'Askeleet ja kehonpaino nyt, uni ja palautuminen myöhemmin asetuksista. Ilman tätä Gievra on '
                        'pelkkä treenipäiväkirja; kellon ja sykevyön treenitiedot toimivat silti.',
                      ),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    value: _health,
                    onChanged: (v) => setState(() => _health = v),
                  ),
                  if (_health && stepsSupported)
                    SwitchListTile(
                      key: const ValueKey('onbSteps'),
                      // Suurella tekstillä kuvake otsikon alkuun: vasemman reunan kuvake ja kytkin kavensivat
                      // tekstin kahden sanan riveiksi (saame, Suuri, emulaattori 16.11.).
                      secondary: bigText ? null : const Text('👣', style: TextStyle(fontSize: 22)),
                      title: Text(
                        bigText ? '👣 ${t('Seurataanko päivän askeleita?')}' : t('Seurataanko päivän askeleita?'),
                      ),
                      subtitle: Text(
                        t(
                          'Askeleet päivittäin Health Connectista (puhelin, älysormus tai -kello) ilman päällekkäisyyksiä. '
                          'Näkyvät etusivulla ja tilastoissa. Voit muuttaa tätä myöhemmin asetuksista.',
                        ),
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      value: _steps,
                      onChanged: (v) => setState(() => _steps = v),
                    ),
                  if (_health)
                    SwitchListTile(
                      key: const ValueKey('onbBody'),
                      secondary: bigText ? null : const Text('⚖️', style: TextStyle(fontSize: 22)),
                      title: Text(bigText ? '⚖️ ${t('Seurataanko kehonpainoa?')}' : t('Seurataanko kehonpainoa?')),
                      subtitle: Text(
                        t(
                          'Valinnainen. Punnitse milloin haluat: päivittäin, viikoittain tai harvemmin. Näet painon kehityksen ja painoindeksin Tilastot-välilehdellä.',
                        ),
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      value: _body,
                      onChanged: (v) => setState(() => _body = v),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t('Kaiken voi kytkeä päälle tai pois myöhemmin asetuksista.'),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            if (_health && _body) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _height,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                        LengthLimitingTextInputFormatter(3),
                      ],
                      key: const ValueKey('onbHeight'),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: t('Pituus'),
                        suffixText: 'cm',
                        border: const OutlineInputBorder(),
                        errorText: _showErrors && _heightBad ? t('Anna pituus 100–250 cm.') : null,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _weight,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        LengthLimitingTextInputFormatter(5),
                      ],
                      key: const ValueKey('onbWeight'),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: t('Paino nyt'),
                        suffixText: 'kg',
                        border: const OutlineInputBorder(),
                        errorText: _showErrors && _weightBad ? t('Anna paino 20–400 kg.') : null,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Akunsäästö (Android): ehdotus sallia toiminta taustalla, jotta treeni ei pysähdy näytön sammuessa.
            if (BatteryHelp.supported) ...[
              SectionLabel(t('Saako Gievra toimia taustalla?')),
              const BatteryIntroSection(),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Sami.red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _done,
              child: Text(t('Aloitetaan'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
