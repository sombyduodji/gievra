import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Kun treeni tuntui raskaalta (😫 tai 😕): mitkä liikkeet? Liikkeelle 😫/😕 jatkokysymys "Liian raskas?".
/// Lopuksi päivän syyt kerran koko treenille (väsynyt, rankka päivä …). Tulos tallentuu treeniin.
Future<bool> askMoveFeedback(BuildContext context, Workout w) async {
  final moves = [for (final e in w.exercises.where((e) => e.workSets.isNotEmpty)) e.name];
  if (moves.isEmpty) return false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MoveFeedbackSheet(w: w, moves: moves),
  );
  return ok == true;
}

class _MoveFeedbackSheet extends StatefulWidget {
  final Workout w;
  final List<String> moves;
  const _MoveFeedbackSheet({required this.w, required this.moves});
  @override
  State<_MoveFeedbackSheet> createState() => _MoveFeedbackSheetState();
}

class _MoveFeedbackSheetState extends State<_MoveFeedbackSheet> {
  late final Map<String, int> _feel = {...widget.w.moveFeeling};
  late final Set<String> _heavy = {...widget.w.tooHeavy};
  late final Set<String> _reasons = {...widget.w.dayReasons};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          Text(t('Mikä tuntui raskaalta?'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            t('Arvioi liikkeet, joista on jotain sanottavaa. Näin seuraavan kerran ehdotukset osuvat paremmin.'),
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          for (final m in widget.moves) ...[
            const SizedBox(height: 14),
            ExName(m, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final (v, emoji, label) in feelings)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Material(
                        color: _feel[m] == v ? Sami.yellow.withValues(alpha: .25) : cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() {
                            if (_feel[m] == v) {
                              _feel.remove(m);
                            } else {
                              _feel[m] = v;
                            }
                            if ((_feel[m] ?? 3) > 2) _heavy.remove(m);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              children: [
                                Text(emoji, style: const TextStyle(fontSize: 22)),
                                Text(t(label), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if ((_feel[m] ?? 3) <= 2)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(t('Liian raskas paino?'), style: const TextStyle(fontSize: 13))),
                    ChoiceChip(
                      label: Text(t('Kyllä')),
                      selected: _heavy.contains(m),
                      onSelected: (_) => setState(() => _heavy.add(m)),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(t('Ei')),
                      selected: !_heavy.contains(m),
                      onSelected: (_) => setState(() => _heavy.remove(m)),
                    ),
                  ],
                ),
              ),
          ],
          SectionLabel(t('Vaikuttiko jokin muu?')),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final r in dayReasonChoices)
                FilterChip(
                  label: Text(t(r)),
                  selected: _reasons.contains(r),
                  onSelected: (on) => setState(() => on ? _reasons.add(r) : _reasons.remove(r)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              widget.w
                ..moveFeeling = _feel
                ..tooHeavy = _heavy.where((m) => (_feel[m] ?? 3) <= 2).toSet()
                ..dayReasons = dayReasonChoices.where(_reasons.contains).toList();
              Navigator.pop(context, true);
            },
            child: Text(t('Valmis')),
          ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Ohita'))),
        ],
      ),
    );
  }
}
