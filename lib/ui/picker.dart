import 'package:flutter/material.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../injuries.dart';
import '../theme.dart';
import '../l10n.dart';
import 'widgets.dart';

/// Liikkeen valinta: haku, kategoriat ja omat liikkeet. Palauttaa liikkeen nimen.
class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key});
  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  String _cat = 'Voimanosto';
  String _q = '';

  Map<String, List<String>> get _all => allExercises();

  /// Viimeksi tehdyt liikkeet ensin.
  List<String> get _recent {
    final seen = <String>[];
    for (final w in store.workouts) {
      for (final e in w.exercises) {
        if (e.sets.isNotEmpty && !seen.contains(e.name)) seen.add(e.name);
      }
      if (seen.length >= 8) break;
    }
    return seen;
  }

  Future<void> _create() async {
    final c = TextEditingController(text: _q);
    var cat = _cat == 'Viimeksi' || _cat == 'Voimanosto' || _cat == ownCategory ? 'Koko keho' : _cat;
    var measure = Measure.reps;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          scrollable: true,
          title: Text(t('Oma liike')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: t('Liikkeen nimi, esim. Kaapelisoutu yhdellä kädellä')),
              ),
              const SizedBox(height: 14),
              Text(t('Lihasryhmä')),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in exerciseCategories)
                    ChoiceChip(label: Text(k), selected: cat == k, onSelected: (_) => set(() => cat = k)),
                ],
              ),
              const SizedBox(height: 14),
              Text(t('Mitataan')),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in Measure.values)
                    ChoiceChip(
                      label: Text(t(m.label)),
                      selected: measure == m,
                      onSelected: (_) => set(() => measure = m),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(t('Lisää'))),
          ],
        ),
      ),
    );
    final name = v?.trim();
    if (name == null || name.isEmpty || !mounted) return;
    settings.addCustomExercises({name: cat});
    if (measure != Measure.reps) settings.setMeasure(name, measure);
    Navigator.pop(context, name);
  }

  Widget? _injuryLine(String n, ColorScheme cs) {
    final st = injuryStatus(n, settings.injuries);
    if (st.avoid.isNotEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: RedNote(
          '⚠️ ${t('Vältä ({0})', [st.avoid.map(t).join(', ')])}${st.substitute != null ? ' → ${exerciseLabel(st.substitute!)}' : ''}',
        ),
      );
    }
    if (st.modify.isNotEmpty) {
      return Text(
        '🩹 ${t(st.modify.first)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _q.toLowerCase();
    final items = <(String, String)>[];
    final cats = {'Viimeksi': _recent, ..._all};
    for (final e in cats.entries) {
      if (q.isEmpty && e.key != _cat) continue;
      if (q.isNotEmpty && e.key == 'Viimeksi') continue;
      for (final n in e.value) {
        if (q.isNotEmpty && items.any((x) => x.$2 == n)) continue;
        if (q.isEmpty || matchesSearch(n, q)) items.add((categoryOf(n) ?? ownCategory, n));
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(t('Valitse liike'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('Hae liikettä…'),
                filled: true,
                fillColor: cs.surfaceContainer,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              children: [
                for (final c in cats.keys)
                  if (c != 'Viimeksi' || _recent.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(t(c)),
                        selected: q.isEmpty && c == _cat,
                        onSelected: (_) => setState(() => _cat = c),
                      ),
                    ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                for (final (cat, n) in items)
                  ListTile(
                    leading: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: groupColor(bodyGroupOf(n)), shape: BoxShape.circle),
                    ),
                    title: ExName(n),
                    subtitle: _injuryLine(n, cs),
                    trailing: Text(t(cat), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    onTap: () => Navigator.pop(context, n),
                  ),
                ListTile(
                  leading: Icon(Icons.add, color: yellowText(context)),
                  title: Text(
                    _q.isEmpty ? t('Luo oma liike') : t('Luo oma liike "{0}"', [_q]),
                    style: TextStyle(color: yellowText(context)),
                  ),
                  onTap: _create,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
