import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'gps_filter.dart';
import 'gpx.dart';
import 'maps/map_store.dart';
import 'maps/path_snap.dart';

// Reitin tallennus: puhelimen GPS -> suodatin (gps_filter.dart) -> aika, matka, vauhti ja reitti.
// Androidissa paikannukset tulevat omasta etualapalvelusta (android/.../GpsService.kt), joka kirjoittaa ne myös
// tiedostoon. Tallennuksen tila (laji, aloitus, tauot) on omassa tiedostossaan, joten kesken jäänyt tallennus
// voidaan palauttaa, vaikka Android sulkisi sovelluksen kesken lenkin.

/// Paikannusten lähde (Android-palvelu tai testien keksitty reitti).
abstract class GpsSource {
  Stream<Map<String, Object?>> get events;
  Future<bool> enabled();
  Future<void> start({required String title, required String text, required String channel});
  Future<void> stop();
  Future<bool> running();

  /// Palvelun kirjoittamat paikannukset (aika ms, lat, lon, tarkkuus) palautusta varten.
  Future<List<GpsFix>> savedFixes();
  Future<void> clearSaved();
  Future<void> openSettings();
}

class AndroidGpsSource implements GpsSource {
  static const _ctl = MethodChannel('fi.somby.gievra/gpsctl');
  static const _ev = EventChannel('fi.somby.gievra/gps');

  @override
  Stream<Map<String, Object?>> get events =>
      _ev.receiveBroadcastStream().map((e) => Map<String, Object?>.from(e as Map));

  @override
  Future<bool> enabled() async => await _ctl.invokeMethod<bool>('enabled') ?? false;

  @override
  Future<void> start({required String title, required String text, required String channel}) =>
      _ctl.invokeMethod('start', {'title': title, 'text': text, 'channel': channel});

  @override
  Future<void> stop() => _ctl.invokeMethod('stop');

  @override
  Future<bool> running() async => await _ctl.invokeMethod<bool>('running') ?? false;

  Future<File> _raw() async => File((await _ctl.invokeMethod<String>('rawPath'))!);

  @override
  Future<List<GpsFix>> savedFixes() async {
    final f = await _raw();
    if (!await f.exists()) return [];
    return parseRawFixes(await f.readAsString());
  }

  @override
  Future<void> clearSaved() async {
    final f = await _raw();
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> openSettings() => _ctl.invokeMethod('settings');
}

/// Palvelun tiedosto: "aika_ms,lat,lon,tarkkuus" riveittäin; vajaat rivit ohitetaan.
List<GpsFix> parseRawFixes(String text) {
  final out = <GpsFix>[];
  for (final line in const LineSplitter().convert(text)) {
    final f = line.split(',');
    if (f.length < 4) continue;
    final t = int.tryParse(f[0]);
    final lat = double.tryParse(f[1]), lon = double.tryParse(f[2]), acc = double.tryParse(f[3]);
    if (t == null || lat == null || lon == null || acc == null) continue;
    out.add(GpsFix(DateTime.fromMillisecondsSinceEpoch(t), lat, lon, acc));
  }
  return out;
}

GpsFix? fixFromEvent(Map<String, Object?> e) {
  final t = e['t'], lat = e['lat'], lon = e['lon'], acc = e['acc'];
  if (t is! int || lat is! double || lon is! double || acc is! num) return null;
  return GpsFix(DateTime.fromMillisecondsSinceEpoch(t), lat, lon, acc.toDouble());
}

enum RecState { idle, searching, recording, paused }

/// Valmis tallennus treeniin liitettäväksi.
class RouteResult {
  final DateTime started;
  final int seconds; // kesto ilman taukoja
  final double distanceKm;
  final String gpx;
  final List<List<TrackPoint>> segments;
  const RouteResult({
    required this.started,
    required this.seconds,
    required this.distanceKm,
    required this.gpx,
    required this.segments,
  });
}

class GpsRecorder extends ChangeNotifier {
  final GpsSource source;
  final DateTime Function() now;

  /// Väylät reitin ympäriltä polulle korjausta varten (oletus: ladatut offline-kartat).
  final Future<List<SnapWay>> Function(List<List<TrackPoint>>) ways;
  GpsRecorder({
    GpsSource? source,
    DateTime Function()? now,
    Future<List<SnapWay>> Function(List<List<TrackPoint>>)? ways,
  }) : source = source ?? AndroidGpsSource(),
       now = now ?? DateTime.now,
       ways = ways ?? _mapWays;

