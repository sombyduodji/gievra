import 'package:flutter/material.dart';

import '../app_state.dart';
import '../effort.dart';
import '../exercises.dart';
import '../heart_rate.dart' show hrProfile;
import '../hr_calc.dart';
import '../l10n.dart';
import '../models.dart';
import '../session_compare.dart' show fmtDuration;
import '../sports.dart';
import '../theme.dart';
import 'widgets.dart';

/// Treeni valmis -ikkunan tulos: fiilis 1–5 tai [feelingSkipped] (Ohita) ja rasitus (jos kysyttiin).
class FinishResult {
  final int feeling;
  final String? intensity;
  const FinishResult(this.feeling, this.intensity);
}

/// Treeni valmis -ikkuna (mockup 8 ja 9, käyttäjän valinta 14.11.): yhteenveto ylhäällä, liikunnassa rasitus
/// värillisenä asteikkona (esivalittu sykkeestä tai vauhdista), fiilis isoina kasvoina; kasvon napautus tallentaa.
/// Salitreenissä ylhäällä ennätykset ja suurin painonnousu, ja Raskas/Tahmea avaa samaan ikkunaan
/// "Mikä tuntui raskaalta?" -vaiheen ([heavyStep]): valitut liikkeet tallentuvat liian raskaiksi (seuraavalla
/// kerralla kevyempi paino) ja päivän syyt kuten ennen erillisessä ikkunassa.
/// Palauttaa null, kun ikkuna suljetaan takaisin-painikkeella tai pyyhkäisemällä (lopetus peruttiin).
Future<FinishResult?> showFinishSheet(
  BuildContext context, {
  Workout? w,
  bool askIntensity = false,
  String? intensity,
  HrSeries? series,
  int? durationSec,
  bool heavyStep = false,
}) => showModalBottomSheet<FinishResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) => FinishSheet(
    w: w,
    askIntensity: askIntensity,
    intensity: intensity,
    series: series,
    durationSec: durationSec,
    heavyStep: heavyStep,
  ),
);

class FinishSheet extends StatefulWidget {
  final Workout? w;
  final bool askIntensity, heavyStep;
  final String? intensity;
  final HrSeries? series;
  final int? durationSec;
  const FinishSheet({
    super.key,
    this.w,
    this.askIntensity = false,
    this.intensity,
    this.series,
    this.durationSec,
    this.heavyStep = false,
  });

