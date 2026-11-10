import 'package:flutter/material.dart';

import '../sync/drive_remote.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'import_export.dart';
import 'widgets.dart';
import '../l10n.dart';

/// ☰ → Synkronointi: valinnainen Google Drive -synkronointi.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  String _ago(DateTime d0) {
    final d = DateTime.now().difference(d0);
    if (d.inMinutes < 1) return t('juuri nyt');
    if (d.inHours < 1) return t('{0} min sitten', [d.inMinutes]);
    if (d.inDays < 1) return t('{0} h sitten', [d.inHours]);
    return '${numDate(d0)} ${d0.hour}:${d0.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    void snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(t('Synkronointi'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
          children: [
            const SamiBand(height: 4, pattern: false),
            const SizedBox(height: 14),
            Text(
              t(
                'Valinnainen. Treenit, asetukset ja ohjelma tallentuvat aina puhelimeen; synkronointi '
                'kopioi ne lisäksi Google Driveen, jolloin ne näkyvät PC:llä ja toisella puhelimella.',
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),
            if (!sync.configured)
              _note(
                cs,
                Icons.hourglass_empty,
                t(
                  'Google Drive -yhteys ei ole vielä käytössä tässä versiossa: sovellukselle pitää ensin '
                  'rekisteröidä Google-tunnus. Muutokset, asetukset ja tuonti toimivat normaalisti.',
                ),
              )
            else if (!sync.enabled)
              FilledButton.icon(
                onPressed: () async {
                  final err = await sync.connect();
                  if (err != null) snack(err);
                },
                icon: const Icon(Icons.add_to_drive),
                label: Text(t('Yhdistä Google Driveen')),
              )
            else ...[
              Card(
                child: ListTile(
                  leading: Icon(
                    sync.busy
                        ? Icons.sync
                        : (sync.status?.startsWith('Virhe') ?? false)
                        ? Icons.sync_problem
                        : Icons.cloud_done,
                    color: (sync.status?.startsWith('Virhe') ?? false) ? cs.error : greenText(context),
                  ),
                  title: Text(sync.email ?? t('Google Drive')),
                  subtitle: Text(
                    '${sync.status ?? ''}${sync.lastSync != null ? ' · ${_ago(sync.lastSync!)}' : ''}\n'
                    'Kansio: Drive → $driveFolderName',
                    style: sub,
                  ),
                  isThreeLine: true,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: sync.busy
                          ? null
                          : () async {
                              final r = await sync.syncNow();
                              if (r != null) snack(r.summary());
                            },
                      icon: const Icon(Icons.sync),
                      label: Text(t('Synkronoi nyt')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: sync.busy
                        ? null
                        : () async {
                            final r = await sync.syncNow(all: true);
                            if (r != null) snack(t('Kaikki: {0}', [r.summary()]));
                          },
                    child: Text(t('Kaikki')),
                  ),
                ],
              ),
              SectionLabel(t('Asetukset tällä laitteella')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('Tarkista käynnistyksessä')),
                subtitle: Text(
                  t('Hae PC:llä tai toisella puhelimella tehdyt muutokset, kun sovellus avataan.'),
                  style: sub,
                ),
                value: sync.onStartup,
                onChanged: sync.setOnStartup,
              ),
              const SizedBox(height: 4),
              Text(t('Synkronoi viimeiset')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (d, l) in const [(7, '7 pv'), (30, '30 pv'), (90, '90 pv'), (365, 'vuosi'), (0, 'kaikki')])
                    ChoiceChip(label: Text(l), selected: sync.days == d, onSelected: (_) => sync.setDays(d)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                t(
                  'Uudet ja muutetut treenit lähtevät heti tallennuksen jälkeen. Asetukset ja ohjelma '
                  'synkronoidaan aina. Ilman verkkoa muutokset odottavat ja lähtevät seuraavalla kerralla.',
                ),
                style: sub,
              ),
            ],
            SectionLabel(t('Hyvä tietää')),
            _note(
              cs,
              Icons.lock_outline,
              t(
                'Sovellus näkee Drivessa vain tiedostot, jotka se on itse luonut kansioon {0}. Muuta '
                'Driveasi se ei näe. Kirjautuminen tapahtuu puhelimen Google-tilillä, salasanaa ei kysytä.',
                [driveFolderName],
              ),
            ),
            _note(
              cs,
              Icons.computer,
              t(
                'PC:llä voit avata ja muokata näitä .md-tiedostoja (Drive selaimessa tai Drive for '
                'desktop). Muutokset tulevat puhelimeen synkronoinnissa.',
              ),
            ),
            _note(
              cs,
              Icons.note_add_outlined,
              t(
                'Jos teet PC:llä kokonaan uuden treenitiedoston, sovellus ei näe sitä Drivessa. Lataa '
                'tiedosto puhelimeen ja tuo se: Tuonti ja varmuuskopio → Tuo .md-tiedostoja. Sen jälkeen '
                'se synkronoituu normaalisti.',
              ),
              action: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportExportScreen())),
                child: Text(t('Avaa tuonti')),
              ),
            ),
            _note(
              cs,
              Icons.call_split,
              t(
                'Jos sama päivä muuttuu sekä puhelimessa että PC:llä, uudempi versio jää voimaan ja toinen '
                'säilyy treenikansiossa nimellä ristiriita-…md. Drivessa poistetut menevät roskakoriin (30 '
                'pv).',
              ),
            ),
            if (sync.enabled) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t('Katkaistaanko yhteys?')),
                      content: Text(
                        t('Synkronointi loppuu tällä laitteella. Tiedostot jäävät sekä puhelimeen että Driveen.'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Katkaise'))),
                      ],
                    ),
                  );
                  if (ok == true) await sync.disconnect();
                },
                icon: Icon(Icons.link_off, color: cs.error),
                label: Text(t('Katkaise yhteys'), style: TextStyle(color: cs.error)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _note(ColorScheme cs, IconData icon, String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 13)),
              ?action,
            ],
          ),
        ),
      ],
    ),
  );
}
