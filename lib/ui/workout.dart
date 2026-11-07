import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../program.dart';
import '../exercises.dart';
import '../session_compare.dart';
import '../theme.dart';
import 'new_workout.dart';
import 'picker.dart';
import 'share.dart';
import 'rest_banner.dart';
import 'watch.dart';
import 'set_logger.dart';
import 'move_feedback.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Käynnissä oleva / muokattava treeni. Tallentuu automaattisesti jokaisen muutoksen jälkeen.
class WorkoutScreen extends StatefulWidget {
  final Workout workout;
  final PlanDay? planDay;
  const WorkoutScreen({super.key, required this.workout, this.planDay});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  Workout get w => widget.workout;
  late final _notes = TextEditingController(text: w.notes);
  Timer? _tick;

  bool get _isToday => w.date == dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    // Ajastin käynnistyy, kun tämän päivän uusi treeni avataan (ei jo kirjattuun treeniin).
    if (_isToday && w.started == null && w.minutes == null && w.exercises.every((e) => e.sets.isEmpty)) {
      w.started = DateTime.now();
    }
    if (_isToday && w.started != null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
    }
  }

  int? get _elapsed {
    if (w.started == null) return null;
    final m = DateTime.now().difference(w.started!).inMinutes;
    return m < 0 || m > 300 ? null : m; // yli 5 h: kello on unohtunut päälle
  }

  Future<void> _save() async {
    w.notes = _notes.text;
    if (w.isEmpty) return;
    try {
      await store.save(w);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Tallennus epäonnistui: {0}', [e]))));
      }
    }
  }

  Future<void> _addExercise() async {
    final name = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (name == null || !mounted) return;
    var entry = w.exercises.where((e) => e.name == name).firstOrNull;
    if (entry == null) {
      entry = ExerciseEntry(name);
      w.exercises.add(entry);
    }
    await _log(entry);
  }

  PlanItem? _planItem(String name) => widget.planDay?.items.where((i) => i.exercise == name).firstOrNull;

  Future<void> _logPlanned(PlanItem it) async {
    var entry = w.exercises.where((e) => e.name == it.exercise).firstOrNull;
    if (entry == null) {
      entry = ExerciseEntry(it.exercise);
      w.exercises.add(entry);
    }
    await _log(entry);
  }

  Future<void> _log(ExerciseEntry e) async {
    final it = _planItem(e.name);
    final p = settings.program;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SetLoggerScreen(
          date: w.date,
          entry: e,
          onChanged: _save,
          target: it == null || p == null ? null : targetFor(p, it, w.date),
          note: it?.note,
        ),
      ),
    );
    w.exercises.removeWhere((x) => x.sets.isEmpty && x != e);
    if (e.sets.isEmpty) w.exercises.remove(e);
    setState(() {});
    await _save();
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: w.title);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Treenin nimi')),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) {
      setState(() => w.title = v.trim());
      await _save();
    }
  }

  Future<void> _finish() async {
    if (_isToday && _elapsed != null && !w.watchTime) w.minutes = _elapsed; // kellon kesto voittaa ajastimen
    await _save();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(workout: w)));
  }

  Future<void> _deleteWorkout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko treeni?')),
        content: Text(t('Tiedosto {0}.md poistetaan.', [isoDate(w.date)])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista'))),
        ],
      ),
    );
    if (ok != true) return;
    await store.delete(w.date, w.session);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    w.notes = _notes.text;
    if (!w.isEmpty) store.save(w);
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isToday = w.date == dateOnly(DateTime.now());
    final done = w.exercises.where((e) => e.sets.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _rename,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trName(w.title)),
              Text(
                '${isToday ? t('Tänään') : longDateYear(w.date)}'
                '${w.session > 1 ? ' · ${w.session}. treeni' : ''}'
                '${w.minutes != null
                    ? ' · kesto ${fmtDuration(w.minutes!)}'
                    : isToday && _elapsed != null
                    ? ' · ⏱ ${fmtDuration(_elapsed!)}'
                    : ''}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'rename' => _rename(),
              'share' => shareWorkout(context, w),
              _ => _deleteWorkout(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'share', child: Text(t('Jaa'))),
              PopupMenuItem(value: 'rename', child: Text(t('Nimeä treeni'))),
              PopupMenuItem(value: 'delete', child: Text(t('Poista treeni'))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonal(onPressed: _finish, child: Text(t('Valmis ✓'))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Sami.yellow,
        foregroundColor: Colors.black,
        onPressed: _addExercise,
        icon: const Icon(Icons.add),
        label: Text(t('Liike'), style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
        children: [
          const SamiBand(height: 4, pattern: false),
          const Padding(padding: EdgeInsets.only(top: 10), child: RestBanner()),
          if (w.warmup != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Sami.green.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
                border: const Border(left: BorderSide(color: Sami.green, width: 4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_run, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t('Lämmittely · {0} {1} min', [w.warmup!.equipment, w.warmup!.minutes]))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() => w.warmup = null);
                      _save();
                    },
                  ),
                ],
              ),
            ),
          if (done.isEmpty && widget.planDay == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                t('Ei vielä liikkeitä.\nPaina + Liike aloittaaksesi.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          for (final e in done)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _log(e),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ExName(e.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            ),
                            Text(
                              t('{0} sarjaa', [e.workSets.length]),
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in e.sets)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: s.pr ? Sami.yellow : (s.warmup ? Colors.transparent : cs.surfaceContainerHigh),
                                  borderRadius: BorderRadius.circular(20),
                                  border: s.warmup ? Border.all(color: cs.outlineVariant) : null,
                                ),
                                child: Text(
                                  '${s.warmup ? '🔥 ' : ''}${fmtSet(e.name, s)}${s.pr ? ' 🏆' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: s.pr ? Colors.black : (s.warmup ? cs.onSurfaceVariant : null),
                                    fontWeight: s.pr ? FontWeight.w700 : null,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (widget.planDay != null && settings.program != null) ...[
            for (final it in widget.planDay!.items.where((i) => !done.any((e) => e.name == i.exercise)))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Material(
                  color: cs.surfaceContainer.withValues(alpha: .5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    leading: const Icon(Icons.radio_button_unchecked),
                    title: ExName(it.exercise),
                    subtitle: Builder(
                      builder: (_) {
                        final tg = targetFor(settings.program!, it, w.date);
                        final mu = measureOf(it.exercise);
                        return Text(
                          '${tg.sets} × ${tg.reps}${mu == Measure.reps ? '' : ' ${t(mu.unit)}'} · ${reserveTarget(mu, tg.rir)}${it.note != null ? '\n🩹 ${it.note}' : ''}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        );
                      },
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _logPlanned(it),
                  ),
                ),
              ),
          ],
          if (done.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Sami.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _finish,
                icon: const Icon(Icons.flag_rounded),
                label: Text(
                  widget.planDay != null && widget.planDay!.items.any((i) => !done.any((e) => e.name == i.exercise))
                      ? t('Treeni valmis! (osa liikkeistä jäi)')
                      : t('Treeni valmis!'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (settings.watch)
            WatchCard(
              w: w,
              withDuration: true,
              onChanged: () {
                setState(() {});
                _save();
              },
            ),
          SectionLabel(t('Miltä tuntui?')),
          FeelingPicker(
            value: w.feeling,
            onChanged: (v) async {
              setState(() => w.feeling = v);
              // Raskas treeni: kysytään mitkä liikkeet ja miksi (ehdotukset seuraavalle kerralle).
              if (v != null && v <= 2 && await askMoveFeedback(context, w)) setState(() {});
              _save();
            },
          ),
          SectionLabel(t('Muistiinpanot')),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: t('Kivut, unet, tavoitteet… (vapaaehtoinen)'),
              filled: true,
              fillColor: cs.surfaceContainer,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onEditingComplete: _save,
          ),
        ],
      ),
    );
  }
}

