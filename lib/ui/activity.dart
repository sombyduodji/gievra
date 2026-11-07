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

  Future<void> _save() async {
    w.notes = _notes.text;
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
        title: Text(w.activity ?? t('Liikunta')),
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
                  for (final s in sports.where((s) => s.group == g))
                    ActionChip(
                      avatar: Text(s.icon),
                      label: Text(s.name),
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
                  child: Text(w.activity!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ),
                TextButton(onPressed: () => setState(() => w.activity = null), child: Text(t('Vaihda laji'))),
              ],
            ),
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
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(t('Vauhti {0}', [w.pace]), style: TextStyle(color: cs.onSurfaceVariant)),
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
