import 'dart:io';

import 'licenses_screen.dart';
import 'stats_screen.dart';
import '../sync/sync_service.dart';
import 'sync_screen.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../rest.dart';
import '../models.dart';
import '../theme.dart';
import 'bug_report.dart';
import 'import_export.dart';
import 'injury_screen.dart';
import 'program_screen.dart';
import 'program_template.dart';
import 'programs_screen.dart';
import 'widgets.dart';
import '../l10n.dart';

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// ☰-valikko samaan tapaan kuin Sátni FST:ssä: nimi ja tekijä, avattavat asetukset,
/// lopuksi Tietoa, Lähetä palautetta, Osallistu ja tue sekä versio.
// Samat Futuret joka rakennuksella: muuten versio ja kansiopolku vilkkuvat tyhjinä jokaisen asetusmuutoksen jälkeen.
final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();
String? _rootKey;
Future<Directory>? _root;
Future<Directory> _rootDir() {
  if (_root == null || _rootKey != settings.folder) {
    _rootKey = settings.folder;
    _root = store.rootDir();
  }
  return _root!;
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([settings, store]),
          builder: (context, _) => ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(
                  children: [
                    const AppLogo(size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(AppInfo.fullName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          InkWell(
                            onTap: () => showAbout(context),
                            child: Text(
                              t('Tekijä: {0}', [AppInfo.author]),
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: SamiBand(height: 4, pattern: false)),
              const SizedBox(height: 8),
              ExpansionTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(t('Asetukset')),
                shape: const Border(),
                children: const [_SettingsSection()],
              ),
              ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(t('Ohjelma ja tavoitteet')),
                subtitle: Text(
                  settings.program?.displayTitle ?? t('Treenaat vapaasti'),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgramScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: Text(t('Tuo ohjelmapohja')),
                subtitle: Text(t('.gmd-tiedosto valmentajalta, kaverilta tai verkosta')),
                onTap: () async {
                  // Valikko pysyy auki dialogin ajan, jotta konteksti on voimassa; suljetaan lopuksi.
                  await importTemplate(context);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.healing),
                title: Text(t('Vammatila')),
                subtitle: settings.injuries.isEmpty
                    ? null
                    : Text(
                        t('{0} aluetta valittuna', [settings.injuries.length]),
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => InjuryScreen(initial: settings.injuries)));
                },
              ),
              ListTile(
                leading: Icon(settings.activePause == null ? Icons.bedtime_outlined : Icons.play_circle_outline),
                title: Text(settings.activePause == null ? t('Tauko: sairas tai loma') : t('Lopeta tauko')),
                subtitle: settings.activePause == null
                    ? null
                    : Text(
                        settings.activePause!.sick ? t('Sairauslomalla') : t('Lomalla'),
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                onTap: () {
                  Navigator.pop(context);
                  settings.activePause == null ? showPauseDialog(context) : settings.endPause();
                },
              ),
              ListTile(
                leading: const Icon(Icons.insights),
                title: Text(t('Edistyminen ja tilastot')),
                subtitle: Text(t('Viikko- ja kuukausikoosteet, fiilis, voimakehitys')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsScreen()));
                },
              ),
              // Synkronointi näkyy vasta, kun se on julkaistu (ei "tulossa"-paikkamerkkiä).
              if (!isDemo && syncReleased)
                ListenableBuilder(
                  listenable: sync,
                  builder: (context, _) => ListTile(
                    leading: const Icon(Icons.cloud_sync_outlined),
                    title: Text(t('Synkronointi')),
                    subtitle: Text(
                      sync.enabled ? 'Google Drive · ${sync.status ?? ''}' : t('Pois päältä (valinnainen)'),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen()));
                    },
                  ),
                ),
              if (!isDemo)
                ListTile(
                  leading: const Icon(Icons.import_export),
                  title: Text(t('Tuonti ja varmuuskopio')),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportExportScreen()));
                  },
                ),
              const Divider(indent: 18, endIndent: 18),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(t('Tietoa')),
                onTap: () => showAbout(context),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(t('Lähetä palautetta')),
                onTap: () => showFeedback(context),
              ),
              if (!isDemo)
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: Text(t('Ilmoita ongelmasta')),
                  subtitle: Text(t('Tallennus, tuonti, vienti… liitteineen')),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BugReportScreen()));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.favorite_outline, color: Sami.red),
                title: Text(t('Osallistu ja tue')),
                onTap: () => showSupport(context),
              ),
              ListTile(
                leading: const Text('☕', style: TextStyle(fontSize: 20)),
                title: Text(t('Tarjoa kahvit')),
                subtitle: Text(t('Vapaaehtoinen tuki kehitykselle')),
                onTap: () => _open(AppInfo.coffee),
              ),
              FutureBuilder(
                future: _packageInfo,
                builder: (context, snap) => Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Text(
                    snap.hasData ? t('Versio {0}', [snap.data!.version]) : '',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection();

  Future<void> _editName(BuildContext context) async {
    final c = TextEditingController(text: settings.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Miksi sinua kutsutaan?')),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(t('Tallenna'))),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) settings.setName(v);
  }

  Future<void> _pickFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await FilePicker.getDirectoryPath(dialogTitle: t('Valitse treenikansio'));
    if (dir == null) return;
    // Androidilla toisen sovelluksen (Nextcloud, Seafile, Syncthing…) synkkaamaa kansiota
    // voi lukea vain "Kaikkien tiedostojen käyttö" -luvalla.
    if (Platform.isAndroid && !await Permission.manageExternalStorage.isGranted) {
      final st = await Permission.manageExternalStorage.request();
      if (!st.isGranted) {
        messenger.showSnackBar(
          SnackBar(content: Text(t('Kansion käyttö vaatii luvan "Kaikkien tiedostojen käyttö".'))),
        );
        return;
      }
    }
    if (!context.mounted) return;
    await changeFolder(context, dir);
  }

  // Osio on const-lapsi, joten valikon ListenableBuilder ei rakenna sitä uudelleen: kuunnellaan itse,
  // muuten valinnat (teema, painon lisäys …) tallentuvat, mutta valikko näyttää vanhan valinnan.
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Listenable.merge([settings, store]), builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(t('Nimesi')),
            subtitle: Text(settings.name ?? '', style: sub),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () => _editName(context),
          ),
          ListTile(
            title: Text(t('Ohjelmat')),
            subtitle: Text(t('Tallennetut ohjelmat: vaihda, nimeä, vie, tuo, poista'), style: sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgramsScreen())),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 6), child: Text('Kieli · Giella')),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: LanguagePicker()),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 6), child: Text(t('Teema'))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Auto'), maxLines: 1)),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Tumma'), maxLines: 1)),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Vaalea'), maxLines: 1)),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setTheme(s.first),
            ),
          ),
          Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text(t('Painon lisäys (kg)'))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 1.25, label: Text('1,25')),
                ButtonSegment(value: 2.5, label: Text('2,5')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
              selected: {settings.weightStep},
              onSelectionChanged: (s) => settings.setWeightStep(s.first),
            ),
          ),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 6), child: Text(t('Liikkeiden nimet'))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'fi',
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Suomi'), maxLines: 1)),
                ),
                const ButtonSegment(
                  value: 'en',
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text('English', maxLines: 1)),
                ),
                ButtonSegment(
                  value: 'both',
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Molemmat'), maxLines: 1)),
                ),
              ],
              selected: {settings.moveNames},
              onSelectionChanged: (s) => settings.setMoveNames(s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              t('Haku löytää liikkeet aina molemmilla kielillä. Tiedostoihin nimet tallentuvat suomeksi.'),
              style: sub,
            ),
          ),
          SwitchListTile(
            title: Text(t('Urheilu ja liikunta')),
            subtitle: Text(
              t('Juoksu, kävely, pyöräily, salibandy, squash ja muut lajit treenien rinnalle.'),
              style: sub,
            ),
            value: settings.sports,
            onChanged: settings.setSports,
          ),
          SwitchListTile(
            title: Text(t('Palautusajastin')),
            subtitle: Text(
              t(
                'Sarjan tallennus käynnistää palautuksen: raskaissa ja lähellä maksimia pidempi, kevennysviikolla lyhyempi. Ohjelman liikkeillä ohjelman tauko.',
              ),
              style: sub,
            ),
            value: settings.restTimer,
            onChanged: (v) async {
              settings.setRestTimer(v);
              // Ilmoitus näkyy ja soi myös näytön ollessa pois päältä tai toisessa sovelluksessa.
              if (v && RestTimer.native) {
                RestTimer.notificationsOk = (await Permission.notification.request()).isGranted;
              }
            },
          ),
          if (settings.restTimer && !isDemo) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(t('Ilmoitusääni'), style: sub),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        for (final (v, l) in [
                          ('pling', 'Pling'),
                          ('boop', 'Boop'),
                          ('chime', t('Kello')),
                          ('none', t('Värinä')),
                        ])
                          ButtonSegment(
                            value: v,
                            label: FittedBox(fit: BoxFit.scaleDown, child: Text(l, maxLines: 1)),
                          ),
                      ],
                      selected: {settings.restSound},
                      onSelectionChanged: (s) {
                        settings.setRestSound(s.first);
                        RestTimer.preview();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: t('Kuuntele'),
                    onPressed: RestTimer.preview,
                    icon: const Icon(Icons.volume_up_outlined),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const _RestTimes(),
          ],
          SwitchListTile(
            title: Text(t('Sykemittari ja älykello')),
            subtitle: Text(
              t('Kirjaa kellosta kesto, kalorit sekä keski- ja maksimisyke treeneihin ja liikuntaan.'),
              style: sub,
            ),
            value: settings.watch,
            onChanged: settings.setWatch,
          ),
          SwitchListTile(
            title: Text(t('Vinkit ja edistyminen')),
            subtitle: Text(t('Edistyminen etusivulla ja kevennysviikon ehdotukset.'), style: sub),
            value: settings.tips,
            onChanged: settings.setTips,
          ),
          if (settings.tips) ...[
            Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 6), child: Text(t('Ehdota kevennystä (viikon välein)'))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 4, label: Text('4')),
                  ButtonSegment(value: 5, label: Text('5')),
                  ButtonSegment(value: 6, label: Text('6')),
                  ButtonSegment(value: 8, label: Text('8')),
                ],
                selected: {settings.deloadEvery},
                onSelectionChanged: (s) => settings.setDeloadEvery(s.first),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (!isDemo)
            FutureBuilder(
              future: _rootDir(),
              builder: (context, snap) => ListTile(
                title: Text(t('Treenikansio (.md)')),
                subtitle: Text(
                  '${snap.data?.path ?? ''}\n${t('Valitse esim. Nextcloud-, Seafile-, ownCloud- tai Drive-synkattu kansio.')}',
                  style: sub,
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.folder_open),
                onTap: () => _pickFolder(context),
              ),
            ),
          if (settings.folder != null && !isDemo)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(onPressed: () => changeFolder(context, null), child: Text(t('Palauta oletuskansio'))),
            ),
          ListTile(
            title: Text(t('Lämmittelylaitteet')),
            subtitle: Text(settings.equipment.map((e) => e.name).join(', '), style: sub),
            trailing: TextButton(
              onPressed: () => settings.setEquipment([...Settings.defaultEquipment]),
              child: Text(t('Palauta')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(t('Laitteita voi lisätä ja poistaa uuden treenin Muokkaa-napista.'), style: sub),
          ),
        ],
      ),
    );
  }
}

