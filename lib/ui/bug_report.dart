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
  final bool sensitive; // terveystietoa (punnitukset): varoitus ja oletuksena pois
  _Attachment(this.name, this.path, {this.on = true, this.sensitive = false});
}

class _BugReportScreenState extends State<BugReportScreen> {
  static const _channel = MethodChannel('fi.somby.gievra/email');
  String _type = 'save';
  final _desc = TextEditingController();
  final _files = <_Attachment>[];
  bool _busy = false;

  List<(String, String, String)> get _types => [
    ('save', '💾', t('Treeni ei tallennu tai katoaa')),
    ('import', '📥', t('Tuonti ei onnistu')),
    ('export', '📤', t('Vienti tai varmuuskopio ei onnistu')),
    ('program', '📋', t('Ohjelma tai ehdotus näyttää väärältä')),
    ('crash', '💥', t('Sovellus kaatuu tai jumittuu')),
    ('other', '💬', t('Muu ongelma tai ehdotus')),
  ];

  @override
  void initState() {
    super.initState();
    _addDefaults();
  }

  /// Oletusliitteet: kolme viimeisintä treeniä sekä asetukset ja ohjelma, jos ne ovat olemassa.
  Future<void> _addDefaults() async {
    final root = (await store.rootDir()).path;
    final recent = [...store.workouts]..sort((a, b) => b.date.compareTo(a.date));
    for (final w in recent.take(3)) {
      final rel = workoutPath(w.date, w.session);
      final f = File(p.join(root, rel));
      if (await f.exists()) _files.add(_Attachment(p.basename(rel), f.path));
    }
    for (final n in ['asetukset.md', 'ohjelma.md']) {
      final f = File(p.join(root, n));
      if (await f.exists()) _files.add(_Attachment(n, f.path));
    }
    // Punnitukset ovat terveystietoa: mukana valittavana, mutta oletuksena pois ja varoituksen kera.
    final body = File(p.join(root, bodyFileName));
    if (await body.exists()) _files.add(_Attachment(bodyFileName, body.path, on: false, sensitive: true));
    if (mounted) setState(() {});
  }

  Future<void> _pick({required bool images}) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: images ? t('Valitse kuvakaappaukset') : t('Valitse .md-tiedostot'),
      type: images ? FileType.image : FileType.any,
    );
    for (final f in picked) {
      final path = f.path;
      if (path == null) continue;
      if (!images && !f.name.toLowerCase().endsWith('.md')) continue;
      _files.add(_Attachment(f.name, path));
    }
    setState(() {});
  }

  Future<String> _diagnostics() async {
    final info = await PackageInfo.fromPlatform();
    return [
      '${AppInfo.name} ${info.version} (${info.buildNumber})',
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'UI: $uiLang · treenejä ${store.workouts.length} · kansio ${settings.folder == null ? 'oletus' : 'oma'}',
    ].join('\n');
  }

  Future<void> _send() async {
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
        await _diagnostics(),
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
          SectionLabel(t('Mitä tapahtui?')),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: t('Esim. mitä teit, mitä odotit ja mitä tapahtui. Toistuuko ongelma?'),
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
              subtitle: a.sensitive
                  ? Text(
                      t(
                        '⚠ Sisältää punnituksesi ja pituutesi (terveystietoa). Lähetä vain, jos ongelma liittyy painoon.',
                      ),
                      style: TextStyle(fontSize: 12, color: cs.error),
                    )
                  : null,
              secondary: Icon(
                a.name.toLowerCase().endsWith('.md') ? Icons.description_outlined : Icons.image_outlined,
                size: 20,
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pick(images: false),
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: Text(t('Lisää .md-tiedosto')),
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
              'Viesti lähtee omasta sähköpostistasi osoitteeseen {0}. Mukana on myös sovelluksen versio ja '
              'puhelimen käyttöjärjestelmä. Mitään ei lähetetä ennen kuin painat sähköpostissa Lähetä.',
              [AppInfo.feedbackEmail],
            ),
            style: sub,
          ),
        ],
      ),
    );
  }
}
