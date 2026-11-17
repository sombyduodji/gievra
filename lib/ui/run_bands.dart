import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../running.dart';
import 'widgets.dart' show selectedText;

/// Juoksun matkaryhmät etusivun Kehitys-korttiin (käyttäjä 17.11.): 1–3 ryhmää, kullakin oma matkaväli. Tyhjä yläraja =
/// ei ylärajaa. Ryhmät saavat mennä päällekkäin (esim. vain 9–11 km kymppien seurantaan).
Future<void> editRunBands(BuildContext context) async {
  final rows = [
    for (final b in settings.runBands) (selectedText(fmtNum(b.$1)), selectedText(b.$2 == null ? '' : fmtNum(b.$2!))),
  ];
  String? error;
  final saved = await showDialog<List<RunBand>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        List<RunBand>? parse() {
          final out = <RunBand>[];
          for (final (a, b) in rows) {
            final lo = a.text.trim().isEmpty ? 0.0 : parseNum(a.text);
            final hi = b.text.trim().isEmpty ? null : parseNum(b.text);
            if (lo == null || lo < 0 || (b.text.trim().isNotEmpty && (hi == null || hi <= lo))) return null;
            out.add((lo, hi));
          }
          return out;
        }

        return AlertDialog(
          title: Text(t('Juoksun matkaryhmät')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    'Etusivun Kehitys-kortti vertaa jokaisen ryhmän vauhtia ja sykettä: viimeiset 4 viikkoa vs. 8 '
                    'viikkoa ennen. Tyhjä yläraja = ei ylärajaa.',
                  ),
                  style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                for (final (i, (a, b)) in rows.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: ValueKey('runBandFrom_$i'),
                            controller: a,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: t('Vähintään'), suffixText: 'km', isDense: true),
                            onChanged: (_) => set(() => error = null),
                          ),
                        ),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
                        Expanded(
                          child: TextField(
                            key: ValueKey('runBandTo_$i'),
                            controller: b,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: t('Alle'), suffixText: 'km', isDense: true),
                            onChanged: (_) => set(() => error = null),
                          ),
                        ),
                        IconButton(
                          key: ValueKey('runBandRemove_$i'),
                          tooltip: t('Poista'),
                          onPressed: rows.length == 1 ? null : () => set(() => rows.removeAt(i)),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ),
                if (rows.length < 3)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('runBandAdd'),
                      onPressed: () => set(() => rows.add((selectedText(''), selectedText('')))),
                      icon: const Icon(Icons.add),
                      label: Text(t('Lisää ryhmä')),
                    ),
                  ),
                if (error != null) Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('runBandDefault'),
              onPressed: () => Navigator.pop(ctx, defaultRunBands),
              child: Text(t('Oletus')),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
            FilledButton(
              key: const ValueKey('runBandSave'),
              onPressed: () {
                final v = parse();
                if (v == null) {
                  set(() => error = t('Tarkista matkat: yläraja suurempi kuin alaraja.'));
                } else {
                  Navigator.pop(ctx, v);
                }
              },
              child: Text(t('Tallenna')),
            ),
          ],
        );
      },
    ),
  );
  if (saved != null) settings.setRunBands(saved);
}