// --- Dialogit -------------------------------------------------------------

Widget _h(String t) => Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 6),
  child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
);

Widget _bullets(BuildContext context, List<(String, String)> items) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (final (b, tx) in items)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '•  '),
              if (b.isNotEmpty)
                TextSpan(
                  text: '$b ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              TextSpan(text: tx),
            ],
          ),
        ),
      ),
  ],
);

Future<void> showAbout(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  final cs = Theme.of(context).colorScheme;
  final platform = isDemo ? t('verkkodemo') : (Platform.isAndroid ? 'Android' : t('työpöytä'));
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      icon: const AppLogo(size: 56),
      title: Column(
        children: [
          const Text(AppInfo.fullName, textAlign: TextAlign.center),
          const Text(AppInfo.slogan, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          Text(
            t('Versio {0} ({1})', [info.version, platform]),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('Maksuton ja avoin treenipäiväkirja salille ja kuntoiluun.'),
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          _h(t('Tekijä')),
          const Text(AppInfo.author, style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => _open('mailto:${AppInfo.feedbackEmail}'),
                child: const Text(AppInfo.feedbackEmail),
              ),
              if (AppInfo.github != null) TextButton(onPressed: () => _open(AppInfo.github!), child: Text(t('GitHub'))),
            ],
          ),
          _h(t('Treenit ovat sinun')),
          Text(
            t(
              'Jokainen treeni tallentuu tavallisena Markdown-tiedostona (.md) valitsemaasi kansioon, '
              'yksi tiedosto treeniä kohden. Tiedostot aukeavat millä tahansa tekstieditorilla tai '
              'esimerkiksi Obsidianilla, ja ne kulkevat laitteelta toiselle Nextcloudin, Seafilen, '
              'ownCloudin tai Driven kautta.',
            ),
          ),
          _h(t('Tietosuoja')),
          Text(
            t(
              'Sovelluksessa ei ole tiliä, mainoksia eikä analytiikkaa, eikä se lähetä tietoja '
              'minnekään. Treenit pysyvät omassa kansiossasi.',
            ),
          ),
          _h(t('Saamelainen teema')),
          Text(
            t(
              'Värit ja aurinko/kuu-ympyrä tulevat saamen lipusta, ja koristenauha on lainattu gáktin '
              'reunuksista. Kalenterissa kuukaudet näkyvät myös pohjoissaameksi.',
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => LicensesScreen(version: info.version))),
            icon: const Icon(Icons.code, size: 18),
            label: Text(t('Avoin lähdekoodi ja lisenssit')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => LicensesScreen(version: info.version))),
          child: Text(t('Lisenssit')),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Sulje'))),
      ],
    ),
  );
}

