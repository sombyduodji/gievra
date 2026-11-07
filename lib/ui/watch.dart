import 'package:flutter/material.dart';

import '../models.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Sykemittarin / älykellon tiedot: kesto (valinnainen), kalorit, keski- ja maksimisyke.
/// Näkyy vain, kun ☰ → Asetukset → Sykemittari ja älykello on päällä.
class WatchCard extends StatelessWidget {
  final Workout w;
  final bool withDuration; // salitreenissä kesto kellosta korvaa sovelluksen ajastimen
  final VoidCallback onChanged;
  const WatchCard({super.key, required this.w, required this.onChanged, this.withDuration = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Future<void> ask(String title, int? current, void Function(int?) set, {int def = 0}) async {
      final v = await askNumber(context, title, (current ?? def).toDouble(), decimals: false);
      if (v == null) return;
      set(v <= 0 ? null : v.round());
      onChanged();
    }

    Widget box(String emoji, String label, int? value, String unit, VoidCallback onTap) => Expanded(
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                Text(value == null ? '–' : '$value $unit', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(t('Kellon tiedot')),
        Row(
          children: [
            if (withDuration) ...[
              box('⌚', t('kesto'), w.watchTime ? w.minutes : null, 'min', () async {
                await ask(t('Kesto kellosta (min)'), w.minutes, (v) {
                  w.watchTime = v != null;
                  if (v != null) w.minutes = v;
                }, def: 60);
              }),
              const SizedBox(width: 6),
            ],
            box(
              '🔥',
              t('kalorit'),
              w.kcal,
              'kcal',
              () => ask(t('Kalorit (kcal)'), w.kcal, (v) => w.kcal = v, def: 400),
            ),
            const SizedBox(width: 6),
            box(
              '❤️',
              t('keskisyke'),
              w.hrAvg,
              '',
              () => ask(t('Keskisyke (lyöntiä/min)'), w.hrAvg, (v) => w.hrAvg = v, def: 130),
            ),
            const SizedBox(width: 6),
            box(
              '💓',
              t('maksimisyke'),
              w.hrMax,
              '',
              () => ask(t('Maksimisyke (lyöntiä/min)'), w.hrMax, (v) => w.hrMax = v, def: 170),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            withDuration
                ? t('Napauta ja kirjoita arvo kellosta. Kellon kesto korvaa sovelluksen ajastimen. 0 tyhjentää.')
                : t('Napauta ja kirjoita arvo kellosta. 0 tyhjentää.'),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Lyhyt rivi tuloksiin ja jakoon: "❤️ 142 / 178 · 🔥 520 kcal".
String? watchLine(Workout w) {
  final parts = [
    if (w.hrAvg != null || w.hrMax != null) '❤️ ${w.hrAvg ?? '–'} / ${w.hrMax ?? '–'}',
    if (w.kcal != null) t('🔥 {0} kcal', [w.kcal]),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
