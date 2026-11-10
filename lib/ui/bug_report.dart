import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../body.dart';
import '../l10n.dart';
import '../maps/map_store.dart';
import '../theme.dart';
import 'widgets.dart';

/// ☰ → Ilmoita ongelmasta: ongelman tyyppi, kuvaus ja liitteet (treenitiedostot, asetukset, kuvakaappaukset).
/// Androidilla avautuu sähköpostisovellus valmiilla vastaanottajalla, aiheella ja liitteillä; muualla jakovalikko.
class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});
  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _Attachment {
  final String name;
  final String path; // tiedosto levyllä (kopioidaan välimuistiin lähetettäessä)
  bool on;
  final String? warning; // arkaluonteinen (punnitukset, GPS-reitti): varoitus ja oletuksena pois
  _Attachment(this.name, this.path, {this.on = true, this.warning});
}

/// Vikailmoituksen oletusliitteet (nimi, polku, valittuna, varoitus): kolme viimeisintä treeniä, niiden GPS-reitit
/// (oletuksena pois, varoituksen kera), asetukset ja ohjelma sekä punnitukset (oletuksena pois).
Future<List<(String, String, bool, String?)>> defaultReportAttachments() async {
  final root = (await store.rootDir()).path;
  final out = await workoutAttachments(0, 3, on: true);
  for (final n in ['asetukset.md', 'ohjelma.md']) {
    final f = File(p.join(root, n));
    if (await f.exists()) out.add((n, f.path, true, null));
  }
  // Punnitukset ovat terveystietoa: mukana valittavana, mutta oletuksena pois ja varoituksen kera.
  final body = File(p.join(root, bodyFileName));
  if (await body.exists()) {
    out.add((
      bodyFileName,
      body.path,
      false,
      t('⚠ Sisältää punnituksesi ja pituutesi (terveystietoa). Lähetä vain, jos ongelma liittyy painoon.'),
    ));
  }
  return out;
}

/// Treenitiedostot uusimmasta alkaen: [skip] ohitetaan, [take] seuraavaa. GPS-reitti aina oletuksena pois.
Future<List<(String, String, bool, String?)>> workoutAttachments(int skip, int take, {required bool on}) async {
  final root = (await store.rootDir()).path;
  final out = <(String, String, bool, String?)>[];
  final recent = [...store.workouts]..sort((a, b) => b.date.compareTo(a.date));
  for (final w in recent.skip(skip).take(take)) {
    final rel = workoutPath(w.date, w.session);
    final f = File(p.join(root, rel));
    if (await f.exists()) out.add((p.basename(rel), f.path, on, null));
    // GPS-reitti näyttää, missä liikuit: mukana valittavana, oletuksena pois ja varoituksen kera.
    if (w.route != null) {
      final g = File(p.join(root, routeRel(w)));
      if (await g.exists()) out.add((w.route!, g.path, false, _gpxWarning));
    }
  }
  return out;
}

String get _gpxWarning => t(
  '⚠ Sisältää GPS-reitin: se näyttää, missä liikuit (esim. kodin lähellä). Lähetä vain, jos ongelma liittyy '
  'reittiin, matkaan tai GPS:ään.',
);

class _BugReportScreenState extends State<BugReportScreen> {
  static const _channel = MethodChannel('fi.somby.gievra/email');
  String _type = 'save';
  final _desc = TextEditingController();

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  final _files = <_Attachment>[];
  bool _busy = false;
  int _shown = 3; // näytettyjä treenejä (uusimmasta alkaen)

  List<(String, String, String)> get _types => [
    ('save', '💾', t('Treeni ei tallennu tai katoaa')),
    ('import', '📥', t('Tuonti ei onnistu')),
    ('export', '📤', t('Vienti tai varmuuskopio ei onnistu')),
    ('program', '📋', t('Ohjelma tai ehdotus näyttää väärältä')),
    ('crash', '💥', t('Sovellus kaatuu tai jumittuu')),
    ('gps', '📍', t('GPS, kartat tai korkeustiedot')),
    ('health', '❤️', t('Health Connect -tuonti')),
    ('lang', '🌐', t('Käännösvirhe tai väärä kieli')),
    ('other', '💬', t('Muu ongelma tai ehdotus')),
  ];