Future<void> showFeedback(BuildContext context) => showDialog(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(t('Lähetä palautetta')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('Virheet, puuttuvat liikkeet, toiveet ja ideat ovat tervetulleita.')),
        const SizedBox(height: 14),
        // Osoite näkyy ja kopioituu, koska sähköpostilinkki ei toimi ilman sähköpostiohjelmaa.
        Row(
          children: [
            const Expanded(
              child: SelectableText(AppInfo.feedbackEmail, style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: AppInfo.feedbackEmail));
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t('Osoite kopioitu'))));
              },
              child: Text(t('Kopioi')),
            ),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => _open('mailto:${AppInfo.feedbackEmail}?subject=Gievra-palaute'),
        child: Text(t('Avaa sähköposti')),
      ),
      if (AppInfo.github != null)
        TextButton(onPressed: () => _open(AppInfo.issues!), child: Text(t('Tee ilmoitus GitHubissa'))),
      FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Sulje'))),
    ],
  ),
);

Future<void> showSupport(BuildContext context) => showDialog(
  context: context,
  builder: (ctx) => AlertDialog(
    scrollable: true,
    title: Text(t('Osallistu ja tue')),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(
            '{0} on maksuton ja avoin sovellus kaikille salista ja kuntoilusta kiinnostuneille. Siinä '
            'ei ole mainoksia, tilauksia eikä maksullisia lisäosia, eikä tule olemaan.',
            [AppInfo.fullName],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t(
            'Gievra on vapaa ohjelma GNU GPL v3.0 -lisenssillä: sen lähdekoodia saa käyttää, tutkia, '
            'muokata ja jakaa, kunhan muokatut versiot jaetaan samalla lisenssillä. Sovellus käyttää '
            'avoimen lähdekoodin kirjastoja, jotka on lueteltu kohdassa Tietoa → Avoin lähdekoodi ja '
            'lisenssit.',
          ),
          style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
        ),
        _h(t('Näin voit auttaa')),
        _bullets(ctx, [
          (t('Ehdota liikkeitä:'), t('kerro, jos luettelosta puuttuu salilla yleinen liike.')),
          (t('Ilmoita virheistä:'), t('kerro, jos jokin ei toimi tai treeni ei tallennu oikein.')),
          (t('Ehdota ideoita:'), t('uusia ominaisuuksia, tilastoja tai käyttöliittymän muutoksia.')),
          (t('Saavutettavuus:'), t('kerro, mikä helpottaisi käyttöä esimerkiksi näkö- tai liikuntavamman kanssa.')),
          (t('Käännökset:'), t('auta tuomaan sovellus saameksi.')),
          (t('Osallistu kehitykseen:'), t('lähdekoodi on avointa, ja korjaukset ovat tervetulleita.')),
        ]),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                showFeedback(context);
              },
              child: Text(t('Lähetä palautetta')),
            ),
            if (AppInfo.github != null)
              OutlinedButton(onPressed: () => _open(AppInfo.github!), child: Text(t('GitHub'))),
          ],
        ),
        _h(t('Miksi tukea?')),
        Text(
          t(
            'Sovelluksen kehittäminen ja ylläpito tehdään vapaa-ajalla. Tarjoamalla kahvit tuet '
            'suoraan tätä työtä:',
          ),
        ),
        const SizedBox(height: 6),
        _bullets(ctx, [
          ('', t('sovellus pysyy maksuttomana ja mainoksettomana kaikille')),
          (
            '',
            t(
              'sovellus pysyy ajan tasalla, ja Windows- ja Linux-versiot valmistuvat, kun sovellus on '
              'hiottu valmiiksi',
            ),
          ),
          ('', t('saamenkielinen versio ja uudet ominaisuudet etenevät nopeammin')),
        ]),
        const SizedBox(height: 10),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Sami.yellow, foregroundColor: Colors.black),
            onPressed: () => _open(AppInfo.coffee),
            icon: const Text('☕', style: TextStyle(fontSize: 18)),
            label: Text(t('Buy me a coffee'), style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          t('Tuki on vapaaehtoista eikä avaa mitään lisäominaisuuksia: sovellus pysyy kaikille maksuttomana.'),
          style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Text(t('Giitu! Kiitos, että tuet sovellusta!'), style: TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
    actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Sulje')))],
  ),
);

