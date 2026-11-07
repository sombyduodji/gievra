import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../program.dart';

/// Ohjelmapohjan (.gmd) tallennus: nimi ja tekijä valinnaisia; maksimit ja aloituspäivä jäävät pois.
Future<void> exportTemplate(BuildContext context, Program p) async {
  final name = TextEditingController(text: p.displayTitle.split(' · ').first);
  final author = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Tallenna ohjelmapohja')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              'Ohjelmapohja (.gmd) on tavallinen tekstitiedosto, jonka voi lähettää toiselle. Siinä ovat päivät, '
              'liikkeet, sarjat ja toistot, ei maksimeja, treenejä eikä aloituspäivää.',
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: t('Ohjelman nimi')),
          ),
          TextField(
            controller: author,
            decoration: InputDecoration(labelText: t('Tekijä (vapaaehtoinen)')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Tallenna'))),
      ],
    ),
  );
  if (ok != true) return;
  final text = programToTemplate(p, name: name.text, author: author.text);
  final base = name.text.trim().isEmpty ? 'ohjelma' : name.text.trim().replaceAll(RegExp(r'[^\w\-äöåÄÖÅ ]'), '');
  final saved = await FilePicker.saveFile(
    dialogTitle: t('Tallenna ohjelmapohja'),
    fileName: '$base.$templateExtension',
    bytes: Uint8List.fromList(utf8.encode(text)),
  );
  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Ohjelmapohja tallennettu.'))));
  }
}

/// Ohjelmapohjan tuonti tiedostosta tai (Androidilla) "Avaa sovelluksella" -toiminnosta saadusta tekstistä.
/// Palauttaa true, jos pohja otettiin käyttöön.
/// [activate] false: pohja tallennetaan vain ohjelmaluetteloon (☰ → Asetukset → Ohjelmat).
Future<bool> importTemplate(BuildContext context, {String? text, bool activate = true}) async {
  if (text == null) {
    final files = await FilePicker.pickFiles(dialogTitle: t('Valitse ohjelmapohja (.gmd)'));
    if (files.isEmpty) return false;
    text = utf8.decode(await files.first.xFile.readAsBytes(), allowMalformed: true);
  }
  final p = looksLikeProgram(text) ? parseProgram(text) : null;
  if (!context.mounted) return false;
  if (p == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Tiedosto ei ole Gievran ohjelmapohja.'))));
    return false;
  }
  final meta = {
    for (final m in RegExp(r'^(name|author): (.+)$', multiLine: true).allMatches(text)) m[1]!: m[2]!.trim(),
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(meta['name'] ?? p.displayTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta['author'] != null) Text(t('Tekijä: {0}', [meta['author']])),
          Text(p.displayTitle, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          for (final d in p.plan) ...[
            Text(d.uiName, style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final i in d.items)
              Text(
                '  ${i.exercise}  ${switch (i.kind) {
                  'H' => t('raskas, viikon mukaan'),
                  'V' => t('volyymi, viikon mukaan'),
                  _ => '${i.sets} × ${i.lo == i.hi ? i.lo : '${i.lo}–${i.hi}'}',
                }}',
              ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 6),
          Text(
            !activate
                ? t('Pohja lisätään tallennettuihin ohjelmiin.')
                : settings.program == null
                ? t('Ohjelma otetaan käyttöön tänään.')
                : t('Nykyinen ohjelma korvataan tällä. Arvioidut maksimit säilyvät.'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Ota käyttöön'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  if (!activate) {
    await saveProgramAs(p, meta['name'] ?? p.displayTitle.split(' · ').first);
    return true;
  }
  if (!await askSaveCurrent(context)) return false;
  // Omat maksimit säilyvät (pohjassa niitä ei ole).
  if (settings.program != null) p.maxes = {...settings.program!.maxes, ...p.maxes};
  await settings.setProgram(p);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Ohjelmapohja otettu käyttöön.'))));
  }
  return true;
}

/// Tallennetut ohjelmat treenikansion ohjelmat/-kansiossa (.gmd). Treenit eivät muutu ohjelmaa vaihdettaessa.
const savedProgramsDir = 'ohjelmat';

String _safeName(String s) {
  final n = s.trim().replaceAll(RegExp(r'[^\w\-äöåÄÖÅ ]'), '').trim();
  return n.isEmpty ? 'ohjelma' : n;
}

/// Ennen ohjelman vaihtoa: tallennetaanko nykyinen myöhempää käyttöä varten? false = peruttiin.
Future<bool> askSaveCurrent(BuildContext context) async {
  final cur = settings.program;
  if (cur == null) return true;
  final name = TextEditingController(text: cur.displayTitle.split(' · ').first);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Tallennetaanko nykyinen ohjelma?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              'Voit vaihtaa siihen myöhemmin takaisin: ☰ → Ohjelma ja tavoitteet → Tallennetut ohjelmat. '
              'Treenisi säilyvät joka tapauksessa.',
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: t('Ohjelman nimi')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text(t('Peruuta'))),
        TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: Text(t('Älä tallenna'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(t('Tallenna'))),
      ],
    ),
  );
  if (r == null || r == 'cancel') return false;
  if (r == 'save') await saveProgramAs(cur, name.text);
  return true;
}

/// Tallentaa ohjelman nimellä (koko ohjelma maksimeineen ja aloituspäivineen, jotta viikot jatkuvat).
Future<void> saveProgramAs(Program p, String name) async {
  final md = programToMarkdown(p).replaceFirst('---\n', '---\nname: ${name.trim()}\n');
  await files.write('$savedProgramsDir/${_safeName(name)}.$templateExtension', md);
}

/// Tallennetut ohjelmat: (polku, nimi, ohjelma).
Future<List<(String, String, Program)>> savedPrograms() async {
  final out = <(String, String, Program)>[];
  for (final e in (await files.all()).entries) {
    if (!e.key.startsWith('$savedProgramsDir/') || !e.key.endsWith('.$templateExtension')) continue;
    final p = parseProgram(e.value);
    if (p == null) continue;
    final name =
        RegExp(r'^name: (.+)$', multiLine: true).firstMatch(e.value)?[1]?.trim() ??
        e.key.split('/').last.replaceAll('.$templateExtension', '');
    out.add((e.key, name, p));
  }
  out.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
  return out;
}

/// Vaihtaa tallennettuun ohjelmaan (kysyy ensin nykyisen tallennuksen).
Future<void> switchToSaved(BuildContext context, String path, Program p) async {
  if (!await askSaveCurrent(context)) return;
  await settings.setProgram(p);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Ohjelma vaihdettu. Treenisi säilyivät.'))));
  }
}
