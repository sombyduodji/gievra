import 'package:flutter/material.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../program_check.dart' show muscleAreas;
import '../injuries.dart';
import '../theme.dart';
import '../l10n.dart';
import 'exercise_guide.dart';
import 'suggest_exercise.dart';
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
    // Lihakset viikon kuormaa varten (käyttäjä 16.11.): kategorian osat valmiina näkyvissä, muut "Muut lihakset".
    final muscles = <String>{};
    var allMuscles = false;
    String label(String m) => m == 'vatsa' ? t('keskivartalo') : t(m);
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
                    ChoiceChip(label: Text(t(k)), selected: cat == k, onSelected: (_) => set(() => cat = k)),
                ],
              ),
              const SizedBox(height: 14),
              Text(t('Mitä lihaksia liike kuormittaa?')),
              Text(
                t('Valitse pääasialliset. Näkyvät viikon kuormassa.'),
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              for (final area in muscleAreas.entries)
                if (allMuscles || area.key == cat || area.value.any(muscles.contains)) ...[
                  if (allMuscles || area.key != cat)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(t(area.key), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in area.value)
                        FilterChip(
                          label: Text(label(m)),
                          selected: muscles.contains(m),
                          onSelected: (on) => set(() => on ? muscles.add(m) : muscles.remove(m)),
                        ),
                    ],
                  ),
                ],
              if (!allMuscles)
                TextButton(
                  key: const ValueKey('allMuscles'),
                  onPressed: () => set(() => allMuscles = true),
                  child: Text(t('Muut lihakset…')),
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
    if (muscles.isNotEmpty) settings.setCustomMuscles(name, muscles.toList());
    Navigator.pop(context, name);
  }

  /// Oman liikkeen poisto luettelosta. Tehdyt treenit säilyvät (liikkeen nimi jää niihin).
  Future<void> _deleteOwn(String n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko oma liike {0}?', [n])),
        content: Text(t('Liike poistuu valitsimesta. Tehdyt treenit säilyvät, eikä ohjelma muutu.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => settings.removeCustomExercise(n));
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
        maxLines: linesFor(context, 1),
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
    final big = MediaQuery.textScalerOf(context).scale(14) >= 21;
    return Scaffold(
      appBar: AppBar(title: BarTitle(Text(t('Valitse liike')))),
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
            // Korkeus tekstikoon mukaan: suurella fontilla (puhelin 1,3 + Suuri) sirujen teksti leikkautui alareunasta.
            height: 38 + MediaQuery.textScalerOf(context).scale(14),
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
                    // Suurella tekstillä kategoria nimen alle: oikealla se kavensi nimeä niin, että nimi katkesi
                    // sanan keskeltä ("Takakyykk-y"; Samsung, puhelin 1,3 + Suuri, 16.11. ilta).
                    subtitle: big
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ?_injuryLine(n, cs),
                              Text(t(cat), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            ],
                          )
                        : _injuryLine(n, cs),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!big) Text(t(cat), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                        // Oma liike: ehdota Gievraan (käyttäjä 16.11.; treenin jälkeen kysytään vain kerran).
                        if (settings.customExercises.contains(n))
                          IconButton(
                            tooltip: t('Ehdota Gievraan: {0}', [n]),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.lightbulb_outline, color: cs.onSurfaceVariant),
                            onPressed: () => suggestExercises(context, [n]),
                          ),
                        // Ohje ja animaatio ennen valintaa (käyttäjä 16.11.).
                        if (hasExerciseGuide(n))
                          IconButton(
                            tooltip: t('Näin teet: {0}', [exerciseLabel(n)]),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.play_circle_outline, color: cs.onSurfaceVariant),
                            onPressed: () async {
                              if (await showExerciseGuide(context, n) && context.mounted) Navigator.pop(context, n);
                            },
                          ),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, n),
                    // Oma liike: pitkä painallus poistaa sen luettelosta (käyttäjä 16.11.: poistoa ei ollut).
                    onLongPress: settings.customExercises.contains(n) ? () => _deleteOwn(n) : null,
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
