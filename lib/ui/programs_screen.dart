import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../program.dart';
import 'program_template.dart';
import '../theme.dart';
import 'widgets.dart';

/// ☰ → Asetukset → Ohjelmat: tallennetut ohjelmat (ohjelmat/*.gmd). Käyttöönotto, nimeäminen, vienti,
/// poisto ja tuonti. Treenit eivät muutu ohjelmaa vaihdettaessa.
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});
  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  late Future<List<(String, String, Program)>> _list = savedPrograms();

  void _refresh() => setState(() => _list = savedPrograms());

  Future<String?> _askName(String initial, String title) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: t('Ohjelman nimi')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t('Tallenna'))),
        ],
      ),
    );
  }

  Future<void> _rename(String path, String name, Program p) async {
    final n = await _askName(name, t('Nimeä ohjelma'));
    if (n == null || n.isEmpty || n == name) return;
    await files.delete(path);
    await saveProgramAs(p, n);
    _refresh();
  }

  Future<void> _export(String name, Program p) async {
    final text = programToTemplate(p, name: name);
    await FilePicker.saveFile(
      dialogTitle: t('Tallenna ohjelmapohja'),
      fileName: '$name.$templateExtension',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
  }

  Future<void> _delete(String path, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko "{0}"?', [name])),
        content: Text(t('Vain tallennettu ohjelma poistuu. Treenit säilyvät.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista'))),
        ],
      ),
    );
    if (ok != true) return;
    await files.delete(path);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = settings.program;
    return Scaffold(
      appBar: AppBar(title: Text(t('Ohjelmat'))),
      body: FutureBuilder(
        future: _list,
        builder: (context, snap) {
          final list = snap.data ?? const <(String, String, Program)>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              const SamiBand(height: 4, pattern: false),
              SectionLabel(t('Käytössä')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(cur?.displayTitle ?? t('Treenaat vapaasti')),
                trailing: cur == null
                    ? null
                    : TextButton(
                        onPressed: () async {
                          final n = await _askName(cur.displayTitle.split(' · ').first, t('Tallenna nimellä'));
                          if (n == null || n.isEmpty) return;
                          await saveProgramAs(cur, n);
                          _refresh();
                        },
                        child: Text(t('Tallenna nimellä')),
                      ),
              ),
              SectionLabel(t('Tallennetut ohjelmat')),
              if (list.isEmpty)
                Text(
                  t('Ei vielä tallennettuja ohjelmia. Kun vaihdat ohjelmaa, sovellus tarjoutuu tallentamaan nykyisen.'),
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              for (final (path, name, p) in list)
                Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(p.displayTitle, style: const TextStyle(fontSize: 12)),
                    onTap: () async {
                      await switchToSaved(context, path, p);
                      _refresh();
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => switch (v) {
                        'use' => switchToSaved(context, path, p).then((_) => _refresh()),
                        'rename' => _rename(path, name, p),
                        'export' => _export(name, p),
                        _ => _delete(path, name),
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'use', child: Text(t('Ota käyttöön'))),
                        PopupMenuItem(value: 'rename', child: Text(t('Nimeä'))),
                        PopupMenuItem(value: 'export', child: Text(t('Vie pohjaksi (.gmd)'))),
                        PopupMenuItem(value: 'delete', child: Text(t('Poista'))),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await importTemplate(context, activate: false)) _refresh();
                },
                icon: const Icon(Icons.file_open_outlined),
                label: Text(t('Tuo ohjelmapohja (.gmd)')),
              ),
              const SizedBox(height: 8),
              Text(
                t('Ohjelmat tallentuvat treenikansion ohjelmat-kansioon .gmd-tiedostoina.'),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}
