import 'dart:io';

import 'maps_screen.dart';
import 'licenses_screen.dart';
import 'stats_screen.dart';
import '../sync/sync_service.dart';
import 'sync_screen.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../auto_backup.dart';
import '../rest.dart';
import '../models.dart';
import '../theme.dart';
import 'bug_report.dart';
import 'import_export.dart';
import '../injuries.dart' show knownInjuries;
import 'injury_screen.dart';
import 'intro.dart';
import 'program_screen.dart';
import 'body_screen.dart';
import 'widgets.dart';
import '../l10n.dart';
import '../maps/elevation.dart' show copernicusAttribution;

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

/// Valikon kohta: suljetaan valikko ja avataan näkymä.
void _go(BuildContext context, {required WidgetBuilder builder}) {
  Navigator.pop(context);
  Navigator.of(context).push(MaterialPageRoute(builder: builder));
}

/// Valikon ryhmän pieni otsikko.
Widget _cap(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
  child: Text(
    text,
    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
  ),
);

/// Alarivin teksti ja "Käytössä"-merkki rinnakkain.
Widget _withBadge(Widget text) =>
    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [text, const ActiveBadge()]);

/// Pieni "Käytössä"-merkki valikossa (vammatila, tauko).
class ActiveBadge extends StatelessWidget {
  const ActiveBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Sami.yellow.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
    child: Text(
      t('Käytössä'),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: yellowText(context)),
    ),
  );
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
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
              _cap(context, t('Treeni ja terveys')),
              ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(t('Ohjelma ja tavoitteet')),
                subtitle: Text(settings.program?.displayTitle ?? t('Treenaat vapaasti'), style: sub),
                onTap: () => _go(context, builder: (_) => const ProgramScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.insights),
                title: Text(t('Edistyminen ja tilastot')),
                subtitle: Text(t('Viikko- ja kuukausikoosteet, fiilis, voimakehitys'), style: sub),
                onTap: () => _go(context, builder: (_) => const StatsScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.healing),
                title: Text(t('Vammatila')),
                // Kuvaus myös pois päältä, jotta vammatila löytyy; "Käytössä" alarivillä, ettei otsikko rivity.
                subtitle: knownInjuries(settings.injuries).isEmpty
                    ? Text(t('Kipu tai vamma: vältettävät liikkeet ja korvaavat'), style: sub)
                    : _withBadge(
                        Text(t('{0} aluetta valittuna', [knownInjuries(settings.injuries).length]), style: sub),
                      ),
                onTap: () => _go(context, builder: (_) => InjuryScreen(initial: settings.injuries)),
              ),
              ListTile(
                leading: Icon(settings.activePause == null ? Icons.bedtime_outlined : Icons.play_circle_outline),
                title: Text(settings.activePause == null ? t('Tauko: sairas tai loma') : t('Lopeta tauko')),
                subtitle: settings.activePause == null
                    ? null
                    : _withBadge(Text(settings.activePause!.sick ? t('Sairauslomalla') : t('Lomalla'), style: sub)),
                onTap: () {
                  Navigator.pop(context);
                  settings.activePause == null ? showPauseDialog(context) : settings.endPause();
                },
              ),
              // Kartat, synkronointi ja tiedostot (ei selainversiossa).
              if (!isDemo) ...[
                const Divider(indent: 18, endIndent: 18),
                _cap(context, t('Tiedot ja laitteet')),
                if (Platform.isAndroid)
                  ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: Text(t('Kartat')),
                    subtitle: Text(t('Offline-kartat GPS-reiteille: lataa alue tai kunnat'), style: sub),
                    onTap: () => _go(context, builder: (_) => const MapsScreen()),
                  ),
                // Synkronointi näkyy vasta, kun se on julkaistu (ei "tulossa"-paikkamerkkiä).
                if (syncReleased)
                  ListenableBuilder(
                    listenable: sync,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.cloud_sync_outlined),
                      title: Text(t('Synkronointi')),
                      subtitle: Text(
                        sync.enabled ? 'Google Drive · ${sync.status ?? ''}' : t('Pois päältä (valinnainen)'),
                        style: sub,
                      ),
                      onTap: () => _go(context, builder: (_) => const SyncScreen()),
                    ),
                  ),
                // Ohjelmapohjan (.gmd) tuonti: Tuo tiedosto, sekä Ohjelma ja tavoitteet.
                ListTile(
                  leading: const Icon(Icons.import_export),
                  title: Text(t('Tuonti, vienti ja varmuuskopio')),
                  onTap: () => _go(context, builder: (_) => const ImportExportScreen()),
                ),
              ],
              const Divider(indent: 18, endIndent: 18),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(t('Asetukset')),
                onTap: () => _go(context, builder: (_) => const SettingsScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(t('Tietoa, palaute ja tuki')),
                onTap: () => _go(context, builder: (_) => const AboutScreen()),
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

enum SettingsGroup { general, training, rest, body, storage }

/// Asetukset omana näkymänään: ryhmät, joista kukin avaa oman sivun.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static String title(SettingsGroup g) => switch (g) {
    SettingsGroup.general => t('Yleiset'),
    SettingsGroup.training => t('Harjoittelu'),
    SettingsGroup.rest => t('Palautusajastin'),
    SettingsGroup.body => t('Keho ja laitteet'),
    SettingsGroup.storage => t('Tallennus'),
  };

  @override
  Widget build(BuildContext context) {
    final sub = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final groups = [
      (
        SettingsGroup.general,
        Icons.person_outline,
        // Englanniksi liikkeiden nimet ovat aina englanniksi, eikä valintaa näytetä.
        isEnglish ? t('Nimi, kieli, teema') : t('Nimi, kieli, teema, liikkeiden nimet'),
      ),
      (SettingsGroup.training, Icons.fitness_center, t('Mitä treenaat, painon lisäys, lämmittely, vinkit ja kevennys')),
      (SettingsGroup.rest, Icons.timer_outlined, t('Ääni, palautusajat ja ilmoitus')),
      (SettingsGroup.body, Icons.monitor_heart_outlined, t('Kehonpaino, sykemittari, Health Connect')),
      // Selainversiossa ei omaa treenikansiota.
      if (!isDemo) (SettingsGroup.storage, Icons.folder_outlined, t('Treenikansio (.md)')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t('Asetukset'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (g, icon, text) in groups)
            ListTile(
              leading: Icon(icon),
              title: Text(title(g)),
              subtitle: Text(text, style: sub),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(title(g))),
                    body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [_SettingsSection(g)]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tietoa, palaute ja tuki yhdessä näkymässä (ennen viisi valikon kohtaa).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    void push({required WidgetBuilder builder}) => Navigator.of(context).push(MaterialPageRoute(builder: builder));
    return Scaffold(
      appBar: AppBar(title: Text(t('Tietoa, palaute ja tuki'))),
      body: FutureBuilder(
        future: _packageInfo,
        builder: (context, snap) {
          final version = snap.data?.version ?? '';
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Row(
                  children: [
                    const AppLogo(size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(AppInfo.fullName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(
                            t('Tekijä: {0}', [AppInfo.author]),
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                          if (version.isNotEmpty) Text(t('Versio {0}', [version]), style: sub),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(t('Tietoa')),
                onTap: () => showAbout(context),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: Text(t('Avoin lähdekoodi ja lisenssit')),
                onTap: () => push(builder: (_) => LicensesScreen(version: version)),
              ),
              const Divider(indent: 18, endIndent: 18),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(t('Lähetä palautetta')),
                onTap: () => showFeedback(context),
              ),
              if (!isDemo)
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: Text(t('Ilmoita ongelmasta')),
                  subtitle: Text(t('Tallennus, tuonti, vienti… liitteineen'), style: sub),
                  onTap: () => push(builder: (_) => const BugReportScreen()),
                ),
              const Divider(indent: 18, endIndent: 18),
              ListTile(
                leading: const Icon(Icons.favorite_outline, color: Sami.red),
                title: Text(t('Osallistu ja tue')),
                onTap: () => showSupport(context),
              ),
              ListTile(
                leading: const Text('☕', style: TextStyle(fontSize: 20)),
                title: Text(t('Tarjoa kahvit')),
                subtitle: Text(t('Vapaaehtoinen tuki kehitykselle'), style: sub),
                onTap: () => _open(AppInfo.coffee),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Nimen muokkaus. Oma tila, jotta tekstikenttä vapautetaan vasta, kun dialogi on kokonaan suljettu
/// (sulkuanimaatio käyttää kenttää vielä muutaman ruudun ajan).
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _c = TextEditingController(text: settings.name);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('Miksi sinua kutsutaan?')),
    content: TextField(controller: _c, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Peruuta'))),
      FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: Text(t('Tallenna'))),
    ],
  );
}

/// Automaattiset varmuuskopiot (backup/): päiväys, versio ja koko; tallenna (esim. Lataukset) tai jaa.
class _AutoBackups extends StatefulWidget {
  @override
  State<_AutoBackups> createState() => _AutoBackupsState();
}

class _AutoBackupsState extends State<_AutoBackups> {
  List<(File, int)> _files = [];

  @override
  void initState() {
    super.initState();
    autoBackup.addListener(_load);
    settings.addListener(_load); // kansion vaihto
    _load();
  }

  @override
  void dispose() {
    autoBackup.removeListener(_load);
    settings.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final out = <(File, int)>[];
    try {
      for (final f in await autoBackup.list()) {
        out.add((f, await f.length()));
      }
    } catch (_) {}
    if (mounted) setState(() => _files = out);
  }

  Future<void> _save(File f) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = await FilePicker.saveFile(
        fileName: p.basename(f.path),
        bytes: await f.readAsBytes(),
        mimeType: 'application/zip',
        dialogTitle: t('Tallenna varmuuskopio'),
      );
      if (uri != null) messenger.showSnackBar(SnackBar(content: Text(t('Varmuuskopio tallennettu.'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(t('Virhe: {0}', [errorText(e)]))));
    }
  }

  String _title(File f) {
    final parsed = AutoBackup.parseName(p.basename(f.path));
    if (parsed == null) return p.basename(f.path);
    final at = parsed.$1;
    return t('{0} klo {1}', [
      numDate(at, year: true),
      '${at.hour}${isEnglish ? ':' : '.'}${at.minute.toString().padLeft(2, '0')}',
    ]);
  }

  Future<void> _delete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko "{0}"?', [_title(f)])),
        content: Text(t('Poistettua varmuuskopiota ei voi palauttaa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista'))),
        ],
      ),
    );
    if (ok == true) await autoBackup.delete(f);
  }

  Future<void> _share(File f) async {
    // Jaetaan väliaikaisen kopion kautta (kuten treenin .md-tiedosto).
    final tmp = File(p.join((await getTemporaryDirectory()).path, p.basename(f.path)));
    await f.copy(tmp.path);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(tmp.path, mimeType: 'application/zip')],
        subject: p.basename(f.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            t('Automaattiset varmuuskopiot'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            t(
              'Tehdään, kun uusi versio käynnistyy ensimmäisen kerran, ennen kuin se muuttaa mitään. Enintään 3; oma '
              'varmuuskopio korvaa ne. Ne ovat treenikansiossa, joten ne poistuvat, jos oletuskansiota käyttävä '
              'sovellus poistetaan: tallenna tärkeä kopio talteen.',
            ),
            style: sub,
          ),
        ),
        if (_files.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(t('Ei vielä automaattisia varmuuskopioita.'), style: sub),
          ),
        for (final (f, size) in _files)
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            // Päivä ja kellonaika otsikkona, versio ja koko alarivillä (koko koontinimi rivittyi kolmelle riville).
            title: Text(_title(f)),
            subtitle: Text(() {
              final mb = fmtNum((size / 1e5).round() / 10);
              final parsed = AutoBackup.parseName(p.basename(f.path));
              return parsed == null
                  ? t('{0} Mt', [mb])
                  : t('ennen {0} · {1} Mt', [AutoBackup.shortVersion(parsed.$2), mb]);
            }(), style: sub),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: t('Tallenna'), icon: const Icon(Icons.save_alt), onPressed: () => _save(f)),
                IconButton(tooltip: t('Jaa'), icon: const Icon(Icons.share_outlined), onPressed: () => _share(f)),
                IconButton(tooltip: t('Poista'), icon: const Icon(Icons.delete_outline), onPressed: () => _delete(f)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final SettingsGroup group;
  const _SettingsSection(this.group);

  Future<void> _editName(BuildContext context) async {
    final v = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
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
  /// Pelkästä kestävyydestä saliin tai molempiin: tarjotaan treeniohjelmaa (kysymykset), jos sitä ei vielä ole.
  Future<void> _changeMode(BuildContext context, String v) async {
    final fromCardio = settings.trainMode == 'cardio';
    settings.setTrainMode(v);
    if (!fromCardio || v == 'cardio' || settings.program != null || !context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Tehdäänkö treeniohjelma?')),
        content: Text(
          t(
            'Vastaa muutamaan kysymykseen (tavoite, kokemus, päivät, kesto), niin saat salille valmiin ohjelman. '
            'Voit myös treenata vapaasti ja tehdä ohjelman myöhemmin.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Myöhemmin'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Tee ohjelma'))),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      final nav = Navigator.of(context);
      nav.push(MaterialPageRoute(builder: (_) => const ProgramScreen()));
      nav.push(MaterialPageRoute(builder: (_) => const IntroScreen()));
    }
  }

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
          if (group == SettingsGroup.general) ...[
            ListTile(
              title: Text(t('Nimesi')),
              subtitle: Text(settings.name ?? '', style: sub),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => _editName(context),
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
            // Saamenkielisessä käyttöliittymässä vammatilan ohjeet suomeksi tai englanniksi (ei käännetty saameksi).
            if (isSami) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Text(t('Vammatilan ohjeet ja liikevinkit')),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'fi', label: Text(t('Suomi'))),
                    const ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {settings.healthLang},
                  onSelectionChanged: (s) => settings.setHealthLang(s.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  t(
                    'Vammatilan ohjeita ja liikevinkkejä ei ole käännetty saameksi: valitse, näytetäänkö ne suomeksi vai englanniksi.',
                  ),
                  style: sub,
                ),
              ),
            ],
            // Englanninkielisessä käyttöliittymässä nimet ovat aina englanniksi: valintaa ei tarvita.
            if (!isEnglish) ...[
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
                  t(
                    'Liikkeiden ja lajien nimet. Haku löytää ne aina molemmilla kielillä, ja tiedostoihin nimet tallentuvat suomeksi.',
                  ),
                  style: sub,
                ),
              ),
            ],
          ],
          if (group == SettingsGroup.training) ...[
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text(t('Mitä treenaat?'))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TrainModePicker(
                value: settings.trainMode,
                icons: false,
                onChanged: (v) => _changeMode(context, v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                t(
                  'Sali: salitreenit ja ohjelma. Kestävyys: juoksu, pyöräily, hiihto ja muut lajit. Molemmat: '
                  'etusivulla valinta Sali / Kestävyys.',
                ),
                style: sub,
              ),
            ),
            Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text(t('Painon lisäys (kg)'))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<double>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 1.25, label: Text(fmtNum(1.25))),
                  ButtonSegment(value: 2.5, label: Text(fmtNum(2.5))),
                  const ButtonSegment(value: 5, label: Text('5')),
                ],
                selected: {settings.weightStep},
                onSelectionChanged: (s) => settings.setWeightStep(s.first),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: Text(t('Lämmittelylaitteet')),
              subtitle: Text(settings.equipment.map((e) => t(e.name)).join(', '), style: sub),
              trailing: TextButton(
                onPressed: () => settings.setEquipment([...Settings.defaultEquipment]),
                child: Text(t('Palauta')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text(t('Laitteita voi lisätä ja poistaa uuden treenin Muokkaa-napista.'), style: sub),
            ),
            const SizedBox(height: 8),
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
          ],
          if (group == SettingsGroup.rest) ...[
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
              // Kuuntele-painike otsikkoriville: neljä ääntä saa koko leveyden (saameksi "Doarggistus"
              // kutistui kapealla puhelimella lukukelvottomaksi).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                child: Row(
                  children: [
                    Expanded(child: Text(t('Ilmoitusääni'), style: sub)),
                    IconButton(
                      tooltip: t('Kuuntele'),
                      visualDensity: VisualDensity.compact,
                      onPressed: RestTimer.preview,
                      icon: const Icon(Icons.volume_up_outlined),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  expandedInsets: EdgeInsets.zero,
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
                    visualDensity: VisualDensity.compact,
                  ),
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
              const SizedBox(height: 8),
              const _RestTimes(),
            ],
            if (!isDemo && Platform.isAndroid)
              SwitchListTile(
                title: Text(t('Ilmoitus käynnissä olevasta treenistä')),
                subtitle: Text(
                  t('Pudotusvalikossa näkyy esim. "Salitreeni käynnissä" ja kulunut aika, kunnes treeni on valmis.'),
                  style: sub,
                ),
                value: settings.ongoingNote,
                onChanged: settings.setOngoingNote,
              ),
          ],
          if (group == SettingsGroup.body) ...[
            SwitchListTile(
              title: Text(t('Kehonpainon seuranta')),
              subtitle: Text(
                t(
                  'Tämän päivän paino etusivulla, painon kehitys ja painoindeksi tilastoissa. Punnitse milloin haluat.',
                ),
                style: sub,
              ),
              value: settings.bodyTracker,
              onChanged: settings.setBodyTracker,
            ),
            if (settings.bodyTracker)
              ListTile(
                leading: const Icon(Icons.monitor_weight_outlined),
                title: Text(t('Paino ja pituus')),
                subtitle: Text(
                  settings.body.isEmpty
                      ? t('Lisää punnitus ja pituus')
                      : [
                          if (settings.body.sorted.lastOrNull case final last?) '${fmtNum(last.$2)} kg',
                          if (settings.body.heightCm != null) '${settings.body.heightCm} cm',
                        ].join(' · '),
                  style: sub,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BodyScreen())),
              ),
            SwitchListTile(
              title: Text(t('Sykemittari ja älykello')),
              subtitle: Text(
                t('Kirjaa kellosta kesto, kalorit sekä keski- ja maksimisyke treeneihin ja liikuntaan.'),
                style: sub,
              ),
              value: settings.watch,
              onChanged: settings.setWatch,
            ),
            // Tehdyn liikunnan lisäys Health Connectista etusivun painikkeesta (Android, kestävyyslajit; oletus pois).
            if (!isDemo && Platform.isAndroid && settings.sports)
              SwitchListTile(
                title: Text(t('Lisää tehty liikunta Health Connectista')),
                subtitle: Text(
                  t(
                    'Etusivulle painike, josta kellon tai muun sovelluksen Health Connectiin tallentama liikunta '
                    'lisätään Gievraan: laji, aika, matka, syke, kalorit ja askeleet.',
                  ),
                  style: sub,
                ),
                value: settings.hcImport,
                onChanged: settings.setHcImport,
              ),
          ],
          if (group == SettingsGroup.storage) ...[
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
            // Sovelluksen omat kopiot: oletuskansio (Android/data) ei näy puhelimen tiedostonhallinnassa, joten
            // tallennus ja jakaminen tästä.
            if (!isDemo) _AutoBackups(),
          ],
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
          _h(t('Kartat')),
          Text(
            t(
              'Karttatiedot {0}, lisenssi ODbL 1.0. Rannikot ja rajat pienillä mittakaavoilla: Natural Earth '
              '(public domain). Kunta- ja maakuntarajat: Tilastokeskus, CC BY 4.0.',
              [MapCredits.osm],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Muiden maiden aluerajat: Ruotsi, Norja, Tanska, Islanti, Espanja ja Irlanti {0} (ODbL). Iso-Britannia: '
              'Office for National Statistics, Open Government Licence v3.0; sisältää OS:n aineistoa '
              '© Crown copyright and database right 2024.',
              [MapCredits.osm],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Korkeustiedot (Suomi): Maanmittauslaitos, Korkeusmalli 10 m (2019), CC BY 4.0; muunnettu Gievraa varten '
              '25 metrin ruudukoksi.',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Korkeustiedot (Ruotsi, Norja, Tanska, Islanti, Iso-Britannia, Espanja ja Irlanti): Copernicus DEM GLO-30, '
              'muunnettu Gievraa varten noin 30 metrin ruudukoksi.',
            ),
          ),
          // Copernicus DEM -lisenssin vaatimat ilmoitus ja vastuuvapauslauseke sellaisenaan (ei käännetä).
          const Text('$copernicusAttribution.', style: TextStyle(fontSize: 12)),
          const Text(
            'The organisations in charge of the Copernicus programme by law or by delegation do not incur any '
            'liability for any use of the Copernicus WorldDEM-30.',
            style: TextStyle(fontSize: 12),
          ),
          TextButton(onPressed: () => _open(MapCredits.osmUrl), child: const Text(MapCredits.osm)),
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
        const SizedBox(height: 8),
        Text(t('Voit kirjoittaa suomeksi, saameksi tai englanniksi.')),
        const SizedBox(height: 8),
        Text(
          t('Jos jokin ei toimi, käytä mieluummin Ilmoita ongelmasta: se liittää mukaan tarvittavat tiedot.'),
          style: Theme.of(ctx).textTheme.bodySmall,
        ),
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BugReportScreen()));
          },
          icon: const Icon(Icons.bug_report_outlined, size: 18),
          label: Text(t('Ilmoita ongelmasta')),
        ),
        const SizedBox(height: 6),
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
                final d = await pickDate(ctx, initial: start, first: DateTime(2000), last: DateTime.now());
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
      messenger.showSnackBar(SnackBar(content: Text(t('Kopiointi epäonnistui: {0}', [errorText(e)]))));
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