  static Future<List<SnapWay>> _mapWays(List<List<TrackPoint>> segs) async {
    final store = MapStore.instance;
    if (store.installed.isEmpty) await store.load(network: false);
    return store.waysAround(segs);
  }

  RecState state = RecState.idle;
  String sport = '';
  GpsFilter _filter = GpsFilter(GpsLimits.run);
  GpsFilter get filter => _filter;

  /// Viimeisin paikannus (signaalin tila) ja sen ikä.
  GpsFix? lastFix;

  /// Puhelimen kello, kun viimeisin paikannus saapui (GPS-aika ja puhelimen kello voivat erota).
  DateTime? lastFixAt;
  bool gpsDisabled = false;

  /// Ajanotto: aloitus ja tauot [alku, loppu); käynnissä olevalla tauolla loppu = null.
  DateTime? startedAt;
  final pauses = <(DateTime, DateTime?)>[];

  StreamSubscription<Map<String, Object?>>? _sub;
  Timer? _tick;

  /// Hyvä signaali: viimeisin paikannus alle 5 s vanha ja tarkkuus enintään 20 m.
  bool get goodSignal {
    final f = lastFix;
    final at = lastFixAt;
    return f != null && at != null && f.accuracy <= GpsFilter.startAccuracy && now().difference(at).inSeconds < 5;
  }

  /// Kesto ilman taukoja.
  Duration get elapsed {
    final s = startedAt;
    if (s == null) return Duration.zero;
    var d = now().difference(s);
    for (final (a, b) in pauses) {
      d -= (b ?? now()).difference(a);
    }
    return d.isNegative ? Duration.zero : d;
  }

  double get distanceKm => _filter.distance / 1000;

  /// Keskivauhti s/km (null, kun matkaa alle 50 m).
  double? get avgPace => _filter.distance < 50 ? null : elapsed.inMilliseconds / 1000 / distanceKm;

  /// Nykyinen vauhti viimeisen noin 30 s ajalta (s/km); null, jos ei liikuta.
  double? get currentPace {
    final pts = _filter.segments.isEmpty ? const <TrackPoint>[] : _filter.segments.last;
    if (pts.length < 2) return null;
    final end = pts.last;
    var i = pts.length - 1;
    while (i > 0 && end.time.difference(pts[i - 1].time).inSeconds <= 30) {
      i--;
    }
    final start = pts[i];
    final secs = end.time.difference(start.time).inMilliseconds / 1000;
    var d = 0.0;
    for (var k = i + 1; k < pts.length; k++) {
      d += geoDistance(pts[k - 1].lat, pts[k - 1].lon, pts[k].lat, pts[k].lon);
    }
    final at = lastFixAt;
    if (secs < 10 || d < 20 || at == null || now().difference(at).inSeconds > 15) return null;
    return secs / (d / 1000);
  }

  // ---- tilatiedosto palautusta varten ----

  /// Testejä varten: tilatiedoston kansio.
  @visibleForTesting
  static Directory? stateDirOverride;

  static Future<File> _stateFile() async =>
      File(p.join((stateDirOverride ?? await getApplicationSupportDirectory()).path, 'gps-recording.json'));

  Future<void> _saveState() async {
    if (kIsWeb) return;
    try {
      final f = await _stateFile();
      await f.writeAsString(
        jsonEncode({
          'sport': sport,
          'started': startedAt?.toIso8601String(),
          'paused': state == RecState.paused,
          'pauses': [
            for (final (a, b) in pauses) [a.toIso8601String(), b?.toIso8601String()],
          ],
        }),
      );
    } catch (_) {}
  }