  /// Mitä kuhunkin ongelmaan kannattaa liittää ja kertoa.
  String? get _hint => switch (_type) {
    'save' => t('Tuoreimmat treenitiedostot ovat mukana. Kerro, minkä päivän treeni katosi tai jäi tallentumatta.'),
    'import' => t(
      'Liitä tiedosto, jonka tuonti epäonnistui (Lisää tiedosto), jos siinä ei ole mitään, mitä et halua jakaa. '
      'Kerro, mistä sovelluksesta se on.',
    ),
    'export' => t('Kerro, minne yritit viedä (kansio, jakaminen) ja mikä virheilmoitus tuli. Kuvakaappaus auttaa.'),
    'program' => t('Ohjelma ja asetukset ovat mukana. Kerro, mikä ehdotus näytti väärältä ja mitä odotit.'),
    'crash' => t('Kerro, mitä teit juuri ennen ja toistuuko ongelma. Kuvakaappaus auttaa, jos sovellus jumittuu.'),
    'gps' => t(
      'Jos ongelma koskee reittiä tai matkaa, valitse lenkin GPS-reitti (.gpx) alta. Ladattujen karttojen ja '
      'korkeustietojen määrä on mukana automaattisesti, alueiden nimet eivät.',
    ),
    'health' => t('Kerro, mikä sovellus tai kello tallentaa tiedot Health Connectiin ja mitä jäi tuomatta.'),
    'lang' => t('Kirjoita väärä teksti ja oikea muoto. Lisää kuvakaappaus näkymästä.'),
    _ => null,
  };

  static const _fileTypes = ['.md', '.gpx', '.gmd', '.fitnotes', '.zip', '.csv', '.txt'];

  @override
  void initState() {
    super.initState();
    _addDefaults();
  }

  Future<void> _addDefaults() async {
    for (final (name, path, on, warning) in await defaultReportAttachments()) {
      _files.add(_Attachment(name, path, on: on, warning: warning));
    }
    if (mounted) setState(() {});
  }

  /// Näytä lisää: seuraavat 10 vanhempaa treeniä listaan valitsemattomina.
  Future<void> _more() async {
    final more = await workoutAttachments(_shown, 10, on: false);
    _shown += 10;
    // Uudet treenit treenilistan jatkoksi (ennen asetuksia ja ohjelmaa).
    var at = _files.lastIndexWhere((a) => a.name.endsWith('.gpx') || RegExp(r'^\d{4}-').hasMatch(a.name)) + 1;
    for (final (name, path, on, warning) in more) {
      if (_files.any((a) => a.path == path)) continue;
      _files.insert(at++, _Attachment(name, path, on: on, warning: warning));
    }
    if (mounted) setState(() {});
  }

