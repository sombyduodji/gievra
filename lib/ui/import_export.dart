import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../body.dart';
import '../garmin_import.dart';
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

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) _snack(t('Virhe: {0}', [errorText(e)]));
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
      await _preview(readFitnotes(tmp.path, translate: true));
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  });

  Future<void> _importGarmin() => _run(() async {
    final files = await FilePicker.pickFiles(dialogTitle: t('Valitse Garmin Connectin CSV-tiedosto'));
    final f = files.firstOrNull;
    if (f == null) return;
    final text = utf8.decode(await f.xFile.readAsBytes(), allowMalformed: true);
    // Tunnistamattomat lajit: käyttäjä valitsee parin (tai ohittaa), ei arvata.
    final choices = <String, String?>{};
    for (final (type, n) in garminUnknownTypes(text)) {
      if (!mounted) return;
      choices[type.toLowerCase()] = await _askSport(type, n);
    }
    final (r, skipped) = readGarminCsv(text, store.workouts, choices: choices);
    if (r.workouts.isEmpty) {
      _snack(t('Tiedostosta ei löytynyt Garmin-suorituksia. Vie CSV Garmin Connectin Suoritukset-sivulta.'));
      return;
    }
    if (skipped > 0) _snack(t('Ohitettiin {0} voimaharjoittelua: salitreenit kirjataan Gievrassa.', [skipped]));
    // Liikunta näkyviin, jos se on asetuksista pois.
    if (!settings.sports) settings.setSports(true);
    if (!settings.watch && r.workouts.any((w) => w.hrAvg != null || w.kcal != null)) settings.setWatch(true);
    await _preview(r);
  });

  /// Mikä Gievran laji vastaa toisen sovelluksen lajia [type] ([n] suoritusta)? null = ohita (ei tuoda).
  Future<String?> _askSport(String type, int n) =>
      pickSport(context, t('Gievra ei tunnista lajia "{0}" ({1} suoritusta). Valitse lähin laji:', [type, n]));

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
    if (r.workouts.isEmpty && r.bodyMd == null) {
      _snack(t('Tiedostosta ei löytynyt treenejä.'));
      return;
    }
    final cs = Theme.of(context).colorScheme;
    final newCount = r.workouts.length - r.existing;
    // Punnitukset: uusia ovat päivät, joilta Gievrassa ei vielä ole punnitusta (olemassa olevat säilyvät).
    final weighIns = r.bodyMd == null ? const <DateTime, double>{} : parseBody(r.bodyMd!).weights;
    final newWeighIns = weighIns.keys.where((d) => !settings.body.weights.containsKey(d)).length;
    var enableTracker = !settings.bodyTracker && newWeighIns > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          scrollable: true,
          title: Text(t('Tuo: {0}', [r.source])),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(t('Treenipäiviä'), '${r.workouts.length}'),
              if (r.sets > 0 || r.workouts.every((w) => w.activity == null)) _row(t('Sarjoja'), '${r.sets}'),
              if (r.workouts.any((w) => w.activity != null))
                _row(
                  t('Liikuntaa'),
                  '${r.workouts.where((w) => w.activity != null).length} · '
                  '${fmtNum((r.workouts.fold<double>(0, (a, w) => a + (w.distanceKm ?? 0)) * 10).round() / 10)} km',
                ),
              if (r.first != null) _row(t('Aikaväli'), '${isoDate(r.first!)} – ${isoDate(r.last!)}'),
              // Punnitukset (kaikki päivät) kehonpaino.md:hen; vanha laskuri vain, jos punnituksia ei ole erikseen.
              if (r.bodyMd != null)
                _row(
                  t('Punnituksia'),
                  newWeighIns == weighIns.length
                      ? '${weighIns.length}'
                      : t('{0} (uusia {1})', [weighIns.length, newWeighIns]),
                )
              else if (r.bodyweights > 0)
                _row(t('Kehonpainoja'), '${r.bodyweights}'),
              if (!settings.bodyTracker && newWeighIns > 0)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: enableTracker,
                  onChanged: (v) => setDialog(() => enableTracker = v ?? false),
                  title: Text(t('Ota kehonpainon seuranta käyttöön')),
                  subtitle: Text(t('Paino ja painoindeksi tilastoissa, tämän päivän paino etusivulla.')),
                ),
              if (r.cardioNotes > 0) _row(t('Kardio/aika muistiinpanoihin'), '${r.cardioNotes}'),
              if (r.newExercises.isNotEmpty) _row(t('Uusia omia liikkeitä'), '${r.newExercises.length}'),
              if (r.settingsMd != null) _row(t('Asetukset'), restoresAll(r) ? t('palautetaan') : t('yhdistetään')),
              if (r.programMd != null)
                _row(
                  t('Ohjelma'),
                  restoresAll(r) ? t('palautetaan') : (settings.program == null ? t('tuodaan') : t('nykyinen säilyy')),
                ),
              if (r.savedPrograms.isNotEmpty) _row(t('Tallennetut ohjelmat'), '${r.savedPrograms.length}'),
              const SizedBox(height: 10),
              if (r.existing > 0)
                Text(
                  t('{0} päivää on jo päiväkirjassa. Niitä ei muuteta.', [r.existing]),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              Text(
                newWeighIns > 0
                    ? t('Tuodaan {0} uutta treeniä ja {1} punnitusta.', [newCount, newWeighIns])
                    : t('Tuodaan {0} uutta treeniä.', [newCount]),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
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
            // Tuotavaa on, jos on uusia treenejä tai uusia punnituksia (esim. FitNotes-tuonti uudelleen punnitusten takia).
            FilledButton(
              onPressed: newCount == 0 && newWeighIns == 0 ? null : () => Navigator.pop(ctx, true),
              child: Text(t('Tuo')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = await applyImport(r);
    if (enableTracker) settings.setBodyTracker(true);
    if (mounted) {
      _snack(
        newWeighIns > 0
            ? t('Tuotiin {0} treeniä ja {1} punnitusta. Giitu!', [n, newWeighIns])
            : t('Tuotiin {0} treeniä. Giitu!', [n]),
      );
    }
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
          // Aina paikallaan (tyhjänä, kun ei käynnissä): listaan lisätty rivi siirtäisi painikkeita, jolloin
          // napautuksen korostus välähtäisi väärässä painikkeessa.
          SizedBox(height: 4, child: _busy ? const LinearProgressIndicator() : null),
          SectionLabel(t('Tuo toisesta sovelluksesta')),
          tile(
            Icons.fitness_center,
            t('FitNotes'),
            t(
              'Varmuuskopio (.fitnotes). FitNotes: Asetukset → Varmuuskopio. Tunnetut liikkeet yhdistyvät Gievran liikkeisiin.',
            ),
            _importFitnotes,
          ),
          tile(
            Icons.watch_outlined,
            t('Garmin Connect (.csv)'),
            t(
              'Garmin Connect → Suoritukset → Vie CSV. Juoksut, kävelyt, pyöräily ym.: matka, kesto, kalorit ja '
              'syke; nousu ja askeltiheys muistiinpanoihin.',
            ),
            _importGarmin,
          ),
          SectionLabel(t('Gievran varmuuskopio')),
          tile(
            Icons.archive_outlined,
            t('Vie varmuuskopio (.zip)'),
            t('Kaikki .md-tiedostot, reitit (.gpx) ja asetukset.md yhdessä zip-tiedostossa.'),
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
