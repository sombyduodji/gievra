import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../drafts.dart';
import '../gps_filter.dart';
import '../gps_recorder.dart';
import '../gpx.dart';
import '../maps/map_store.dart';
import '../maps/map_view.dart';
import '../models.dart';
import '../share_text.dart' show thousands;
import '../sports.dart';
import '../theme.dart';
import 'maps_screen.dart';
import 'record_screen.dart';
import 'watch.dart';
import 'widgets.dart';
import 'workout.dart';
import '../l10n.dart';

/// Urheilu tai liikunta: laji, kesto, matka (kestävyyslajit), rasitus, fiilis ja muistiinpanot.
class ActivityScreen extends StatefulWidget {
  final Workout workout;

  /// Avataan kesken jäänyt GPS-tallennus heti (sovellus suljettiin kesken lenkin).
  final bool recoverGps;

  /// Palautettu luonnos (Android sulki sovelluksen kesken kirjauksen): näkymän oma tila.
  final Map<String, Object?>? draft;
  const ActivityScreen({super.key, required this.workout, this.recoverGps = false, this.draft});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  Workout get w => widget.workout;
  late final _notes = TextEditingController(text: w.notes);
  Timer? _draftTick;
  bool _saved = false;

  /// Valittu "Kirjaa ilman GPS:ää" (lomake näkyy kuten ennen).
  bool _manual = false;

  /// Offline-kartta puuttuu viimeisimmästä sijainnista (tai karttoja ei ole lainkaan).
  bool _mapMissing = false;

  /// Ajanotto ilman GPS:ää (Manuaalinen, esim. juoksumatto): käynnissä olevan jakson alku ja kertynyt aika.
  DateTime? _swStart;
  Duration _swAcc = Duration.zero;
  bool _swUsed = false;
  Timer? _swTick;

  Duration get _swElapsed => _swAcc + (_swStart == null ? Duration.zero : DateTime.now().difference(_swStart!));

  /// Ajanotto tarjotaan uudelle, tänään tehtävälle liikunnalle.
  bool get _canStopwatch =>
      w.date == dateOnly(DateTime.now()) && !_hasRoute && !store.onDay(w.date).any((x) => x.session == w.session);

  void _swStartPause() {
    Future.microtask(_saveDraft);
    setState(() {
      if (_swStart == null) {
        _swStart = DateTime.now();
        if (!_swUsed) w.started = _swStart;
        _swUsed = true;
        _swTick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      } else {
        _swAcc = _swElapsed;
        _swStart = null;
        _swTick?.cancel();
      }
    });
  }

  /// Lopetus: aika kenttään (voi vielä muokata).
  void _swStop() {
    setState(() {
      _swAcc = _swElapsed;
      _swStart = null;
      _swTick?.cancel();
      final secs = _swAcc.inSeconds;
      if (_timed) {
        _setSec(secs < 60 ? 60 : secs);
      } else {
        w.minutes = (secs / 60).round().clamp(1, 600);
      }
      _swAcc = Duration.zero;
    });
  }

  /// Treenin reitti piirtoa varten (tallennettu .gpx tai juuri tallennettu).
  List<List<TrackPoint>>? _route;

  @override
  void initState() {
    super.initState();
    w.minutes ??= 45;
    w.intensity ??= 'reipas';
    if (widget.recoverGps) WidgetsBinding.instance.addPostFrameCallback((_) => _record(recover: true));
    _restoreDraft(widget.draft);
    _checkMaps();
    _loadRoute();
    // Keskeneräinen kirjaus talteen muutaman sekunnin välein (vain muuttuessa).
    _draftTick = Timer.periodic(const Duration(seconds: 3), (_) => _saveDraft());
  }

  /// Näkymän oma tila luonnokseen: valinta (GPS / manuaalinen), ajanotto ja tallentamaton GPS-reitti.
  Map<String, Object?> _draftExtra() => {
    'manual': _manual,
    if (_swStart != null) 'swStart': _swStart!.toIso8601String(),
    'swAccMs': _swAcc.inMilliseconds,
    'swUsed': _swUsed,
    if (w.routeGpx != null) 'routeGpx': w.routeGpx,
  };

