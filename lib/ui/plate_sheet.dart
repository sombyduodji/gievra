import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../plates.dart';
import '../theme.dart';
import 'widgets.dart';

// Levylaskuri: tankoliikkeen painon alla levyt puolta kohden; napautus avaa kuvan ja omat levyt.

/// Tangon paino liikkeelle: liikkeen oma (asetettu levylaskurista), muuten hex barin tai tavallisen tangon oletus.
/// Null = hex bar -liike ilman asetettua painoa (ei levylaskuria).
double? barFor(String? exercise, {bool hex = false}) =>
    (exercise == null ? null : settings.exerciseBars[exercise]) ?? (hex ? settings.hexBarKg : settings.barKg);

/// Levyt tekstinä: "25 + 15 + 1,25".
String platesText(List<double> ps) => ps.map(fmtNum).join(' + ');

/// Levyrivi painokentän alle (vain tankoliikkeissä). Napautus avaa levylaskurin.
class PlateLine extends StatelessWidget {
  final double kg;
  final ValueChanged<double>? onPick;

  /// Hex bar -liike: tangon paino asetuksesta Hex bar (pakollinen; ilman sitä riviä ei näytetä).
  final bool hex;

  /// Liike, jolle voi olla oma tanko (käyttäjä 18.11.).
  final String? exercise;
  const PlateLine({super.key, required this.kg, this.onPick, this.hex = false, this.exercise});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final barKg = barFor(exercise, hex: hex) ?? settings.barKg;
    final (ps, rest) = platesPerSide(kg, barKg, settings.plates);
    final String text;
    if (kg < barKg) {
      text = t('Kevyempi kuin tanko ({0} kg)', [fmtNum(barKg)]);
    } else if (ps.isEmpty && rest == 0) {
      text = t('Pelkkä tanko');
    } else {
      text = t('Levyt / puoli: {0}', [platesText(ps)]) + (rest > 0 ? ' · ${t('ei tarkalleen')}' : '');
    }
    return Center(
      child: TextButton.icon(
        onPressed: () => showPlateSheet(context, kg: kg, onPick: onPick, hex: hex, exercise: exercise),
        icon: const Icon(Icons.fitness_center, size: 16),
        label: Text(text, style: TextStyle(fontSize: 13, color: rest > 0 ? cs.error : null)),
      ),
    );
  }
}

/// Levylaskuri. [kg] null = vain omien levyjen ja tangon valinta (asetuksista). [onPick]: valittu lähin
/// mahdollinen paino takaisin kirjaukseen.
Future<void> showPlateSheet(
  BuildContext context, {
  double? kg,
  ValueChanged<double>? onPick,
  bool hex = false,
  String? exercise,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => _PlateSheet(kg: kg, onPick: onPick, hex: hex, exercise: exercise),
  ),
);

class _PlateSheet extends StatelessWidget {
  final double? kg;
  final ValueChanged<double>? onPick;
  final bool hex;
  final String? exercise;
  const _PlateSheet({this.kg, this.onPick, this.hex = false, this.exercise});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final kg = this.kg;
    final own = settings.plates;
    final bar = barFor(exercise, hex: hex) ?? settings.barKg;
    final ex = exercise;
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
                        kg <= bar
                            ? ''
                            : hex
                            ? t('{0} kg / puoli + hex bar {1} kg', [fmtNum((kg - bar) / 2), fmtNum(bar)])
                            : t('{0} kg / puoli + tanko {1} kg', [fmtNum((kg - bar) / 2), fmtNum(bar)]),
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
            // Liikkeen oma tanko (käyttäjä 18.11.: esim. ranteen koukistus 10 kg:n tangolla). Kirjatut sarjat ovat
            // kokonaispainoja, joten vaihto ei muuta aiempia treenejä.
            if (ex != null) _ExerciseBarPicker(exercise: ex, hex: hex),
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
                      if (next.isNotEmpty) settings.setPlates(next, settings.barKg);
                    },
                  ),
              ],
            ),
            SectionLabel(ex == null ? t('Tanko (kg)') : t('Oletustanko (kg)')),
            Wrap(
              spacing: 6,
              children: [
                for (final b in const [20.0, 15.0, 10.0, 7.0])
                  ChoiceChip(
                    label: Text(fmtNum(b)),
                    selected: settings.barKg == b,
                    onSelected: (_) => settings.setPlates(own, b),
                  ),
              ],
            ),
            const HexBarPicker(),
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

/// Hex barin paino (käyttäjä 18.11.): hex barit painavat mitä tahansa, joten paino asetetaan itse. Ilman sitä
/// hex bar -liikkeissä ei ole levylaskuria eikä tangon painoa valmiina.
class HexBarPicker extends StatelessWidget {
  const HexBarPicker({super.key});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: settings, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = settings.hexBarKg;
    const common = [20.0, 22.0, 25.0, 27.0, 30.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Hex bar (kg)')),
        Text(
          t(
            'Kuusikulmatanko: punnitse tai katso tangosta. Ilman painoa levylaskuri ei ole käytössä hex bar -liikkeissä.',
          ),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: const ValueKey('hexBarNone'),
              label: Text(t('Ei asetettu')),
              selected: cur == null,
              onSelected: (_) => settings.setHexBarKg(null),
            ),
            for (final b in common)
              ChoiceChip(
                key: ValueKey('hexBar_${fmtNum(b)}'),
                label: Text(fmtNum(b)),
                selected: cur == b,
                onSelected: (_) => settings.setHexBarKg(b),
              ),
            ActionChip(
              key: const ValueKey('hexBarOther'),
              label: Text(cur != null && !common.contains(cur) ? '${fmtNum(cur)} ✓' : t('Muu…')),
              onPressed: () async {
                final v = await askNumber(context, t('Hex bar (kg)'), cur ?? 25, min: 5, max: 60);
                if (v != null) settings.setHexBarKg(v);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Tämän liikkeen tanko: oletus (asetuksista) tai oma paino, joka muistetaan liikkeelle.
class _ExerciseBarPicker extends StatelessWidget {
  final String exercise;
  final bool hex;
  const _ExerciseBarPicker({required this.exercise, required this.hex});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: settings, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final own = settings.exerciseBars[exercise];
    final def = hex ? settings.hexBarKg : settings.barKg;
    final choices = hex ? const [20.0, 22.0, 25.0, 27.0, 30.0] : const [20.0, 15.0, 10.0, 7.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Tämän liikkeen tanko (kg)')),
        Text(
          t(
            'Muistetaan tälle liikkeelle. Kirjatut sarjat ovat kokonaispainoja, joten vaihto ei muuta aiempia treenejä.',
          ),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: const ValueKey('exerciseBarDefault'),
              label: Text(def == null ? t('Oletus (ei asetettu)') : t('Oletus ({0})', [fmtNum(def)])),
              selected: own == null,
              onSelected: (_) => settings.setExerciseBar(exercise, null),
            ),
            for (final b in choices)
              ChoiceChip(
                key: ValueKey('exerciseBar_${fmtNum(b)}'),
                label: Text(fmtNum(b)),
                selected: own == b,
                onSelected: (_) => settings.setExerciseBar(exercise, b),
              ),
            ActionChip(
              key: const ValueKey('exerciseBarOther'),
              label: Text(own != null && !choices.contains(own) ? '${fmtNum(own)} ✓' : t('Muu…')),
              onPressed: () async {
                final v = await askNumber(context, t('Tämän liikkeen tanko (kg)'), own ?? def ?? 20, min: 1, max: 60);
                if (v != null) settings.setExerciseBar(exercise, v);
              },
            ),
          ],
        ),
      ],
    );
  }
}
