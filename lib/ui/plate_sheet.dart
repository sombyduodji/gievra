import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../plates.dart';
import '../theme.dart';
import 'widgets.dart';

// Levylaskuri: tankoliikkeen painon alla levyt puolta kohden; napautus avaa kuvan ja omat levyt.

/// Levyt tekstinä: "25 + 15 + 1,25".
String platesText(List<double> ps) => ps.map(fmtNum).join(' + ');

/// Levyrivi painokentän alle (vain tankoliikkeissä). Napautus avaa levylaskurin.
class PlateLine extends StatelessWidget {
  final double kg;
  final ValueChanged<double>? onPick;
  const PlateLine({super.key, required this.kg, this.onPick});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (ps, rest) = platesPerSide(kg, settings.barKg, settings.plates);
    final String text;
    if (kg < settings.barKg) {
      text = t('Kevyempi kuin tanko ({0} kg)', [fmtNum(settings.barKg)]);
    } else if (ps.isEmpty && rest == 0) {
      text = t('Pelkkä tanko');
    } else {
      text = t('Levyt / puoli: {0}', [platesText(ps)]) + (rest > 0 ? ' · ${t('ei tarkalleen')}' : '');
    }
    return Center(
      child: TextButton.icon(
        onPressed: () => showPlateSheet(context, kg: kg, onPick: onPick),
        icon: const Icon(Icons.fitness_center, size: 16),
        label: Text(text, style: TextStyle(fontSize: 13, color: rest > 0 ? cs.error : null)),
      ),
    );
  }
}

/// Levylaskuri. [kg] null = vain omien levyjen ja tangon valinta (asetuksista). [onPick]: valittu lähin
/// mahdollinen paino takaisin kirjaukseen.
Future<void> showPlateSheet(BuildContext context, {double? kg, ValueChanged<double>? onPick}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) => _PlateSheet(kg: kg, onPick: onPick),
      ),
    );

class _PlateSheet extends StatelessWidget {
  final double? kg;
  final ValueChanged<double>? onPick;
  const _PlateSheet({this.kg, this.onPick});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final kg = this.kg;
    final own = settings.plates;
    final bar = settings.barKg;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('Levylaskuri'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (kg != null) ...[
              const SizedBox(height: 8),
              Text(
                '${fmtNum(kg)} kg',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
              ),
              Builder(
                builder: (_) {
                  final (ps, rest) = platesPerSide(kg, bar, own);
                  final near = loadableTotal(kg, bar, own);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      SizedBox(height: 96, child: _BarPicture(plates: ps)),
                      const SizedBox(height: 8),
                      Text(
                        kg <= bar
                            ? t('Pelkkä tanko')
                            : t('Levyt / puoli: {0}', [
                                platesText(ps.isEmpty ? const [0] : ps),
                              ]),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        kg <= bar ? '' : t('{0} kg / puoli + tanko {1} kg', [fmtNum((kg - bar) / 2), fmtNum(bar)]),
                        textAlign: TextAlign.center,
                        style: sub,
                      ),
                      if (rest > 0 && kg > bar) ...[
                        const SizedBox(height: 8),
                        Text(
                          t('Omilla levyillä ei saa tarkalleen. Lähin: {0} kg.', [fmtNum(near)]),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.error),
                        ),
                        if (onPick != null)
                          Center(
                            child: TextButton(
                              onPressed: () {
                                onPick!(near);
                                Navigator.pop(context);
                              },
                              child: Text(t('Käytä {0} kg', [fmtNum(near)])),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ],
            SectionLabel(t('Omat levyt (kg)')),
            Text(t('Laskuri käyttää vain valittuja levyjä, pareittain.'), style: sub),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in plateCatalog)
                  FilterChip(
                    label: Text(fmtNum(p)),
                    selected: own.contains(p),
                    onSelected: (on) {
                      final next = [...own.where((x) => x != p), if (on) p];
                      if (next.isNotEmpty) settings.setPlates(next, bar);
                    },
                  ),
              ],
            ),
            SectionLabel(t('Tanko (kg)')),
            Wrap(
              spacing: 6,
              children: [
                for (final b in const [20.0, 15.0, 10.0, 7.0])
                  ChoiceChip(label: Text(fmtNum(b)), selected: bar == b, onSelected: (_) => settings.setPlates(own, b)),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('Valmis'))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tangon toinen puoli: levyt korkeuden ja värin mukaan (kilpailulevyjen värit, pienet harmaina).
class _BarPicture extends StatelessWidget {
  final List<double> plates;
  const _BarPicture({required this.plates});

  static Color _color(double p) => switch (p) {
    >= 25 => Sami.red,
    >= 20 => Sami.blue,
    >= 15 => Sami.yellow,
    >= 10 => Sami.green,
    _ => Colors.grey,
  };

  static double _height(double p) => switch (p) {
    >= 15 => 92,
    >= 10 => 80,
    >= 5 => 62,
    >= 2 => 48,
    _ => 38,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bar = Container(width: 40, height: 10, color: cs.outline);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        bar,
        Container(width: 6, height: 26, color: cs.outline),
        for (final p in plates)
          Container(
            width: p >= 10 ? 16 : 11,
            height: _height(p),
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: _color(p),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: cs.outline, width: .5),
            ),
          ),
        Container(width: 24, height: 10, margin: const EdgeInsets.only(left: 2), color: cs.outline),
      ],
    );
  }
}