  Future<void> _clearState() async {
    if (kIsWeb) return;
    try {
      final f = await _stateFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Kesken jäänyt tallennus (laji), jos sellainen on.
  static Future<String?> pendingSport() async {
    if (kIsWeb) return null;
    try {
      final f = await _stateFile();
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return m['sport'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ---- ohjaus ----

  /// Avaa GPS:n ja odottaa signaalia (ajanotto ei vielä käy). [title] ja [text] ilmoitukseen.
  Future<void> open(String sport, {required String title, required String text, required String channel}) async {
    this.sport = sport;
    _filter = GpsFilter(GpsLimits.forSport(sport));
    _lastFedTime = null;
    gpsDisabled = !await source.enabled();
    _listen();
    await source.clearSaved();
    await source.start(title: title, text: text, channel: channel);
    state = RecState.searching;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  /// Palauttaa kesken jääneen tallennuksen tilatiedostosta ja palvelun tallentamista paikannuksista.
  Future<bool> recover({required String title, required String text, required String channel}) async {
    try {
      final f = await _stateFile();
      if (!await f.exists()) return false;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      sport = m['sport'] as String? ?? '';
      _filter = GpsFilter(GpsLimits.forSport(sport));
      _lastFedTime = null;
      startedAt = DateTime.tryParse(m['started'] as String? ?? '');
      pauses
        ..clear()
        ..addAll([
          for (final e in (m['pauses'] as List? ?? const []))
            (DateTime.parse((e as List)[0] as String), e[1] == null ? null : DateTime.parse(e[1] as String)),
        ]);
      for (final fix in await source.savedFixes()) {
        _feed(fix, live: false);
      }
      state = startedAt == null ? RecState.searching : (m['paused'] == true ? RecState.paused : RecState.recording);
      _listen();
      if (!await source.running()) await source.start(title: title, text: text, channel: channel);
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = source.events.listen((e) {
      if (e['status'] == 'disabled') gpsDisabled = true;
      if (e['status'] == 'enabled') gpsDisabled = false;
      final fix = fixFromEvent(e);
      if (fix != null) {
        gpsDisabled = false;
        _feed(fix, live: true);
      }
      notifyListeners();
    });
  }

  /// Paikannus suotimelle vain ajanoton käydessä (ei odottaessa eikä tauolla).
  void _feed(GpsFix fix, {required bool live}) {
    lastFix = fix;
    lastFixAt = live ? now() : fix.time;
    final s = startedAt;
    if (s == null || fix.time.isBefore(s)) return;
    for (final (a, b) in pauses) {
      if (!fix.time.isBefore(a) && (b == null || fix.time.isBefore(b))) return;
    }
    // Tauon jälkeen uusi osuus: tauon aikana kuljettua matkaa ei lasketa. Tarkistetaan kaikki tauot, jotka
    // päättyivät edellisen ja tämän paikannuksen välissä (palautuksessa niitä voi olla useita).
    final prev = _lastFedTime;
    for (final (_, b) in pauses) {
      if (b != null && !fix.time.isBefore(b) && (prev == null || prev.isBefore(b))) {
        _filter.breakSegment();
        break;
      }
    }
    _lastFedTime = fix.time;
    _filter.add(fix);
  }

  /// Viimeisimmän suotimelle annetun paikannuksen aika.
  DateTime? _lastFedTime;

  /// Ajanotto käyntiin (signaali löytyi tai "Aloita silti").
  Future<void> start() async {
    startedAt = now();
    state = RecState.recording;
    notifyListeners(); // näkymä päivittyy heti; tila tallennetaan perään
    await _saveState();
  }

  Future<void> pause() async {
    if (state != RecState.recording) return;
    pauses.add((now(), null));
    state = RecState.paused;
    notifyListeners(); // näkymä päivittyy heti; tila tallennetaan perään
    await _saveState();
  }

  Future<void> resume() async {
    if (state != RecState.paused) return;
    final (a, _) = pauses.removeLast();
    pauses.add((a, now()));
    state = RecState.recording;
    notifyListeners(); // näkymä päivittyy heti; tila tallennetaan perään
    await _saveState();
  }

  /// Lopetus: palauttaa tuloksen (null, jos ajanotto ei ehtinyt alkaa).
  Future<RouteResult?> finish({required String name}) async {
    if (state == RecState.paused) await resume();
    _filter.finish();
    final s = startedAt;
    final secs = elapsed.inSeconds;
    await _close();
    if (s == null) return null;
    var segs = _filter.segments.where((x) => x.length >= 2).toList();
    var desc = _filter.diagnostics;
    // Korjaus poluille offline-kartoilla, kun reitti selvästi kulkee väylää pitkin (path_snap.dart). Matka pysyy
    // suodattimen mittaamana; vain reittiviiva korjataan.
    if (snapModeFor(sport) != null && segs.isNotEmpty) {
      try {
        final r = snapRoute(segs, await ways(segs), sport);
        segs = r.segments;
        if (r.total > 0) desc = '$desc; polulle korjattu ${(100 * r.snapped / r.total).round()} % pisteistä';
      } catch (_) {}
    }
    return RouteResult(
      started: s,
      seconds: secs,
      distanceKm: (_filter.distance / 10).round() / 100,
      gpx: routeToGpx(segs, name: name, type: sport, desc: desc),
      segments: segs,
    );
  }

  /// Hylkää tallennuksen.
  Future<void> discard() => _close();

  Future<void> _close() async {
    _tick?.cancel();
    _tick = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await source.stop();
      await source.clearSaved();
    } catch (_) {}
    await _clearState();
    state = RecState.idle;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
