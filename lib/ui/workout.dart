import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rest.dart';
import '../app_state.dart';
import '../models.dart';
import '../program.dart';
import '../running.dart';
import '../share_text.dart' show thousands;
import '../sports.dart';
import '../exercises.dart';
import '../session_compare.dart';
import '../superset.dart';
import '../theme.dart';
import 'new_workout.dart';
import 'picker.dart';
import 'share.dart';
import 'rest_banner.dart';
import 'running_screen.dart';
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
  Timer? _notesSave;

  bool get _isToday => w.date == dateOnly(DateTime.now());

  /// Valmiiksi merkitty treeni avautuu lukutilaan; muokkaus kysyy ensin.
  late bool _locked = w.minutes != null || w.feeling != null;

  /// Tallennettu (lopetettu) treeni: kellon tiedot ja fiilis näkyvät treenin sivulla.
  late final bool _finished = _locked;

  Future<void> _unlock() async {
    if (await askEditSaved(context) && mounted) setState(() => _locked = false);
  }

  List<Widget> _guard(List<Widget> xs) =>
      !_locked ? xs : [xs.first, for (final x in xs.skip(1)) EditGuard(locked: true, onTap: _unlock, child: x)];

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
    // Uusi treeni ohjelmasta: ohjelman supersarjat treeniin (muokattavissa ⋮ → Supersarjat).
    if (w.supersets.isEmpty && w.exercises.every((e) => e.sets.isEmpty) && widget.planDay != null) {
      final groups = <String, List<String>>{};
      for (final i in widget.planDay!.items) {
        if (i.group != null) groups.putIfAbsent(i.group!, () => []).add(i.exercise);
      }
      w.supersets = [
        for (final k in groups.keys.toList()..sort())
          if (groups[k]!.toSet().length >= 2) groups[k]!.toSet().toList(),
      ];
    }
    // Muistiinpanot tallentuvat 2 s kirjoittamisen jälkeen (ei vasta kentästä poistuttaessa).
    _notes.addListener(() {
      _notesSave?.cancel();
      _notesSave = Timer(const Duration(seconds: 2), _save);
    });
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('Tallennus epäonnistui: {0}', [errorText(e)]))));
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
    w.skipMoves.remove(e.name); // poistettu liike lisätty takaisin
    final it = _planItem(e.name);
    final p = settings.program;
    final group = supersetOf(w, e.name);
    // Paluuarvo: true = liike merkitty valmiiksi, liikkeen nimi = supersarjan seuraava liike.
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => SetLoggerScreen(
          date: w.date,
          entry: e,
          onChanged: _save,
          target: it == null || p == null ? null : targetFor(p, it, w.date),
          note: it?.note,
          superset: group,
          supersetNext: group == null ? null : () => supersetNext(w, e.name, planned: _planned),
        ),
      ),
    );
    // Tyhjät liikkeet pois; supersarjan jäsenet näkyvät ryhmäkortissa silti (ryhmä on treenin tiedoissa).
    w.exercises.removeWhere((x) => x.sets.isEmpty && x != e);
    if (e.sets.isEmpty) w.exercises.remove(e);
    if (result == true && e.sets.isNotEmpty) w.doneMoves.add(e.name);
    setState(() {});
    await _save();
    if (result is String && mounted) await _logByName(result);
  }

  /// Liike tehty: merkitty valmiiksi tai ohjelman työsarjat täynnä.
  bool _isDone(ExerciseEntry e) {
    if (w.doneMoves.contains(e.name)) return true;
    final it = _planItem(e.name);
    return it != null && e.workSets.length >= it.sets;
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

  /// Treeni valmis -painiketta painettu (tuplanapautus ei avaa kahta kyselyä eikä tallenna kahdesti).
  bool _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      // Fiilis ensin ponnahdusikkunassa (Ohita jatkaa ilman; takaisin peruu lopetuksen eikä muuta mitään).
      if (w.feeling == null) {
        final v = await askFeeling(context);
        if (v == null || !mounted) return;
        if (v != feelingSkipped) {
          w.feeling = v;
          if (v <= 2) await askMoveFeedback(context, w);
          if (!mounted) return;
        }
      }
      rest.stop(); // treeni valmis: ei palautusmuistutusta
      // Kellon tai käsin asetettu kesto voittaa ajastimen.
      if (_isToday && _elapsed != null && !w.fixedTime) w.minutes = _elapsed;
      await _save();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(workout: w)));
    } finally {
      _finishing = false;
    }
  }

  /// Muokkaa kestoa (kun kellon tiedot eivät ole käytössä; muuten kesto muutetaan Kellon tiedot -ruudusta):
  /// aloitusaika ja kesto, päättymisaika näytetään. Käsin asetettu kesto ei muutu ajastimesta.
  Future<void> _editDuration() async {
    if (_locked) {
      await _unlock();
      if (_locked || !mounted) return;
    }
    final r = await showDialog<(int, TimeOfDay?)>(
      context: context,
      builder: (_) => _DurationDialog(
        minutes: w.minutes ?? _elapsed ?? 60,
        start: w.started == null ? null : TimeOfDay.fromDateTime(w.started!),
      ),
    );
    if (r == null || !mounted) return;
    final (m, start) = r;
    setState(() {
      w.minutes = m;
      w.manualTime = true;
      w.watchTime = false;
      if (start != null) w.started = DateTime(w.date.year, w.date.month, w.date.day, start.hour, start.minute);
    });
    await _save();
  }

  bool _deleted = false;

  Future<void> _deleteWorkout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko treeni?')),
        content: Text(
          t('Tiedosto {0}.md poistetaan.', [workoutPath(w.date, w.session).split('/').last.replaceAll('.md', '')]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista'))),
        ],
      ),
    );
    if (ok != true) return;
    // Ei tallennusta sivulta poistuttaessa (dispose), muuten poistettu treeni palaisi.
    _deleted = true;
    _notesSave?.cancel();
    rest.stop(); // ei palautusmuistutusta poistetusta treenistä
    await store.delete(w.date, w.session);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _notesSave?.cancel();
    w.notes = _notes.text;
    if (!w.isEmpty && !_deleted) store.save(w);
    _notes.dispose();
    super.dispose();
  }

  /// Tehty liike korttina (sarjat näkyvissä).
  /// Liike, jolla on sarjoja. Valmis: tiivis vihreä rivi ✓. Ohjelman liike kesken: täyttyvä rengas, "kesken" ja
  /// jäljellä olevat sarjat (näkyy, mihin palata, jos välillä tekee muita liikkeitä). Oma lisäys: sarjat kuten ennen.
  Widget _doneCard(ExerciseEntry e, ColorScheme cs) {
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    String chip(SetEntry s) => '${s.warmup ? '🔥 ' : ''}${fmtSet(e.name, s)}${s.pr ? ' 🏆' : ''}';
    if (_isDone(e)) {
      final work = e.sets.where((s) => !s.warmup);
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Material(
          key: ValueKey('done-${e.name}'),
          color: Sami.green.withValues(alpha: .1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Sami.green.withValues(alpha: .35)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _log(e),
            onLongPress: () => _moveMenu(e.name),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Sami.green, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExName(e.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                          '${setsLabel(e.workSets.length)} · ${work.map(chip).join(', ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sub,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final planned = _planItem(e.name)?.sets;
    final left = planned == null ? 0 : planned - e.workSets.length;
    final progress = planned != null && planned > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        key: ValueKey('progress-${e.name}'),
        shape: progress
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Sami.yellow, width: 1.5),
              )
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _log(e),
          onLongPress: () => _moveMenu(e.name),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (progress) ...[
                      SizedBox.square(
                        dimension: 24,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: CircularProgressIndicator(
                            value: (e.workSets.length / planned).clamp(0.0, 1.0),
                            strokeWidth: 3.5,
                            strokeCap: StrokeCap.round,
                            backgroundColor: cs.outlineVariant,
                            color: Sami.yellow,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          ExName(e.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          if (progress)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                              decoration: BoxDecoration(
                                color: Sami.yellow.withValues(alpha: .25),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(t('kesken'), style: TextStyle(fontSize: 11, color: yellowText(context))),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      progress ? '${e.workSets.length}/$planned' : setsLabel(e.workSets.length),
                      style: progress
                          ? TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: yellowText(context))
                          : sub,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.only(left: progress ? 34 : 0),
                  child: Wrap(
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
                            chip(s),
                            style: TextStyle(
                              fontSize: 12,
                              color: s.pr ? Colors.black : (s.warmup ? cs.onSurfaceVariant : null),
                              fontWeight: s.pr ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                      // Jäljellä olevat sarjat: napautus jatkaa kirjausta.
                      if (left > 0)
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _log(e),
                          child: DottedChip(text: '+ ${setsLabel(left)}', color: yellowText(context)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ohjelman liike, jota ei ole vielä aloitettu.
  Widget _planTile(PlanItem it, ColorScheme cs) => Padding(
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
              '${tg.sets} × ${tg.reps}${mu == Measure.reps ? '' : ' ${t(mu.unit)}'}'
              '${it.pct == null || it.kind != null ? '' : ' @ ${fmtNum(double.parse((it.pct! * 100).toStringAsFixed(1)))} %'}'
              ' · ${reserveTarget(mu, tg.rir)}${it.note != null ? '\n🩹 ${trNote(it.note!)}' : ''}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            );
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _logPlanned(it),
        onLongPress: () => _moveMenu(it.exercise),
      ),
    ),
  );

  /// Liikkeet järjestyksessä: tehdyt, sitten ohjelman jäljellä olevat; supersarja yhtenä korttina ensimmäisen
  /// jäsenensä kohdalla.
  List<Widget> _items(List<ExerciseEntry> done, ColorScheme cs) {
    final showPlan = !_locked && widget.planDay != null && settings.program != null;
    final planned = showPlan
        ? widget.planDay!.items
              .where((i) => !w.skipMoves.contains(i.exercise) && !done.any((e) => e.name == i.exercise))
              .toList()
        : <PlanItem>[];
    final order = [...done.map((e) => e.name), ...planned.map((i) => i.exercise)];
    final out = <Widget>[];
    final shown = <List<String>>{};
    for (final n in order) {
      final g = supersetOf(w, n);
      if (g != null) {
        if (shown.add(g)) out.add(_groupCard(g, cs));
        continue;
      }
      final e = done.where((x) => x.name == n).firstOrNull;
      out.add(e != null ? _doneCard(e, cs) : _planTile(planned.firstWhere((i) => i.exercise == n), cs));
    }
    return out;
  }

  /// Ohjelman sarjamäärä liikkeelle (null = ei ohjelmassa): supersarjan kierrokset.
  int? _planned(String name) {
    final it = _planItem(name);
    final p = settings.program;
    return it == null || p == null ? null : targetFor(p, it, w.date).sets;
  }

  /// Supersarja tai kiertoharjoittelu yhtenä korttina: jäsenet järjestyksessä, seuraava korostettuna.
  Widget _groupCard(List<String> g, ColorScheme cs) {
    final label = supersetLabel(w, g.first).substring(0, 1);
    final current = supersetCurrent(w, g, planned: _planned);
    final round = supersetRound(w, g, planned: _planned);
    final rounds = g.map(_planned).whereType<int>().fold<int>(0, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    g.length > 2 ? t('Kiertoharjoittelu {0}', [label]) : t('Supersarja {0}', [label]),
                    style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                  ),
                ),
                Text(
                  current == null
                      ? t('valmis ✓')
                      : rounds > 0
                      ? t('kierros {0} / {1}', [round, rounds])
                      : t('kierros {0}', [round]),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final n in g)
              Builder(
                builder: (_) {
                  final e = w.exercises.where((x) => x.name == n).firstOrNull;
                  final sets = e?.workSets ?? const <SetEntry>[];
                  final it = _planItem(n);
                  final finished = e != null && _isDone(e);
                  final next = n == current;
                  return Material(
                    color: next ? cs.primary.withValues(alpha: .10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _logByName(n),
                      onLongPress: () => _moveMenu(n),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 30,
                              child: Text(supersetLabel(w, n), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ExName(n, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(
                                    sets.isNotEmpty
                                        ? sets.map((s) => fmtSet(n, s)).join(' · ')
                                        : it != null && settings.program != null
                                        ? '${targetFor(settings.program!, it, w.date).sets} × ${targetFor(settings.program!, it, w.date).reps}'
                                        : t('ei vielä sarjoja'),
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (finished)
                              const Icon(Icons.check_circle, color: Sami.green, size: 20)
                            else if (next)
                              Text(t('seuraava ›'), style: TextStyle(fontSize: 12, color: cs.primary)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _logByName(String name) async {
    var entry = w.exercises.where((e) => e.name == name).firstOrNull;
    if (entry == null) {
      entry = ExerciseEntry(name);
      w.exercises.add(entry);
    }
    await _log(entry);
  }

  /// Supersarjojen muokkaus: nykyiset ryhmät (purku) ja uusi ryhmä valituista liikkeistä.
  /// Pitkä painallus liikkeeseen: poista tästä treenistä, lisää supersarjaan tai pura supersarja.
  Future<void> _moveMenu(String n) async {
    if (_locked) return _unlock();
    final group = supersetOf(w, n);
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: ExName(n, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            if (group == null)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(t('Lisää supersarjaan')),
                onTap: () => Navigator.pop(ctx, 'superset'),
              )
            else
              ListTile(
                leading: const Icon(Icons.link_off),
                title: Text(t('Pura supersarja')),
                onTap: () => Navigator.pop(ctx, 'unlink'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text(t('Poista tästä treenistä'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            ListTile(leading: const Icon(Icons.close), title: Text(t('Peruuta')), onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (v) {
      case 'superset':
        await _addToSuperset(n);
      case 'unlink':
        setState(() => w.supersets.remove(group));
        await _save();
      case 'delete':
        await _deleteMove(n);
    }
  }

  /// Tämän treenin liikkeet, joita voi yhdistää (tehdyt ja ohjelman jäljellä olevat).
  List<String> get _moveNames => {
    ...w.exercises.where((e) => e.sets.isNotEmpty).map((e) => e.name),
    ...?widget.planDay?.items.map((i) => i.exercise).where((x) => !w.skipMoves.contains(x)),
  }.toList();

  /// Supersarja liikkeestä [n]: valitaan liikkeet, jotka tehdään vuorotellen sen kanssa (valintajärjestyksessä).
  Future<void> _addToSuperset(String n) async {
    final free = _moveNames.where((x) => x != n && supersetOf(w, x) == null).toList();
    final picked = <String>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(t('Lisää supersarjaan')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Valitse liikkeet, jotka tehdään vuorotellen tämän kanssa. Tauko vasta kierroksen jälkeen.'),
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text('1. ${exerciseLabel(n)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (free.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(t('Lisää ensin vähintään kaksi liikettä.')),
                  ),
                for (final x in free)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: picked.contains(x),
                    title: Text(
                      picked.contains(x) ? '${picked.indexOf(x) + 2}. ${exerciseLabel(x)}' : exerciseLabel(x),
                    ),
                    onChanged: (v) => set(() => v == true ? picked.add(x) : picked.remove(x)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
            FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(t('OK'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => w.supersets.add([n, ...picked]));
    await _save();
  }

  /// Poistaa liikkeen tästä treenistä: kirjatut sarjat (kysytään ensin) ja ohjelman liikkeen tämän päivän listalta.
  Future<void> _deleteMove(String n) async {
    final e = w.exercises.where((x) => x.name == n).firstOrNull;
    if (e != null && e.sets.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Poistetaanko {0} tästä treenistä?', [exerciseLabel(n)])),
          content: Text(t('Kirjatut sarjat ({0}) poistuvat.', [e.sets.length])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      w.exercises.removeWhere((x) => x.name == n);
      w.doneMoves.remove(n);
      for (final g in [...w.supersets]) {
        if (g.remove(n) && g.length < 2) w.supersets.remove(g);
      }
      if (_planItem(n) != null) w.skipMoves.add(n);
    });
    await _save();
  }

  Future<void> _editSupersets() async {
    final names = {
      ...w.exercises.where((e) => e.sets.isNotEmpty).map((e) => e.name),
      ...?widget.planDay?.items.map((i) => i.exercise),
    }.toList();
    final picked = <String>[];
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final free = names.where((n) => supersetOf(w, n) == null).toList();
          return AlertDialog(
            title: Text(t('Supersarjat')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Valitut liikkeet tehdään vuorotellen valintajärjestyksessä, tauko vasta kierroksen jälkeen.'),
                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  for (final g in w.supersets)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link),
                      title: Text(g.map(exerciseLabel).join(' → ')),
                      trailing: IconButton(
                        tooltip: t('Pura supersarja'),
                        icon: const Icon(Icons.link_off),
                        onPressed: () => set(() => w.supersets.remove(g)),
                      ),
                    ),
                  if (free.length >= 2) ...[
                    const Divider(),
                    for (final n in free)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: picked.contains(n),
                        title: Text(
                          picked.contains(n) ? '${picked.indexOf(n) + 1}. ${exerciseLabel(n)}' : exerciseLabel(n),
                        ),
                        onChanged: (v) => set(() => v == true ? picked.add(n) : picked.remove(n)),
                      ),
                  ] else if (w.supersets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(t('Lisää ensin vähintään kaksi liikettä.')),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Valmis'))),
              if (picked.length >= 2)
                FilledButton(
                  onPressed: () => set(() {
                    w.supersets.add([...picked]);
                    picked.clear();
                  }),
                  child: Text(t('Yhdistä ({0})', [picked.length])),
                ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isToday = w.date == dateOnly(DateTime.now());
    final done = w.exercises.where((e) => e.sets.isNotEmpty).toList();
    return Scaffold(
      // Valmiissa (lukitussa) treenissä ei palautusajastinta.
      // Alareuna varattu treenin lopetukselle: Treeni valmis -painike aina samassa paikassa (ajastin sen yllä).
      bottomNavigationBar: _locked
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RestBanner(),
                if (done.isNotEmpty)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Sami.green,
                          foregroundColor: Colors.white,
                          // Matala näyttö: tiiviimpi, ettei palautusajastimen kanssa vie puolta näytöstä.
                          padding: EdgeInsets.symmetric(vertical: MediaQuery.sizeOf(context).height < 700 ? 8 : 16),
                        ),
                        onPressed: _finish,
                        icon: const Icon(Icons.flag_rounded),
                        // Osa liikkeistä jäi: toisella rivillä pienemmällä, ettei teksti jää kapeaksi.
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t('Treeni valmis!'),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                            if (widget.planDay != null &&
                                widget.planDay!.items.any(
                                  (i) => !w.skipMoves.contains(i.exercise) && !done.any((e) => e.name == i.exercise),
                                ))
                              Text(
                                '(${t('osa liikkeistä jäi')})',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _locked ? _unlock() : _rename(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trName(w.title)),
              Text(
                '${isToday ? t('Tänään') : longDateYear(w.date)}'
                '${w.session > 1 ? ' · ${w.session}. treeni' : ''}'
                '${w.minutes != null
                    ? ' · ${t('kesto {0}', [fmtDuration(w.minutes!)])}'
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
              'rename' => _locked ? _unlock() : _rename(),
              'share' => shareWorkout(context, w),
              'duration' => _editDuration(),
              'superset' => _locked ? _unlock() : _editSupersets(),
              _ => _deleteWorkout(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'share', child: Text(t('Jaa'))),
              PopupMenuItem(value: 'rename', child: Text(t('Nimeä treeni'))),
              PopupMenuItem(value: 'superset', child: Text(t('Supersarjat'))),
              // Kellon tiedot päällä: kesto muutetaan Kellon tiedot -ruudusta (sama arvo).
              if (!settings.watch) PopupMenuItem(value: 'duration', child: Text(t('Muokkaa kestoa'))),
              PopupMenuItem(value: 'delete', child: Text(t('Poista treeni'))),
            ],
          ),
          // Valmis-painike vain listan lopussa (vihreä "Treeni valmis!"), ei yläpalkissa.
          if (_locked) LockButton(onTap: _unlock),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: _guard([
          const SamiBand(height: 4, pattern: false),
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
                  Expanded(child: Text(t('Lämmittely · {0} {1} min', [t(w.warmup!.equipment), w.warmup!.minutes]))),
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
                t('Ei vielä liikkeitä.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ..._items(done, cs),
          // Liikkeen lisäys listan perässä (alareuna on Treeni valmis -painikkeelle).
          if (!_locked)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                key: const ValueKey('addExercise'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: yellowText(context),
                  side: BorderSide(color: Sami.yellow.withValues(alpha: .6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: Text(t('Lisää liike'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          // Kesken olevassa treenissä kellon tiedot ja fiilis kysytään lopussa (Treeni valmis); tallennetussa näkyvät.
          if (settings.watch && _finished)
            WatchCard(
              w: w,
              withDuration: true,
              onChanged: () {
                setState(() {});
                _save();
              },
            ),
          if (_finished) SectionLabel(t('Miltä tuntui?')),
          if (_finished)
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
        ]),
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

  Future<void> _persist() async {
    if (!workout.isEmpty) await store.save(workout);
  }

  Future<void> _changeFeeling() async {
    final sport = workout.activity != null;
    final v = await askFeeling(context, askIntensity: sport, intensity: workout.intensity);
    if (v == null || !mounted) return;
    setState(() {
      if (sport) workout.intensity = askedIntensity;
      if (v != feelingSkipped) workout.feeling = v;
    });
    if (v == feelingSkipped) {
      await _persist();
      return;
    }
    if (v <= 2 && workout.activity == null && await askMoveFeedback(context, workout)) setState(() {});
    await _persist();
  }

  /// Kellon tiedot: Health Connect -haku ja käsin syöttö (sama kortti kuin kirjauksessa) paneelissa.
  Future<void> _editWatch() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: WatchCard(
            w: workout,
            withDuration: workout.activity == null,
            onChanged: () async {
              setSheet(() {});
              setState(() {});
              await _persist();
            },
          ),
        ),
      ),
    ),
  );

  /// Tallennettu tiedosto (polku ja Markdown) paneelissa.
  Future<void> _showFile() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final sub = TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            Text(t('Tallennettu tiedosto'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            FutureBuilder(
              future: store.rootDir(),
              builder: (context, snap) => SelectableText(
                snap.hasData ? '${snap.data!.path}/${store.fileName(workout.date, workout.session)}' : '',
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
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final c = compareSession(workout, store.workouts, settings.program);
    final sets = workout.exercises.fold(0, (a, e) => a + e.workSets.length);
    String kg(double v) => '${fmtNum(v.roundToDouble())} kg';
    String pct(double a, double b) {
      final p = ((a - b) / b * 100).round();
      return p > 0 ? '+$p %' : '$p %';
    }

    final sport = sportOf(workout.activity);
    final intensity = intensityOf(workout.intensity);
    final hasWatch = workout.kcal != null || workout.hrAvg != null || workout.hrMax != null || workout.steps != null;
    // Vain täytetyt luvut (ei tyhjiä "–"-ruutuja).
    final stats = <(String, String)>[
      if (workout.seconds != null)
        (fmtDurationSec(workout.seconds!), t('kesto'))
      else if (workout.minutes != null)
        (fmtDuration(workout.minutes!), t('kesto')),
      if (workout.activity == null) ...[
        if (sets > 0) ('$sets', sets == 1 ? t('sarja') : t('sarjaa')),
        if (c.volume > 0) (kg(c.volume), t('volyymi')),
      ] else ...[
        if (workout.distanceKm != null) ('${fmtNum(workout.distanceKm!)} km', t('matka')),
        if (workout.pace != null) (workout.pace!, t('vauhti')),
        if (workout.distanceKm == null && intensity != null) ('${intensity.$3} ${t(intensity.$2)}', t('rasitus')),
      ],
    ];
    final watchStats = <(String, String)>[
      if (workout.kcal != null) ('🔥 ${workout.kcal}', t('kcal')),
      if (workout.hrAvg != null) ('❤️ ${workout.hrAvg}', t('keskisyke')),
      if (workout.hrMax != null && workout.steps == null) ('💓 ${workout.hrMax}', t('maksimisyke')),
      if (workout.steps != null) ('👣 ${thousands(workout.steps!)}', t('askeleet')),
    ];
    Widget statRow(List<(String, String)> xs, {double size = 18}) => Row(
      children: [
        for (final (i, (v, l)) in xs.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      v,
                      style: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(l, style: sub),
                ],
              ),
            ),
          ),
        ],
      ],
    );
    final feel = feelingOf(workout.feeling);
    final when = [
      shortDate(workout.date),
      if (workout.started != null)
        [
          fmtClock(TimeOfDay.fromDateTime(workout.started!)),
          if (workout.minutes != null)
            fmtClock(TimeOfDay.fromDateTime(workout.started!.add(Duration(minutes: workout.minutes!)))),
        ].join('–'),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(t('Treeni valmis!'))),
      // Toiminnot alareunassa: pienet linkit ja yksi pääpainike.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TextButton.icon(
                        onPressed: () => shareWorkout(context, workout),
                        icon: const Icon(Icons.share, size: 18),
                        label: Text(t('Jaa')),
                      ),
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => NewWorkoutScreen(date: workout.date, newSession: true)),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(t('Uusi treeni')),
                      ),
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TextButton.icon(
                        onPressed: _showFile,
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: Text(t('Tiedosto')),
                      ),
                    ),
                  ),
                ],
              ),
              FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: Text(t('Valmis'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          const SamiBand(),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Sami.green.withValues(alpha: .15), shape: BoxShape.circle),
                child: Text(sport?.icon ?? '💪', style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Giitu! {0} tehty', [
                        workout.activity != null ? sportName(workout.activity!) : trName(workout.title),
                      ]),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    Text(when, style: sub),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (stats.isNotEmpty) statRow(stats),
          if (watchStats.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: settings.watch ? _editWatch : null,
              child: statRow(watchStats, size: 16),
            ),
            if (workout.healthSource != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '♥ ${t('Health Connectista ({0})', [workout.healthSource])}',
                  style: TextStyle(fontSize: 12, color: Sami.green),
                ),
              ),
          ] else if (settings.watch && !hasWatch)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Material(
                color: Sami.yellow.withValues(alpha: .12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Sami.yellow.withValues(alpha: .6)),
                ),
                child: ListTile(
                  key: const ValueKey('fetchWatch'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: Icon(Icons.favorite_border, color: yellowText(context)),
                  title: Text(t('Hae kellon tiedot')),
                  subtitle: Text(t('Kalorit ja syke Health Connectista tai käsin'), style: sub),
                  trailing: Icon(Icons.chevron_right, color: yellowText(context)),
                  onTap: _editWatch,
                ),
              ),
            ),
          const SizedBox(height: 10),
          // Fiilis yhtenä rivinä (kysytty jo lopussa); Muuta avaa saman valinnan.
          Material(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              key: const ValueKey('feelingRow'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: Text(feel?.$2 ?? '🙂', style: TextStyle(fontSize: 26, color: feel == null ? cs.outline : null)),
              title: Text(feel == null ? t('Miltä tuntui?') : t('Fiilis: {0}', [t(feel.$3).toLowerCase()])),
              subtitle: workout.activity != null && intensity != null && workout.distanceKm != null
                  ? Text('${intensity.$3} ${t(intensity.$2)}', style: sub)
                  : null,
              trailing: Text(
                feel == null ? t('Valitse') : t('Muuta'),
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
              ),
              onTap: _changeFeeling,
            ),
          ),
          // Juoksu: vertailu edelliseen samantyyppiseen lenkkiin ja oma kehitysnäkymä.
          if (isRun(workout.activity) && workout.paceSecPerKm != null) _RunCompare(run: workout),
          if (_tiredTip() != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('🌙 ${_tiredTip()}', style: const TextStyle(fontSize: 13)),
            ),
          if (c.prs > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '🏆 ${c.prs > 1 ? t('{0} ennätystä!', [c.prs]) : t('1 ennätys!')}',
                style: TextStyle(fontWeight: FontWeight.w700, color: yellowText(context)),
              ),
            ),
          const SizedBox(height: 14),
          // Juoksussa vertailu on yllä (samantyyppinen lenkki); yleinen vertailu vain muille.
          if (!(isRun(workout.activity) && workout.paceSecPerKm != null))
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
                      '${t('Edellinen kerta: {0} ({1})', [sportName(workout.activity!), shortDate(c.previous!.date)])}: '
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
        ],
      ),
    );
  }
}

/// Juoksun jälkeen: vauhti ja nopeus, vertailu edelliseen suunnilleen yhtä pitkään lenkkiin, linkki kehitysnäkymään.
class _RunCompare extends StatelessWidget {
  final Workout run;
  const _RunCompare({required this.run});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prev = previousRun(store.workouts, run);
    String? cmp;
    if (prev != null) {
      final d = (run.paceSecPerKm! - prev.paceSecPerKm!).round();
      cmp = t('Edellinen {0} ({1}): {2} min/km', [t('juoksu'), shortDate(prev.date), fmtPace(prev.paceSecPerKm!)]);
      cmp += d == 0 ? ' · =' : (d < 0 ? ' · ${t('{0} s/km nopeampi', [-d])}' : ' · ${t('{0} s/km hitaampi', [d])}');
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vauhti näkyy jo yllä olevissa luvuissa; tässä vain vertailu ja nopeus.
          Text('🏃 ${cmp ?? '${fmtNum((run.speedKmh! * 10).round() / 10)} km/h'}'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RunningScreen())),
              icon: const Icon(Icons.show_chart),
              label: Text(t('Juoksun kehitys')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muokkaa kestoa -ikkuna: kesto minuutteina ja aloitusaika (valinnainen), päättymisaika näytetään.
/// Oma tila, jotta tekstikentän ohjain vapautetaan vasta, kun ikkuna on sulkeutunut.
class _DurationDialog extends StatefulWidget {
  final int minutes;
  final TimeOfDay? start;
  const _DurationDialog({required this.minutes, required this.start});
  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late final _c = TextEditingController(text: '${widget.minutes}');
  late TimeOfDay? _start = widget.start;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = int.tryParse(_c.text.trim());
    final valid = m != null && m > 0 && m <= 1440;
    String end(TimeOfDay s, int m) =>
        fmtClock(TimeOfDay.fromDateTime(DateTime(2000, 1, 1, s.hour, s.minute).add(Duration(minutes: m))));
    return AlertDialog(
      title: Text(t('Muokkaa kestoa')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: t('Kesto (min)')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text(t('Aloitusaika'))),
              TextButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_start == null ? t('ei tiedossa') : fmtClock(_start!)),
                onPressed: () async {
                  final v = await pickTime(context, _start ?? TimeOfDay.now(), title: t('Aloitusaika'));
                  if (v != null && mounted) setState(() => _start = v);
                },
              ),
            ],
          ),
          if (_start != null && valid)
            Text(
              t('Päättyi klo {0}', [end(_start!, m)]),
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Peruuta'))),
        FilledButton(onPressed: valid ? () => Navigator.pop(context, (m, _start)) : null, child: Text(t('Tallenna'))),
      ],
    );
  }
}

/// Katkoviivareunainen siru: jäljellä olevat sarjat keskeneräisessä liikkeessä.
class DottedChip extends StatelessWidget {
  final String text;
  final Color color;
  const DottedChip({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorder(color.withValues(alpha: .7)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _DashedBorder extends CustomPainter {
  final Color color;
  const _DashedBorder(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