/// Valmis-näkymä: yhteenveto, vertailu saman ohjelmapäivän aiempiin kertoihin ja tallennettu tiedosto.
class SavedScreen extends StatefulWidget {
  final Workout workout;
  const SavedScreen({super.key, required this.workout});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  Workout get workout => widget.workout;

  /// Kolme tahmeaa tai raskasta treeniä peräkkäin -> lepovinkki (pois päältä vinkkiasetuksesta).
  String? _tiredTip() {
    if (!settings.tips) return null;
    final recent = [
      workout,
      ...store.workouts.where((w) => w.date.isBefore(workout.date) && w.feeling != null).take(2),
    ];
    if (recent.length < 3 || recent.any((w) => (w.feeling ?? 5) > 2)) return null;
    return t(
      'Kolme raskasta treeniä peräkkäin. Harkitse lepopäivää tai kevyempää viikkoa; uni, '
      'syöminen ja stressi vaikuttavat palautumiseen.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final c = compareSession(workout, store.workouts, settings.program);
    final sets = workout.exercises.fold(0, (a, e) => a + e.workSets.length);
    Widget stat(String v, String l) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(l, style: sub),
          ],
        ),
      ),
    );
    String kg(double v) => '${fmtNum(v.roundToDouble())} kg';
    String pct(double a, double b) {
      final p = ((a - b) / b * 100).round();
      return p > 0 ? '+$p %' : '$p %';
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('Treeni valmis!'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SamiBand(),
          const SizedBox(height: 14),
          Text(t('Giitu, hienoa työtä! 💪'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text(trName(workout.title), style: sub),
          const SizedBox(height: 12),
          Row(
            children: [
              stat(workout.minutes == null ? '–' : fmtDuration(workout.minutes!), t('kesto')),
              const SizedBox(width: 8),
              if (workout.activity != null) ...[
                stat(workout.distanceKm == null ? '–' : '${fmtNum(workout.distanceKm!)} km', t('matka')),
                const SizedBox(width: 8),
                stat(workout.pace ?? t(workout.intensity ?? '–'), workout.pace != null ? t('vauhti') : t('rasitus')),
              ] else ...[
                stat('$sets', t('sarjaa')),
                const SizedBox(width: 8),
                stat(c.volume > 0 ? kg(c.volume) : '–', t('volyymi')),
              ],
            ],
          ),
          SectionLabel(t('Miltä tuntui?')),
          FeelingPicker(
            value: workout.feeling,
            onChanged: (v) async {
              setState(() => workout.feeling = v);
              if (v != null && v <= 2 && await askMoveFeedback(context, workout)) setState(() {});
              if (!workout.isEmpty) await store.save(workout);
            },
          ),
          if (_tiredTip() != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('🌙 ${_tiredTip()}', style: const TextStyle(fontSize: 13)),
            ),
          // Kellon tiedot heti treenin jälkeen (kalorit ja syke näkyvät kellossa vasta lopussa).
          if (settings.watch)
            WatchCard(
              w: workout,
              withDuration: workout.activity == null,
              onChanged: () async {
                setState(() {});
                if (!workout.isEmpty) await store.save(workout);
              },
            )
          else if (watchLine(workout) != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(watchLine(workout)!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          if (c.prs > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '🏆 ${c.prs > 1 ? t('{0} ennätystä!', [c.prs]) : t('1 ennätys!')}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: Sami.yellow),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
            child: c.skipReason != null
                ? Text(
                    t(
                      'Tämä oli {0}: kuorma on tarkoituksella pienempi, joten tätä kertaa ei verrata aiempiin. '
                      'Tärkeintä on palautua.',
                      [c.skipReason],
                    ),
                  )
                : c.previous == null
                ? Text(t('Ensimmäinen kerta tällä treenillä. Ensi kerralla näet, miten kehityit.'))
                : workout.activity != null
                ? Text(
                    '${t('Edellinen kerta: {0} ({1})', [workout.activity!, shortDate(c.previous!.date)])}: '
                    '${[if (c.previous!.minutes != null) fmtDuration(c.previous!.minutes!), if (c.previous!.distanceKm != null) '${fmtNum(c.previous!.distanceKm!)} km', ?c.previous!.pace, ?c.previous!.intensity].join(' · ')}',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('Verrattuna edelliseen kertaan ({0})', [shortDate(c.previous!.date)]),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      if (c.previousVolume != null && c.previousVolume! > 0 && c.volume > 0)
                        Text(
                          t('Volyymi {0} → {1} ({2})', [
                            kg(c.previousVolume!),
                            kg(c.volume),
                            pct(c.volume, c.previousVolume!),
                          ]),
                          style: sub,
                        ),
                      if (c.previous!.minutes != null && workout.minutes != null)
                        Text(
                          t('Kesto {0} → {1}', [fmtDuration(c.previous!.minutes!), fmtDuration(workout.minutes!)]),
                          style: sub,
                        ),
                      if (c.previous!.feeling != null && workout.feeling != null)
                        Text(
                          t('Fiilis {0} → {1}', [feelingOf(c.previous!.feeling)!.$2, feelingOf(workout.feeling)!.$2]),
                          style: sub,
                        ),
                      const SizedBox(height: 8),
                      for (final e in c.exercises)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                switch (e.trend) {
                                  1 => '↑ ',
                                  -1 => '↓ ',
                                  2 => '＋ ',
                                  _ => '= ',
                                },
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: switch (e.trend) {
                                    1 => Sami.green,
                                    -1 => Sami.red,
                                    _ => cs.onSurfaceVariant,
                                  },
                                ),
                              ),
                              Expanded(child: ExName(e.name)),
                              Text(
                                e.before == null ? e.now : '${e.before} → ${e.now}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      if (c.history.length > 2) ...[
                        const SizedBox(height: 8),
                        Text(
                          t('Volyymi viime kerroilla: {0} kg', [
                            c.history.map((h) => fmtNum(h.$2.roundToDouble())).join(' → '),
                          ]),
                          style: sub,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        t(
                          'Paras sarja verrataan arvioituna maksimina, joten raskaampi paino tai useampi toisto '
                          'näkyy nousuna. Kevennys- ja paluuviikot jätetään vertailusta pois.',
                        ),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ExpansionTile(
              shape: const Border(),
              title: Text(t('Tallennettu tiedosto')),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                FutureBuilder(
                  future: store.rootDir(),
                  builder: (context, snap) => SelectableText(
                    snap.hasData ? '${snap.data!.path}/${store.fileName(workout.date)}' : '',
                    style: sub,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  workout.isEmpty ? t('(tyhjä treeni, ei tallennettu)') : workoutToMarkdown(workout),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => shareWorkout(context, workout),
                  icon: const Icon(Icons.share),
                  label: Text(t('Jaa')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => NewWorkoutScreen(date: workout.date, newSession: true)),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(t('Uusi treeni tälle päivälle')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: Text(t('Takaisin etusivulle')),
          ),
        ],
      ),
    );
  }
}