  Future<void> _pick({required bool images}) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: images ? t('Valitse kuvakaappaukset') : t('Valitse tiedostot'),
      type: images ? FileType.image : FileType.any,
    );
    for (final f in picked) {
      final path = f.path;
      if (path == null) continue;
      final lower = f.name.toLowerCase();
      if (!images && !_fileTypes.any(lower.endsWith)) continue;
      _files.add(_Attachment(f.name, path, on: true, warning: lower.endsWith('.gpx') ? _gpxWarning : null));
    }
    setState(() {});
  }

  /// Kehittäjälle suomeksi: versio, laite, kieliasetukset, näyttö ja kartat. Ei sijaintia eikä alueiden nimiä.
  Future<String> _diagnostics(MediaQueryData mq) async {
    final info = await PackageInfo.fromPlatform();
    String device = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    if (Platform.isAndroid) {
      try {
        device = await _channel.invokeMethod<String>('device') ?? device;
      } catch (_) {}
    }
    var maps = '';
    try {
      final files = await MapStore.instance.installedFiles();
      final mb = files.fold<int>(0, (a, f) => a + f.$2) / 1e6;
      final elev = files.where((f) => f.$1.endsWith('.elev')).length;
      maps = 'karttatiedostoja ${files.length - elev}, korkeustiedostoja $elev, yht. ${mb.round()} Mt';
    } catch (_) {}
    return [
      '${AppInfo.name} ${info.version} (${info.buildNumber})',
      device,
      'Kieli: $uiLang · liikenimet ${settings.moveNames} · vammaohjeet ${settings.healthLang}',
      'Näyttö: ${mq.size.width.round()}×${mq.size.height.round()} dp, tekstikoko '
          '${mq.textScaler.scale(100).round()} % · teema ${settings.themeMode.name}',
      'Treenejä ${store.workouts.length} · tila ${settings.trainMode} · kansio '
          '${settings.folder == null ? 'oletus' : 'oma'} · Health Connect ${settings.hcImport ? 'päällä' : 'pois'}',
      if (maps.isNotEmpty) '$maps · korkeus karttojen kanssa ${settings.elevWithMaps ? 'kyllä' : 'ei'}',
    ].join('\n');
  }

  Future<void> _send() async {
    final mq = MediaQuery.of(context);
    setState(() => _busy = true);
    try {
      final type = _types.firstWhere((x) => x.$1 == _type);
      // Liitteet välimuistin reports/-kansioon (Androidin FileProvider jakaa vain sen).
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'reports'));
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final paths = <String>[];
      for (final a in _files.where((a) => a.on)) {
        final target = File(p.join(dir.path, a.name));
        await File(a.path).copy(target.path);
        paths.add(target.path);
      }
      // Viesti suomeksi kehittäjälle (tyyppi myös käyttäjän kielellä).
      final subject = 'Gievra: ${type.$3}';
      final body = [
        'Ongelma: ${type.$3} [${type.$1}]',
        '',
        _desc.text.trim().isEmpty ? '(ei kuvausta)' : _desc.text.trim(),
        '',
        '---',
        await _diagnostics(mq),
        if (paths.isNotEmpty) 'Liitteet: ${paths.map(p.basename).join(', ')}',
      ].join('\n');
      if (Platform.isAndroid) {
        await _channel.invokeMethod('send', {
          'to': AppInfo.feedbackEmail,
          'subject': subject,
          'body': body,
          'paths': paths,
        });
      } else {
        await SharePlus.instance.share(
          ShareParams(
            text: '${AppInfo.feedbackEmail}\n\n$body',
            subject: subject,
            files: [for (final x in paths) XFile(x)],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Virhe: {0}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(t('Ilmoita ongelmasta'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          SectionLabel(t('Mikä ei toimi?')),
          RadioGroup<String>(
            groupValue: _type,
            onChanged: (v) => setState(() => _type = v ?? _type),
            child: Column(
              children: [
                for (final (id, icon, label) in _types)
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: id,
                    title: Text('$icon  $label'),
                  ),
              ],
            ),
          ),
          if (_hint != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_hint!, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          SectionLabel(t('Mitä tapahtui?')),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: t('Esim. mitä teit, mitä odotit ja mitä tapahtui. Toistuuko ongelma?'),
              helperText: t('Voit kirjoittaa suomeksi, saameksi tai englanniksi.'),
              filled: true,
              fillColor: cs.surfaceContainer,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          SectionLabel(t('Liitteet')),
          Text(
            t(
              'Treenitiedostot auttavat selvittämään tallennus-, tuonti- ja vientiongelmia. Ne sisältävät '
              'treenisi ja muistiinpanosi: poista rasti, jos et halua lähettää jotain.',
            ),
            style: sub,
          ),
          for (final a in _files)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: a.on,
              onChanged: (v) => setState(() => a.on = v ?? false),
              title: Text(a.name),
              subtitle: a.warning == null ? null : Text(a.warning!, style: TextStyle(fontSize: 12, color: cs.error)),
              secondary: Icon(
                a.name.toLowerCase().endsWith('.md')
                    ? Icons.description_outlined
                    : a.name.toLowerCase().endsWith('.gpx')
                    ? Icons.route_outlined
                    : Icons.image_outlined,
                size: 20,
              ),
            ),
          if (store.workouts.length > _shown)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _more,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(t('Näytä vanhempia treenejä ({0} lisää)', [store.workouts.length - _shown])),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pick(images: false),
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: Text(t('Lisää tiedosto')),
              ),
              OutlinedButton.icon(
                onPressed: () => _pick(images: true),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(t('Lisää kuvakaappaus')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Ota kuvakaappaus ongelmasta (yleensä virta- ja äänenvoimakkuus alas -näppäimet yhtä aikaa) '
              'ja lisää se tästä.',
            ),
            style: sub,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send),
            label: Text(t('Avaa sähköposti ja lähetä')),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              'Viesti lähtee omasta sähköpostistasi osoitteeseen {0}. Mukana on myös sovelluksen versio, puhelimen '
              'malli ja Android-versio, kieli- ja näyttöasetukset sekä ladattujen karttojen määrä (ei sijaintia). '
              'Näet kaiken sähköpostissa, eikä mitään lähetetä ennen kuin painat siellä Lähetä.',
              [AppInfo.feedbackEmail],
            ),
            style: sub,
          ),
        ],
      ),
    );
  }
}
