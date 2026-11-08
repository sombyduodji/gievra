import 'dart:math' as math;

// GPS-reitin suodatus tallennuksen aikana. Puhdasta Dartia, ei riippuvuuksia: sama koodi toimii livenä
// (piste kerrallaan) ja jälkikäteen (koko reitti). Vaiheet:
//  1. Tarkkuus: puhelimen ilmoittama tarkkuus yli 25 m -> pois; ennen ensimmäistä hyvää paikannusta (≤ 20 m)
//     ei aloiteta.
//  2. Mahdoton nopeus: siirtymä edellisestä hyväksytystä pisteestä nopeammin kuin lajin yläraja (+ mittausvirheen
//     vara) -> pois.
//  3. Piikki: piste, joka käy sivussa ja palaa (A -> B -> C, B kaukana suorasta A–C ja kiertotie paljon pidempi)
//     -> pois. Tämän takia live-näkymä on yhden pisteen jäljessä.
//  4. Kalman-suodin (vakionopeusmalli, kiihtyvyys rajattu lajin mukaan): tasoittaa sik-sakin ja hylkää pisteet,
//     jotka eivät sovi fysikaalisesti mahdolliseen liikkeeseen (ei äkkispurtteja). Jos useampi peräkkäinen piste
//     hylätään ja ne sopivat keskenään yhteen, suodin aloitetaan alusta uudesta paikasta.
//  5. Paikallaanolo: kun nopeus on lähes nolla (liikennevalot), matkaa ei kerry eikä pisteitä tallenneta.
//  6. Katkos (tunneli, alikulku): yli 10 s ilman pisteitä -> uusi osuus. Katkon yli kuljettu matka lasketaan,
//     jos se on lajille uskottava, muuten ei.

/// Puhelimen antama paikannus. [accuracy] = vaakatarkkuus metreinä (Androidissa 68 %:n säde).
class GpsFix {
  final DateTime time;
  final double lat, lon, accuracy;
  const GpsFix(this.time, this.lat, this.lon, this.accuracy);
}

/// Suodatettu reittipiste.
class TrackPoint {
  final DateTime time;
  final double lat, lon;
  const TrackPoint(this.time, this.lat, this.lon);
}

/// Lajin rajat: suurin nopeus (m/s) ja tyypillinen kiihtyvyys (m/s², Kalman-suotimen prosessikohina).
class GpsLimits {
  final double maxSpeed, accel;
  const GpsLimits(this.maxSpeed, this.accel);

  static const walk = GpsLimits(12 / 3.6, 0.3);
  static const run = GpsLimits(30 / 3.6, 0.6);
  static const ski = GpsLimits(50 / 3.6, 1.0);
  static const paddle = GpsLimits(20 / 3.6, 0.4);
  static const cycle = GpsLimits(70 / 3.6, 1.0);

  /// Rajat lajin nimen mukaan (sports.dart). Tuntematon laji: juoksun rajat.
  static GpsLimits forSport(String? sport) => switch (sport) {
    'Kävely' || 'Sauvakävely' || 'Retkeily' || 'Lumikenkäily' || 'Uinti' => walk,
    'Pyöräily' => cycle,
    'Hiihto' || 'Luistelu' => ski,
    'Soutu' || 'Melonta' => paddle,
    _ => run,
  };
}

