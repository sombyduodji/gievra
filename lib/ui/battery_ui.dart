import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../battery.dart';
import '../l10n.dart';
import '../theme.dart';

// Akunsäästön ohje: kerran päivityksen jälkeen ja aloituksessa (ehdotus), sitten Asetuksissa.

const _shownKey = 'batteryHintShown';

/// Merkitään ohje nähdyksi (aloitus näytti sen, tai käyttäjä sulki sen).
Future<void> markBatteryHintShown() async => (await SharedPreferences.getInstance()).setBool(_shownKey, true);

/// Kerran päivityksen jälkeen, jos Gievraa ei ole sallittu toimia taustalla. Uusi asennus näkee ehdotuksen
/// aloituksessa, joten tätä ei näytetä sille.
Future<void> maybeShowBatteryHint(BuildContext context) async {
  if (!BatteryHelp.supported) return;
  final sp = await SharedPreferences.getInstance();
  if (sp.getBool(_shownKey) == true) return;
  await sp.setBool(_shownKey, true);
  if (store.workouts.isEmpty) return; // uusi asennus: aloitus kertoi jo
  await battery.refresh();
  if (battery.exempt != false || !context.mounted) return;
  await showBatteryHelp(context);
}

/// Avaa Androidin oman kysymyksen; jos se ei aukea, sovelluksen asetukset (Akku → Rajoittamaton).
Future<void> allowBackground() async {
  if (!await battery.request()) await battery.openAppSettings();
}

/// Ohje: miksi, Salli-painike, käsin tehtävät vaiheet (myös Samsung) ja treeni-ilmoituksen merkitys.
Future<void> showBatteryHelp(BuildContext context) async {
  await battery.refresh();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const BatteryHelpSheet(),
  );
}

class BatteryHelpSheet extends StatelessWidget {
  const BatteryHelpSheet({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: battery,
    builder: (context, _) {
      final cs = Theme.of(context).colorScheme;
      final sub = TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.35);
      final ok = battery.exempt == true;
      Widget step(String n, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(n, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Text(text, style: sub)),
          ],
        ),
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('Salli Gievran toimia taustalla'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  'Puhelimen akunsäästö voi pysäyttää Gievran, kun näyttö on pois päältä. Silloin palautuksen '
                  'ilmoitus myöhästyy, eikä sykevyön lukemia saada.',
                ),
                style: sub,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (ok ? Sami.green : Sami.yellow).withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(ok ? Icons.check_circle : Icons.battery_alert, color: ok ? greenText(context) : null),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ok
                            ? t('Sallittu: Gievra saa toimia taustalla.')
                            : t('Nyt rajoitettu: akunsäästö voi pysäyttää treenin.'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              if (!ok) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('batteryAllow'),
                  onPressed: allowBackground,
                  icon: const Icon(Icons.battery_charging_full),
                  label: Text(t('Salli toiminta taustalla')),
                ),
                const SizedBox(height: 4),
                Text(t('Puhelin kysyy vahvistusta: valitse OK tai Salli.'), style: sub),
              ],
              const SizedBox(height: 16),
              Text(t('Jos se ei riitä, tee näin:'), style: const TextStyle(fontWeight: FontWeight.w700)),
              step('1.', t('Avaa sovelluksen asetukset alla olevasta painikkeesta.')),
              step('2.', t('Valitse Akku (tai Akun käyttö).')),
              step('3.', t('Valitse Rajoittamaton (tai Älä optimoi).')),
              if (battery.samsung)
                step(
                  '4.',
                  t(
                    'Samsung: avaa myös Asetukset → Akku → Taustakäytön rajoitukset ja varmista, ettei Gievra ole '
                    'nukkuvien tai syvästi nukkuvien sovellusten listalla.',
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('batteryAppSettings'),
                onPressed: battery.openAppSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(t('Avaa sovelluksen asetukset')),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(
                        'Älä sulje treenin ilmoitusta treenin aikana: sen ansiosta Android pitää Gievran käynnissä. '
                        'Ilmoitus poistuu itsestään, kun treeni on valmis.',
                      ),
                      style: sub,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Valmis'))),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Asetuksiin: tila ja ohje (Asetukset → Yleiset, treeni-ilmoituksen alla).
class BatterySettingsTile extends StatelessWidget {
  const BatterySettingsTile({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: battery,
    builder: (context, _) {
      final ok = battery.exempt == true;
      return ListTile(
        key: const ValueKey('batteryTile'),
        leading: Icon(ok ? Icons.battery_full : Icons.battery_alert),
        title: Text(t('Toiminta taustalla')),
        subtitle: Text(ok ? t('Sallittu') : t('Rajoitettu: akunsäästö voi pysäyttää treenin')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showBatteryHelp(context),
      );
    },
  );
}

/// Aloitukseen: ehdotus ja Salli-painike (tila päivittyy, kun palataan puhelimen kysymyksestä).
class BatteryIntroSection extends StatelessWidget {
  const BatteryIntroSection({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: battery,
    builder: (context, _) {
      final cs = Theme.of(context).colorScheme;
      final ok = battery.exempt == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ok
                    ? Row(
                        children: [
                          Icon(Icons.check_circle, color: greenText(context)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t('Sallittu: Gievra saa toimia taustalla.'))),
                        ],
                      )
                    : OutlinedButton.icon(
                        key: const ValueKey('introBatteryAllow'),
                        onPressed: allowBackground,
                        icon: const Icon(Icons.battery_charging_full),
                        label: Text(t('Salli toiminta taustalla')),
                      ),
              ),
              TextButton(onPressed: () => showBatteryHelp(context), child: Text(t('Ohjeet'))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              t(
                'Suositus: muuten puhelimen akunsäästö voi pysäyttää treenin näytön ollessa pois päältä '
                '(palautuksen ilmoitus myöhästyy, sykevyö ei toimi). Voit tehdä tämän myöhemmin asetuksista.',
              ),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    },
  );
}
