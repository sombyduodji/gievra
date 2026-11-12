import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../auto_backup.dart';
import '../body.dart';
import '../daily_steps.dart';
import '../csv_export.dart';
import '../garmin_import.dart';
import '../import_detect.dart';
import '../import_export.dart';
import '../injuries.dart' show injuryById, injuryShortName;
import '../models.dart';
import '../theme.dart';
import 'bug_report.dart';
import 'program_template.dart' show importTemplate;
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

  /// Tuo tiedosto: yksi painike, tyyppi tunnistetaan sisällöstä (FitNotes, Garmin, Gievran varmuuskopio,
  /// .md-treenit, ohjelmapohja). Useampi .md-tiedosto kerralla tuodaan yhdessä.
  Future<void> _importAny() => _run(() async {
    final files = await FilePicker.pickFiles(dialogTitle: t('Valitse tuotava tiedosto'));
    if (files.isEmpty) return;
    final picked = [for (final f in files) (f.name, await f.xFile.readAsBytes())];
    final kinds = [for (final (n, b) in picked) detectImport(n, b)];
    if (picked.length > 1) {
      if (kinds.every((k) => k == ImportKind.md)) {
        await _preview(readMdBytes({for (final (n, b) in picked) n: b}));
      } else {
        _snack(t('Valitse yksi tiedosto kerrallaan (useampi vain .md-treenitiedostoina).'));
      }
      return;
    }
    final (name, bytes) = picked.single;
    switch (kinds.single) {
      case ImportKind.fitnotes:
        await _importFitnotesBytes(bytes);
      case ImportKind.garmin:
        await _importGarminText(utf8.decode(bytes, allowMalformed: true));
      case ImportKind.gievraZip:
        await _preview(readZip(bytes));
      case ImportKind.md:
        await _preview(readMdBytes({name: bytes}));
      case ImportKind.template:
        if (mounted) await importTemplate(context, text: utf8.decode(bytes, allowMalformed: true));
      case ImportKind.mapPack:
        _snack(t('Tämä on karttapaketti: tuo se Kartat-sivulla (Tuo tiedostosta).'));
      case ImportKind.gievraCsv:
        _snack(
          t('Tämä on Gievran luettava CSV-vienti, ei varmuuskopio: sitä ei voi tuoda. Käytä varmuuskopiota (.zip).'),
        );
      case ImportKind.unknown:
        _snack(
          t(
            'Tiedostoa ei tunnistettu. Tuettu: FitNotes (.fitnotes), Garmin Connect (.csv), Gievran varmuuskopio (.zip), .md-treenit ja ohjelmapohja (.gmd).',
          ),
        );
    }
  });

  Future<void> _importFitnotesBytes(List<int> bytes) async {
    // SQLite tarvitsee tiedostopolun: kopioidaan väliaikaiskansioon.
    final tmp = File(p.join((await getTemporaryDirectory()).path, 'fitnotes-import.db'));
    await tmp.writeAsBytes(bytes);
    try {
      await _preview(readFitnotes(tmp.path, translate: true));
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  Future<void> _importGarminText(String text) async {
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
  }

  /// Mikä Gievran laji vastaa toisen sovelluksen lajia [type] ([n] suoritusta)? null = ohita (ei tuoda).
  Future<String?> _askSport(String type, int n) =>
      pickSport(context, t('Gievra ei tunnista lajia "{0}" ({1} suoritusta). Valitse lähin laji:', [type, n]));

  Future<void> _importZip() => _run(() async {
    final f = await _pick(['zip']);
    if (f == null) return;
    await _preview(readZip(await f.xFile.readAsBytes()));
  });

  Future<void> _export() => _run(() async {
    final bytes = await exportZip();
    final uri = await FilePicker.saveFile(
      fileName: 'gievra-${isoDate(DateTime.now())}.zip',
      bytes: bytes,
      mimeType: 'application/zip',
      dialogTitle: t('Tallenna varmuuskopio'),
    );
    if (uri == null) return;
    // Oma täysi varmuuskopio korvaa sovelluksen automaattiset (backup/-kansio).
    await autoBackup.deleteAll();
    if (mounted) _snack(t('Varmuuskopio tallennettu ({0} treeniä).', [store.workouts.length]));
  });

  /// Luettava vienti (CSV) käyttäjän kielellä: käyttäjä valitsee, mitä jaetaan ja miltä ajalta.
  Future<void> _exportCsv() async {
    final today = dateOnly(DateTime.now());
    var period = 90; // päiviä; 0 = kaikki, -1 = oma aikaväli
    DateTimeRange? custom;
    var gym = true, cardio = true, body = false, notes = false, steps = false;
    final hasBody = settings.body.weights.isNotEmpty;
    // Askeleet valittavissa, kun päivän askeleet ovat päällä tai niitä on tallennettu (luettu käynnistyessä).
    final hasSteps = settings.dailySteps || dailySteps.days.isNotEmpty;
    DateTime from() => switch (period) {
      0 => DateTime(1900),
      -1 => custom?.start ?? today,
      _ => today.subtract(Duration(days: period - 1)),
    };
    DateTime to() => period == -1 ? custom?.end ?? today : today;
    CsvExportOptions opts() => CsvExportOptions(
      from: from(),
      to: to(),
      gym: gym,
      cardio: cardio,
      body: body && hasBody,
      notes: notes,
      steps: steps && hasSteps,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final files = buildCsvExport(store.workouts, settings.body, opts(), steps: dailySteps.days);
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            scrollable: true,
            title: Text(t('Vie luettavaksi tai taulukkoon')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Sami.yellow.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    t(
                      '⚠️ Tämä on luettava vienti käyttöliittymän kielellä (CSV: Excel, LibreOffice, Google Sheets, '
                      'valmentaja tai toinen sovellus), ei varmuuskopio. Siirtoon toiseen puhelimeen ja palautukseen '
                      'käytä varmuuskopiota (.zip).',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 10),
                Text(t('Aikaväli'), style: const TextStyle(fontWeight: FontWeight.w600)),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final (d, l) in [
                      (30, t('30 päivää')),
                      (90, t('90 päivää')),
                      (365, t('12 kuukautta')),
                      (0, t('Kaikki')),
                    ])
                      ChoiceChip(label: Text(l), selected: period == d, onSelected: (_) => setDialog(() => period = d)),
                    ChoiceChip(
                      label: Text(
                        period == -1 && custom != null
                            ? '${shortDate(custom!.start)} – ${shortDate(custom!.end)}'
                            : t('Valitse päivät'),
                      ),
                      selected: period == -1,
                      onSelected: (_) async {
                        final r = await showDateRangePicker(
                          context: ctx,
                          firstDate: DateTime(2000),
                          lastDate: today,
                          initialDateRange: custom,
                        );
                        if (r != null) setDialog(() => (period, custom) = (-1, r));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(t('Mitä viedään'), style: const TextStyle(fontWeight: FontWeight.w600)),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: gym,
                  onChanged: (v) => setDialog(() => gym = v ?? false),
                  title: Text(t('Salitreenit: sarjat, painot ja toistot')),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: cardio,
                  onChanged: (v) => setDialog(() => cardio = v ?? false),
                  title: Text(t('Liikunta: laji, kesto, matka, vauhti, syke')),
                ),
                if (hasBody)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: body,
                    onChanged: (v) => setDialog(() => body = v ?? false),
                    title: Text(t('Punnitukset ja pituus')),
                    subtitle: Text(t('Terveystietoa: jaa harkiten.'), style: TextStyle(color: cs.error)),
                  ),
                if (hasSteps)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: steps,
                    onChanged: (v) => setDialog(() => steps = v ?? false),
                    title: Text(t('Päivän askeleet')),
                    subtitle: Text(t('Terveystietoa: jaa harkiten.'), style: TextStyle(color: cs.error)),
                  ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: notes,
                  onChanged: (v) => setDialog(() => notes = v ?? false),
                  title: Text(t('Muistiinpanot')),
                  subtitle: Text(t('Omat tekstisi treeneistä: voivat olla yksityisiä.')),
                ),
                const SizedBox(height: 6),
                Text(
                  files.isEmpty
                      ? t('Valitulla aikavälillä ei ole vietävää.')
                      : files.map((f) => t('{0}: {1} riviä', [f.name, f.rows])).join('\n'),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
              FilledButton(onPressed: files.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(t('Vie'))),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final files = buildCsvExport(store.workouts, settings.body, opts(), steps: dailySteps.days);
      final stamp = isoDate(today);
      final (name, bytes) = files.length == 1
          ? ('gievra-${files.single.name.replaceAll('.csv', '')}-$stamp.csv', utf8.encode(files.single.text))
          : ('gievra-csv-$stamp.zip', csvZip(files));
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List.fromList(bytes),
        dialogTitle: t('Tallenna vienti'),
      );
      if (uri != null && mounted) _snack(t('Vienti tallennettu.'));
    });
  }

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

  /// Testeille: tuonnin yhteenveto ilman tiedostovalitsinta.
  @visibleForTesting
  Future<void> previewForTest(ImportResult r) => _preview(r);

  Future<void> _preview(ImportResult r) async {
    if (!mounted) return;
    if (r.workouts.isEmpty && r.bodyMd == null && r.stepsMd == null && r.unreadable.isEmpty) {
      _snack(t('Tiedostosta ei löytynyt treenejä.'));
      return;
    }
    final cs = Theme.of(context).colorScheme;
    final newCount = r.workouts.length - r.existing;
    // Punnitukset: uusia ovat päivät, joilta Gievrassa ei vielä ole punnitusta (olemassa olevat säilyvät).
    final weighIns = r.bodyMd == null ? const <DateTime, double>{} : parseBody(r.bodyMd!).weights;
    final newWeighIns = weighIns.keys.where((d) => !settings.body.weights.containsKey(d)).length;
    var enableTracker = !settings.bodyTracker && newWeighIns > 0;
    // Askelpäivät: uusia ovat päivät, joita tällä laitteella ei vielä ole (olemassa olevat säilyvät).
    final stepDays = r.stepsMd == null ? const <DateTime, int>{} : parseSteps(r.stepsMd!).$1;
    final newStepDays = stepDays.keys.where((d) => !dailySteps.days.containsKey(d)).length;
    // Vammatila ei tule yhdistettäessä itsestään (vanha vamma voi olla jo parantunut): oletuksena pois.
    final injuries = newInjuries(r);
    var enableInjuries = false;
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
              // Päivän askeleet (askeleet.md): puuttuvat päivät lisätään, tämän laitteen luvut pysyvät.
              if (r.stepsMd != null)
                _row(
                  t('Askelpäiviä'),
                  newStepDays == stepDays.length
                      ? '${stepDays.length}'
                      : t('{0} (uusia {1})', [stepDays.length, newStepDays]),
                ),
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
              if (injuries.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: enableInjuries,
                  onChanged: (v) => setDialog(() => enableInjuries = v ?? false),
                  title: Text(t('Ota vammatila käyttöön')),
                  subtitle: Text(
                    t('Varmuuskopiossa: {0}. Valitse vain, jos vaiva on yhä ajankohtainen.', [
                      {for (final id in injuries) injuryShortName(t(injuryById(id)!.name))}.join(', '),
                    ]),
                  ),
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
              // Väärä merkistö luettiin korjattuna; lukukelvottomat voi lähettää ongelmaraporttina.
              if (r.repaired > 0) _row(t('Merkistö korjattu'), '${r.repaired}'),
              if (r.unreadable.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  t('Treenitiedostoja ei voitu lukea: {0}', [r.unreadable.length]),
                  style: TextStyle(color: redText(context), fontWeight: FontWeight.w600),
                ),
                for (final e in r.unreadableWhy.entries.take(8))
                  Text('${e.key}: ${e.value}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                if (r.unreadable.length > 8) Text('…', style: TextStyle(color: cs.onSurfaceVariant)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _reportUnreadable(r),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: Text(t('Lähetä ongelmaraportti')),
                  ),
                ),
              ],
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
              if (newStepDays > 0) Text(t('Lisäksi {0} askelpäivää.', [newStepDays])),
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
            // Tuotavaa on, jos on uusia treenejä, punnituksia tai askelpäiviä (esim. FitNotes-tuonti uudelleen
            // punnitusten takia tai varmuuskopio, josta tulee vain askeleita).
            FilledButton(
              onPressed: newCount == 0 && newWeighIns == 0 && newStepDays == 0 ? null : () => Navigator.pop(ctx, true),
              child: Text(t('Tuo')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = await applyImport(r, addInjuries: enableInjuries);
    if (enableTracker) settings.setBodyTracker(true);
    if (mounted) {
      _snack(
        newWeighIns > 0
            ? t('Tuotiin {0} treeniä ja {1} punnitusta. Giitu!', [n, newWeighIns])
            : t('Tuotiin {0} treeniä. Giitu!', [n]),
      );
    }
  }

  /// Lukukelvottomat tiedostot sellaisinaan (alkuperäiset tavut) ongelmaraportin liitteiksi.
  Future<void> _reportUnreadable(ImportResult r) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'unreadable'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final attach = <(String, String)>[];
    for (final e in r.unreadable.entries) {
      final f = File(p.join(dir.path, p.basename(e.key)));
      await f.writeAsBytes(e.value);
      attach.add((p.basename(e.key), f.path));
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BugReportScreen(
          type: 'import',
          attach: attach,
          description: t('Treenitiedostoja ei voitu lukea: {0}', [
            [for (final e in r.unreadableWhy.entries) '${e.key} (${e.value})'].join('; '),
          ]),
        ),
      ),
    );
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
      appBar: AppBar(title: Text(t('Tuonti, vienti ja varmuuskopio'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          // Aina paikallaan (tyhjänä, kun ei käynnissä): listaan lisätty rivi siirtäisi painikkeita, jolloin
          // napautuksen korostus välähtäisi väärässä painikkeessa.
          SizedBox(height: 4, child: _busy ? const LinearProgressIndicator() : null),
          SectionLabel(t('Tuo')),
          tile(
            Icons.file_open_outlined,
            t('Tuo tiedosto'),
            t(
              'Sovellus tunnistaa tiedoston itse: FitNotes (.fitnotes, FitNotes: Asetukset → Varmuuskopio), '
              'Garmin Connect (.csv, Suoritukset → Vie CSV), Gievran varmuuskopio (.zip), .md-treenit tai '
              'ohjelmapohja (.gmd). Olemassa olevia päiviä ei ylikirjoiteta.',
            ),
            _importAny,
          ),
          SectionLabel(t('Gievran varmuuskopio')),
          tile(
            Icons.archive_outlined,
            t('Vie varmuuskopio (.zip)'),
            t(
              'Kaikki treenit, reitit (.gpx), asetukset, ohjelma, punnitukset, askeleet ja tallennetut ohjelmat yhdessä zip-tiedostossa.',
            ),
            _export,
          ),
          tile(
            Icons.unarchive_outlined,
            t('Palauta varmuuskopiosta (.zip)'),
            t('Tuo treenit zipistä. Olemassa olevia päiviä ei ylikirjoiteta.'),
            _importZip,
          ),
          SectionLabel(t('Vie')),
          tile(
            Icons.table_chart_outlined,
            t('Vie luettavaksi tai taulukkoon (CSV)'),
            t('Valitse, mitä jaetaan ja miltä ajalta. Käyttöliittymän kielellä; ei varmuuskopio.'),
            _exportCsv,
          ),
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
