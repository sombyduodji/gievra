import 'package:flutter/material.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../l10n.dart';
import '../models.dart';
import '../progression.dart';
import '../rest.dart';
import 'widgets.dart';

// Prosenttilaskuri: painot prosentteina arvioidusta maksimista (e1RM). Napautus valitsee painon kirjaukseen.

/// Arvioitu maksimi laskurille: viimeisten 4 viikon työmaksimi (tai ohjelman maksimi), muuten paras koskaan.
double? estimatedMax(String exercise, DateTime date) {
  final w = workingE1rm(exercise, date);
  if (w != null && w > 0) return w;
  final b = bestE1rmBefore(exercise, addDays(date, 1));
  return b > 0 ? b : null;
}

/// Toistot, jotka yleensä onnistuvat painolla [pct] maksimista (Epleyn kaava käänteisenä), ~1–15.
int? repsAt(double pct) {
  if (pct >= 1) return 1;
  final r = (30 * (1 / pct - 1)).round();
  return r < 1 || r > 15 ? null : r;
}

double _round(double kg, double step) => (kg / step).round() * step;

Future<void> showPercentSheet(
  BuildContext context, {
  required String exercise,
  required DateTime date,
  ValueChanged<double>? onPick,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _PercentSheet(exercise: exercise, date: date, onPick: onPick),
);

class _PercentSheet extends StatefulWidget {
  final String exercise;
  final DateTime date;
  final ValueChanged<double>? onPick;
  const _PercentSheet({required this.exercise, required this.date, this.onPick});
  @override
  State<_PercentSheet> createState() => _PercentSheetState();
}

class _PercentSheetState extends State<_PercentSheet> {
  late final double? _estimate = estimatedMax(widget.exercise, widget.date);
  late double _max = _round(_estimate ?? 60, settings.weightStep);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final step = settings.weightStep;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .75,
      maxChildSize: .95,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          Text(t('Prosenttia maksimista'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(exerciseLabel(widget.exercise), style: sub),
          SectionLabel(t('Arvioitu maksimi (1 toisto)')),
          ValueStepper(
            value: fmtNum(_max),
            unit: 'kg',
            onMinus: () => setState(() => _max = (_max - step).clamp(step, 1000)),
            onPlus: () => setState(() => _max = (_max + step).clamp(step, 1000)),
            onTap: () async {
              final v = await askNumber(context, t('Maksimi (kg)'), _max);
              if (v != null && v > 0 && v <= 1000) setState(() => _max = v);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _estimate == null
                  ? t('Ei vielä arviota: kirjaa sarjoja tai anna maksimi itse.')
                  : t('Arvio kirjatuista sarjoista: {0} kg. Voit muuttaa sitä tässä.', [
                      fmtNum(_estimate.roundToDouble()),
                    ]),
              style: sub,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          for (final p in const [95, 90, 85, 80, 75, 70, 65, 60, 50])
            Builder(
              builder: (_) {
                final kg = _round(_max * p / 100, step);
                final reps = repsAt(p / 100);
                // Oma rivi ListTilen sijaan: pitkä toistoteksti (esim. saameksi) rivittyy eikä vie riviä yli.
                return InkWell(
                  onTap: widget.onPick == null
                      ? null
                      : () {
                          widget.onPick!(kg);
                          Navigator.pop(context);
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text('$p %', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: Text(
                            '${fmtNum(kg)} kg',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            reps == null ? '' : t('n. {0} toistoa', [reps]),
                            textAlign: TextAlign.end,
                            style: sub,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 6),
          Text(t('Toistomäärät ovat suuntaa antavia (Epleyn kaava). Napauta riviä käyttääksesi painoa.'), style: sub),
        ],
      ),
    );
  }
}
