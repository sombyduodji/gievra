import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rest.dart';
import 'orientation_lock.dart';
import '../app_state.dart';
import '../injuries.dart' show injuryAdjusted;
import '../models.dart';
import '../ongoing.dart';
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
import 'suggest_exercise.dart';
import 'rest_banner.dart';
import 'running_screen.dart';
import 'watch.dart';
import 'set_logger.dart';
import 'move_feedback.dart';
import 'widgets.dart';
import 'finish_sheet.dart';
import 'hr_ui.dart';
import 'kcal_card.dart';
import 'health_import.dart' show HealthImportButton;
import 'hc_update.dart';
import 'activity.dart' show ActivityScreen;
import 'record_screen.dart' show RoutePainter;
import '../maps/map_view.dart' show RouteMap;
import '../gpx.dart' show parseGpx;
import '../gps_filter.dart' show TrackPoint;
import '../heart_rate.dart' show hr, applyHeartRate, activeKcal, hrProfile;
import '../l10n.dart';
import '../time_zone.dart';

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

  /// Käynnissä oleva treeni: tänään, tai ajastin käynnissä alle 5 h (treeni jatkuu yli puolenyön).
  bool get _live {
    if (_isToday) return true;
    final s = w.started;
    if (s == null || w.minutes != null || w.fixedTime || dateOnly(s) != w.date) return false;
    final age = DateTime.now().difference(s);
    return !age.isNegative && age < const Duration(hours: 5);
  }

  /// Valmiiksi merkitty treeni avautuu lukutilaan; muokkaus kysyy ensin.
  late bool _locked = w.minutes != null || w.feeling != null;

  /// Sykevyön istunto tälle treenille (päivä ja treenin numero).
  String get _hrKey => 'gym:${isoDate(w.date)}-${w.session}';

  /// Tallennettu (lopetettu) treeni: kellon tiedot ja fiilis näkyvät treenin sivulla.
  late final bool _finished = _locked;

  Future<void> _unlock() async {
    if (await askEditSaved(context) && mounted) setState(() => _locked = false);
  }

  /// Muistiinpanot ovat muokattavissa myös lukittuna kuten liikunnassa (yötesti 27.11. Nothing: "Muokataanko?"
  /// -kysymyksen jälkeen kenttä ei saanut fokusta ja lista hyppäsi, kun ohjelman tekemättömät liikkeet ilmestyivät).
  static final _openWhenLocked = {const ValueKey('notesLabel'), const ValueKey('notes')};

  List<Widget> _guard(List<Widget> xs) => !_locked
      ? xs
      : [
          xs.first,
          for (final x in xs.skip(1))
            _openWhenLocked.contains(x.key) ? x : EditGuard(locked: true, onTap: _unlock, child: x),
        ];

  /// Aikavyöhyke vaihtui kesken treenin: sama kalenteripäivä uuden vyöhykkeen keskiyönä (muuten "tänään",
  /// ajastin ja kesto katoavat).
  void _tzChanged() {
    w.date = rebaseDay(w.date);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    lockPortrait();
    tzWatch.addListener(_tzChanged);
    _hadContent = !w.isEmpty;
    // Ajastin käynnistyy, kun tämän päivän uusi treeni avataan (ei jo kirjattuun treeniin).
    if (_isToday && w.started == null && w.minutes == null && w.exercises.every((e) => e.sets.isEmpty)) {
      w.started = DateTime.now();
    }
    if (_live && w.started != null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
    }
    // Sykevyö (jos valittu): tämän päivän keskeneräinen treeni kerää sykkeen.
    if (_live && !_locked) hr.begin(_hrKey);
    // Ilmoitus treenin alusta asti (myös lämmittelyn aikana ja ennen ensimmäistä sarjaa; käyttäjä 17.11.).
    if (_live && !_locked && w.minutes == null && w.feeling == null) Ongoing.setOpenGym(w);
    // Lämmittelyllä alkava treeni talteen heti: etusivun Jatka-kortti ja palkki näkyvät, jos näkymästä poistutaan.
    if (_live && w.warmup != null && !_stored && w.exercises.every((e) => e.sets.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _save() : null);
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

  /// Tyhjeni tässä näkymässä (ainoa sarja tai liike poistettiin) ja tiedosto on tallessa. Valmiiksi tyhjänä
  /// avattua tiedostoa (vanha versio, käsin tehty) ei poisteta pelkästä katsomisesta.
  bool _hadContent = false; // asetetaan initStatessa ja jokaisessa tallennuksessa
  bool get _stored => _hadContent && store.onDay(w.date).any((x) => x.session == w.session);

  Future<void> _save() async {
    if (_deleted) return; // myöhäinen tallennus ei tuo poistettua treeniä takaisin
    w.notes = _notes.text;
    try {
      // Tyhjäksi muuttunut tallennettu treeni (ainoa sarja tai liike poistettu): poistetaan tiedosto, muuten
      // poistettu sarja palaisi etusivulle ja seuraavalla avauksella.
      if (w.isEmpty) {
        if (_stored) await store.delete(w.date, w.session);
        return;
      }
      _hadContent = true;
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

  // Ohjelman liike myös vaihtoehdon nimellä (käyttäjä 16.11.: "penkki tai pysäytetty penkki").
  PlanItem? _planItem(String name) => widget.planDay?.items.where((i) => i.covers(name)).firstOrNull;

  Future<void> _logPlanned(PlanItem it) async {
    var entry = w.exercises.where((e) => it.covers(e.name)).firstOrNull;
    if (entry == null) {
      final name = it.alts.isEmpty ? it.exercise : await _chooseAlt(it);
      if (name == null || !mounted) return;
      entry = ExerciseEntry(name);
      w.exercises.add(entry);
    }
    await _log(entry);
  }

  /// Vaihtoehtoinen liike: kumpi tänään? Viimeksi tehty päivä näkyy, jotta vuorottelu on helppoa.
  Future<String?> _chooseAlt(PlanItem it) => showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(t('Minkä teet tänään?'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          for (final n in it.choices)
            ListTile(
              title: ExName(n),
              subtitle: Text(switch (store.lastBefore(n, w.date, w.session)) {
                null => t('ei vielä tehty'),
                final last => t('viimeksi {0}', [shortDateY(last.$1)]),
              }, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, n),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

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
          session: w.session,
          entry: e,
          onChanged: _save,
          target: it == null || p == null ? null : targetFor(p, it, w.date),
          note: it?.note,
          superset: group,
          supersetNext: group == null ? null : () => supersetNext(w, e.name, planned: _planned),
        ),
      ),
    );
    // Vammatilan vaihto: alkuperäinen pois tästä treenistä (ohjelma ei muutu) ja korvaaja tilalle.
    if (result is ExerciseSwap && e.sets.isEmpty) {
      final to =
          result.to ??
          (mounted
              ? await Navigator.of(context)
                    .push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()))
              : null);
      if (to == null || !mounted) {
        if (e.sets.isEmpty) w.exercises.remove(e);
        setState(() {});
        return;
      }
      w.exercises.remove(e);
      if (it != null) w.skipMoves.add(e.name);
      final next = w.exercises.where((x) => x.name == to).firstOrNull ?? (ExerciseEntry(to));
      if (!w.exercises.contains(next)) w.exercises.add(next);
      await _save();
      if (!mounted) return;
      setState(() {});
      await _log(next);
      return;
    }
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
    if (_finishing || rest.justClosed) return; // myös: palautuspalkki sulkeutui juuri sormen alta
    _finishing = true;
    try {
      // Treeni valmis (käyttäjä 20.11.): kello pysähtyy ja treeni tallentuu heti; fiilis kysytään yhteenvedon
      // alareunassa (ennen erillinen ikkuna, sitten yhteenveto ja Sulje).
      // Kesto lopetusnapautuksen hetkellä.
      final endSec = _live && _elapsed != null && !w.fixedTime ? DateTime.now().difference(w.started!).inSeconds : null;
      rest.stop(); // treeni valmis: ei palautusmuistutusta
      // Kellon tai käsin asetettu kesto voittaa ajastimen.
      // Tarkka kesto sekunteina (käyttäjä 16.11.: tallennetaan ja lasketaan tarkasta, vain yhteenvedot pyöristetään);
      // minuutit pyöristettynä (1:55 → 2 min) vanhoille lukijoille ja yhteenvetoihin.
      if (endSec != null) {
        final sec = endSec;
        w.seconds = sec;
        w.minutes = minutesFromSeconds(sec);
      }
      // Sykevyö: käyrä, keskisyke, maksimi ja kalorit (kesto ensin, se tarvitaan kaloreihin).
      final s = await hr.end(_hrKey);
      if (s != null) applyHeartRate(w, s);
      await _save();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(workout: w, fresh: true)));
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
      w.seconds = null; // käsin asetettu kesto korvaa ajanoton tarkan ajan
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
    unlockPortrait();
    tzWatch.removeListener(_tzChanged);
    if (identical(Ongoing.openGym, w)) Ongoing.setOpenGym(null);
    _tick?.cancel();
    _notesSave?.cancel();
    w.notes = _notes.text;
    // Treenistä poistuttiin: sykkeet säilyvät, jos treeniä jatketaan. Tyhjä (tallentamaton) tai poistettu treeni
    // hylkää ne, ettei seuraava avaus peri leposykettä ja yhteyskatkoa ennen oikeaa alkua.
    if (w.isEmpty || _deleted) {
      hr.end(_hrKey);
    } else {
      hr.pause(_hrKey);
    }
    if (!_deleted) {
      if (!w.isEmpty) {
        store.save(w);
      } else if (_stored) {
        store.delete(w.date, w.session);
      }
    }
    _notes.dispose();
    super.dispose();
  }

  /// Tehty liike korttina (sarjat näkyvissä).
  /// Liike, jolla on sarjoja. Valmis: tiivis vihreä rivi ✓. Ohjelman liike kesken: täyttyvä rengas, "kesken" ja
  /// jäljellä olevat sarjat (näkyy, mihin palata, jos välillä tekee muita liikkeitä). Oma lisäys: sarjat kuten ennen.
  Widget _doneCard(ExerciseEntry e, ColorScheme cs) {
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    String chip(SetEntry s) => '${s.warmup ? '🔥 ' : ''}${fmtSetHand(e.name, s)}${s.pr ? ' 🏆' : ''}';
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
            onTap: () => rest.justClosed ? null : _log(e), // palautuspalkki sulkeutui juuri sormen alta
            onLongPress: () => _moveMenu(e.name),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: greenText(context), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExName(e.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                          // Tiivis luettelo, yksikkö kerran (kahden käsipainon liikkeissä kg/käsi).
                          '${setsLabel(e.workSets.length)} · ${fmtSetsUnit(e.name, work)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sub,
                        ),
                      ],
                    ),
                  ),
                  // Sarjapisteet (luonnos T1): täytetty = tehty sarja.
                  _SetDots(done: e.workSets.length, total: e.workSets.length, color: greenText(context)),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final planned = _planItem(e.name)?.sets;
    // Valmis (tallennettu) treeni: ei "kesken"-merkkiä, rengasta eikä "+ N sarjaa" (yötesti 15.11.).
    final left = planned == null || _finished ? 0 : planned - e.workSets.length;
    final progress = !_finished && planned != null && planned > 0;
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
          onTap: () => rest.justClosed ? null : _log(e), // palautuspalkki sulkeutui juuri sormen alta
          onLongPress: () => _moveMenu(e.name),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (progress) ...[
                      // Rengas vain kuvana: ruudunlukija luki sen arvon nimen eteen ("33, Bulgarian Split Squat"),
                      // edistyminen kerrotaan jo tekstinä (1/3).
                      ExcludeSemantics(
                        child: SizedBox.square(
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
                          onTap: () => rest.justClosed ? null : _log(e), // palautuspalkki sulkeutui juuri sormen alta
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
            final target = bindNumbers(
              '${tg.text}${mu == Measure.reps ? '' : ' ${t(mu.unit)}'}'
              '${it.pct == null || it.kind != null ? '' : ' @ ${fmtNum(double.parse((it.pct! * 100).toStringAsFixed(1)))} %'}'
              ' · ${reserveTarget(mu, tg.rir)}',
            );
            return Text(
              '$target'
              '${it.alts.isEmpty ? '' : '\n${t('tai: {0}', [it.alts.map(exerciseLabel).join(', ')])}'}'
              '${it.note != null
                  ? '\n🩹 ${trNote(it.note!)}'
                  : injuryMark(it.exercise) != null
                  ? '\n${injuryMark(it.exercise)}'
                  : ''}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            );
          },
        ),
        // Tekemättömät sarjat ontoin pistein (luonnos T1).
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SetDots(done: 0, total: it.sets, color: greenText(context)),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => rest.justClosed ? null : _logPlanned(it),
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
              .where((i) => !w.skipMoves.contains(i.exercise) && !done.any((e) => i.covers(e.name)))
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
                                        ? fmtSetsUnit(n, sets)
                                        : it != null && settings.program != null
                                        ? targetFor(settings.program!, it, w.date).text
                                        : t('ei vielä sarjoja'),
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (finished)
                              Icon(Icons.check_circle, color: greenText(context), size: 20)
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
      if (_planItem(n) case final it?) w.skipMoves.add(it.exercise);
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
                      // Koko treenin lopetus täytettynä vihreänä 🏁-painikkeena (ulkoasun kohennus 16.11.): erottuu
                      // liikkeen läpinäkyvästä "✓ … valmis" -painikkeesta, ettei niitä sekoiteta.
                      child: FilledButton.icon(
                        key: const ValueKey('finishWorkout'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00843D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          // Matala näyttö: tiiviimpi, ettei palautusajastimen kanssa vie puolta näytöstä.
                          padding: EdgeInsets.symmetric(vertical: MediaQuery.sizeOf(context).height < 700 ? 8 : 14),
                        ),
                        onPressed: _finish,
                        icon: const Text('🏁', style: TextStyle(fontSize: 18)),
                        // Osa liikkeistä jäi: toisella rivillä pienemmällä, ettei teksti jää kapeaksi.
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t('Lopeta treeni'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            if (widget.planDay != null &&
                                widget.planDay!.items.any(
                                  (i) => !w.skipMoves.contains(i.exercise) && !done.any((e) => i.covers(e.name)),
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
        // Otsikko ja päivärivi: suurella tekstillä (Asetukset → Tekstin koko) korkeampi palkki.
        toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight).clamp(kToolbarHeight, 80),
        title: GestureDetector(
          onTap: () => _locked ? _unlock() : _rename(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BarTitle(Text(trName(w.title))),
              BarTitle(
                Text(
                  '${isToday ? t('Tänään') : longDateYear(w.date)}'
                  '${w.session > 1 ? ' · ${t('{0}. treeni', [w.session])}' : ''}'
                  '${w.minutes != null
                      ? ' · ${t('kesto {0}', [fmtDuration(w.minutes!)])}'
                      : _live && _elapsed != null
                      ? ' · ⏱ ${fmtDuration(_elapsed!)}'
                      : ''}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
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
          PauseReminder(),
          const InjuryReminder(),
          // Sykevyö: iso syke, alue ja minikäyrä treenin ajan.
          const Padding(padding: EdgeInsets.only(top: 4), child: HrLiveStrip()),
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
                    tooltip: t('Poista'),
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
          if (_finished) HrDetails(w),
          if (_finished)
            EffortFeelingCard(
              feeling: w.feeling,
              onFeeling: (v) async {
                setState(() => w.feeling = v);
                // Raskas treeni: kysytään mitkä liikkeet ja miksi (ehdotukset seuraavalle kerralle).
                if (v != null && v <= 2 && await askMoveFeedback(context, w)) setState(() {});
                _save();
              },
            ),
          KeyedSubtree(key: const ValueKey('notesLabel'), child: SectionLabel(t('Muistiinpanot'))),
          TextField(
            key: const ValueKey('notes'),
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            maxLength: notesLimit(w.notes),
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            buildCounter: notesCounter,
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

  /// Aiempi treeni kalenterista tai listasta: otsikkona treenin nimi, alareunassa Muokkaa (ei Valmis / Uusi treeni).
  final bool history;

  /// Juuri lopetettu treeni (käyttäjä 20.11.): tiivis yhteenveto yhdelle ruudulle ja alareunassa "Miltä tuntui?"
  /// kasvoina ja leveä Ohita; valinta vie etusivulle. Treeni on jo tallennettu.
  final bool fresh;
  const SavedScreen({super.key, required this.workout, this.history = false, this.fresh = false});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  // Muokkauksen jälkeen tallennettu versio varastosta (muokkausnäkymä käsittelee kopiota).
  Workout get workout =>
      store.workouts.where((w) => w.date == widget.workout.date && w.session == widget.workout.session).firstOrNull ??
      widget.workout;

  /// Liikelista muokattavaksi (lukittu kuten ennen: muokkaus kysyy ensin).
  Future<void> _edit() async {
    final p = settings.program;
    final day = p?.plan.where((x) => x.matches(workout.dayKey)).firstOrNull;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutScreen(
          workout: workout.copy(),
          planDay: day == null ? null : injuryAdjusted(day, settings.injuries),
        ),
      ),
    );
    if (!mounted) return;
    // Poistettu tai tyhjennetty: ei jäädä vanhaan yhteenvetoon.
    if (!store.workouts.any((w) => w.date == widget.workout.date && w.session == widget.workout.session)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  /// Sivun alun suojaviive: Treeni valmis -ikkunan kasvon pikakaksois- tai kolmoisnapautus ei osu tämän sivun
  /// painikkeisiin (esim. "Uusi treeni" samassa kohdassa), kun ikkuna on jo sulkeutunut (havaittu Samsungilla 15.11.).
  bool _armed = false;
  Timer? _armTimer;
  Timer? _suggestTimer;

  bool _showAllMoves = false, _closing = false;

  /// Reitti tiedostosta (tallennus siirtää GPX:n omaan tiedostoonsa ja tyhjentää routeGpx:n).
  List<List<TrackPoint>>? _route;

  @override
  void initState() {
    super.initState();
    if (widget.fresh) {
      store.readRoute(workout).then((g) {
        if (g != null && mounted) setState(() => _route = parseGpx(g));
      });
    }
    // Oman liikkeen ehdotus kerran, treenin jälkeen (ei kesken treenin, käyttäjä 16.11.). Vain jos treenissä on
    // omia liikkeitä; ajastin perutaan, jos sivulta poistutaan ennen sitä.
    if (!widget.history && widget.workout.exercises.any((e) => settings.customExercises.contains(e.name))) {
      _suggestTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) maybeSuggestOwnExercises(context, widget.workout);
      });
    }
    _armTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _suggestTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(ignoring: !_armed, child: widget.fresh ? _buildFresh(context) : _buildBody(context));

  /// Liikunnan oma sivu reitin korjaukseen; palatessa reitti ja luvut luetaan uudelleen.
  Future<void> _fixRoute() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ActivityScreen(workout: workout.copy())));
    if (!mounted) return;
    final g = await store.readRoute(workout);
    if (!mounted) return;
    setState(() => _route = g == null ? null : parseGpx(g));
  }

  /// Fiilis tai Ohita yhteenvedon alareunasta: tallennus ja etusivulle. Salissa Raskas/Tahmea kysyy ensin liikkeet.
  Future<void> _done(int? v) async {
    if (_closing) return;
    _closing = true;
    try {
      final w = workout;
      if (v != null) {
        // Raskas tai Tahmea: mikä painoi (salissa myös raskaat liikkeet), kaikissa lajeissa (käyttäjä 20.11.).
        if (v <= 2) {
          final r = await showHeavySheet(context, w, v);
          if (r == null || !mounted) return; // paneeli suljettiin: jäädään yhteenvetoon
        }
        w.feeling = v;
      }
      await _persist();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } finally {
      _closing = false;
    }
  }

  /// Tiivis yhteenveto juuri lopetetulle treenille (mockup 20.11.): luvut ruutuina, reitti, liikkeet lyhyesti,
  /// matala sykekäyrä ja kellon tiedot; alareunassa fiilis.
  Widget _buildFresh(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final w = workout;
    final c = compareSession(w, store.workouts, settings.program);
    final sets = w.exercises.fold(0, (a, e) => a + e.workSets.length);
    final sport = sportOf(w.activity);
    final gym = w.activity == null;
    final active = activeKcal(w, hrProfile());
    final tiles = <(String, String, bool)>[
      if (w.seconds != null)
        (fmtDurationSec(w.seconds!), t('kesto'), false)
      else if (w.minutes != null)
        (fmtDuration(w.minutes!), t('kesto'), false),
      if (gym) ...[
        if (sets > 0) ('$sets', sets == 1 ? t('sarja') : t('sarjaa'), false),
        if (c.volume > 0) ('${thousands(c.volume.round())} kg', t('volyymi'), false),
      ] else ...[
        if (w.distanceKm != null) ('${fmtNum((w.distanceKm! * 100).round() / 100)} km', t('matka'), false),
        // Pyöräily ym.: keskinopeus (km/h) vauhdin sijaan, kuten liikuntasivulla.
        if (speedSports.contains(w.activity) && w.distanceKm != null && (w.durationSec ?? 0) > 0)
          ('${fmtNum(((w.distanceKm! / (w.durationSec! / 3600)) * 10).round() / 10)} km/h', t('keskinopeus'), false)
        else if (w.pace != null)
          (w.pace!, t('vauhti'), false),
      ],
      if (w.hrAvg != null) ('❤ ${w.hrAvg}', t('syke ka.'), false),
      if (w.kcal != null) ('🔥 ${active ?? w.kcal}', active != null ? t('aktiiviset kcal') : t('kcal'), false),
      if (w.steps != null) (thousands(w.steps!), t('askelta'), false),
      if (c.prs > 0) ('🏆 ${c.prs}', c.prs == 1 ? t('ennätys') : t('ennätystä'), true),
    ];
    Widget tile((String, String, bool) x) => Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: x.$3 ? Sami.yellow.withValues(alpha: .18) : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(x.$1, maxLines: 1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(x.$2, maxLines: 1, style: sub),
          ),
        ],
      ),
    );
    final route = _route;
    final moves = w.exercises.where((e) => e.workSets.isNotEmpty).toList();
    final shown = _showAllMoves ? moves : moves.take(3).toList();
    final name = gym ? trName(w.title) : sportName(w.activity!);
    return Scaffold(
      appBar: AppBar(
        title: BarTitle(Text(t('Treeni valmis!'))),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(4), child: SamiBand(height: 4, pattern: false)),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: Column(
            key: const ValueKey('savedFeeling'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Miltä tuntui?'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              FaceRow(value: w.feeling, onTap: _done),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('savedSkip'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: cs.outline, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _done(null),
                child: Text(t('Ohita'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (gym ? Sami.red : Sami.green).withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: gym
                    ? Icon(Icons.fitness_center_rounded, size: 22, color: redText(context))
                    : Text(sport?.icon ?? '🏃', style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('Giitu! {0} tehty', [name]),
                  maxLines: 2,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Text(shortDate(w.date), style: sub),
            ],
          ),
          if (route != null && route.any((s) => s.length >= 2)) ...[
            const SizedBox(height: 10),
            SizedBox(
              key: const ValueKey('savedRoute'),
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RouteMap(
                  segments: route,
                  fallback: Container(
                    color: cs.surfaceContainer,
                    child: CustomPaint(painter: RoutePainter(route, cs.primary), child: const SizedBox.expand()),
                  ),
                ),
              ),
            ),
            // Reitin korjaus poluille, kyydin poisto tai reitin poisto liikunnan omalla sivulla (käyttäjä 20.11.:
            // ennen erillinen tarkistussivu ennen yhteenvetoa).
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const ValueKey('savedFixRoute'),
                onPressed: _fixRoute,
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: Text(t('Korjaa reittiä')),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Kolme ruutua rivissä.
          for (var i = 0; i < tiles.length; i += 3) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              children: [
                for (var j = i; j < i + 3; j++) ...[
                  if (j > i) const SizedBox(width: 6),
                  Expanded(child: j < tiles.length ? tile(tiles[j]) : const SizedBox()),
                ],
              ],
            ),
          ],
          if (gym && moves.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('savedExercises'),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in shown)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${e.sets.any((x) => x.pr) ? '🏆 ' : ''}${exerciseLabel(e.name)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            e.workSets.length == 1 ? t('1 sarja') : t('{0} sarjaa', [e.workSets.length]),
                            style: sub,
                          ),
                          const SizedBox(width: 6),
                          _SetPill(
                            exercise: e.name,
                            set: e.workSets.reduce((a, b) => b.kg > a.kg || (b.kg == a.kg && b.reps > a.reps) ? b : a),
                          ),
                        ],
                      ),
                    ),
                  if (moves.length > 3)
                    TextButton(
                      key: const ValueKey('savedAllMoves'),
                      onPressed: () => setState(() => _showAllMoves = !_showAllMoves),
                      child: Text(_showAllMoves ? t('Näytä vähemmän') : t('+{0} liikettä', [moves.length - 3])),
                    ),
                ],
              ),
            ),
          ],
          HrDetails(w, compact: true),
          // Rasitus sykkeestä (käyttäjä 20.11.): käyrän kanssa syke-kortissa, pelkällä keskisykkeellä omana rivinään.
          if (w.hrSeries == null) HrEffortRow(w),
          // Kellon tiedot: odotus ja lisäys (valinta tiedoittain) samalla sivulla.
          if (HcUpdateRow.wanted(w))
            HcUpdateRow(
              key: ValueKey('hc_${w.date}_${w.session}'),
              w: w,
              waiting: true,
              onApplied: () async {
                await _persist();
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    );
  }

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
    final r = await showFinishSheet(context, w: workout, heavyStep: !sport);
    if (r == null || !mounted) return;
    // Rasitus tulee sykkeestä (käyttäjä 20.11.): vanha tallennettu rasitus säilyy tiedostossa.
    setState(() {
      if (r.feeling != feelingSkipped) workout.feeling = r.feeling;
      // Hyvä fiilis ei jätä vanhoja "Mikä painoi?" -vastauksia (yötesti 21.11.: Raskas → Hyvä näytti yhä "Liian
      // raskas: …" ja keventäisi seuraavaa ehdotusta); sama kuin lukitun liikunnan fiiliksessä (activity.dart).
      if (r.feeling > 2) {
        workout.tooHeavy.clear();
        workout.dayReasons.clear();
      }
    });
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

  Widget _buildBody(BuildContext context) {
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
        // Ennätykset ylös omana ruutunaan (käyttäjä 17.11.: "missä ennätykset?" — rivi oli liikkeiden alla).
        if (c.prs > 0) ('🏆 ${c.prs}', c.prs == 1 ? t('ennätys') : t('ennätystä')),
      ] else ...[
        if (workout.distanceKm != null) ('${fmtNum(workout.distanceKm!)} km', t('matka')),
        if (workout.pace != null) (workout.pace!, t('vauhti')),
        if (workout.distanceKm == null && intensity != null) ('${intensity.$3} ${t(intensity.$2)}', t('rasitus')),
      ],
    ];
    final active = activeKcal(workout, hrProfile());
    final ring = workout.kcal != null && active != null;
    final watchStats = <(String, String)>[
      // Aktiiviset tiedossa: kalorit renkaana rivin alla (käyttäjä 17.11.).
      if (workout.kcal != null && active == null) ('🔥 ${workout.kcal}', t('kcal')),
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
            // Seinäkellon laskuna (ei DateTime.add): vyöhykkeen vaihto kesken treenin ei sekoita alkua ja loppua
            // ("22:42–07:43" ajanotolla 1 min; Android 11 -emulaattori 15.11.).
            fmtClock(
              TimeOfDay.fromDateTime(
                DateTime(
                  2000,
                  1,
                  1,
                  workout.started!.hour,
                  workout.started!.minute,
                ).add(Duration(minutes: workout.minutes!)),
              ),
            ),
        ].join('–'),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: BarTitle(
          Text(
            widget.history
                ? (workout.activity != null ? sportName(workout.activity!) : trName(workout.title))
                : t('Treeni valmis!'),
          ),
        ),
        // Ohut saamen nauha otsikon alla kuten muissa näkymissä (ennen paksu siksak sisällön alussa).
        bottom: const PreferredSize(preferredSize: Size.fromHeight(4), child: SamiBand(height: 4, pattern: false)),
      ),
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
                  if (!widget.history)
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
              if (widget.history)
                // Aiempi treeni: muokkaus liikelistassa (kuten liikunnan Muokkaa).
                OutlinedButton.icon(
                  key: const ValueKey('savedEdit'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(t('Muokkaa'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                )
              else
                // Treeni on jo tallennettu: painike vain sulkee yhteenvedon (käyttäjä 19.11.: "Valmis" näytti siltä,
                // että jotain pitää vielä tallentaa).
                FilledButton(
                  key: const ValueKey('savedClose'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: Text(t('Sulje'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                // Väri lajin mukaan kuten muualla: sali punainen (käsipaino), liikunta vihreä (lajin merkki).
                decoration: BoxDecoration(
                  color: (workout.activity != null ? Sami.green : Sami.red).withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: workout.activity != null
                    ? Text(sport?.icon ?? '🏃', style: const TextStyle(fontSize: 30))
                    : Icon(Icons.fitness_center_rounded, size: 30, color: redText(context)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.history
                          ? (workout.activity != null ? sportName(workout.activity!) : trName(workout.title))
                          : t('Giitu! {0} tehty', [
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
          if (workout.activity == null) ...[
            // Sali (käyttäjä 17.11.): keho ensin kuten liikunnassa: syke, kalorit ja sykekäyrä, sitten liikkeet.
            if (watchStats.isNotEmpty || ring) ...[
              const SizedBox(height: 8),
              if (watchStats.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: settings.watch ? _editWatch : null,
                  child: statRow(watchStats, size: 16),
                ),
              if (ring)
                Padding(
                  padding: EdgeInsets.only(top: watchStats.isEmpty ? 0 : 8),
                  child: KcalRing(
                    total: workout.kcal!,
                    active: active,
                    color: cs.surfaceContainer,
                    onTap: settings.watch ? _editWatch : null,
                  ),
                ),
              if (workout.healthSource != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '♥ ${t('Health Connectista ({0})', [workout.healthSource])}',
                    style: TextStyle(fontSize: 12, color: greenText(context)),
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
            // Health Connect: rivi vain, kun kellolla on uutta tietoa (juuri tallennetussa odottaa kellon siirtoa).
            if (HcUpdateRow.wanted(workout))
              HcUpdateRow(
                key: ValueKey('hc_${workout.date}_${workout.session}'),
                w: workout,
                waiting: !widget.history,
                onApplied: () async {
                  await _persist();
                  if (mounted) setState(() {});
                },
              ),
            HrDetails(workout),
            // Salitreenin liikkeet sarjoineen: sarjat "pilleinä" (käyttäjä 17.11.: modernimmaksi); lämmittelyt
            // himmeinä, ennätykset kultaisina, pudotussarja nuolella.
            if (workout.activity == null && workout.exercises.any((e) => e.sets.isNotEmpty)) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('savedExercises'),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, e) in workout.exercises.where((e) => e.sets.isNotEmpty).indexed) ...[
                      if (i > 0) Divider(height: 22, color: cs.outlineVariant.withValues(alpha: .5)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              exerciseLabel(e.name),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            [
                              e.workSets.length == 1 ? t('1 sarja') : t('{0} sarjaa', [e.workSets.length]),
                              if (unitOnce(e.name, e.workSets)) kgUnit(e.name, short: true),
                            ].join(' · '),
                            style: sub,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final st in e.sets) _SetPill(exercise: e.name, set: st)],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Fiilis yhtenä rivinä (kysytty jo lopussa); Muuta avaa saman valinnan.
            Material(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                key: const ValueKey('feelingRow'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Text(
                  feel?.$2 ?? '🙂',
                  style: TextStyle(fontSize: 26, color: feel == null ? cs.outline : null),
                ),
                title: Text(feel == null ? t('Miltä tuntui?') : t('Fiilis: {0}', [t(feel.$3).toLowerCase()])),
                subtitle: workout.activity != null && intensity != null && workout.distanceKm != null
                    ? Text('${intensity.$3} ${t(intensity.$2)}', style: sub)
                    // Sali: liian raskaiksi merkityt liikkeet (Treeni valmis -ikkunan Mikä tuntui raskaalta?).
                    // Sali: liian raskaat liikkeet ja päivän syyt (ennen syyt eivät näkyneet, yötesti 15.11.).
                    : workout.activity == null && (workout.tooHeavy.isNotEmpty || workout.dayReasons.isNotEmpty)
                    ? Text(
                        [
                          if (workout.tooHeavy.isNotEmpty)
                            t('Liian raskas: {0}', [workout.tooHeavy.map(exerciseLabel).join(', ')]),
                          if (workout.dayReasons.isNotEmpty) workout.dayReasons.map(t).join(', '),
                        ].join(' · '),
                        key: const ValueKey('tooHeavyNote'),
                        style: sub,
                      )
                    : null,
                trailing: Text(
                  feel == null ? t('Valitse') : t('Muuta'),
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                ),
                onTap: _changeFeeling,
              ),
            ),
          ] else ...[
            if (watchStats.isNotEmpty || ring) ...[
              const SizedBox(height: 8),
              if (watchStats.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: settings.watch ? _editWatch : null,
                  child: statRow(watchStats, size: 16),
                ),
              if (ring)
                Padding(
                  padding: EdgeInsets.only(top: watchStats.isEmpty ? 0 : 8),
                  child: KcalRing(
                    total: workout.kcal!,
                    active: active,
                    color: cs.surfaceContainer,
                    onTap: settings.watch ? _editWatch : null,
                  ),
                ),
              if (workout.healthSource != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '♥ ${t('Health Connectista ({0})', [workout.healthSource])}',
                    style: TextStyle(fontSize: 12, color: greenText(context)),
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
            // Health Connect: rivi vain, kun kellolla on uutta tietoa (juuri tallennetussa odottaa kellon siirtoa).
            if (HcUpdateRow.wanted(workout))
              HcUpdateRow(
                key: ValueKey('hc_${workout.date}_${workout.session}'),
                w: workout,
                waiting: !widget.history,
                onApplied: () async {
                  await _persist();
                  if (mounted) setState(() {});
                },
              ),
            const SizedBox(height: 10),
            // Fiilis yhtenä rivinä (kysytty jo lopussa); Muuta avaa saman valinnan.
            Material(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                key: const ValueKey('feelingRow'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Text(
                  feel?.$2 ?? '🙂',
                  style: TextStyle(fontSize: 26, color: feel == null ? cs.outline : null),
                ),
                title: Text(feel == null ? t('Miltä tuntui?') : t('Fiilis: {0}', [t(feel.$3).toLowerCase()])),
                subtitle: workout.activity != null && intensity != null && workout.distanceKm != null
                    ? Text('${intensity.$3} ${t(intensity.$2)}', style: sub)
                    // Sali: liian raskaiksi merkityt liikkeet (Treeni valmis -ikkunan Mikä tuntui raskaalta?).
                    // Sali: liian raskaat liikkeet ja päivän syyt (ennen syyt eivät näkyneet, yötesti 15.11.).
                    : workout.activity == null && (workout.tooHeavy.isNotEmpty || workout.dayReasons.isNotEmpty)
                    ? Text(
                        [
                          if (workout.tooHeavy.isNotEmpty)
                            t('Liian raskas: {0}', [workout.tooHeavy.map(exerciseLabel).join(', ')]),
                          if (workout.dayReasons.isNotEmpty) workout.dayReasons.map(t).join(', '),
                        ].join(' · '),
                        key: const ValueKey('tooHeavyNote'),
                        style: sub,
                      )
                    : null,
                trailing: Text(
                  feel == null ? t('Valitse') : t('Muuta'),
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                ),
                onTap: _changeFeeling,
              ),
            ),
            HrDetails(workout),
          ],
          // Sykevyöllä kävelty (esim. kävelymatolla): laitteen askeleet ja matka Health Connectista.
          if (PadMatch.wanted(workout) && HealthImportButton.available)
            PadMatch(
              w: workout,
              onApplied: () async {
                await _persist();
                if (mounted) setState(() {});
              },
            ),
          // Juoksu: vertailu edelliseen samantyyppiseen lenkkiin ja oma kehitysnäkymä.
          if (isRun(workout.activity) && workout.paceSecPerKm != null) _RunCompare(run: workout),
          if (_tiredTip() != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('🌙 ${_tiredTip()}', style: const TextStyle(fontSize: 13)),
            ),
          if (c.prs > 0 && workout.activity != null)
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
                      '${t('Edellinen kerta: {0} ({1})', [sportName(workout.activity!), shortDateY(c.previous!.date)])}: '
                      '${[if (c.previous!.minutes != null) fmtDuration(c.previous!.minutes!), if (c.previous!.distanceKm != null) '${fmtNum(c.previous!.distanceKm!)} km', ?c.previous!.pace, if (intensityOf(c.previous!.intensity) case final i?) t(i.$2)].join(' · ')}',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Verrattuna edelliseen kertaan ({0})', [shortDateY(c.previous!.date)]),
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
                        // Ei, jos tämän kerran volyymi on 0 (vain aika-, matka- tai kertaliikkeitä: "→ 0 kg" näytti
                        // romahdukselta, testikierros 15.11.).
                        // Nollakerrat (liikunta tai vain kehonpainoliikkeet) pois rivistä: "0 → 630 → 160 → 0 → 400 kg"
                        // näytti romahduksilta (testikierros 16.11.).
                        if (c.history.where((h) => h.$2 > 0).length > 2 && c.volume > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            t('Volyymi viime kerroilla: {0} kg', [
                              c.history.where((h) => h.$2 > 0).map((h) => fmtNum(h.$2.roundToDouble())).join(' → '),
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
  late final _c = selectedText('${widget.minutes}');
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
            // Tallenna on pois käytöstä väärällä arvolla: kerrotaan sallittu väli, ettei painike näytä rikkinäiseltä.
            decoration: InputDecoration(
              labelText: t('Kesto (min)'),
              errorText: valid ? null : t('Sallittu {0}–{1}', ['1', '1440']),
            ),
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

/// Sarjapisteet liikkeen rivillä: [done] täytettyä, loput ontoina (enintään 6 näkyvissä).
class _SetDots extends StatelessWidget {
  final int done, total;
  final Color color;
  const _SetDots({required this.done, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final n = total.clamp(0, 6);
    if (n == 0) return const SizedBox.shrink();
    final off = Theme.of(context).colorScheme.outlineVariant;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < n; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < done ? color : null,
                  border: i < done ? null : Border.all(color: off, width: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sarja pillinä tallennetun salitreenin yhteenvedossa: paino × toistot (yksikkö liikkeen otsikossa), lämmittely
/// himmeänä, ennätys kultaisena, pudotussarja nuolella ja AMRAP merkittynä.
class _SetPill extends StatelessWidget {
  final String exercise;
  final SetEntry set;
  const _SetPill({required this.exercise, required this.set});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = yellowText(context);
    final text = fmtSetsCompact(exercise, [set]).replaceAll(' 🏆', '');
    final warm = set.warmup;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: warm ? Colors.transparent : (set.pr ? gold.withValues(alpha: .14) : cs.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: warm ? cs.outlineVariant : (set.pr ? gold : Colors.transparent),
          width: set.pr ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (set.pr) ...[const Text('🏆', style: TextStyle(fontSize: 13)), const SizedBox(width: 4)],
          if (warm) ...[
            Icon(Icons.local_fire_department_outlined, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: warm ? FontWeight.w500 : FontWeight.w700,
              color: warm ? cs.onSurfaceVariant : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
