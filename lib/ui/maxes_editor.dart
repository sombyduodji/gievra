import 'package:flutter/material.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../insights.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'picker.dart';
import 'widgets.dart';

/// Ennätykset (arvioidut 1 toiston maksimit) muokattavana listana: napautus muuttaa, ✕ poistaa, "Lisää ennätys".
/// Käytössä ohjelmakyselyssä ja Muokkaa ennätyksiä -näkymässä. [maxes] muuttuu paikallaan; [onChanged] piirtää.
class MaxesEditor extends StatelessWidget {
  final Map<String, double> maxes;
  final VoidCallback onChanged;
  const MaxesEditor({super.key, required this.maxes, required this.onChanged});

  /// Lisää ennätys: ensin liike, sitten arvio. Kahvakuulaliikkeessä kysytään raskain kuula viidelle toistolle.
  static Future<void> add(BuildContext context, Map<String, double> maxes, VoidCallback onChanged) async {
    final ex = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (ex == null || !context.mounted) return;
    final kb = kettlebellOnly(ex);
    final v = await askNumber(
      context,
      kb
          ? t('{0}: raskain kuula, jolla teet 5 hyvää toistoa (kg)', [exerciseLabel(ex)])
          : t('{0}: 1 toiston maksimi (kg)', [exerciseLabel(ex)]),
      kb ? 16 : (maxes[ex] ?? 60),
    );
    if (v == null || v <= 0) return;
    // Kahvakuula: 5 toistoa -> arvioitu maksimi (Epley).
    maxes[ex] = kb ? (v * (1 + 5 / 30) * 10).round() / 10 : v;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final now = DateTime.now();
    String d(DateTime t) => numDate(t, year: true);
    String set(LiftRecord r) => '${fmtNum(r.kg)} kg × ${r.reps}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in maxes.keys.toList())
          Builder(
            builder: (context) {
              final pr = bestLift(store.workouts, l);
              final (sug, oldEnd) = suggestedMax(store.workouts, l, now);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  tileColor: cs.surfaceContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  title: Text(exerciseLabel(l), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: pr == null
                      ? Text(t('Oma arvio'), style: sub)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('🏆 Ennätys: {0} ({1}), arvio {2} kg', [
                                set(pr),
                                d(pr.date),
                                fmtNum(pr.e1rm.roundToDouble()),
                              ]),
                              style: sub,
                            ),
                            if (sug != null)
                              Text(
                                oldEnd == null
                                    ? t('Ehdotus: paras 6 kk:n ajalta {0} ({1})', [set(sug), d(sug.date)])
                                    : t('Ehdotus: {0} ({1}). Liikettä ei ole tehty puoleen vuoteen: aloita kevyemmin', [
                                        set(sug),
                                        d(sug.date),
                                      ]),
                                style: sub,
                              ),
                          ],
                        ),
                  isThreeLine: pr != null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${fmtNum(maxes[l]!)} kg',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      IconButton(
                        tooltip: t('Poista'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          maxes.remove(l);
                          onChanged();
                        },
                      ),
                    ],
                  ),
                  onTap: () async {
                    final v = await askNumber(
                      context,
                      t('{0}: 1 toiston maksimi (kg)', [exerciseLabel(l)]),
                      maxes[l] ?? 60,
                    );
                    if (v != null && v > 0) {
                      maxes[l] = v;
                      onChanged();
                    }
                  },
                ),
              );
            },
          ),
        OutlinedButton.icon(
          onPressed: () => add(context, maxes, onChanged),
          icon: const Icon(Icons.add),
          label: Text(t('Lisää ennätys')),
        ),
      ],
    );
  }
}

/// Muokkaa ennätyksiä: vain nykyisen ohjelman ennätykset, ohjelma muuten ennallaan. Tallennus ohjelma.md:hen.
class MaxesScreen extends StatefulWidget {
  const MaxesScreen({super.key});
  @override
  State<MaxesScreen> createState() => _MaxesScreenState();
}

class _MaxesScreenState extends State<MaxesScreen> {
  late final Map<String, double> _maxes = {...?settings.program?.maxes};
  bool _changed = false;

  Future<void> _save() async {
    final p = settings.program;
    if (p != null) {
      p.maxes = {..._maxes};
      await settings.setProgram(p);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _maybePop() async {
    if (!_changed) {
      Navigator.of(context).pop();
      return;
    }
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Tallennetaanko muutokset?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Älä tallenna'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Tallenna'))),
        ],
      ),
    );
    if (save == true) {
      await _save();
    } else if (save == false && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Ennätykset')),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(onPressed: _changed ? _save : null, child: Text(t('Tallenna ✓'))),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
          children: [
            const SamiBand(height: 4, pattern: false),
            const SizedBox(height: 12),
            Text(
              t(
                'Arvioidut 1 toiston maksimit, joista ohjelma laskee painoehdotukset. Muutos ei vaihda ohjelmaa '
                'eikä muuta tehtyjä treenejä. Napauta muuttaaksesi.',
              ),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            MaxesEditor(maxes: _maxes, onChanged: () => setState(() => _changed = true)),
          ],
        ),
      ),
    );
  }
}
