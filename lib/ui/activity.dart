import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../drafts.dart';
import '../gps_filter.dart';
import '../gps_recorder.dart';
import '../gpx.dart';
import '../maps/elevation.dart';
import '../maps/map_store.dart';
import '../maps/map_view.dart';
import '../maps/path_snap.dart';
import '../models.dart';
import '../ongoing.dart';
import '../sports.dart';
import '../theme.dart';
import 'elevation_chart.dart';
import 'maps_screen.dart';
import 'record_screen.dart';
import 'share.dart';
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

  /// Valmiiksi täytetty liikunta (esim. Health Connectista): ei GPS-valintaa, arvot suoraan säätimiin.
  final bool manual;
  const ActivityScreen({super.key, required this.workout, this.recoverGps = false, this.draft, this.manual = false});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  Workout get w => widget.workout;
  late final _notes = TextEditingController(text: w.notes);
  Timer? _draftTick;
  bool _saved = false;

  /// Valittu "Kirjaa ilman GPS:ää" (lomake näkyy kuten ennen).
  late bool _manual = widget.manual;

  /// Offline-kartta puuttuu viimeisimmästä sijainnista (tai karttoja ei ole lainkaan).
  bool _mapMissing = false;

  /// Ajanotto ilman GPS:ää (Manuaalinen, esim. juoksumatto): käynnissä olevan jakson alku ja kertynyt aika.
  DateTime? _swStart;
  Duration _swAcc = Duration.zero;
  bool _swUsed = false;
  Timer? _swTick;

  Duration get _swElapsed => _swAcc + (_swStart == null ? Duration.zero : DateTime.now().difference(_swStart!));

  /// Ajanotto tarjotaan uudelle, tänään tehtävälle liikunnalle.
  // Ei Health Connectista lisätylle: liikunta on jo tehty, aika tuli kellosta.
  bool get _canStopwatch =>
      w.date == dateOnly(DateTime.now()) &&
      !_hasRoute &&
      w.hcId == null &&
      !store.onDay(w.date).any((x) => x.session == w.session);

  /// Ajanoton tila pudotusvalikon ilmoitukseen (käynnissä tai tauolla; lopetettu tai tallennettu = ei ilmoitusta).
  void _syncOngoing({bool clear = false}) {
    final sport = w.activity;
    final active = _swStart != null || _swAcc > Duration.zero;
    Ongoing.activity = clear || sport == null || !active
        ? null
        : OngoingActivity(
            sport,
            since: _swStart == null ? null : DateTime.now().subtract(_swElapsed),
            elapsed: _swElapsed,
          );
    Ongoing.refresh();
  }

  void _swStartPause() {
    Future.microtask(_saveDraft);
    Future.microtask(_syncOngoing);
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
    _syncOngoing();
  }

  /// Treenin reitti piirtoa varten (tallennettu .gpx tai juuri tallennettu).
  List<List<TrackPoint>>? _route;

  @override
  void initState() {
    super.initState();
    w.minutes ??= 45;
    if (widget.recoverGps) WidgetsBinding.instance.addPostFrameCallback((_) => _record(recover: true));
    _restoreDraft(widget.draft);
    if (_swStart != null || _swAcc > Duration.zero) WidgetsBinding.instance.addPostFrameCallback((_) => _syncOngoing());
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
      _initSnap(gpx);
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

  /// GPS:llä mitattu aika ja matka näytetään arvoina (ei säätimiä), kunnes käyttäjä haluaa korjata ne.
  bool _gpsEdit = false;
  bool get _gpsView =>
      _hasRoute && _timed && (sportOf(w.activity)?.distance ?? false) && w.distanceKm != null && !_gpsEdit;

  Widget _gpsSummary(ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: SectionLabel(t('📍 Mitattu GPS:llä'))),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextButton.icon(
              onPressed: _locked ? _unlock : () => setState(() => _gpsEdit = true),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(t('Korjaa')),
            ),
          ),
        ],
      ),
      Row(
        children: [
          _Metric(value: fmtDurationSec(_sec), unit: '', label: t('aika')),
          const SizedBox(width: 8),
          _Metric(value: fmtNum(w.distanceKm!), unit: 'km', label: t('matka')),
        ],
      ),
      if (w.pace != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              _Metric(value: fmtPace(w.paceSecPerKm!), unit: 'min/km', label: t('vauhti')),
              const SizedBox(width: 8),
              _Metric(value: fmtNum((w.speedKmh! * 10).round() / 10), unit: 'km/h', label: t('keskinopeus')),
            ],
          ),
        ),
    ],
  );

  Future<void> _checkMaps() async {
    if (!_canGps) return;
    final ms = MapStore.instance;
    await ms.load(network: false); // vain puhelimen tiedostot: huomautus näkyy heti, myös ilman verkkoa
    final loc = await lastLocation();
    final missing = ms.installed.isEmpty || (loc != null && ms.catalog != null && !ms.covers(loc.$1, loc.$2));
    if (mounted) setState(() => _mapMissing = missing);
  }

  /// Lajit, joissa kilometrien alle nopeus (km/h) vauhdin (min/km) sijaan.
  static const _speedSports = {'Pyöräily', 'Luistelu', 'Laskettelu', 'Melonta', 'Soutu'};

  // Korkeusprofiili ladatuista korkeustiedoista (lasketaan kerran reittiä kohti, taustalla).
  List<List<TrackPoint>>? _profRoute;
  ElevationProfile? _profile;
  bool _profileDone = false; // haku valmis (tulos voi olla null: ei korkeustietoja)

  ElevationProfile? _profileFor(List<List<TrackPoint>>? route) {
    if (route == null) return null;
    if (!identical(route, _profRoute)) {
      _profRoute = route;
      _profile = null;
      _profileDone = false;
      MapStore.instance
          .profileFor(route)
          .then((pr) {
            if (mounted && identical(route, _profRoute)) {
              setState(() {
                _profile = pr;
                _profileDone = true;
              });
            }
          })
          .catchError((Object e) {
            debugPrint('korkeusprofiili: $e');
            if (mounted && identical(route, _profRoute)) setState(() => _profileDone = true);
          });
    }
    return _profile;
  }

  List<List<TrackPoint>>? _splitRoute;
  List<(double, double, double)>? _splits;
  List<(double, double, double)>? _splitsFor(List<List<TrackPoint>>? route) {
    if (route == null) return null;
    if (!identical(route, _splitRoute)) {
      _splitRoute = route;
      _splits = routeKmSplits(route);
    }
    return _splits;
  }

  Future<void> _loadRoute() async {
    final gpx = await store.readRoute(w);
    if (gpx != null && mounted) {
      setState(() {
        _route = parseGpx(gpx);
        _initSnap(gpx);
      });
    }
  }

  // ---- Reitin korjaus poluille (path_snap.dart): alkuperäiset GPS-pisteet säilyvät .gpx:n laajennuksessa,
  // joten korjauksen voi muuttaa tai poistaa milloin tahansa. Matka seuraa korjattua reittiä, aika ei muutu.
  List<List<TrackPoint>>? _raw;
  double? _rawDist;
  String _desc = '';
  List<SnapWay>? _ways;
  Future<void>? _waysLoad;
  int _snapped = 0, _snapTotal = 0;

  bool get _canSnap => _raw != null && snapModeFor(w.activity) != null;

  /// Reitin alkuperäiset pisteet .gpx:stä. Vanhemmissa (ennen 0.4) pääraita on itse GPS-reitti; 0.4:ssä
  /// tallennettaessa korjattua reittiä (desc: "polulle korjattu") ei voi enää säätää.
  void _initSnap(String gpx) {
    _desc = _unescape(RegExp(r'<desc>(.*?)</desc>', dotAll: true).firstMatch(gpx)?[1] ?? '');
    final raw = parseRawGpx(gpx);
    if (raw != null && raw.$1.isNotEmpty) {
      _raw = raw.$1;
      _rawDist = raw.$2 ?? (w.distanceKm ?? 0) * 1000;
    } else if (!_desc.contains('polulle korjattu')) {
      final segs = parseGpx(gpx);
      if (segs.any((s) => s.length >= 2)) {
        _raw = segs;
        _rawDist = (w.distanceKm ?? routeLength(segs) / 1000) * 1000;
      }
    }
    if (_canSnap) _loadWays();
  }

  static String _unescape(String s) =>
      s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&amp;', '&');

  Future<void> _loadWays() => _waysLoad ??= () async {
    try {
      final ms = MapStore.instance;
      if (ms.installed.isEmpty) await ms.load(network: false);
      _ways = await ms.waysAround(_raw!);
    } catch (_) {
      _ways = const [];
    }
    if (mounted) setState(() {});
  }();

  /// Korjaa reitin [m] metriin asti (0 = pois): reitti, .gpx ja matka (ellei matkaa ole kirjoitettu käsin).
  Future<void> _applySnap(int m, {bool remember = true}) async {
    final raw = _raw;
    if (raw == null) return;
    if (m > 0) await _loadWays();
    final ways = _ways ?? const <SnapWay>[];
    final r = m == 0 || ways.isEmpty
        ? SnapResult(raw, 0, raw.fold(0, (a, s) => a + s.length))
        : snapRoute(raw, ways, w.activity, params: SnapParams.forLimit(m));
    if (!mounted) return;
    setState(() {
      w.snapM = m;
      _snapped = r.snapped;
      _snapTotal = r.total;
      _route = r.segments;
      w.routeGpx = routeToGpx(
        r.segments,
        name: w.activity ?? 'Liikunta',
        type: w.activity,
        desc: _desc.isEmpty ? null : _desc,
        raw: raw,
        rawDistance: _rawDist,
      );
      if (!w.distanceManual && _rawDist != null) {
        w.distanceKm = (snappedDistance(raw, r.segments, _rawDist!) / 10).round() / 100;
      }
    });
    if (remember && w.activity != null) settings.setSnapDefault(w.activity!, m);
  }

  Widget _snapCard(ColorScheme cs) {
    final m = w.snapM ?? 0;
    final on = m > 0;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final noMaps = _ways != null && _ways!.isEmpty;
    String info;
    if (_ways == null && on) {
      info = t('Haetaan polkuja kartasta…');
    } else if (noMaps) {
      info = t('Alueen karttaa ei ole ladattu, joten reittiä ei voi korjata.');
    } else if (!on) {
      info = t('Pois: reitti ja matka GPS:n mukaan.');
    } else {
      final pct = _snapTotal == 0 ? 0 : (100 * _snapped / _snapTotal).round();
      info = t('Enintään {0} m · korjattu {1} % pisteistä', [m, pct]);
      if (_rawDist != null && w.distanceKm != null && !w.distanceManual) {
        final diff = (w.distanceKm! * 1000 - _rawDist!).round();
        if (diff.abs() >= 10) {
          info += ' · ${t('matka {0} m GPS:ään verrattuna', ['${diff > 0 ? '+' : '−'}${diff.abs()}'])}';
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.route_outlined),
            title: Text(t('Korjaa reitti poluille')),
            value: on,
            onChanged: noMaps
                ? null
                : (v) => _locked
                      ? _unlock()
                      : _applySnap(v ? (settings.snapFor(w.activity!) > 0 ? settings.snapFor(w.activity!) : 5) : 0),
          ),
          if (on)
            Row(
              children: [
                Text('3 m', style: sub),
                Expanded(
                  child: Slider(
                    min: 3,
                    max: 10,
                    divisions: 7,
                    value: m.clamp(3, 10).toDouble(),
                    label: '$m m',
                    onChanged: _locked ? null : (v) => _applySnap(v.round(), remember: false),
                    onChangeEnd: _locked ? null : (v) => _applySnap(v.round()),
                  ),
                ),
                Text('10 m', style: sub),
              ],
            ),
          Text(info, style: sub),
          if (on && w.distanceManual)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t('Matka on kirjoitettu käsin, joten korjaus muuttaa vain reittiä.'), style: sub),
            ),
          if (noMaps)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _openMaps, child: Text(t('Lataa kartat'))),
            ),
        ],
      ),
    );
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
      w.distanceManual = false;
      w.snapM = null;
      _raw = r.segments.isEmpty ? null : r.segments;
      _rawDist = r.distanceM > 0 ? r.distanceM : r.distanceKm * 1000;
      _desc = r.desc;
      _ways = null;
      _waysLoad = null;
    });
    // Polulle korjaus lajin oletuksella (5 m tai käyttäjän viimeksi valitsema); säädettävissä kartan alla.
    if (_canSnap) await _applySnap(settings.snapFor(sport), remember: false);
    // Reitti luonnokseen heti: tallentimen tiedostot on jo poistettu, joten 3 s:n odotus voisi hukata sen.
    await _saveDraft();
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
    _syncOngoing(clear: true); // luonnos ja ajanotto päättyvät sivulta poistuttaessa
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

  /// Tallennettu liikunta avautuu lukutilaan (ei luonnos eikä palautettu GPS-tallennus); muokkaus kysyy ensin.
  late bool _locked =
      widget.draft == null &&
      !widget.recoverGps &&
      store.onDay(w.date).any((x) => x.session == w.session && x.activity != null);

  bool get _isSaved => store.onDay(w.date).any((x) => x.session == w.session && x.activity != null);

  /// Poistaa tallennetun liikunnan (.md ja oma .gpx). Health Connectista lisätty tulee taas lisättäväksi.
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko liikunta?')),
        content: Text(t('Tiedosto {0}.md poistetaan.', ['${isoDate(w.date)}${w.session > 1 ? '-${w.session}' : ''}'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista'))),
        ],
      ),
    );
    if (ok != true) return;
    _saved = true; // ei luonnosta poistetusta
    _draftTick?.cancel();
    await store.delete(w.date, w.session);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _unlock() async {
    if (await askEditSaved(context) && mounted) setState(() => _locked = false);
  }

  List<Widget> _guard(List<Widget> xs) =>
      !_locked ? xs : [xs.first, for (final x in xs.skip(1)) EditGuard(locked: true, onTap: _unlock, child: x)];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sport = sportOf(w.activity);
    return Scaffold(
      appBar: AppBar(
        title: Text(w.activity == null ? t('Liikunta') : sportName(w.activity!)),
        actions: [
          // Tallennettu liikunta: jakaminen ja poisto (kuten salitreenissä).
          if (_isSaved)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'share' ? shareWorkout(context, w) : _delete(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'share', child: Text(t('Jaa'))),
                PopupMenuItem(value: 'delete', child: Text(t('Poista liikunta'))),
              ],
            ),
          if (_locked) LockButton(onTap: _unlock),
          // Tallennus vain sivun lopussa (vihreä Treeni valmis!, kuten salitreenissä), ei yläpalkissa.
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: _guard([
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
                    among: sports.where((s) => s.group == g && !s.retired),
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
                          // Poisto vain tallentamattomalle reitille (polulle korjaus asettaa routeGpx:n myös
                          // tallennetulle treenille, jonka reittitiedosto jää ennalleen).
                          title: Text(w.routeGpx != null && w.route == null ? t('Reitti tallennettu') : t('Reitti')),
                          subtitle: Text(t('GPS-reitti tallentuu .gpx-tiedostona treenin viereen.')),
                          trailing: w.routeGpx != null && w.route == null
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
                                original: (w.snapM ?? 0) > 0 ? _raw : null,
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
                        if (_profileFor(_route) case final prof?)
                          ElevationCard(prof, speed: _speedSports.contains(w.activity))
                        // Ilman korkeustietoja: kilometrien vauhti silti (reitin omista ajoista).
                        else if (_splitsFor(_route) case final sp? when _profileDone && sp.length > 1)
                          KmSplitsCard(sp, speed: _speedSports.contains(w.activity)),
                        if (_canSnap) _snapCard(Theme.of(context).colorScheme),
                      ],
                    ),
                  ),
                ),
              if (_canStopwatch) _stopwatch(),
              // GPS-lenkki: aika ja matka mitattuina arvoina; Korjaa avaa tavalliset säätimet.
              if (_gpsView)
                _gpsSummary(cs)
              else ...[
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
                    onMinus: () => setState(() {
                      w.distanceKm = ((w.distanceKm ?? 0) - .5).clamp(0, 500);
                      w.distanceManual = _hasRoute;
                    }),
                    onPlus: () => setState(() {
                      w.distanceKm = (w.distanceKm ?? 0) + .5;
                      w.distanceManual = _hasRoute;
                    }),
                    onTap: () async {
                      final v = await askNumber(context, t('Matka (km)'), w.distanceKm ?? 5);
                      if (v != null && v >= 0) {
                        setState(() {
                          w.distanceKm = v == 0 ? null : v;
                          w.distanceManual = _hasRoute;
                        });
                      }
                    },
                  ),
                  if (w.pace != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          _Metric(value: fmtPace(w.paceSecPerKm!), unit: 'min/km', label: t('vauhti')),
                          const SizedBox(width: 8),
                          _Metric(
                            value: fmtNum((w.speedKmh! * 10).round() / 10),
                            unit: 'km/h',
                            label: t('keskinopeus'),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
              // Askeleet Kellon tiedot -kortissa (Health Connect tai käsin), ei omana kohtanaan.
              SectionLabel(t('Rasitus')),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final (k, l, e) in intensities) ButtonSegment(value: k, label: Text('$e ${t(l)}'))],
                // Ei oletusta: rasitus vain, jos käyttäjä valitsee (uudelleen napautus poistaa valinnan).
                emptySelectionAllowed: true,
                selected: {?w.intensity},
                onSelectionChanged: (v) => setState(() => w.intensity = v.firstOrNull),
              ),
              if (settings.watch || w.healthSource != null)
                WatchCard(
                  w: w,
                  onChanged: () async {
                    setState(() {});
                    // Jo tallennettu liikunta: kellon tiedot (Health Connect tai käsin) tiedostoon heti, ettei
                    // takaisin-painike hukkaa niitä. Uusi kirjaus tallentuu Treeni valmis -painikkeella.
                    if (store.onDay(w.date).any((x) => x.session == w.session && x.activity != null)) {
                      await store.save(w);
                    }
                  },
                ),
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
              // Lukitussa (tallennetussa) liikunnassa ei Tallenna-painiketta; muokkaus avaa sen.
              if (!_locked) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Sami.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.flag_rounded),
                  label: Text(t('Treeni valmis!'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ],
        ]),
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
