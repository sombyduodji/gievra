import 'package:flutter/material.dart';

import '../rest.dart';
import '../theme.dart';
import '../l10n.dart';

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Palautusajastin sarjan jälkeen: jäljellä oleva aika, −15 s / +15 s ja Ohita (peruu ajastimen).
/// Näkyy vain, kun ajastin on käynnissä (☰ → Asetukset → Palautusajastin).
class RestBanner extends StatelessWidget {
  const RestBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: rest,
    builder: (context, _) {
      if (!rest.running) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final left = rest.remaining;
      final frac = rest.total == 0 ? 0.0 : (left / rest.total).clamp(0.0, 1.0);
      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(color: Sami.blue.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
          child: Column(
            mainAxisSize: MainAxisSize.min, // alapalkki: vain sisällön korkuinen
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('⏱', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Palautus {0}', [_mmss(left)]),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          t('suositus {0} · {1}', [_mmss(rest.total), rest.exercise]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => rest.adjust(-15), child: const Text('−15 s')),
                  TextButton(onPressed: () => rest.adjust(15), child: const Text('+15 s')),
                  IconButton(tooltip: t('Ohita palautus'), onPressed: rest.stop, icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                  color: Sami.blue,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