/// Etäisyys metreinä (haversine).
double geoDistance(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371008.8;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = p2 - p1, dl = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// Paikallinen tasokoordinaatisto (metrit) ensimmäisen pisteen ympärillä; riittävän tarkka kymmenien km alueella.
class _Plane {
  final double lat0, lon0, kx, ky;
  _Plane(this.lat0, this.lon0) : kx = 111320 * math.cos(lat0 * math.pi / 180), ky = 110574;
  (double, double) xy(double lat, double lon) => ((lon - lon0) * kx, (lat - lat0) * ky);
  (double, double) latLon(double x, double y) => (lat0 + y / ky, lon0 + x / kx);
}

class _Obs {
  final DateTime t;
  final double x, y, acc;
  const _Obs(this.t, this.x, this.y, this.acc);
  double dist(_Obs o) => math.sqrt(math.pow(x - o.x, 2) + math.pow(y - o.y, 2));
  double secs(_Obs o) => t.difference(o.t).inMicroseconds / 1e6;
}

/// Yhden akselin vakionopeus-Kalman: tila (paikka, nopeus), kovarianssi 2×2.
class _Axis {
  double p, v;
  double p00, p01, p11;
  _Axis(this.p, double var0) : v = 0, p00 = var0, p01 = 0, p11 = 4;

  void predict(double dt, double q) {
    p += v * dt;
    final dt2 = dt * dt, dt3 = dt2 * dt, dt4 = dt3 * dt;
    final n00 = p00 + 2 * dt * p01 + dt2 * p11 + q * dt4 / 4;
    final n01 = p01 + dt * p11 + q * dt3 / 2;
    final n11 = p11 + q * dt2;
    p00 = n00;
    p01 = n01;
    p11 = n11;
  }

  /// Innovaation neliö jaettuna varianssilla (Mahalanobis² tällä akselilla).
  double gate(double z, double r) => math.pow(z - p, 2) / (p00 + r);

  void update(double z, double r) {
    final s = p00 + r;
    final k0 = p00 / s, k1 = p01 / s;
    final y = z - p;
    p += k0 * y;
    v += k1 * y;
    final n00 = (1 - k0) * p00;
    final n01 = (1 - k0) * p01;
    final n11 = p11 - k1 * p01;
    p00 = n00;
    p01 = n01;
    p11 = n11;
  }
}

class GpsFilter {
  final GpsLimits limits;

  /// Hylkäysten syyt (testejä ja vianetsintää varten).
  final rejected = <String, int>{'accuracy': 0, 'speed': 0, 'spike': 0, 'gate': 0};

  /// Suodatettu reitti osuuksina (katkos aloittaa uuden osuuden).
  final segments = <List<TrackPoint>>[];

  /// Kuljettu matka metreinä (osuudet + uskottavat katkot).
  double distance = 0;

  GpsFilter(this.limits);

  static const maxAccuracy = 25.0, startAccuracy = 20.0, gapSeconds = 10.0;

  /// Katkon jälkeen viiva jatkuu samana osuutena, jos sijainti on siirtynyt enintään näin paljon (m).
  static const gapJoinMeters = 50.0;

  /// Vianetsintään: vastaanotetut paikannukset ja pisin väli kahden paikannuksen välillä (s).
  int received = 0;
  double maxFixGapSec = 0;
  DateTime? _lastFixTime;

  /// Pienin tallennettava siirtymä (m): jäljelle jäävä värinä ei kerrytä matkaa.
  static const minStep = 5.0;

  /// Tätä hitaampi (m/s) on paikallaanoloa: matkaa ei kerry.
  static const minSpeed = 0.15;

  /// Matkan mittausväli (m), ks. [_measure].
  static const distStep = 10.0;

  /// Paikallaanolo: alle 5 m 20 sekunnissa (hidaskin kävely etenee noin 12 m).
  static const stopWindow = 20.0, stopDistance = 5.0;
  static const _gate = 16.0; // Mahalanobis² (2 vapausastetta) ≈ 99,97 %
  static const _resetAfter = 4;

  _Plane? _plane;
  _Obs? _lastAccepted; // nopeustarkistuksen vertailukohta
  _Obs? _a, _b; // piikkitarkistus: A hyväksytty, B odottaa seuraavaa
  _Axis? _kx, _ky;
  DateTime? _kt;
  final _pendingRejects = <_Obs>[];
  (double, double)? _lastOut; // viimeisin tallennettu piste (x, y)
  DateTime? _lastOutT;
  bool _newSegment = true;
  (double, double)? _mAnchor;
  double _mPending = 0;
  final _window = <(DateTime, double, double)>[];

  /// Kaikki pisteet yhtenä listana.
  List<TrackPoint> get points => [for (final s in segments) ...s];

  /// Lisää paikannus. Palauttaa nyt valmistuneet reittipisteet (live-näkymää varten).
  List<TrackPoint> add(GpsFix f) {
    received++;
    final lt = _lastFixTime;
    if (lt != null) {
      final g = f.time.difference(lt).inMilliseconds / 1000;
      if (g > maxFixGapSec) maxFixGapSec = g;
    }
    _lastFixTime = f.time;
    if (f.accuracy > maxAccuracy || (_plane == null && f.accuracy > startAccuracy)) {
      rejected['accuracy'] = rejected['accuracy']! + 1;
      return const [];
    }
    final plane = _plane ??= _Plane(f.lat, f.lon);
    final (x, y) = plane.xy(f.lat, f.lon);
    final o = _Obs(f.time, x, y, math.max(3, f.accuracy));

    // 2. Mahdoton nopeus edelliseen hyväksyttyyn nähden (mittausvirheen vara mukana).
    final last = _lastAccepted;
    if (last != null) {
      final dt = o.secs(last);
      if (dt <= 0) return const [];
      final allowed = _allowed(o, last, dt);
      if (o.dist(last) > allowed && dt < 30) {
        rejected['speed'] = rejected['speed']! + 1;
        return _maybeReset(o);
      }
    }
    _lastAccepted = o;

    // 3. Piikki: B pidetään odottamassa, kunnes C tulee.
    if (_a == null) {
      _a = o;
      return _toKalman(o);
    }
    if (_b == null) {
      _b = o;
      return const [];
    }
    final a = _a!, b = _b!, c = o;
    final out = <TrackPoint>[];
    if (_isSpike(a, b, c)) {
      rejected['spike'] = rejected['spike']! + 1;
      _lastAccepted = c.dist(a) <= _allowed(c, a, c.secs(a)) ? c : a;
    } else {
      out.addAll(_toKalman(b));
      _a = b;
    }
    _b = c;
    return out;
  }

  /// Loppu: käsittele odottava piste.
  List<TrackPoint> finish() {
    final b = _b;
    _b = null;
    final out = b == null ? const <TrackPoint>[] : _toKalman(b, last: true);
    _flushMeasure();
    return out;
  }

  /// Yhteenveto GPX-tiedostoon vianetsintää varten (suomeksi, ei käännetä).
  String get diagnostics =>
      'Gievra: $received paikannusta, hylätty: tarkkuus ${rejected['accuracy']}, nopeus ${rejected['speed']}, '
      'piikki ${rejected['spike']}, suodin ${rejected['gate']}; pisin väli paikannusten välillä '
      '${maxFixGapSec.round()} s; osuuksia ${segments.length}';

  /// Tauko: nykyinen osuus päättyy, ja seuraava paikannus aloittaa uuden osuuden. Tauon aikana kuljettua
  /// matkaa ei lasketa (toisin kuin GPS-katkossa).
  void breakSegment() {
    final b = _b;
    _b = null;
    if (b != null) _toKalman(b, last: true);
    _flushMeasure();
    _kx = null;
    _ky = null;
    _kt = null;
    _a = null;
    _lastAccepted = null;
    _pendingRejects.clear();
    _newSegment = true;
  }

  /// Osuuden loppu: viimeinen vajaa mittausväli mukaan, jos sitä on kertynyt liikkuessa.
  void _flushMeasure() {
    if (_mPending >= minStep) distance += _mPending;
    _mPending = 0;
    _mAnchor = null;
    _window.clear();
  }

  /// Suurin uskottava siirtymä kahden paikannuksen välillä: lajin huippunopeus + mittausvirheen vara (2σ).
  double _allowed(_Obs a, _Obs b, double dt) =>
      limits.maxSpeed * dt + 2 * math.sqrt(a.acc * a.acc + b.acc * b.acc) / 1.5;

  bool _isSpike(_Obs a, _Obs b, _Obs c) {
    final ac = a.dist(c);
    final detour = a.dist(b) + b.dist(c);
    // B:n etäisyys janasta A–C
    final dx = c.x - a.x, dy = c.y - a.y;
    final len2 = dx * dx + dy * dy;
    double off;
    if (len2 < 1e-6) {
      off = a.dist(b);
    } else {
      final t = (((b.x - a.x) * dx + (b.y - a.y) * dy) / len2).clamp(0.0, 1.0);
      off = math.sqrt(math.pow(a.x + t * dx - b.x, 2) + math.pow(a.y + t * dy - b.y, 2));
    }
    final minOff = math.max(15.0, 1.5 * b.acc);
    return off > minOff && detour > 2 * ac + minOff;
  }

  /// Liian moni peräkkäinen hylkäys, jotka sopivat keskenään: oikea siirtymä (esim. huono alku), aloitetaan
  /// uudesta paikasta.
  List<TrackPoint> _maybeReset(_Obs o) {
    _pendingRejects.add(o);
    if (_pendingRejects.length < _resetAfter) return const [];
    for (var i = 1; i < _pendingRejects.length; i++) {
      final p = _pendingRejects[i - 1], q = _pendingRejects[i];
      if (q.dist(p) > _allowed(q, p, q.secs(p))) {
        _pendingRejects.removeRange(0, i);
        return const [];
      }
    }
    final keep = List.of(_pendingRejects);
    _pendingRejects.clear();
    _kx = null;
    _a = null;
    _b = null;
    _lastAccepted = keep.last;
    _newSegment = true;
    final out = <TrackPoint>[];
    for (final p in keep) {
      out.addAll(_toKalman(p));
    }
    _a = keep.last;
    return out;
  }

  List<TrackPoint> _toKalman(_Obs o, {bool last = false}) {
    _pendingRejects.clear();
    final r = math.pow(o.acc / 1.5, 2).toDouble();
    final kt = _kt;
    final dt = kt == null ? 0.0 : o.t.difference(kt).inMicroseconds / 1e6;
    if (_kx == null || dt > gapSeconds) {
      if (_kx != null && dt > gapSeconds) _gap(o, dt);
      _kx = _Axis(o.x, r);
      _ky = _Axis(o.y, r);
      _flushMeasure();
      _mAnchor = (o.x, o.y);
      _kt = o.t;
      return _emit(o.t, o.x, o.y, force: true);
    }
    final q = limits.accel * limits.accel;
    _kx!.predict(dt, q);
    _ky!.predict(dt, q);
    _kt = o.t;
    final d2 = _kx!.gate(o.x, r) + _ky!.gate(o.y, r);
    if (d2 > _gate) {
      rejected['gate'] = rejected['gate']! + 1;
      return const [];
    }
    _kx!.update(o.x, r);
    _ky!.update(o.y, r);
    // Matka suodatetusta nopeudesta (tasaisempi kuin värisevien pisteiden välimatkat); paikallaan ei kerry.
    _measure(o.t, _kx!.p, _ky!.p);
    return _emit(o.t, _kx!.p, _ky!.p, force: last);
  }

  /// Matka mitataan suodatetuista paikoista vähintään [distStep] metrin välein: jäljelle jäävä 1–2 m värinä ei
  /// juuri vaikuta, eikä paikallaan ajelehtiminen kerrytä matkaa.
  void _measure(DateTime t, double x, double y) {
    // Paikallaanolo: suodatettu paikka ei ole edennyt [stopDistance] metriä [stopWindow] sekunnissa
    // (liikennevalot, tauko). Ankkuri seuraa ajelehtimista, mutta matkaa ei kerry.
    _window.add((t, x, y));
    while (t.difference(_window.first.$1).inMicroseconds / 1e6 > stopWindow) {
      _window.removeAt(0);
    }
    final w0 = _window.first;
    final still =
        t.difference(w0.$1).inMicroseconds / 1e6 >= stopWindow - 1 &&
        math.sqrt(math.pow(x - w0.$2, 2) + math.pow(y - w0.$3, 2)) < stopDistance;
    final m = _mAnchor;
    if (m == null || still) {
      _mAnchor = (x, y);
      _mPending = 0;
      return;
    }
    final d = math.sqrt(math.pow(x - m.$1, 2) + math.pow(y - m.$2, 2));
    _mPending = d;
    if (d >= distStep) {
      distance += d;
      _mAnchor = (x, y);
      _mPending = 0;
    }
  }

  void _gap(_Obs o, double dt) {
    final lo = _lastOut;
    if (lo == null) return;
    final d = math.sqrt(math.pow(o.x - lo.$1, 2) + math.pow(o.y - lo.$2, 2));
    // Katkon yli kuljettu matka lasketaan, jos se on lajille uskottava (enintään 80 % huippunopeudesta).
    final plausible = d <= 0.8 * limits.maxSpeed * dt;
    if (plausible) distance += d;
    // Lyhyt katko (puhelin ei lähettänyt paikannuksia, mutta sijainti tuskin muuttui): viiva jatkuu yhtenä.
    // Uusi osuus vain, jos siirtymä on iso tai epäuskottava (esim. tunneli tai GPS-hyppy).
    if (!plausible || d > gapJoinMeters) _newSegment = true;
  }

  /// Tallenna piste, jos on liikuttu (paikallaanolon ajelehtiminen ei kerrytä matkaa).
  List<TrackPoint> _emit(DateTime t, double x, double y, {bool force = false}) {
    final lo = _lastOut;
    final speed = math.sqrt(math.pow(_kx?.v ?? 0, 2) + math.pow(_ky?.v ?? 0, 2));
    if (lo != null && !_newSegment) {
      final d = math.sqrt(math.pow(x - lo.$1, 2) + math.pow(y - lo.$2, 2));
      final moving = speed >= minSpeed && d >= minStep;
      if (!moving && !(force && d >= minStep)) return const [];
    }
    final (lat, lon) = _plane!.latLon(x, y);
    final p = TrackPoint(t, lat, lon);
    if (_newSegment || segments.isEmpty) {
      segments.add([]);
      _newSegment = false;
    }
    segments.last.add(p);
    _lastOut = (x, y);
    _lastOutT = t;
    return [p];
  }

  /// Viimeisimmän tallennetun pisteen aika (live-näkymän "liikkeellä"-tila).
  DateTime? get lastPointTime => _lastOutT;
}