Future<void> showPauseDialog(BuildContext context) async {
  var reason = 'sairas';
  var start = dateOnly(DateTime.now());
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(t('Tauko treenaamisesta')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'sairas', label: Text(t('🤒 Sairas'))),
                ButtonSegment(value: 'loma', label: Text(t('🏖 Loma'))),
              ],
              selected: {reason},
              onSelectionChanged: (v) => set(() => reason = v.first),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(t('Alkoi {0}.{1}.{2}', [start.day, start.month, start.year])),
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: start,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (d != null) set(() => start = dateOnly(d));
              },
            ),
            const SizedBox(height: 12),
            Text(
              reason == 'sairas'
                  ? t(
                      'Lepää ja parane. Tauko päättyy, kun kirjaat seuraavan treenin. Sen jälkeen sovellus '
                      'ehdottaa noin kahden viikon ajan kevyempiä kuormia ja vähemmän sarjoja tauon pituuden '
                      'mukaan.',
                    )
                  : t(
                      'Tauko päättyy, kun kirjaat seuraavan treenin. Lyhyt loma ei juuri vaikuta voimaan; '
                      'pidemmän jälkeen sovellus ehdottaa aluksi kevyempiä kuormia.',
                    ),
              style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Aloita tauko'))),
        ],
      ),
    ),
  );
  if (ok == true) settings.startPause(reason, start);
}

