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
import '../session_compare.dart' show fmtDuration;
import '../share_text.dart' show thousands;
import '../sports.dart';
import '../theme.dart';
import '../vehicle_ride.dart';
import 'elevation_chart.dart';
import 'maps_screen.dart';
import 'record_screen.dart';
import 'share.dart';
import 'watch.dart';
import 'sport_picker.dart';
import 'widgets.dart';
import 'finish_sheet.dart';
import 'workout.dart';
import '../l10n.dart';
import '../heart_rate.dart' show hr, applyHeartRate, HrStats;
import 'hr_ui.dart';

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

  /// Testeissä: kellotaulun valinta ilman dialogia.
  @visibleForTesting
  static TimeOfDay? Function()? debugPickTime;
  static TimeOfDay? Function()? get _debugPick => debugPickTime;

  /// Testeissä: GPS-tila tarjolla myös muualla kuin Androidissa.
  @visibleForTesting
  static bool? debugGps;
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

  /// Sykevyön istunto ajanotolle (GPS-tallennus käyttää omaansa, ks. RecordScreen).
  static const _hrKey = 'activity';

  /// GPS-tallennuksen sykkeet (RecordScreen), sovelletaan tallennettaessa.
  HrStats? _gpsHr;
  Duration _swAcc = Duration.zero;
  bool _swUsed = false;
  Timer? _swTick;

  /// Ajanotto pysäytetty (Lopeta): alku ja loppu näkyvät muokattavina, Jatka ajanottoa jatkaa.
  bool _swDone = false;
  DateTime? _swEnd;

  /// Ajan kirjaus: true = ajanotto, false = Syötä aika (kesto ja aloitusaika käsin).
  late bool _useWatch = _canStopwatch;

  Duration get _swElapsed => _swElapsedAt(DateTime.now());
  Duration _swElapsedAt(DateTime now) => _swAcc + (_swStart == null ? Duration.zero : now.difference(_swStart!));

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
        hr.begin(_hrKey); // sykevyö (jos valittu) mukaan ajanotosta
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

  /// Lopetus: aika kenttään (voi vielä muokata). [at]: Valmis-napautuksen hetki, ettei kysymyksiin
  /// vastaamiseen kulunut aika lisäänny treeniin.
  void _swStop([DateTime? at]) {
    setState(() {
      _swAcc = _swElapsedAt(at ?? DateTime.now());
      _swStart = null;
      _swTick?.cancel();
      // Jokainen sekunti talteen kaikissa lajeissa (ennen alle minuutti → 1:00, ja muut kuin matkalajit
      // pyöristettiin minuuteiksi).
      _setSec(_swAcc.inSeconds);
      _swAcc = Duration.zero;
      _swDone = true;
      _swEnd = at ?? DateTime.now();
    });
    _syncOngoing();
  }

  /// Ajanotto pois (lajin vaihto tai GPS-tallennus): piilossa jäänyt ajanotto ei saa korvata aikaa.
  void _swReset() {
    _swTick?.cancel();
    _swStart = null;
    _swAcc = Duration.zero;
    _swUsed = false;
    _swDone = false;
    _swEnd = null;
    _syncOngoing();
  }

  /// Pysäytetyn ajanoton jatkaminen näkyvästä kestosta (myös korjatusta).
  void _swResume() {
    setState(() {
      _swAcc = Duration(seconds: _durSec);
      _swDone = false;
      _swEnd = null;
    });
    _swStartPause();
  }

  /// Kesto sekunteina lajista riippumatta (kestävyyslajeissa tarkka aika, muissa minuutit).
  int get _durSec => _timed ? _sec : (w.seconds ?? (w.minutes ?? 45) * 60);
  void _setDurSec(int s) => _setSec(s);

  /// Kesto käsin minuutteina (muut kuin matkalajit): tarkka aika pois, ettei se ja minuutit ole ristiriidassa.
  void _setMinutes(int m) {
    w.minutes = m;
    w.seconds = null;
  }

  DateTime _onDay(TimeOfDay v) => DateTime(w.date.year, w.date.month, w.date.day, v.hour, v.minute);

  Future<TimeOfDay?> _askClock(TimeOfDay init, String title) async =>
      ActivityScreen._debugPick?.call() ?? await pickTime(context, init, title: title);

  /// Loppuaika: pysäytetyn ajanoton loppu; GPS-reitissä viimeisen pisteen aika (kesto ei sisällä taukoja, joten
  /// alku + kesto näytti tauon jälkeen liian aikaista loppua, testikierros 15.11.); muuten alku + kesto.
  DateTime? get _end {
    if (_swDone && _swEnd != null) return _swEnd;
    final s = w.started;
    if (s == null) return null;
    final last = _route?.lastWhere((g) => g.isNotEmpty, orElse: () => const []).lastOrNull?.time.toLocal();
    final byDuration = s.add(Duration(seconds: _durSec));
    return last != null && last.isAfter(byDuration) ? last : byDuration;
  }

  Future<void> _pickStart() async {
    final v = await _askClock(
      w.started == null ? TimeOfDay.now() : TimeOfDay.fromDateTime(w.started!),
      t('Aloitusaika'),
    );
    if (v == null || !mounted) return;
    setState(() {
      var start = _onDay(v);
      // Ajanoton jälkeen loppu pysyy: kesto = loppu − alku. Alku loppua myöhemmin = edellinen päivä (yön yli).
      if (_swDone && _swEnd != null) {
        if (!start.isBefore(_swEnd!)) start = start.subtract(const Duration(days: 1));
        _setDurSec(_swEnd!.difference(start).inSeconds);
      }
      w.started = start;
    });
    Future.microtask(_saveDraft);
  }

  Future<void> _pickEnd() async {
    final v = await _askClock(TimeOfDay.fromDateTime(_end ?? DateTime.now()), t('Loppui'));
    if (v == null || !mounted) return;
    setState(() {
      var end = _onDay(v);
      // Loppu ennen alkua = seuraava päivä (yön yli).
      if (w.started != null && !end.isAfter(w.started!)) end = end.add(const Duration(days: 1));
      if (w.started == null) {
        // Ei alkua: alku lasketaan kestosta.
        w.started = end.subtract(Duration(seconds: _durSec));
      } else if (end.isAfter(w.started!)) {
        _setDurSec(end.difference(w.started!).inSeconds);
      }
      if (_swDone) _swEnd = end;
    });
    Future.microtask(_saveDraft);
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
    // Vertailukohta poistuttaessa: palautettu luonnos tai GPS-tallennus = aina muutoksia.
    _baseline = widget.draft != null || widget.recoverGps || w.activity == null ? null : _snapshot();
  }

  /// Näkymän oma tila luonnokseen: valinta (GPS / manuaalinen), ajanotto ja tallentamaton GPS-reitti.
  Map<String, Object?> _draftExtra() => {
    'manual': _manual,
    if (_swStart != null) 'swStart': _swStart!.toIso8601String(),
    'swAccMs': _swAcc.inMilliseconds,
    'swUsed': _swUsed,
    'useWatch': _useWatch,
    'swDone': _swDone,
    if (_swEnd != null) 'swEnd': _swEnd!.toIso8601String(),
    if (w.routeGpx != null) 'routeGpx': w.routeGpx,
  };

  void _restoreDraft(Map<String, Object?>? d) {
    if (d == null) return;
    _manual = d['manual'] == true;
    _swUsed = d['swUsed'] == true;
    _swAcc = Duration(milliseconds: (d['swAccMs'] as int?) ?? 0);
    _swStart = DateTime.tryParse(d['swStart'] as String? ?? '');
    _useWatch = (d['useWatch'] as bool?) ?? _useWatch;
    _swDone = d['swDone'] == true;
    _swEnd = DateTime.tryParse(d['swEnd'] as String? ?? '');
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
    // Koskematon kirjaus (laji vain valittu tai tallennettu avattu katsottavaksi) ei ole luonnos: muuten Androidin
    // sulkema sovellus palasi lajin näkymään ja Takaisin kysyi "Tallennetaanko liikunta?", vaikka mitään ei tehty.
    if (!_dirty) {
      if (_draftWritten) await ActivityDraft.clear();
      _draftWritten = false;
      return;
    }
    w.notes = _notes.text;
    _draftWritten = true;
    await ActivityDraft.save(w, extra: _draftExtra());
  }

  /// Tältä sivulta on kirjoitettu luonnos (poistetaan, jos muutokset perutaan käsin).
  late bool _draftWritten = widget.draft != null;

  /// GPS tarjotaan uudelle, tänään tehtävälle matkalajille Androidissa (ei verkkodemossa).
  bool get _canGps =>
      (ActivityScreen.debugGps ?? (!kIsWeb && !isDemo && Platform.isAndroid)) &&
      (sportOf(w.activity)?.distance ?? false) &&
      w.date == dateOnly(DateTime.now()) &&
      w.route == null &&
      w.routeGpx == null &&
      !store.onDay(w.date).any((x) => x.session == w.session);

  /// Saman lajin edellinen kirjaus (aloitusnäkymän vertailukohta).
  Workout? get _lastOfSport {
    final xs = store.workouts.where(
      (x) => x.activity == w.activity && !(x.date == w.date && x.session == w.session) && !x.date.isAfter(w.date),
    );
    if (xs.isEmpty) return null;
    return xs.reduce((a, b) => b.date.isAfter(a.date) || (b.date == a.date && b.session > a.session) ? b : a);
  }

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
              _Metric(
                value: paceParts(w.paceSecPerKm!, w.activity).$1,
                unit: paceParts(w.paceSecPerKm!, w.activity).$2,
                label: t('vauhti'),
              ),
              const SizedBox(width: 8),
              _Metric(value: fmtNum((w.speedKmh! * 10).round() / 10), unit: 'km/h', label: t('keskinopeus')),
            ],
          ),
        ),
      if (w.strideM case final m?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              // Askeleet näkyvät kellon tiedoissa; tässä niistä laskettu askelpituus.
              _Metric(value: fmtNum((m * 100).round() / 100), unit: 'm', label: t('askelpituus')),
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

  // ---- Kyyti kävely- tai juoksureitillä (vehicle_ride.dart): tallennus jäi päälle autoon tai bussiin. ----
  bool _ridesDismissed = false;
  List<List<TrackPoint>>? _ridesFor;
  String? _ridesSport;
  List<VehicleRide> _ridesCache = const [];

  /// Kyydit nykyiseltä reitiltä nykyiselle lajille (lajin vaihto pyöräilyksi piilottaa kortin).
  List<VehicleRide> get _rides {
    if (!identical(_raw, _ridesFor) || _ridesSport != w.activity) {
      _ridesFor = _raw;
      _ridesSport = w.activity;
      _ridesCache = _raw == null ? const [] : findVehicleRides(_raw!, w.activity);
    }
    return _ridesCache;
  }

  String _clock(DateTime t) => fmtClock(TimeOfDay.fromDateTime(t.toLocal()));

  Future<void> _removeRide(VehicleRide r) async {
    if (_locked) {
      await _unlock();
      if (_locked || !mounted) return;
    }
    final raw = _raw;
    if (raw == null) return;
    final after = removeRide(raw, r);
    final oldKm = w.distanceKm;
    final oldSec = _sec;
    setState(() {
      _setSec(secondsWithoutRide(_sec, raw, r));
      if (r.atStart && w.started != null) w.started = w.started!.add(r.end.difference(raw.first.first.time));
      _rawDist = distanceWithoutRide(after, _rawDist ?? measureRoute(raw));
      _raw = after;
      final note = 'kyyti poistettu ${_clock(r.start)}–${_clock(r.end)}';
      _desc = _desc.isEmpty ? note : '$_desc; $note';
    });
    await _applySnap(w.snapM ?? 0, remember: false);
    await _saveDraft();
    if (!mounted) return;
    final km = (oldKm ?? 0) - (w.distanceKm ?? 0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t('Kyyti poistettu: matka −{0} km, aika −{1}', [fmtDec(km < 0 ? 0 : km, 2), fmtDurationSec(oldSec - _sec)]),
        ),
      ),
    );
  }

  Widget _rideCard(ColorScheme cs, VehicleRide r) {
    final where = r.atEnd
        ? t('Reitti, matka ja aika päättyvät kyytiä edeltävään kohtaan.')
        : r.atStart
        ? t('Reitti, matka ja aika alkavat kyydin jälkeisestä kohdasta.')
        : t('Kyydin matka ja aika poistetaan; reitti jatkuu kyydin jälkeen.');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: yellowText(context).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: yellowText(context).withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🚌 ${t('Nousitko kyytiin?')}',
            key: const ValueKey('vehicleRide'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            t('Klo {0}–{1} reitti eteni noin {2} km/h ({3} km). Kävellen tai juosten se ei ole mahdollista.', [
              _clock(r.start),
              _clock(r.end),
              r.kmh.round(),
              fmtDec(r.meters / 1000, 1),
            ]),
          ),
          const SizedBox(height: 4),
          Text(where, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(onPressed: () => setState(() => _ridesDismissed = true), child: Text(t('Pidä reitti'))),
              FilledButton(onPressed: () => _removeRide(r), child: Text(t('Poista kyyti'))),
            ],
          ),
        ],
      ),
    );
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
                : (v) async {
                    // Tallennettu treeni: lupa kysytään ja muutos tehdään samalla napautuksella.
                    if (_locked) {
                      await _unlock();
                      if (_locked || !mounted) return;
                    }
                    _applySnap(v ? (settings.snapFor(w.activity!) > 0 ? settings.snapFor(w.activity!) : 5) : 0);
                  },
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
    final hs = hr.take('gps');
    // Kesken jäänyt reitti hylättiin (tallentimen tila poistettu): lajin sivu avattiin vain sitä varten, joten
    // luonnos pois ja etusivulle. Muuten sovellus palasi seuraavalla käynnistyksellä tyhjään lajin sivuun.
    if (r == null && recover && mounted && await GpsRecorder.pendingSport() == null) {
      _saved = true;
      _draftTick?.cancel();
      await ActivityDraft.clear();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (r == null || !mounted) return;
    _gpsHr = hs; // sovelletaan tallennettaessa, kun kesto on lopullinen
    _swReset();
    setState(() {
      w.activity = sport;
      w.started = r.started;
      _setSec(r.seconds);
      w.distanceKm = r.distanceKm > 0 ? r.distanceKm : null;
      w.routeGpx = r.segments.isEmpty ? null : r.gpx;
      _route = r.segments.isEmpty ? null : r.segments;
      _manual = true;
      _useWatch = false; // GPS:n aika näkyy Syötä aika -säätimessä (myös ilman reittiä)
      w.distanceManual = false;
      w.snapM = null;
      _raw = r.segments.isEmpty ? null : r.segments;
      _rawDist = r.distanceM > 0 ? r.distanceM : r.distanceKm * 1000;
      _desc = r.desc;
      _ways = null;
      _waysLoad = null;
      _ridesDismissed = false;
    });
    // Polulle korjaus lajin oletuksella (5 m tai käyttäjän viimeksi valitsema); säädettävissä kartan alla.
    if (_canSnap) await _applySnap(settings.snapFor(sport), remember: false);
    // Reitti luonnokseen heti: tallentimen tiedostot on jo poistettu, joten 3 s:n odotus voisi hukata sen.
    await _saveDraft();
  }

  bool get _timed => sportOf(w.activity)?.distance ?? false;

  /// Kestävyyslajeissa tarkka aika (h:mm:ss); muissa minuutit.
  int get _sec => w.seconds ?? (w.minutes ?? 45) * 60;

  /// Epäuskottava nopeus hyväksytty (Tallenna silti): ei kysytä uudelleen tässä näkymässä.
  bool _speedOk = false;
  void _setSec(int s) {
    w.seconds = s.clamp(1, 24 * 3600);
    w.minutes = minutesFromSeconds(w.seconds!);
  }

  Future<void> _askTime() async {
    final c = selectedText(fmtDurationSec(_sec));
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

  bool _finishing = false;

  /// Kirjaus sellaisena kuin se avattiin (tai laji valittiin); null = muutoksia joka tapauksessa.
  String? _baseline;
  String _snapshot() {
    w.notes = _notes.text;
    return workoutToMarkdown(w);
  }

  bool get _dirty =>
      _swStart != null || _swAcc > Duration.zero || _swDone || _baseline == null || _snapshot() != _baseline;

  /// Takaisin tallentamattomin muutoksin: kysytään (Tallenna, Hylkää tai jatka muokkausta).
  Future<void> _confirmLeave() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isSaved ? t('Tallennetaanko muutokset?') : t('Tallennetaanko liikunta?')),
        content: Text(t('Muuten muutokset hylätään.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(t('Hylkää'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(t('Tallenna'))),
        ],
      ),
    );
    if (!mounted) return;
    if (v == 'discard') {
      Navigator.of(context).pop();
    } else if (v == 'save') {
      await _save();
    }
  }

  Future<void> _save() async {
    if (_finishing) return;
    _finishing = true;
    try {
      await _saveInner();
    } finally {
      _finishing = false;
    }
  }

  Future<void> _saveInner() async {
    // Ajanotto valittu mutta ei aloitettu: muuten tallentuisi oletuskesto huomaamatta.
    if (_canStopwatch && _useWatch && !_swUsed && !_swDone && _swStart == null && _swAcc == Duration.zero) {
      final manual = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Ajanottoa ei ole aloitettu')),
          content: Text(t('Aloita ajanotto tai syötä aika itse.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Syötä aika'))),
          ],
        ),
      );
      if (manual == true && mounted) setState(() => _useWatch = false);
      return;
    }
    // Alle minuutin ajanotto on usein vahingossa aloitettu tai kokeilu: kysytään ennen tallennusta (aika
    // tallentuu tarkkana, esim. 0:16).
    // Käynnissä: kellon aika; pysäytetty (Lopeta): tallennettu tarkka aika.
    final doneAt = DateTime.now(); // kello pysähtyy tähän, vaikka kysymyksiin vastaaminen kestäisi
    final swSecs = _swElapsed > Duration.zero ? _swElapsedAt(doneAt).inSeconds : (_swDone ? (w.seconds ?? 0) : 0);
    if (_canStopwatch && _useWatch && !_isSaved && swSecs > 0 && swSecs < 60) {
      final keep = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Alle minuutin liikunta')),
          content: Text(t('Ajanotto kesti vain {0}. Tallennetaanko se vai hylätäänkö?', [fmtDurationSec(swSecs)])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Hylkää'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Tallenna'))),
          ],
        ),
      );
      if (keep == null || !mounted) return; // takaisin: ajanotto jatkuu
      if (!keep) {
        Navigator.of(context).pop(); // kuten Takaisin → Hylkää: ei tallenneta
        return;
      }
    }
    // Käsin syötetty matka ja aika: epäuskottava nopeus (esim. 1 km ajassa 0:10) on yleensä kirjoitusvirhe.
    final secsNow = swSecs > 0 ? swSecs : _sec;
    if (w.route == null &&
        w.hcId == null &&
        w.healthSource == null &&
        !_speedOk &&
        implausibleSpeed(w.activity, w.distanceKm ?? 0, secsNow)) {
      final kmh = (w.distanceKm! / (secsNow / 3600)).round();
      final keep = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('implausibleSpeed'),
          title: Text(t('Tarkista matka ja aika')),
          content: Text(
            t('{0} km ajassa {1} on noin {2} km/h. Onko matka tai aika väärin?', [
              fmtNum(w.distanceKm!),
              fmtDurationSec(secsNow),
              kmh,
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Tallenna silti'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Muokkaa'))),
          ],
        ),
      );
      if (keep != true || !mounted) return;
      _speedOk = true;
    }
    // Fiilis ponnahdusikkunassa ensin (Ohita jatkaa; takaisin peruu lopetuksen ja ajanotto jatkuu).
    if (w.feeling == null && !_isSaved) {
      // Uudessa liikunnassa rasitus samassa kyselyssä (valinnainen); fiiliksen napautus päättää kyselyn.
      final r = await showFinishSheet(
        context,
        w: w,
        askIntensity: _live,
        intensity: _live ? w.intensity : null,
        series: (hr.peek(_hrKey) ?? _gpsHr)?.series,
        // Käynnissä olevan ajanoton aika (ei oletus 45:00, joka on vasta ajanoton pysäytyksen jälkeen oikea).
        durationSec: swSecs > 0 ? swSecs : _sec,
      );
      if (r == null || !mounted) return;
      if (_live) w.intensity = r.intensity;
      if (r.feeling != feelingSkipped) w.feeling = r.feeling;
    }
    if (_swStart != null || _swAcc > Duration.zero) _swStop(doneAt);
    // Sykevyö (ajanotto tai GPS): käyrä, keskisyke, maksimi ja kalorit.
    final hs = await hr.end(_hrKey) ?? _gpsHr;
    if (hs != null) applyHeartRate(w, hs);
    w.notes = _notes.text;
    if (!isRun(w.activity)) w.runType = null;
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
    hr.end(_hrKey); // tallentamatta poistuttu: sykkeet pois
    // Kirjauksesta poistuttiin itse (takaisin) tai se tallennettiin: luonnosta ei tarvita.
    _draftTick?.cancel();
    ActivityDraft.clear();
    _syncOngoing(clear: true); // luonnos ja ajanotto päättyvät sivulta poistuttaessa
    _notes.dispose();
    super.dispose();
  }

  /// Ajan kirjaus: valinta Ajanotto / Syötä aika (vain uudelle, tänään tehtävälle), sitten valitun tilan kortti.
  Widget _timeSection(ColorScheme cs) {
    final active = _swStart != null || _swAcc > Duration.zero;
    // Käynnissä tai pysäytetty ajanotto näkyy aina (myös keskiyön jälkeen, kun tämä ei ole enää "tänään").
    final choice = _canStopwatch || active || _swDone;
    final watch = active || (_useWatch && choice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (choice)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, icon: const Icon(Icons.timer_outlined), label: Text(t('Ajanotto'))),
                ButtonSegment(value: false, icon: const Icon(Icons.edit_outlined), label: Text(t('Syötä aika'))),
              ],
              selected: {watch},
              // Käynnissä olevaa ajanottoa ei vaihdeta piiloon: valinta näkyy, mutta Syötä aika ei ole valittavissa.
              onSelectionChanged: (v) {
                if (active && !v.first) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(t('Lopeta ajanotto ensin.'))));
                  return;
                }
                setState(() => _useWatch = v.first);
              },
            ),
          ),
        if (watch) _watchCard(cs) else _manualCard(cs),
      ],
    );
  }

  Widget _clockPill(String label, DateTime? v, VoidCallback onTap, {bool end = false}) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 11, letterSpacing: .6, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.schedule, size: 18),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(v == null ? t('ei tiedossa') : fmtClock(TimeOfDay.fromDateTime(v))),
        ),
      ),
    ],
  );

  Widget _startEndRow() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(child: _clockPill(t('Alkoi'), w.started, _pickStart)),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        child: Icon(Icons.arrow_forward, size: 18, color: Theme.of(context).colorScheme.outline),
      ),
      Expanded(child: _clockPill(t('Loppui'), _end, _pickEnd, end: true)),
    ],
  );

  Widget _bigTime(String v, {Color? color}) => Text(
    v,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  /// Tarkka aika, kun se on (ajanotto kaikissa lajeissa); käsin kirjatut minuutit muuten.
  String get _durText =>
      _timed ? fmtDurationSec(_sec) : (w.seconds != null ? fmtDurationSec(w.seconds!) : t('{0} min', [w.minutes]));

  Widget _watchCard(ColorScheme cs) {
    final running = _swStart != null;
    final active = running || _swAcc > Duration.zero;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        key: const ValueKey('stopwatch'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_swDone) ...[
                _startEndRow(),
                const SizedBox(height: 10),
                _bigTime(_durText),
                Text(t('Napauta aikaa muuttaaksesi.'), textAlign: TextAlign.center, style: sub),
                TextButton.icon(
                  onPressed: _swResume,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t('Jatka ajanottoa')),
                ),
              ] else if (active) ...[
                _bigTime(fmtDurationSec(_swElapsed.inSeconds), color: running ? yellowText(context) : null),
                if (w.started != null)
                  Text(
                    t('alkoi {0}', [fmtClock(TimeOfDay.fromDateTime(w.started!))]),
                    textAlign: TextAlign.center,
                    style: sub,
                  ),
                // Sykevyö: iso sykerengas, alue, käyrä ja tilanne tähän asti.
                const HrRing(sessionKey: 'activity'),
                const SizedBox(height: 12),
                // Tauko/Jatka pääpainikkeena, Lopeta reunapainikkeena kuten GPS-tallennuksessa (käyttäjä 15.11.): kello
                // pysähtyy myös Treeni valmis -painikkeesta, joten Lopeta ei ole näkymän tärkein toiminto.
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('swPause'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: _swStartPause,
                        icon: Icon(running ? Icons.pause : Icons.play_arrow),
                        label: Text(running ? t('Tauko') : t('Jatka')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('swStop'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: _swStop,
                        icon: const Icon(Icons.stop),
                        label: Text(t('Lopeta')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(t('Ajanotto jatkuu, vaikka sulkisit sovelluksen.'), textAlign: TextAlign.center, style: sub),
              ] else ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _swStartPause,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t('Aloita'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Text(
                  t('Aloitus- ja loppuaika tallentuvat; voit korjata ne lopuksi.'),
                  textAlign: TextAlign.center,
                  style: sub,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _manualCard(ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
          // Ajanotosta tarkka aika (m:ss); käsin muutettaessa minuutit.
          value: w.seconds != null ? fmtDurationSec(w.seconds!) : '${w.minutes}',
          unit: w.seconds != null ? '' : 'min',
          onMinus: () => setState(() => _setMinutes((((w.seconds ?? w.minutes! * 60) / 60).round() - 5).clamp(5, 600))),
          onPlus: () => setState(() => _setMinutes((((w.seconds ?? w.minutes! * 60) / 60).round() + 5).clamp(5, 600))),
          onTap: () async {
            final v = await askNumber(
              context,
              t('Kesto (min)'),
              w.minutes!.toDouble(),
              decimals: false,
              min: 1,
              max: 1440,
            );
            if (v != null && v > 0) setState(() => _setMinutes(v.round()));
          },
        ),
      ],
      // Aloitusaika: Health Connect etsii tiedot (kävelyllä ja retkeilyllä myös askeleet) tältä ajalta.
      const SizedBox(height: 12),
      _startEndRow(),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          t('Alkuaika on vapaaehtoinen; loppu lasketaan kestosta.'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ),
    ],
  );

  /// Tallennettu liikunta avautuu lukutilaan (ei luonnos eikä palautettu GPS-tallennus); muokkaus kysyy ensin.
  late bool _locked =
      widget.draft == null &&
      !widget.recoverGps &&
      store.onDay(w.date).any((x) => x.session == w.session && x.activity != null);

  /// Uusi, tänään tehtävä liikunta (ei tallennettu eikä Health Connectista): fiilis ja kellon tiedot lopussa.
  bool get _live => !_isSaved && w.hcId == null && w.healthSource == null && w.date == dateOnly(DateTime.now());

  bool get _isSaved => store.onDay(w.date).any((x) => x.session == w.session && x.activity != null);

  /// Poistaa tallennetun liikunnan (.md ja oma .gpx). Health Connectista lisätty tulee taas lisättäväksi.
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko liikunta?')),
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
    _saved = true; // ei luonnosta poistetusta
    _draftTick?.cancel();
    await store.delete(w.date, w.session);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _unlock() async {
    if (await askEditSaved(context) && mounted) setState(() => _locked = false);
  }

  /// Reittikortti jää lukkoon kuulumattomaksi: karttaa voi siirtää ja karttoja ladata muokkaamatta treeniä, ja
  /// polulle korjauksen kytkin kysyy muokkausluvan itse.
  static const _routeKey = ValueKey('route');

  List<Widget> _guard(List<Widget> xs) => !_locked
      ? xs
      : [
          xs.first,
          for (final x in xs.skip(1)) x.key == _routeKey ? x : EditGuard(locked: true, onTap: _unlock, child: x),
        ];

  /// Tallennetun liikunnan lukunäkymä (lukittu; mockup 10, käyttäjän valinta 14.11.): yksi yhteenvetokortti
  /// (aika, matka, vauhti tai nopeus, askeleet, kalorit, syke ja askelpituus, kun tiedossa), reitti, syke, rasitus
  /// ja fiilis, muistiinpanot. Kaikissa lajeissa sama; muokkaus (✎ Muokkaa tai lukko) avaa tavalliset säätimet.
  Widget _readSummary(ColorScheme cs) {
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final speed = _speedSports.contains(w.activity);
    final km = w.distanceKm ?? 0;
    final stats = <(String, String, String)>[
      (_durText, '', t('Aika')),
      if (km > 0) (fmtNum((km * 100).round() / 100), 'km', t('Matka')),
      if (km > 0 && w.pace != null && !speed)
        (
          paceParts(w.paceSecPerKm!, w.activity).$1,
          paceParts(w.paceSecPerKm!, w.activity).$2.substring(3),
          t('vauhti'),
        ),
      if (km > 0 && w.speedKmh != null && speed) (fmtNum((w.speedKmh! * 10).round() / 10), 'km/h', t('keskinopeus')),
      if ((w.steps ?? 0) > 0) (thousands(w.steps!), '', t('askeleet')),
      if ((w.kcal ?? 0) > 0) ('${w.kcal}', 'kcal', t('kalorit')),
      if (w.hrAvg != null) (t('ka {0}', [w.hrAvg]), '', t('Syke')),
      if (w.strideM case final m?) (fmtNum((m * 100).round() / 100), 'm', t('askelpituus')),
    ];
    final end = _end;
    final when = [
      shortDate(w.date),
      if (w.started != null)
        end == null
            ? fmtClock(TimeOfDay.fromDateTime(w.started!))
            // Sananliittäjät: aikaväli rivittyy kokonaisena (ei "12:00–" ja "12:45" eri riveille).
            : '${fmtClock(TimeOfDay.fromDateTime(w.started!))}\u2060–\u2060${fmtClock(TimeOfDay.fromDateTime(end))}',
    ].join(' · ');
    final sources = [
      if (w.healthSource != null) w.healthSource!.isEmpty ? 'Health Connect' : 'Health Connect · ${w.healthSource}',
      if (w.hrSource == 'sykevyö') t('Sykevyö'),
      if (_hasRoute) 'GPS',
    ];
    return Card(
      key: const ValueKey('readSummary'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                  child: FittedBox(child: Text(sportOf(w.activity)?.icon ?? '✨', style: const TextStyle(fontSize: 26))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Yksi rivi, tarvittaessa pienennettynä: pitkä sana ("Sihkkelastin") ei katkea kesken.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          sportName(w.activity!),
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.2),
                        ),
                      ),
                      Text(when, style: sub.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('readEdit'),
                  onPressed: _unlock,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(t('Muokkaa')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Kolmen ruudun rivit, rivin ruudut yhtä korkeita (pitkä nimike kahdella rivillä ei tee rosoa).
            for (var r = 0; r < stats.length; r += 3)
              Padding(
                padding: EdgeInsets.only(top: r == 0 ? 0 : 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = r; i < r + 3; i++) ...[
                        if (i > r) const SizedBox(width: 8),
                        Expanded(child: i < stats.length ? _statTile(stats[i], cs, sub) : const SizedBox()),
                      ],
                    ],
                  ),
                ),
              ),
            if (sources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('♥ ${sources.join(' · ')}', style: TextStyle(fontSize: 12, color: greenText(context))),
              ),
          ],
        ),
      ),
    );
  }

  /// Matka: säädin ja vauhti/keskinopeus (uusi kirjaus ja tallennetun muokkaus).
  List<Widget> _distanceSection() => [
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
        final v = await askNumber(context, t('Matka (km)'), w.distanceKm ?? 5, min: 0, max: 1000);
        if (v != null && v >= 0 && mounted) {
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
            _Metric(
              value: paceParts(w.paceSecPerKm!, w.activity).$1,
              unit: paceParts(w.paceSecPerKm!, w.activity).$2,
              label: t('vauhti'),
            ),
            const SizedBox(width: 8),
            _Metric(value: fmtNum((w.speedKmh! * 10).round() / 10), unit: 'km/h', label: t('keskinopeus')),
          ],
        ),
      ),
  ];

  Widget _statTile((String, String, String) st, ColorScheme cs, TextStyle sub) {
    final (v, unit, label) = st;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(
              TextSpan(
                text: v,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                children: [
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: sub.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
              maxLines: 1,
            ),
          ),
          Text(label, maxLines: 2, style: sub),
        ],
      ),
    );
  }

  /// Muokkausnäkymän ryhmä omana korttinaan (Aika, Matka, Kellon tiedot).
  Widget _group(List<Widget> children) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );

  /// Reittikortti (kartta, korkeusprofiili tai kilometrit, polulle korjaus); sama luku- ja muokkausnäkymässä.
  Widget _routeCard() => Padding(
    key: _routeKey,
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
          if (!_ridesDismissed && _rides.isNotEmpty) _rideCard(Theme.of(context).colorScheme, _rides.first),
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
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sport = sportOf(w.activity);
    final choosing = w.activity == null || (_canGps && !_manual);
    return PopScope(
      // Tallentamaton kirjaus: takaisin kysyy ensin (ei hiljaista hukkaa, ei käynnissä olevan ajanoton katoamista).
      canPop: _locked || _saved || w.activity == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        // Treeni valmis aina alareunassa (kuten salitreenissä); ei lajin tai kirjaustavan valinnassa eikä lukittuna.
        bottomNavigationBar: _locked || choosing
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                  // Reunapainike kuten salitreenissä (käyttäjä 15.11.): ajanoton Tauko on näkymän pääpainike.
                  child: OutlinedButton.icon(
                    key: const ValueKey('finishActivity'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: greenText(context),
                      side: BorderSide(color: greenText(context), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _save,
                    icon: const Icon(Icons.flag_rounded),
                    label: Text(t('Treeni valmis!'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
        appBar: AppBar(
          title: BarTitle(Text(w.activity == null ? t('Liikunta') : sportName(w.activity!))),
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
              SportPicker(
                onPick: (s) => setState(() {
                  w.activity = s;
                  _baseline = _snapshot();
                }),
              ),
            ] else if (_locked) ...[
              // Lukunäkymä: yhteenveto ja tulokset, ei säätimiä (muokkaus avaa ne).
              _readSummary(cs),
              if (_hasRoute) _routeCard(),
              HrDetails(w),
              EffortFeelingCard(
                intensity: w.intensity,
                onIntensity: (v) => setState(() => w.intensity = v),
                feeling: w.feeling,
                onFeeling: (v) => setState(() => w.feeling = v),
              ),
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
                  TextButton(
                    onPressed: () => setState(() {
                      _swReset();
                      w.activity = null;
                    }),
                    child: Text(t('Vaihda laji')),
                  ),
                ],
              ),
              if (_canGps && !_manual) ...[
                const SizedBox(height: 14),
                _GpsChoice(
                  onGps: _record,
                  onWatch: _canStopwatch
                      ? () => setState(() {
                          _manual = true;
                          _useWatch = true;
                        })
                      : null,
                  onManual: () => setState(() {
                    _manual = true;
                    _useWatch = false;
                  }),
                ),
                if (_mapMissing)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Material(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                        child: Row(
                          children: [
                            Icon(Icons.map_outlined, color: cs.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                t('Tämän alueen karttaa ei ole ladattu. GPS toimii ilmankin.'),
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                            ),
                            TextButton(onPressed: _openMaps, child: Text(t('Lataa'))),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_lastOfSport case final last?) ...[
                  SectionLabel(t('Viimeksi: {0}', [sportNameParts(w.activity!).$1])),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      [
                        shortDate(last.date),
                        if (last.distanceKm != null) '${fmtNum(last.distanceKm!)} km',
                        if (last.seconds != null)
                          fmtDurationSec(last.seconds!)
                        else if (last.minutes != null)
                          fmtDuration(last.minutes!),
                        ?last.pace,
                      ].join(' · '),
                    ),
                  ),
                ],
              ] else ...[
                if (_hasRoute) _routeCard(),
                // GPS-lenkki: aika ja matka mitattuina arvoina; Korjaa avaa tavalliset säätimet.
                if (_gpsView)
                  _gpsSummary(cs)
                else if (!_live) ...[
                  // Tallennetun muokkaus: aika ja matka omina kortteinaan (mockup 10).
                  _group([_timeSection(cs)]),
                  if (sport?.distance ?? false) _group(_distanceSection()),
                ] else ...[
                  _timeSection(cs),
                  if (sport?.distance ?? false) ..._distanceSection(),
                ],
                // Askeleet Kellon tiedot -kortissa (Health Connect tai käsin), ei omana kohtanaan.
                // Uusi, tänään tehtävä liikunta: kellon tiedot ja fiilis kysytään lopussa (Treeni valmis → ponnahdus ja
                // yhteenveto). Aiemman päivän, Health Connectista tuodun ja tallennetun kohdalla ne ovat sivulla.
                if ((settings.watch || w.healthSource != null) && !_live)
                  _group([
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
                  ]),
                // Sykevyön käyrä ja sykealueet.
                if (!_live) HrDetails(w),
                // Rasitus ja fiilis yhdessä kortissa sykkeen jälkeen (ennen kellon tiedot ja syke olivat välissä).
                // Uudessa liikunnassa molemmat kysytään lopussa Treeni valmis -ikkunassa.
                if (!_live || _isSaved)
                  EffortFeelingCard(
                    intensity: w.intensity,
                    onIntensity: _live ? null : (v) => setState(() => w.intensity = v),
                    feeling: w.feeling,
                    onFeeling: _isSaved ? (v) => setState(() => w.feeling = v) : null,
                  ),
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
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

/// Matkalajin aloitus: iso GPS-kortti (aika, matka ja reitti mitataan), sen alla Ajanotto (ilman GPS:ää, esim.
/// juoksumatto; vain tänään) ja Syötä itse (jo tehty liikunta).
class _GpsChoice extends StatelessWidget {
  final VoidCallback onGps, onManual;
  final VoidCallback? onWatch;
  const _GpsChoice({required this.onGps, required this.onManual, this.onWatch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget small(IconData icon, String title, String sub, VoidCallback onTap, Key key) => Expanded(
      child: Material(
        key: key,
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
            child: Column(
              children: [
                Icon(icon, size: 26, color: yellowText(context)),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          key: const ValueKey('startGps'),
          color: cs.primary,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onGps,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 12, 18),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 30, color: cs.onPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Aloita GPS:llä'),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onPrimary),
                        ),
                        Text(
                          t('Aika, matka, reitti ja korkeus'),
                          style: TextStyle(fontSize: 12.5, color: cs.onPrimary.withValues(alpha: .85)),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onPrimary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onWatch != null) ...[
                small(
                  Icons.timer_outlined,
                  t('Ajanotto'),
                  t('Ilman GPS:ää, esim. juoksumatto'),
                  onWatch!,
                  const ValueKey('startWatch'),
                ),
                const SizedBox(width: 10),
              ],
              small(
                Icons.edit_outlined,
                t('Syötä itse'),
                t('Jo tehty: aika ja matka'),
                onManual,
                const ValueKey('startManual'),
              ),
            ],
          ),
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
