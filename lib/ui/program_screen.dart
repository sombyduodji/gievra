import 'package:flutter/material.dart';

import '../app_state.dart';
import '../program.dart';
import 'intro.dart';
import 'program_template.dart';
import 'program_view.dart';
import 'programs_screen.dart';
import '../l10n.dart';

/// ☰ → Ohjelma ja tavoitteet: nykyinen ohjelma, uusi ohjelma tai vapaa treeni.
class ProgramScreen extends StatelessWidget {
  const ProgramScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final p = settings.program;
      void intro() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IntroScreen()));
      return Scaffold(
        appBar: AppBar(title: Text(t('Ohjelma ja tavoitteet'))),
        body: p == null
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(t('Treenaat vapaasti ilman ohjelmaa.'), style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      'Sovellus kirjaa treenit, ehdottaa painoja edellisen kerran perusteella ja varoittaa '
                      'vammatilan liikkeistä. Ohjelman voi tehdä milloin vain.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: intro, child: Text(t('Tee ohjelma'))),
                  const SizedBox(height: 8),
                  const _SavedPrograms(),
                  OutlinedButton.icon(
                    onPressed: () => importTemplate(context),
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(t('Tuo ohjelmapohja (.gmd)')),
                  ),
                ],
              )
            : ProgramView(
                program: p,
                header: t('Nykyinen ohjelma'),
                injuries: settings.injuries,
                onChanged: () => settings.setProgram(p),
                footer: [
                  const SizedBox(height: 16),
                  Text(
                    isDemo
                        ? t('Demossa ohjelmaa ei tallenneta. Tallenna pohja tiedostoksi ja tuo se sovellukseen.')
                        : t('Tallennettu treenikansioon ohjelma.md:ksi. Voit muokata sitä myös käsin.'),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: intro, child: Text(t('Tee uusi ohjelma'))),
                  const SizedBox(height: 8),
                  const _SavedPrograms(),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgramsScreen())),
                    icon: const Icon(Icons.folder_copy_outlined, size: 18),
                    label: Text(t('Hallitse ohjelmia')),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => exportTemplate(context, p),
                          icon: const Icon(Icons.download_outlined),
                          label: Text(t('Tallenna pohja')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => importTemplate(context),
                          icon: const Icon(Icons.file_open_outlined),
                          label: Text(t('Tuo pohja')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () async {
                      if (await askSaveCurrent(context)) await settings.setProgram(null);
                    },
                    child: Text(t('Lopeta ohjelma – treenaan vapaasti')),
                  ),
                ],
              ),
      );
    },
  );
}

/// Tallennetut ohjelmat: vaihto yhdellä napautuksella, poisto pitkällä painalluksella.
class _SavedPrograms extends StatefulWidget {
  const _SavedPrograms();
  @override
  State<_SavedPrograms> createState() => _SavedProgramsState();
}

class _SavedProgramsState extends State<_SavedPrograms> {
  late Future<List<(String, String, Program)>> _list = savedPrograms();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _list,
    builder: (context, snap) {
      final list = snap.data ?? const [];
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(t('Tallennetut ohjelmat'), style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final (path, name, p) in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz),
              title: Text(name),
              subtitle: Text(p.displayTitle, style: const TextStyle(fontSize: 12)),
              onTap: () async {
                await switchToSaved(context, path, p);
                if (mounted) setState(() => _list = savedPrograms());
              },
              trailing: IconButton(
                tooltip: t('Poista'),
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  await files.delete(path);
                  if (mounted) setState(() => _list = savedPrograms());
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}
