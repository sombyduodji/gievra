import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../import_export.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Tuonti muista sovelluksista ja oma varmuuskopio (zip .md-tiedostoista).
class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});
  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  bool _busy = false;
  bool _translate = true;

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) _snack(t('Virhe: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PlatformFile?> _pick(List<String> ext) async {
    final files = await FilePicker.pickFiles(dialogTitle: t('Valitse tiedosto'));
    if (files.isEmpty) return null;
    final f = files.first;
    final e = (f.extension ?? '').toLowerCase().replaceAll('.', '');
    if (!ext.contains(e)) {
      _snack(t('Odotettiin tiedostoa: {0}', [ext.map((x) => '.$x').join(' / ')]));
      return null;
    }
    return f;
  }

  Future<void> _importFitnotes() => _run(() async {
    final f = await _pick(['fitnotes', 'db', 'sqlite']);
    if (f == null) return;
    // SQLite tarvitsee tiedostopolun: kopioidaan väliaikaiskansioon.
    final tmp = File(p.join((await getTemporaryDirectory()).path, 'fitnotes-import.db'));
    await tmp.writeAsBytes(await f.xFile.readAsBytes());
    try {
      await _preview(readFitnotes(tmp.path, translate: _translate));
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  });

  Future<void> _importZip() => _run(() async {
    final f = await _pick(['zip']);
    if (f == null) return;
    await _preview(readZip(await f.xFile.readAsBytes()));
  });

  Future<void> _importMd() => _run(() async {
    final files = await FilePicker.pickFiles(dialogTitle: t('Valitse .md-tiedostot'));
    final texts = <String, String>{};
    for (final f in files) {
      if ((f.extension ?? '').toLowerCase().replaceAll('.', '') != 'md') continue;
      texts[f.name] = utf8.decode(await f.xFile.readAsBytes(), allowMalformed: true);
    }
    if (texts.isEmpty) {
      if (files.isNotEmpty) _snack(t('Valitse .md-tiedostoja'));
      return;
    }
    await _preview(readMdFiles(texts));
  });

  Future<void> _export() => _run(() async {
    final bytes = await exportZip();
    final uri = await FilePicker.saveFile(
      fileName: 'gievra-${isoDate(DateTime.now())}.zip',
      bytes: bytes,
      mimeType: 'application/zip',
      dialogTitle: t('Tallenna varmuuskopio'),
    );
    if (uri != null && mounted) _snack(t('Varmuuskopio tallennettu ({0} treeniä).', [store.workouts.length]));
  });

  Future<void> _exportFitnotes() => _run(() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Vie FitNotes-muotoon (kokeellinen)')),
        content: Text(
          t(
            'Tekee FitNotes-varmuuskopion, jonka voi palauttaa FitNotesissa (Asetukset → Varmuuskopio '
            '→ Palauta). Palautus korvaa FitNotesin nykyiset tiedot. Suomennetut liikkeet saavat '
            'takaisin englanninkieliset nimensä. Muistiinpanot ja lämmittely tallentuvat '
            'treenikommentteihin, kehonpaino mittauksiin.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Vie'))),
        ],
      ),
    );
    if (ok != true) return;
    final tmp = p.join((await getTemporaryDirectory()).path, 'FitNotes_Backup.fitnotes');
    final sets = writeFitnotes(tmp, store.workouts);
    final file = File(tmp);
    final uri = await FilePicker.saveFile(
      fileName: 'FitNotes_Backup_${isoDate(DateTime.now())}.fitnotes',
      bytes: await file.readAsBytes(),
      dialogTitle: t('Tallenna FitNotes-varmuuskopio'),
    );
    await file.delete();
    if (uri != null && mounted) _snack(t('Viety {0} treeniä, {1} sarjaa.', [store.workouts.length, sets]));
  });

  Future<void> _preview(ImportResult r) async {
    if (!mounted) return;
    if (r.workouts.isEmpty) {
      _snack(t('Tiedostosta ei löytynyt treenejä.'));
      return;
    }
    final cs = Theme.of(context).colorScheme;
    final newCount = r.workouts.length - r.existing;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(t('Tuo: {0}', [r.source])),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(t('Treenipäiviä'), '${r.workouts.length}'),
            _row(t('Sarjoja'), '${r.sets}'),
            _row(t('Aikaväli'), '${isoDate(r.first!)} – ${isoDate(r.last!)}'),
            if (r.bodyweights > 0) _row(t('Kehonpainoja'), '${r.bodyweights}'),
            if (r.cardioNotes > 0) _row(t('Kardio/aika muistiinpanoihin'), '${r.cardioNotes}'),
            if (r.newExercises.isNotEmpty) _row(t('Uusia omia liikkeitä'), '${r.newExercises.length}'),
            if (r.settingsMd != null) _row(t('Asetukset'), t('yhdistetään')),
            if (r.programMd != null) _row(t('Ohjelma'), settings.program == null ? t('tuodaan') : t('nykyinen säilyy')),
            const SizedBox(height: 10),
            if (r.existing > 0)
              Text(
                t('{0} päivää on jo päiväkirjassa. Niitä ei muuteta.', [r.existing]),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            Text(t('Tuodaan {0} uutta treeniä.', [newCount]), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (r.newExercises.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                t('Omat liikkeet: {0}', [
                  '${r.newExercises.keys.take(12).join(', ')}${r.newExercises.length > 12 ? '…' : ''}',
                ]),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: newCount == 0 ? null : () => Navigator.pop(ctx, true), child: Text(t('Tuo'))),
        ],
      ),
    );
    if (ok != true) return;
    final n = await applyImport(r);
    if (mounted) _snack(t('Tuotiin {0} treeniä. Giitu!', [n]));
  }

  Widget _row(String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(a)),
        Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tile(IconData i, String t, String s, VoidCallback f) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Icon(i),
          title: Text(t),
          subtitle: Text(s, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          onTap: _busy ? null : f,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t('Tuonti ja varmuuskopio'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          if (_busy) const LinearProgressIndicator(),
          SectionLabel(t('Tuo toisesta sovelluksesta')),
          tile(
            Icons.fitness_center,
            t('FitNotes'),
            t('Varmuuskopio (.fitnotes). FitNotes: Asetukset → Varmuuskopio.'),
            _importFitnotes,
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(t('Suomenna tunnetut liikkeet')),
            subtitle: Text(
              t('esim. Barbell Squat → Takakyykky. Muut säilyttävät nimensä omina liikkeinä.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            value: _translate,
            onChanged: (v) => setState(() => _translate = v),
          ),
          Text(
            t('Tulossa myöhemmin: Strong, Hevy ja FitNotesin CSV-vienti.'),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          SectionLabel(t('Gievran varmuuskopio')),
          if (!syncReleased)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
              child: Text(
                t(
                  '☁️ Google Drive -synkronointi on tulossa, mutta sitä ei ole vielä julkaistu. Siihen asti '
                  'siirrä treenit laitteelta toiselle varmuuskopiolla: vie zip täältä ja palauta se toisella '
                  'laitteella.',
                ),
                style: TextStyle(fontSize: 13),
              ),
            ),
          tile(
            Icons.archive_outlined,
            t('Vie varmuuskopio (.zip)'),
            t('Kaikki .md-tiedostot ja asetukset.md yhdessä zip-tiedostossa.'),
            _export,
          ),
          tile(
            Icons.unarchive_outlined,
            t('Palauta varmuuskopiosta (.zip)'),
            t('Tuo treenit zipistä. Olemassa olevia päiviä ei ylikirjoiteta.'),
            _importZip,
          ),
          tile(
            Icons.note_add_outlined,
            t('Tuo .md-tiedostoja'),
            t(
              'Yksi tai useampi treenitiedosto, esim. PC:llä tehty tai muokattu treeni. Olemassa olevia '
              'päiviä ei ylikirjoiteta.',
            ),
            _importMd,
          ),
          SectionLabel(t('Vie toiseen sovellukseen')),
          tile(
            Icons.science_outlined,
            t('FitNotes (.fitnotes) – kokeellinen'),
            t('Jos haluat palata FitNotesiin. Palautetaan FitNotesin varmuuskopiotoiminnolla.'),
            _exportFitnotes,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.sync, size: 16, color: Sami.green),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t(
                    'Synkattu kansio (Nextcloud, Seafile…) on jo itsessään varmuuskopio: tiedostot ovat '
                    'tavallisia .md-tiedostoja.',
                  ),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