  void _restoreDraft(Map<String, Object?>? d) {
    if (d == null) return;
    _manual = d['manual'] == true;
    _swUsed = d['swUsed'] == true;
    _swAcc = Duration(milliseconds: (d['swAccMs'] as int?) ?? 0);
    _swStart = DateTime.tryParse(d['swStart'] as String? ?? '');
    if (_swStart != null) {
      // Ajanotto jatkuu: Android sulki sovelluksen, mutta aika kului.
      _swTick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
    final gpx = d['routeGpx'] as String?;
    if (gpx != null) {
      w.routeGpx = gpx;
      _route = parseGpx(gpx);
    }
  }

  Future<void> _saveDraft() async {
    if (_saved || w.activity == null) return;
    w.notes = _notes.text;
    await ActivityDraft.save(w, extra: _draftExtra());
  }

  /// GPS tarjotaan uudelle, tänään tehtävälle matkalajille Androidissa (ei verkkodemossa).
  bool get _canGps =>
      !kIsWeb &&
      !isDemo &&
      Platform.isAndroid &&
      (sportOf(w.activity)?.distance ?? false) &&
      w.date == dateOnly(DateTime.now()) &&
      w.route == null &&
      w.routeGpx == null &&
      !store.onDay(w.date).any((x) => x.session == w.session);

  bool get _hasRoute => w.route != null || w.routeGpx != null;

  Future<void> _checkMaps() async {
    if (!_canGps) return;
    final ms = MapStore.instance;
    await ms.load(network: false); // vain puhelimen tiedostot: huomautus näkyy heti, myös ilman verkkoa
    final loc = await lastLocation();
    final missing = ms.installed.isEmpty || (loc != null && ms.catalog != null && !ms.covers(loc.$1, loc.$2));
    if (mounted) setState(() => _mapMissing = missing);
  }

  Future<void> _loadRoute() async {
    final gpx = await store.readRoute(w);
    if (gpx != null && mounted) setState(() => _route = parseGpx(gpx));
  }

  Future<void> _openMaps() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapsScreen(sport: w.activity)));
    await _checkMaps();
  }

  Future<void> _record({bool recover = false}) async {
    final sport = recover ? (await GpsRecorder.pendingSport() ?? w.activity!) : w.activity!;
    if (!mounted) return;
    final r = await Navigator.of(context).push<RouteResult>(
      MaterialPageRoute(
        builder: (_) => RecordScreen(sport: sport, recover: recover),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      w.activity = sport;
      w.started = r.started;
      _setSec(r.seconds < 60 ? 60 : r.seconds);
      w.distanceKm = r.distanceKm > 0 ? r.distanceKm : null;
      w.routeGpx = r.segments.isEmpty ? null : r.gpx;
      _route = r.segments.isEmpty ? null : r.segments;
      _manual = true;
    });
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
    if (_swStart != null || _swAcc > Duration.zero) _swStop();
    w.notes = _notes.text;
    if (!isRun(w.activity)) w.runType = null;
    if (!_timed) w.seconds = null;
    w.title = w.activity ?? 'Liikunta'; // tiedostoon aina suomeksi
    await store.save(w);
    _saved = true;
    _draftTick?.cancel();
    await ActivityDraft.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(workout: w)));
  }

  @override
  void dispose() {
    _swTick?.cancel();
    // Kirjauksesta poistuttiin itse (takaisin) tai se tallennettiin: luonnosta ei tarvita.
    _draftTick?.cancel();
    ActivityDraft.clear();
    _notes.dispose();
    super.dispose();
  }

  Widget _stopwatch() {
    final cs = Theme.of(context).colorScheme;
    final running = _swStart != null;
    final active = running || _swAcc > Duration.zero;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(
            children: [
              const Text('⏱', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: active
                    ? Text(
                        fmtDurationSec(_swElapsed.inSeconds),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      )
                    : Text(t('Ajanotto'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (active)
                IconButton.filledTonal(tooltip: t('Lopeta ajanotto'), onPressed: _swStop, icon: const Icon(Icons.stop)),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: _swStartPause,
                icon: Icon(running ? Icons.pause : Icons.play_arrow),
                label: Text(running ? t('Tauko') : (active ? t('Jatka') : t('Aloita'))),
                style: FilledButton.styleFrom(backgroundColor: running ? cs.secondary : null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sport = sportOf(w.activity);
    return Scaffold(
      appBar: AppBar(
        title: Text(w.activity == null ? t('Liikunta') : sportName(w.activity!)),
        actions: [
          if (w.activity != null && !(_canGps && !_manual))
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
            if (_canGps && !_manual) ...[
              const SizedBox(height: 14),
              _GpsChoice(onGps: _record, onManual: () => setState(() => _manual = true)),
              if (_mapMissing)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.map_outlined),
                      title: Text(t('Tämän alueen karttaa ei ole ladattu')),
                      subtitle: Text(
                        t('Kartta näyttää reitin ja auttaa korjaamaan sen poluille. GPS toimii ilmankin.'),
                      ),
                      isThreeLine: true,
                      trailing: TextButton(onPressed: _openMaps, child: Text(t('Lataa kartat'))),
                    ),
                  ),
                ),
            ] else ...[
              if (_hasRoute)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Text('📍', style: TextStyle(fontSize: 22)),
                          title: Text(w.routeGpx != null ? t('Reitti tallennettu') : t('Reitti')),
                          subtitle: Text(t('GPS-reitti tallentuu .gpx-tiedostona treenin viereen.')),
                          trailing: w.routeGpx != null
                              ? TextButton(
                                  onPressed: () => setState(() {
                                    w.routeGpx = null;
                                    _route = null;
                                  }),
                                  child: Text(t('Poista reitti')),
                                )
                              : null,
                        ),
                        if (_route != null && _route!.any((s) => s.length >= 2))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: SizedBox(
                              height: 240,
                              child: RouteMap(
                                segments: _route!,
                                fallback: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: CustomPaint(
                                    painter: RoutePainter(_route!, Theme.of(context).colorScheme.primary),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
                    child: Text(
                      t(runTypeOf(w.runType)!.$5),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
              if (_canStopwatch) _stopwatch(),
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
              // Kävelylajeissa askeleet (esim. puhelimesta tai kellosta).
              if (sport?.steps ?? false) ...[
                SectionLabel(t('Askeleet')),
                ValueStepper(
                  value: thousands(w.steps ?? 0),
                  unit: t('askelta'),
                  onMinus: () => setState(() {
                    final v = ((w.steps ?? 0) - 500).clamp(0, 200000);
                    w.steps = v == 0 ? null : v;
                  }),
                  onPlus: () => setState(() => w.steps = ((w.steps ?? 0) + 500).clamp(0, 200000)),
                  onTap: () async {
                    final v = await askNumber(context, t('Askeleet'), (w.steps ?? 0).toDouble(), decimals: false);
                    if (v != null && v >= 0 && v <= 200000) setState(() => w.steps = v == 0 ? null : v.round());
                  },
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
        ],
      ),
    );
  }
}

/// Matkalajin aloitus: GPS:llä (aika, matka ja reitti mitataan) tai ilman (lomake kuten ennen).
class _GpsChoice extends StatelessWidget {
  final VoidCallback onGps, onManual;
  const _GpsChoice({required this.onGps, required this.onManual});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const pad = EdgeInsets.symmetric(vertical: 14, horizontal: 16);
    Widget label(String title, String sub, Color? subColor) => Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: subColor),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(padding: pad),
          onPressed: onGps,
          child: label(t('📍 GPS-tila'), t('Mittaa ajan, matkan ja reitin'), null),
        ),
        const SizedBox(height: 12),
        // Sama tyyli kuin etusivun "Merkitse aamupaino": ääriviiva ja punainen otsikko.
        OutlinedButton(
          style: OutlinedButton.styleFrom(padding: pad),
          onPressed: onManual,
          child: label(t('Manuaalinen'), t('Syötä matka ja aika itse'), cs.onSurfaceVariant),
        ),
      ],
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