/// Treenikansion vaihto: jos nykyisessä kansiossa on tiedostoja, kysytään kopioidaanko ne uuteen.
/// Kopiointi ei ylikirjoita uuden kansion tiedostoja, ja alkuperäiset jäävät vanhaan kansioon.
Future<void> changeFolder(BuildContext context, String? newDir) async {
  final messenger = ScaffoldMessenger.of(context);
  final old = await store.rootDir();
  final target = newDir == null ? await store.defaultDir() : Directory(newDir);
  if (p.equals(old.path, target.path)) return;
  final oldFiles = await Settings.mdFiles(old);
  final newFiles = await Settings.mdFiles(target);
  var copy = false;
  if (oldFiles.isNotEmpty && context.mounted) {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Kopioidaanko treenit?')),
        content: Text(
          '${t('Nykyisessä kansiossa on {0} tiedostoa (treenit, asetukset ja ohjelma).', [oldFiles.length])} '
          '${newFiles.isEmpty ? t('Uusi kansio on tyhjä.') : t('Uudessa kansiossa on jo {0} .md-tiedostoa.', [newFiles.length])}\n\n'
          '${t('Kopioidaanko treenit uuteen kansioon? Uuden kansion tiedostoja ei ylikirjoiteta, ja alkuperäiset '
          'jäävät myös vanhaan kansioon.')}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'no'), child: Text(t('Älä kopioi'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'copy'), child: Text(t('Kopioi'))),
        ],
      ),
    );
    if (choice == null) return;
    copy = choice == 'copy';
  }
  var msg = '';
  if (copy) {
    try {
      final (c, sk) = await Settings.copyMdFiles(old, target);
      msg = sk > 0
          ? t('Kopioitu {0} tiedostoa, {1} oli jo uudessa kansiossa. ', [c, sk])
          : t('Kopioitu {0} tiedostoa. ', [c]);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(t('Kopiointi epäonnistui: {0}', [e]))));
      return;
    }
  }
  await settings.setFolder(newDir);
  await store.reload();
  messenger.showSnackBar(SnackBar(content: Text(t('{0}Löytyi {1} treeniä.', [msg, store.workouts.length]))));
}

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Palautusajat kuormaluokittain: oletus ohjelman (tai tutkimusten) mukaan, oma säätö ±15 s.
class _RestTimes extends StatelessWidget {
  const _RestTimes();