  @override
  State<FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<FinishSheet> {
  late final (String, EffortSource)? _estimate = widget.askIntensity && widget.intensity == null && widget.w != null
      ? estimateEffort(
          widget.w!,
          series: widget.series ?? widget.w!.hrSeries,
          maxHr: hrProfile()?.maxHr(DateTime.now()),
          durationSec: widget.durationSec,
        )
      : null;
  late String? _intensity = widget.intensity ?? _estimate?.$1;
  bool get _estimated => _estimate != null && _intensity == _estimate.$1 && widget.intensity == null;

  int? _feeling;
  bool _heavyStage = false;
  late final Set<String> _heavy = {...?widget.w?.tooHeavy};
  late final Set<String> _reasons = {...?widget.w?.dayReasons};

  List<String> get _moves => [
    for (final e in widget.w?.exercises ?? const <ExerciseEntry>[])
      if (e.workSets.isNotEmpty) e.name,
  ];

  void _pickFeeling(int v) {
    if (widget.heavyStep && v <= 2 && _moves.isNotEmpty) {
      setState(() {
        _feeling = v;
        _heavyStage = true;
      });
      return;
    }
    Navigator.pop(context, FinishResult(v, _intensity));
  }

  void _heavyDone() {
    final w = widget.w!;
    for (final m in _moves) {
      if (_heavy.contains(m)) {
        w.tooHeavy.add(m);
        w.moveFeeling[m] = 1;
      } else {
        w.tooHeavy.remove(m);
      }
    }
    w.dayReasons
      ..clear()
      ..addAll(_reasons);
    Navigator.pop(context, FinishResult(_feeling!, _intensity));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.25);
    final w = widget.w;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('finishSheet'),
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (w != null) ...[_header(w, cs, sub, dark), Divider(height: 28, color: cs.outlineVariant)],
            if (widget.askIntensity) ...[
              _title(t('Rasitus'), t('Kuinka kovaa kehollesi'), sub, badge: _estimated ? _badge(cs) : null),
              const SizedBox(height: 10),
              _effortRow(dark),
              const SizedBox(height: 18),
            ],
            _title(t('Miltä tuntui?'), t('Millainen olo'), sub),
            const SizedBox(height: 12),
            _faces(cs, dark),
            if (_heavyStage) ..._heavySection(cs, sub, dark),
            if (!_heavyStage)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(t('Fiilis tallentaa treenin'), style: sub)),
                    TextButton(
                      onPressed: () => Navigator.pop(context, FinishResult(feelingSkipped, _intensity)),
                      child: Text(
                        t('Ohita'),
                        style: TextStyle(color: redText(context), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(Workout w, ColorScheme cs, TextStyle sub, bool dark) {
    final name = w.activity != null ? sportName(w.activity!) : trName(w.title);
    final icon = w.activity != null ? (sportOf(w.activity)?.icon ?? '🏃') : '💪';
    final dur = widget.durationSec ?? w.durationSec;
    final s = widget.series ?? w.hrSeries;
    final hasHr = s != null && dur != null && s.coverage(dur) >= .5 && s.avg != null;
    final parts = <String>[
      if (w.activity == null) setsLabel(w.exercises.fold(0, (a, e) => a + e.workSets.length)),
      if (w.activity != null && (w.distanceKm ?? 0) > 0) '${fmtNum((w.distanceKm! * 100).round() / 100)} km',
      // Alle minuutin salitreenissä ei "0 min".
      if (dur != null && (w.activity != null || dur >= 60))
        w.activity == null ? fmtDuration((dur / 60).round()) : fmtDurationSec(dur),
      if (hasHr)
        t('ka {0}', [s.avg])
      else if (w.activity != null && (w.distanceKm ?? 0) > 0 && dur != null && (sportOf(w.activity)?.steps ?? false))
        '${fmtPace(dur / w.distanceKm!)} /km',
    ];
    final chips = <Widget>[];
    if (w.activity == null) {
      final (prs, best) = gymHighlights(w, store.workouts);
      final gold = dark ? const Color(0xFF3A3214) : const Color(0xFFFFF4C2);
      final green = dark ? const Color(0xFF12301F) : const Color(0xFFE3F3E9);
      if (prs > 0) chips.add(_chip('🏆 ${prs > 1 ? t('{0} ennätystä!', [prs]) : t('1 ennätys!')}', gold));
      if (best != null) chips.add(_chip('⬆ ${exerciseLabel(best.$1)} +${fmtNum(best.$2)} kg', green));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: FittedBox(child: Text(icon, style: const TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Giitu! {0} tehty', [name]),
                    maxLines: 2,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  if (parts.isNotEmpty) Text(parts.join(' · '), style: sub.copyWith(fontSize: 13.5)),
                ],
              ),
            ),
          ],
        ),
        if (chips.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: chips)],
      ],
    );
  }

  Widget _chip(String text, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
  );

  Widget _title(String title, String subtitle, TextStyle sub, {Widget? badge}) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(subtitle, style: sub, maxLines: 2),
          ],
        ),
      ),
      if (badge != null) ...[const SizedBox(width: 8), Flexible(child: badge)],
    ],
  );

  Widget _badge(ColorScheme cs) => Container(
    key: const ValueKey('effortEstimate'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: cs.outlineVariant),
      borderRadius: BorderRadius.circular(99),
    ),
    // Kahdelle riville tarvittaessa (pienentäminen teki englannin tekstistä liian pienen isolla tekstillä).
    child: Text(
      '✦ ${_estimate!.$2 == EffortSource.heartRate ? t('arvio sykkeestä') : t('arvio vauhdista')}',
      maxLines: 2,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, height: 1.2),
    ),
  );

  Widget _effortRow(bool dark) => EffortScale(value: _intensity, onChanged: (v) => setState(() => _intensity = v));

  Widget _faces(ColorScheme cs, bool dark) => FaceRow(value: _feeling, onTap: _pickFeeling);

  /// Päivän syiden kuvakkeet (ruudukon laatoissa).
  static const _reasonIcons = {
    'väsynyt': '😴',
    'huonosti nukuttu': '🛏️',
    'rankka päivä': '😓',
    'stressi': '😬',
    'sairastumassa': '🤒',
    'huono ruokailu': '🍽️',
    'kipua': '🤕',
  };

  /// Kahden sarakkeen ruudukko yhtä leveitä laattoja (liikkeet ja päivän syyt samalla tavalla; pitkä nimi
  /// rivittyy kahdelle riville). Jos jokin sana ei mahdu puolikkaaseen laattaan (esim. "sairastumassa",
  /// "Bulgarialainen" tai suuri tekstikoko), sen laatta on koko levyinen, jotta sana ei katkea kesken.
  Widget _grid(List<Widget> tiles, List<String> labels) => LayoutBuilder(
    builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      final scaler = MediaQuery.textScalerOf(context);
      bool fits(String label) {
        const style = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.2);
        for (final word in label.split(' ')) {
          final tp = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          // Täyte (2 × 12), emojikuvake (skaalautuu tekstikoon mukana, leveys ~1,4 × fontti) ja väli 8 (ks. _tile).
          if (tp.width > w - 24 - scaler.scale(18) * 1.4 - 8) return false;
        }
        return true;
      }

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < tiles.length; i++) SizedBox(width: fits(labels[i]) ? w : c.maxWidth, child: tiles[i]),
        ],
      );
    },
  );

  Widget _tile({
    required Key key,
    required String label,
    required bool on,
    required Color accent,
    required Color onBg,
    required VoidCallback onTap,
    String? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: on ? onBg : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: on ? accent : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Text(icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(
                    on ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    size: 18,
                    color: on ? accent : cs.outline,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: on ? accent : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _heavySection(ColorScheme cs, TextStyle sub, bool dark) {
    final red = redText(context);
    final yellow = dark ? Sami.yellow : yellowText(context);
    return [
      Divider(height: 28, color: cs.outlineVariant),
      _title(t('Mikä tuntui raskaalta?'), t('Valitse liikkeet, jotka tuntuivat liian raskailta'), sub),
      const SizedBox(height: 12),
      _grid([
        for (final m in _moves)
          _tile(
            key: ValueKey('heavy_$m'),
            label: exerciseLabel(m),
            on: _heavy.contains(m),
            accent: red,
            onBg: red.withValues(alpha: dark ? .16 : .1),
            onTap: () => setState(() => _heavy.contains(m) ? _heavy.remove(m) : _heavy.add(m)),
          ),
      ], [for (final m in _moves) exerciseLabel(m)]),
      const SizedBox(height: 20),
      _title(t('Vaikuttiko jokin muu?'), t('Valinnainen'), sub),
      const SizedBox(height: 12),
      _grid([
        for (final r in dayReasonChoices)
          _tile(
            key: ValueKey('reason_$r'),
            label: t(r),
            icon: _reasonIcons[r],
            on: _reasons.contains(r),
            accent: yellow,
            onBg: Sami.yellow.withValues(alpha: dark ? .16 : .22),
            onTap: () => setState(() => _reasons.contains(r) ? _reasons.remove(r) : _reasons.add(r)),
          ),
      ], [for (final r in dayReasonChoices) t(r)]),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey('heavyDone'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF007229),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _heavyDone,
          child: Text(t('Valmis'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    ];
  }
}

/// Rasitus värillisenä asteikkona (Kevyt vihreä, Reipas keltainen, Kova punainen): Treeni valmis -ikkunassa ja
/// tallennetun liikunnan sivulla. Uusi napautus valittuun poistaa valinnan.
class EffortScale extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const EffortScale({super.key, required this.value, required this.onChanged});

  static const _dark = [
    (Color(0xFF2FAE6B), Color(0xFF12301F), Color(0xFF5BD08A)),
    (Color(0xFFE6A23C), Color(0xFF3A2F14), Color(0xFFF2C060)),
    (Color(0xFFD52B1E), Color(0xFF3B1A18), Color(0xFFFF8378)),
  ];
  static const _light = [
    (Color(0xFF007229), Color(0xFFE3F3E9), Color(0xFF007229)),
    (Color(0xFFB07800), Color(0xFFFFF4D6), Color(0xFF7A5C00)),
    (Color(0xFFC0261B), Color(0xFFFBE6E4), Color(0xFFC0261B)),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        for (var i = 0; i < intensities.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final (key, label, emoji) = intensities[i];
                final (strong, _, fg) = (dark ? _dark : _light)[i];
                final on = value == key;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  transform: Matrix4.translationValues(0, on ? -3 : 0, 0),
                  // Valitsematon harmaana (vain teksti värillinen): ennen kolme värillistä laattaa näyttivät valituilta,
                  // vaikka mitään ei ollut valittu (käyttäjä 14.11.).
                  decoration: BoxDecoration(
                    color: on ? strong : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: on
                        ? const [BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 6))]
                        : null,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: ValueKey('effort_$key'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onChanged(on ? null : key),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
                        child: Column(
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 26, height: 1)),
                            const SizedBox(height: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                t(label),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: on ? Colors.white : fg,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Fiilis viitenä isona kasvona (valittu keltaisella renkaalla ja hieman suurempana).
class FaceRow extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onTap;
  const FaceRow({super.key, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        for (final (v, emoji, label) in feelings)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                key: ValueKey('face_$v'),
                customBorder: const StadiumBorder(),
                onTap: () => onTap(v),
                child: Column(
                  children: [
                    AnimatedScale(
                      scale: value == v ? 1.1 : 1,
                      duration: const Duration(milliseconds: 160),
                      child: Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: value == v
                              ? (dark ? const Color(0xFF3A3214) : const Color(0xFFFFF4C2))
                              : cs.surfaceContainerHighest,
                          border: value == v ? Border.all(color: Sami.yellow, width: 3) : null,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(emoji, style: const TextStyle(fontSize: 30, height: 1)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(t(label), maxLines: 1, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tallennetun treenin rasitus ja fiilis yhdessä kortissa (samat otsikot ja asteikot kuin Treeni valmis
/// -ikkunassa). [onIntensity] null: ei rasitusta (sali); [onFeeling] null: ei fiilistä.
class EffortFeelingCard extends StatelessWidget {
  final String? intensity;
  final ValueChanged<String?>? onIntensity;
  final int? feeling;
  final ValueChanged<int?>? onFeeling;
  const EffortFeelingCard({super.key, this.intensity, this.onIntensity, this.feeling, this.onFeeling});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.25);
    Widget title(String a, String b) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        Text(b, style: sub, maxLines: 2),
      ],
    );
    return Card(
      key: const ValueKey('effortFeelingCard'),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onIntensity != null) ...[
              title(t('Rasitus'), t('Kuinka kovaa kehollesi')),
              const SizedBox(height: 10),
              EffortScale(value: intensity, onChanged: onIntensity!),
              if (onFeeling != null) Divider(height: 28, color: cs.outlineVariant),
            ],
            if (onFeeling != null) ...[
              title(t('Miltä tuntui?'), t('Millainen olo')),
              const SizedBox(height: 12),
              FeelingPicker(value: feeling, onChanged: onFeeling!),
            ],
          ],
        ),
      ),
    );
  }
}
