import 'maxes_editor.dart';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../program.dart';
import 'intro.dart';
import 'program_template.dart';
import 'program_view.dart';
import 'programs_screen.dart';
import 'share_card.dart';
import '../l10n.dart';
import 'widgets.dart' show BarTitle;
import 'injury_screen.dart';
import 'drawer.dart' show showPauseDialog, stopPause;
import '../injuries.dart' show knownInjuries;
import '../theme.dart';

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
        appBar: AppBar(
          title: BarTitle(Text(t('Ohjelma ja tavoitteet'))),
          // Ohut saamen värien viiva kuten muilla välilehdillä (ulkoasun kohennus 16.11.).
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(10),
            child: Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 6), child: SamiBand(height: 4, pattern: false)),
          ),
        ),
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
                  const SizedBox(height: 12),
                  _ModeCards(),
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
                  // Vammatila ja tauko ohjelman yhteydessä, koska ne muuttavat ohjelmaa (luonnos valilehdet).
                  _ModeCards(),
                  const SizedBox(height: 12),
                  Text(
                    isDemo
                        ? t('Demossa ohjelmaa ei tallenneta. Tallenna pohja tiedostoksi ja tuo se sovellukseen.')
                        : t('Tallennettu treenikansioon ohjelma.md:ksi. Voit muokata sitä myös käsin.'),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  // Ohjelman hallinta yhtenä korttina (ulkoasun kohennus 16.11.): ennen seitsemän painiketta allekkain
                  // ja punainen Tee uusi ohjelma, vaikka ohjelma oli jo käytössä (yksi pääpainike näkymää kohden).
                  _ManageCard(program: p, onNew: intro),
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
              subtitle: Text(p.kindTitle, style: const TextStyle(fontSize: 12)),
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

/// Vammatila ja tauko kahtena korttina Ohjelma-välilehdellä (tila näkyy kortissa).
class _ModeCards extends StatelessWidget {
  const _ModeCards();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final inj = knownInjuries(settings.injuries);
    final pause = settings.activePause;
    Widget card(Key key, String title, String state, bool on, VoidCallback onTap) => Expanded(
      child: Card(
        key: key,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: on ? BorderSide(color: yellowText(context), width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pitkä sana (saame Roasmmohuvvan) pienenee mahtumaan eikä katkea kesken sanan.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700), softWrap: false),
                ),
                const SizedBox(height: 2),
                Text(state, style: on ? sub.copyWith(color: yellowText(context)) : sub),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        card(
          const ValueKey('modeInjury'),
          '🩹 ${t('Vammatila')}',
          inj.isEmpty
              ? t('pois')
              : (inj.length == 1 ? t('1 alue valittuna') : t('{0} aluetta valittuna', [inj.length])),
          inj.isNotEmpty,
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InjuryScreen(initial: settings.injuries))),
        ),
        const SizedBox(width: 10),
        card(
          const ValueKey('modePause'),
          '⏸ ${t('Tauko')}',
          pause == null ? t('aloita tauko') : t('käytössä · lopeta'),
          pause != null,
          () => pause == null ? showPauseDialog(context) : stopPause(context),
        ),
      ],
    );
  }
}

/// Ohjelman hallinta riveinä: ennätykset, uusi ohjelma, tallennetut, pohjat, jako ja lopetus (punaisella tekstillä).
class _ManageCard extends StatelessWidget {
  final Program program;
  final VoidCallback onNew;
  const _ManageCard({required this.program, required this.onNew});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    Widget row(String key, IconData icon, String title, String? subtitle, VoidCallback onTap, {Color? color}) =>
        ListTile(
          key: ValueKey(key),
          leading: Icon(icon, color: color ?? cs.onSurfaceVariant),
          title: Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
          subtitle: subtitle == null ? null : Text(subtitle, style: sub),
          trailing: color == null ? const Icon(Icons.chevron_right) : null,
          onTap: onTap,
        );
    Widget divider() => Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: .5));
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          row(
            'manageMaxes',
            Icons.emoji_events_outlined,
            t('Muokkaa ennätyksiä'),
            t('Painoehdotusten pohjana olevat maksimit'),
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MaxesScreen())),
          ),
          divider(),
          row(
            'managePrograms',
            Icons.folder_copy_outlined,
            t('Hallitse ohjelmia'),
            t('Tallennetut ohjelmat: vaihda, nimeä, poista'),
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgramsScreen())),
          ),
          divider(),
          row(
            'manageNew',
            Icons.auto_awesome_outlined,
            t('Tee uusi ohjelma'),
            t('Kysely: tavoite, päivät, kesto'),
            onNew,
          ),
          divider(),
          row(
            'manageShare',
            Icons.share_outlined,
            t('Jaa ohjelma'),
            t('Kuvana tai ohjelmapohjana (.gmd)'),
            () => shareProgram(context, program),
          ),
          divider(),
          row(
            'manageExport',
            Icons.download_outlined,
            t('Tallenna pohja'),
            null,
            () => exportTemplate(context, program),
          ),
          divider(),
          row('manageImport', Icons.file_open_outlined, t('Tuo pohja'), null, () => importTemplate(context)),
          divider(),
          row('manageEnd', Icons.stop_circle_outlined, t('Lopeta ohjelma – treenaan vapaasti'), null, () async {
            if (await askSaveCurrent(context)) await settings.setProgram(null);
          }, color: redText(context)),
        ],
      ),
    );
  }
}
