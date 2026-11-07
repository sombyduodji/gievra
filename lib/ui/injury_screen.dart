import 'package:flutter/material.dart';

import '../app_state.dart';
import '../injuries.dart';
import '../program.dart';
import '../theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Vammatila: valitse alueet. [picker] = palauttaa valinnan (aloituskysely), muuten tallentaa asetuksiin.
class InjuryScreen extends StatefulWidget {
  final List<String> initial;
  final bool picker;
  const InjuryScreen({super.key, required this.initial, this.picker = false});
  @override
  State<InjuryScreen> createState() => _InjuryScreenState();
}

class _InjuryScreenState extends State<InjuryScreen> {
  late final Set<String> _sel = {...widget.initial};

  Future<void> _save() async {
    final ids = [
      for (final r in injuryRegions)
        if (_sel.contains(r.id)) r.id,
    ];
    if (widget.picker) {
      Navigator.pop(context, ids);
      return;
    }
    settings.setInjuries(ids);
    final p = settings.program;
    if (p != null) {
      final redo = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Päivitetäänkö ohjelma?')),
          content: Text(t('Ohjelman liikkeet valitaan uudelleen vammojen mukaan. Aloituspäivä ja viikko säilyvät.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ei')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Päivitä'))),
          ],
        ),
      );
      if (redo == true) {
        await settings.setProgram(
          generateProgram(
            goal: p.goal,
            experience: p.experience,
            days: p.days,
            minutes: p.minutes,
            injuries: ids,
            maxes: p.maxes,
            start: p.start,
            repStyle: p.repStyle,
            equipment: p.equipment,
            kbFocus: p.kbFocus,
          ),
        );
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Vammatila')),
        actions: [TextButton(onPressed: _save, child: Text(widget.picker ? t('Valmis') : t('Tallenna')))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Sami.red.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Sami.red.withValues(alpha: .6)),
            ),
            child: Text(
              t(
                'Vammatila ei tee diagnoosia eikä korvaa fysioterapeutin tai lääkärin arviota. Se ehdottaa '
                'varovaisia muutoksia harjoitteluun. Jos kipu on kova, pahenee tai ei helpota parissa '
                'viikossa, hakeudu ammattilaisen arvioon.',
              ),
              style: TextStyle(fontSize: 13),
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.warning_amber, color: Sami.red),
            title: Text(t('Punaiset liput: milloin lääkäriin')),
            children: [Padding(padding: const EdgeInsets.only(bottom: 8), child: _Md(injuryRedFlags))],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.speed),
            title: Text(t('Kipuasteikko ja paluu kuormaan')),
            children: [Padding(padding: const EdgeInsets.only(bottom: 8), child: _Md(injuryGeneralRules))],
          ),
          SectionLabel(t('Missä vaiva on?')),
          for (final r in injuryRegions)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                shape: const Border(),
                leading: Checkbox(
                  value: _sel.contains(r.id),
                  onChanged: (v) => setState(() => v == true ? _sel.add(r.id) : _sel.remove(r.id)),
                ),
                title: Text(r.name),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.explanation, style: const TextStyle(fontSize: 13)),
                  if (r.avoid.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(t('Vältä aluksi: {0}', [r.avoid.join(', ')]), style: sub),
                  ],
                  if (r.recommended.isNotEmpty)
                    Text(t('Yleensä hyvin siedetyt: {0}', [r.recommended.join(', ')]), style: sub),
                  if (r.tendon.isNotEmpty) ...[const SizedBox(height: 6), Text(r.tendon, style: sub)],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(t('Lähteet: docs/tutkimus/vammatila.md (JOSPT-hoitosuositukset, Käypä hoito, BJSM ym.).'), style: sub),
        ],
      ),
    );
  }
}

/// Yksinkertainen Markdown-näyttö (lihavointi ja luettelot) ohjeteksteille.
class _Md extends StatelessWidget {
  final String text;
  const _Md(this.text);

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          Padding(
            padding: EdgeInsets.only(left: l.startsWith('  ') ? 16 : 0, bottom: 4),
            child: Text.rich(
              _rich(l.trim().replaceFirst(RegExp(r'^[-*]\s+'), '• ').replaceFirst(RegExp(r'^\d+\.\s+'), '• ')),
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }

  TextSpan _rich(String s) {
    final parts = s.split('**');
    return TextSpan(
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
      ],
    );
  }
}