  // const-lapsi: kuunnellaan asetuksia itse, muuten ±15 s ei näkyisi heti.
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: settings, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final defs = restDefaults(settings.program);
    final labels = [
      t('Kevyt kuorma (yli 12 toistoa)'),
      t('Keskiraskas (6–12 toistoa)'),
      t('Raskas (1–5 toistoa tai lähellä maksimia)'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Palautusajat'), style: sub),
          for (var c = 0; c < 3; c++)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(labels[c], style: const TextStyle(fontSize: 13)),
                      Text(
                        settings.restAdjust[c] == 0
                            ? (settings.program != null ? t('ohjelmasi oletus') : t('oletus'))
                            : t('oletus {0}, oma säätö {1}{2} s', [
                                _mmss(defs[c]),
                                settings.restAdjust[c] > 0 ? '+' : '',
                                settings.restAdjust[c],
                              ]),
                        style: sub,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '−15 s',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => settings.adjustRest(c, -15),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    _mmss((defs[c] + settings.restAdjust[c]).clamp(15, 600)),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '+15 s',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => settings.adjustRest(c, 15),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          if (settings.restAdjust.any((x) => x != 0))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  for (var c = 0; c < 3; c++) {
                    settings.adjustRest(c, null);
                  }
                },
                child: Text(t('Palauta oletukset')),
              ),
            ),
          Text(
            t('Eristävät liikkeet ja lämmittelysarjat lyhyemmin. Ei varaa: +30 s. Kevennysviikolla × 0,75.'),
            style: sub,
          ),
        ],
      ),
    );
  }
}
