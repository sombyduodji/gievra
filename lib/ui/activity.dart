import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../sports.dart';
import '../theme.dart';
import 'watch.dart';
import 'widgets.dart';
import 'workout.dart';
import '../l10n.dart';

/// Urheilu tai liikunta: laji, kesto, matka (kestävyyslajit), rasitus, fiilis ja muistiinpanot.
class ActivityScreen extends StatefulWidget {
  final Workout workout;
  const ActivityScreen({super.key, required this.workout});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  Workout get w => widget.workout;
  late final _notes = TextEditingController(text: w.notes);

  @override
  void initState() {
    super.initState();
    w.minutes ??= 45;
    w.intensity ??= 'reipas';
  }

  bool get _timed => sportOf(w.activity)?.distance ?? false;

  /// Kestävyyslajeissa tarkka aika (h:mm:ss); muissa minuutit.
  int get _sec => w.seconds ?? (w.minutes ?? 45) * 60;
  void _setSec(int s) {
    w.seconds = s.clamp(60, 24 * 3600);
    w.minutes = (w.seconds! / 60).round();
  }

  Future<void> _askTime() async {
    final c = TextEditingController(text: fmtDurationSec(_sec));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Aika')),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(hintText: '25:31', helperText: t('min:s tai h:min:s')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
    final s = v == null ? null : parseDurationSec(v);
    if (s != null && s > 0) setState(() => _setSec(s));
  }

  Future<void> _save() async {
    w.notes = _notes.text;
    if (!isRun(w.activity)) w.runType = null;
    if (!_timed) w.seconds = null;
    w.title = w.activity ?? 'Liikunta'; // tiedostoon aina suomeksi
    await store.save(w);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(workout: w)));
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sport = sportOf(w.activity);
    return Scaffold(
      appBar: AppBar(
        title: Text(w.activity == null ? t('Liikunta') : sportName(w.activity!)),
        actions: [
          if (w.activity != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(onPressed: _save, child: Text(t('Tallenna ✓'))),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          if (w.activity == null) ...[
            for (final g in sportGroups) ...[
              SectionLabel(t(g)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Eniten käytetyt ensin.
                  for (final s in sportsByUse(
                    store.workouts.map((w) => w.activity),
                    among: sports.where((s) => s.group == g),
                  ))
                    ActionChip(
                      avatar: Text(s.icon),
                      label: Text(sportName(s.name)),
                      onPressed: () => setState(() => w.activity = s.name),
                    ),
                ],
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(sport?.icon ?? '✨', style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sportName(w.activity!),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(onPressed: () => setState(() => w.activity = null), child: Text(t('Vaihda laji'))),
              ],
            ),
            if (isRun(w.activity)) ...[
              SectionLabel(t('Lenkin tyyppi')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (k, l, e, inten, _) in runTypes)
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: Text(e),
                      label: Text(t(l)),
                      selected: w.runType == k,
                      onSelected: (on) => setState(() {
                        w.runType = on ? k : null;
                        if (on) w.intensity = inten;
                      }),
                    ),
                ],
              ),
              if (runTypeOf(w.runType) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(t(runTypeOf(w.runType)!.$5), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
            ],
            if (_timed) ...[
              SectionLabel(t('Aika')),
              ValueStepper(
                value: fmtDurationSec(_sec),
                unit: '',
                onMinus: () => setState(() => _setSec(_sec - 60)),
                onPlus: () => setState(() => _setSec(_sec + 60)),
                onTap: _askTime,
              ),
            ] else ...[
              SectionLabel(t('Kesto')),
              ValueStepper(
                value: '${w.minutes}',
                unit: 'min',
                onMinus: () => setState(() => w.minutes = (w.minutes! - 5).clamp(5, 600)),
                onPlus: () => setState(() => w.minutes = (w.minutes! + 5).clamp(5, 600)),
                onTap: () async {
                  final v = await askNumber(context, t('Kesto (min)'), w.minutes!.toDouble(), decimals: false);
                  if (v != null && v > 0) setState(() => w.minutes = v.round());
                },
              ),
            ],
            if (sport?.distance ?? false) ...[
              SectionLabel(t('Matka')),
              ValueStepper(
                value: fmtNum(w.distanceKm ?? 0),
                unit: 'km',
                onMinus: () => setState(() => w.distanceKm = ((w.distanceKm ?? 0) - .5).clamp(0, 500)),
                onPlus: () => setState(() => w.distanceKm = (w.distanceKm ?? 0) + .5),
                onTap: () async {
                  final v = await askNumber(context, t('Matka (km)'), w.distanceKm ?? 5);
                  if (v != null && v >= 0) setState(() => w.distanceKm = v == 0 ? null : v);
                },
              ),
              if (w.pace != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      _Metric(value: fmtPace(w.paceSecPerKm!), unit: '/km', label: t('vauhti')),
                      const SizedBox(width: 8),
                      _Metric(value: fmtNum((w.speedKmh! * 10).round() / 10), unit: 'km/h', label: t('keskinopeus')),
                    ],
                  ),
                ),
            ],
            SectionLabel(t('Rasitus')),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final (k, l, e) in intensities) ButtonSegment(value: k, label: Text('$e ${t(l)}'))],
              selected: {w.intensity ?? 'reipas'},
              onSelectionChanged: (v) => setState(() => w.intensity = v.first),
            ),
            if (settings.watch) WatchCard(w: w, onChanged: () => setState(() {})),
            SectionLabel(t('Miltä tuntui?')),
            FeelingPicker(value: w.feeling, onChanged: (v) => setState(() => w.feeling = v)),
            SectionLabel(t('Muistiinpanot')),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: t('Reitti, sää, joukkue, tulos… (vapaaehtoinen)'),
                filled: true,
                fillColor: cs.surfaceContainer,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _save,
              child: Text(t('Tallenna'), style: TextStyle(fontSize: 17)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value, unit, label;
  const _Metric({required this.value, required this.unit, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
