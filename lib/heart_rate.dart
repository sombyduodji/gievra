import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'hr_calc.dart';
import 'l10n.dart';
import 'models.dart';
import 'sports.dart';

// Sykevyö Bluetoothilla (Polar H10, Verity Sense, Garmin HRM ym.; standardi Heart Rate Service).
// Android-puoli: android/.../HeartRateBle.kt. Vyö muistetaan vain tällä puhelimella (SharedPreferences), koska
// Bluetooth-osoite on laitekohtainen. Treeni avaa "istunnon" (begin), joka yhdistää vyöhön ja kerää sykkeet;
// lopetus (end) palauttaa keskisykkeen ja maksimin treeniin. Kun istuntoja ei ole, yhteys katkaistaan (akku).

/// Sykevyön tapahtumien lähde (Android tai testien keksitty vyö).
abstract class HrSource {
  Stream<Map<String, Object?>> get events;
  Future<bool> supported();
  Future<bool> enabled();
  Future<void> scan(int seconds);
  Future<void> stopScan();
  Future<void> connect(String address);
  Future<void> disconnect();
  Future<void> requestEnable();

  /// Android 11 ja vanhemmat: Bluetooth-haku vaatii sijaintiluvan (uusia Bluetooth-lupia ei ole).
  Future<bool> needsLocation();

  /// Onko haun ja yhteyden luvat oikeasti annettu (oma tarkistus Kotlinissa, ei lupakirjaston tieto).
  Future<bool> permitted();
}

class AndroidHrSource implements HrSource {
  static const _ctl = MethodChannel('fi.somby.gievra/hr');
  static const _ev = EventChannel('fi.somby.gievra/hr/events');

  @override
  Stream<Map<String, Object?>> get events =>
      _ev.receiveBroadcastStream().map((e) => Map<String, Object?>.from(e as Map));
  @override
  Future<bool> supported() async => await _ctl.invokeMethod<bool>('supported') ?? false;
  @override
  Future<bool> enabled() async => await _ctl.invokeMethod<bool>('enabled') ?? false;
  @override
  Future<void> scan(int seconds) => _ctl.invokeMethod('scan', {'seconds': seconds});
  @override
  Future<void> stopScan() => _ctl.invokeMethod('stopScan');
  @override
  Future<void> connect(String address) => _ctl.invokeMethod('connect', {'address': address});
  @override
  Future<void> disconnect() => _ctl.invokeMethod('disconnect');
  @override
  Future<void> requestEnable() => _ctl.invokeMethod('enable');
  @override
  Future<bool> needsLocation() async => await _ctl.invokeMethod<bool>('needsLocation') ?? false;
  @override
  Future<bool> permitted() async => await _ctl.invokeMethod<bool>('permitted') ?? false;
}

enum HrState { none, connecting, connected }

/// Testejä varten: valitun vyön tiedoston kansio (oletus: sovelluksen oma kansio).
Directory? hrDeviceDirOverride;

/// Testejä varten: vyö muistiin tiedoston sijaan (widget-testeissä tiedostotoiminnot eivät valmistu).
Map<String, String>? hrDeviceMemory;

/// Haussa löytynyt vyö.
class HrDevice {
  final String address, name;
  final int rssi;
  const HrDevice(this.address, this.name, this.rssi);
}

/// Treenin sykkeet: keskisyke, maksimi ja käyrä (5 s välein).
class HrStats {
  final int avg, max, samples;
  final HrSeries? series;
  const HrStats(this.avg, this.max, this.samples, [this.series]);
}

/// Kalorilaskennan tiedot asetuksista: syntymävuosi, sukupuoli, pituus ja viimeisin paino. null, jos jokin puuttuu.
HrProfile? hrProfile() {
  final y = settings.birthYear, sex = settings.sex, h = settings.body.heightCm;
  final kg = settings.body.sorted.lastOrNull?.$2;
  if (y == null || sex == null || h == null || kg == null) return null;
  return HrProfile(
    birthYear: y,
    male: sex == 'mies',
    heightCm: h,
    weightKg: kg,
    adjustPct: settings.kcalAdjustPct,
    maxHrOverride: settings.maxHr,
  );
}

/// Sykevyön tiedot treeniin: käyrä, keskisyke ja maksimi sekä kalorit (sali: Compendiumin MET sykkeen mukaan,
/// kestävyys: Keytel 2005, ks. hr_calc.dart). Käsin kirjattuja ei korvata. Sykevyö voittaa kellon tiedot, koska
/// se mittaa juuri tämän treenin rinnasta.
void applyHeartRate(Workout w, HrStats s) {
  final series = s.series;
  if (series != null) w.hrSeries = series;
  if (w.hrSource != 'käsin') {
    w.hrAvg = s.avg;
    w.hrMax = s.max;
    w.hrSource = 'sykevyö';
  }
  final p = hrProfile();
  if (p == null || series == null || w.kcalSource == 'käsin') return;
  final gym = w.activity == null;
  final minutes = w.durationSec == null ? series.length.inMinutes : (w.durationSec! / 60).round();
  // Kävely tai juoksu, jonka sykettä on alle puolelta ajasta (vyö katkesi, puhelin taskussa): matkasta ja ajasta
  // (kaverin kävely 14.11.: syke 100 s 68 minuutista, kalorit sykkeestä vain 7).
  if (_lowCoverageWalk(w, series)) {
    w.kcal = p.kcalFromSpeed(run: isRun(w.activity), km: w.distanceKm!, seconds: w.durationSec!);
    w.kcalSource = 'nopeus';
    return;
  }
  w.kcal = gym ? p.kcalGym(series, minutes) : p.kcalEnduranceFor(series, w.durationSec);
  w.kcalSource = 'syke';
}

/// Kävely tai juoksu (askellaji, matka tiedossa), jonka sykettä on alle puolelta kestosta.
bool _lowCoverageWalk(Workout w, HrSeries series) {
  final dur = w.durationSec;
  return w.activity != null &&
      (sportOf(w.activity)?.steps ?? false) &&
      (w.distanceKm ?? 0) > 0 &&
      dur != null &&
      series.coverage(dur) < .5;
}

/// Vanha tallennus (ennen 0.6.6): sykkeestä lasketut kalorit kävelylle tai juoksulle, jonka sykettä on alle puolelta
/// ajasta, korjataan luettaessa matkasta ja ajasta kuten tallennettaessa nykyään (kaverin kävely 14.11.: 7 kcal
/// 68 minuutista -> noin 370). Vain muistissa: tiedosto korjautuu, kun treeni seuraavan kerran tallennetaan.
/// Käsin kirjattuja ja kellon kaloreita ei muuteta. Palauttaa true, jos muuttui.
bool repairLowCoverageKcal(Workout w, HrProfile? p) {
  final series = w.hrSeries;
  if (p == null || series == null || w.kcalSource != 'syke' || !_lowCoverageWalk(w, series)) return false;
  w.kcal = p.kcalFromSpeed(run: isRun(w.activity), km: w.distanceKm!, seconds: w.durationSec!);
  w.kcalSource = 'nopeus';
  return true;
}

class HeartRateMonitor extends ChangeNotifier {
  HeartRateMonitor({DateTime Function()? now}) : now = now ?? DateTime.now;

  HrSource? _source;
  final DateTime Function() now;

  /// Testejä varten: oma lähde (ennen ensimmäistä käyttöä).
  set source(HrSource s) {
    _sub?.cancel();
    _sub = null;
    _source = s;
  }

  HrSource get _src => _source ??= AndroidHrSource();
  StreamSubscription<Map<String, Object?>>? _sub;

  /// Vain Androidilla (ei verkkoversiossa eikä testeissä ilman omaa lähdettä).
  bool get available => _source != null || (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  // Valittu vyö (tällä puhelimella).
  String? address, name;
  HrState state = HrState.none;
  int? _bpm;
  DateTime? _bpmAt;
  int? battery;

  /// Ihokontakti: false = vyö kertoo, ettei se tunne sykettä (kuiva tai löysä vyö).
  bool? contact;

  /// Viimeiset 3 min lukemia (näkymän minikäyrä ja suunta).
  final recent = <(DateTime, int)>[];

  /// Yhteys oli jo saanut sykettä ja katkesi (vyö kaukana tai akku): yhdistetään uudelleen.
  bool lost = false;
  Timer? _stale;

  /// Vyön akku vähissä (alle tämän %): varoitus treenin aikana.
  static const lowBattery = 15;
  bool get batteryLow => battery != null && battery! <= lowBattery;

  // Piikkisuodatin: syke muuttuu fysiologisesti vain muutamia lyöntejä sekunnissa, joten yli 25 lyönnin hyppy
  // muutamassa sekunnissa on lähes aina vyön häiriö (huono kontakti, staattinen sähkö, tuplalyönti). Hyppy
  // hyväksytään vasta, kun uusi taso pysyy noin 3 s (oikea muutos, esim. spurtti); yksittäinen piikki hylätään.
  // Raja-arvot ovat Gievran valintoja (ei julkaistu standardi); arvot 30–230 ulkopuolelta hylätään aina.
  static const _jump = 25, _holdSec = 3;
  final _held = <(DateTime, int)>[];

  int? _filter(int v, DateTime t) {
    if (v < 30 || v > 230) return null;
    final last = _bpm, lastAt = _bpmAt;
    final near = last != null && (v - last).abs() <= _jump;
    // Ei aiempaa lukemaa (uusi yhteys) tai se on vanha: ei vertailukohtaa, hyväksytään.
    final stale = last == null || lastAt == null || t.difference(lastAt).inSeconds > 10;
    if (near || stale) {
      _held.clear();
      return v;
    }
    // Hyppy: kerätään ehdokkaita; hyväksytään, kun ne pysyvät lähellä toisiaan riittävän kauan.
    if (_held.isNotEmpty && (v - _held.last.$2).abs() > _jump) _held.clear();
    _held.add((t, v));
    if (t.difference(_held.first.$1).inSeconds >= _holdSec) {
      _held.clear();
      return v;
    }
    return null;
  }

  /// Sykkeen muutos viimeisen minuutin aikana (lyöntiä/min), null jos lukemia liian vähän.
  int? get trend {
    if (recent.length < 2) return null;
    final last = recent.last;
    final from = last.$1.subtract(const Duration(seconds: 60));
    final old = recent.firstWhere((e) => !e.$1.isBefore(from), orElse: () => recent.first);
    if (last.$1.difference(old.$1).inSeconds < 20) return null;
    return last.$2 - old.$2;
  }

  /// Palautunut seuraavaan sarjaan, kun syke on tämän alle (asetuksista, oletus 60 % maksimisykkeestä).
  int? recoveryBpm(DateTime d) {
    final p = hrProfile();
    if (p == null) return null;
    return (p.maxHr(d) * settings.hrRecoveryPct / 100).round();
  }

  // Haku.
  bool scanning = false;

  /// Viimeisin haku päättyi löytämättä yhtään vyötä (näytetään ohje, ettei haku vain katoa näkyvistä).
  bool scanEmpty = false;
  final Map<String, HrDevice> found = {};
  String? error;

  /// Viimeisin syke, jos se on tuore (alle 5 s): muuten vyö ei ole lähettänyt (kantama, kontakti).
  int? get bpm => _bpm != null && _bpmAt != null && now().difference(_bpmAt!).inSeconds < 5 ? _bpm : null;

  /// Valittu vyö (osoite ja nimi) tiedostossa laite/sykevyo.txt sovelluksen omassa kansiossa. Kansio on rajattu
  /// Androidin varmuuskopion ulkopuolelle (backup_rules.xml): vyön osoite kuuluu tähän puhelimeen. Ennen 0.6.6
  /// osoite oli SharedPreferencesissä, joka varmuuskopioidaan asetusten mukana; se siirretään tänne.
  Future<File> _deviceFile() async =>
      File(p.join((hrDeviceDirOverride ?? await getApplicationSupportDirectory()).path, 'laite', 'sykevyo.txt'));

  Future<void> _saveDevice() async {
    final mem = hrDeviceMemory;
    if (mem != null) {
      mem.clear();
      if (address != null) mem.addAll({'address': address!, 'name': name ?? ''});
      return;
    }
    try {
      final f = await _deviceFile();
      if (address == null) {
        if (await f.exists()) await f.delete();
        return;
      }
      await f.parent.create(recursive: true);
      await f.writeAsString('$address\n${name ?? ''}\n', flush: true);
    } catch (_) {
      // Ei tallennusta (testi ilman kansiota): valinta pysyy tämän käynnistyksen ajan.
    }
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final mem = hrDeviceMemory;
    if (mem != null) {
      address = mem['address'] ?? sp.getString('hrAddress');
      name = mem['address'] != null ? (mem['name']!.isEmpty ? null : mem['name']) : sp.getString('hrName');
      await _saveDevice();
      await sp.remove('hrAddress');
      await sp.remove('hrName');
      notifyListeners();
      return;
    }
    var migrated = false; // vanha SharedPreferences-arvo poistetaan vasta, kun tiedosto on varmasti olemassa
    try {
      final f = await _deviceFile();
      if (await f.exists()) {
        final l = (await f.readAsString()).split('\n');
        address = l.first.trim().isEmpty ? null : l.first.trim();
        name = l.length > 1 && l[1].trim().isNotEmpty ? l[1].trim() : null;
        migrated = true;
      } else if (sp.getString('hrAddress') != null) {
        address = sp.getString('hrAddress');
        name = sp.getString('hrName');
        await _saveDevice();
        migrated = await f.exists();
      } else {
        migrated = true;
      }
    } catch (_) {}
    if (migrated) {
      await sp.remove('hrAddress');
      await sp.remove('hrName');
    }
    notifyListeners();
  }

  void _listen() {
    _sub ??= _src.events.listen(_onEvent, onError: (_) {});
  }

  void _onEvent(Map<String, Object?> e) {
    switch (e['type']) {
      case 'device':
        final a = e['address'] as String;
        found[a] = HrDevice(a, (e['name'] as String?) ?? a, (e['rssi'] as num?)?.toInt() ?? 0);
      case 'scanDone':
        scanning = false;
        scanEmpty = found.isEmpty;
      case 'state':
        final was = state;
        state = switch (e['state']) {
          'connected' => HrState.connected,
          'connecting' => HrState.connecting,
          _ => HrState.none,
        };
        // Yhdistetty vyö menetti yhteyden (natiivi yrittää uudelleen): näytetään selvästi.
        if (was == HrState.connected && state == HrState.connecting) lost = true;
        if (state == HrState.none) lost = false;
      case 'hr':
        final raw = (e['bpm'] as num).toInt();
        contact = e['contact'] as bool?;
        state = HrState.connected;
        lost = false;
        final v = _filter(raw, now());
        if (v == null) break; // epäilyttävä piikki: odotetaan, pysyykö taso
        _bpm = v;
        _bpmAt = now();
        // Jos seuraavaa lukemaa ei tule (akku loppui, vyö kaukana), näkymät päivittyvät "ei sykettä" -tilaan.
        _stale?.cancel();
        _stale = recording ? Timer(const Duration(milliseconds: 5100), notifyListeners) : null;
        recent.add((_bpmAt!, v));
        final cut = _bpmAt!.subtract(const Duration(minutes: 3));
        while (recent.isNotEmpty && recent.first.$1.isBefore(cut)) {
          recent.removeAt(0);
        }
        if (contact != false) {
          for (final s in _sessions.values) {
            if (s.active) s.add(v, now());
          }
        }
      case 'battery':
        battery = (e['percent'] as num?)?.toInt();
      case 'error':
        error = e['error'] as String?;
        scanning = false;
    }
    notifyListeners();
  }

  /// Android 11 ja vanhemmat: haku tarvitsee sijaintiluvan (virheteksti nimeää sen, jotta asetuksista löytyy oikea).
  bool locationPermission = false;

  /// Bluetooth-luvat: Android 12+ haku ja yhteys (ilman sijaintia); Android 11 ja vanhemmat sijainti, koska haku
  /// ei muuten palauta yhtään laitetta (permission_handler näyttää uudet luvat siellä "myönnettyinä").
  Future<bool> ensurePermissions() async {
    locationPermission = await _src.needsLocation();
    // Oma tarkistus ensin ja lopuksi: permission_handler ilmoitti Android 17:ssä luvat myönnetyiksi, vaikka
    // hakulupa oli kielletty. Kirjastoa käytetään vain kysymiseen.
    if (await _src.permitted()) return true;
    // Kysytään vain oikealla laitteella (testien keksityllä vyöllä ei ole lupaikkunaa). Huom.: [_src] luo
    // Android-lähteen ensimmäisellä käytöllä, joten _source ei ole tässä enää null.
    if (_src is AndroidHrSource) {
      if (locationPermission) {
        await Permission.locationWhenInUse.request();
      } else {
        // Yhdessä: Android näyttää ne yhtenä "Lähellä olevat laitteet" -kysymyksenä (erikseen kysyttynä
        // kieltäminen toi saman kysymyksen heti uudelleen).
        await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
      }
    }
    return _src.permitted();
  }

  /// Etsii vöitä 15 s. Palauttaa false, jos Bluetooth on pois tai lupaa ei annettu.
  Future<bool> scan() async {
    error = null;
    scanEmpty = false;
    if (!await ensurePermissions()) {
      error = 'permission';
      notifyListeners();
      return false;
    }
    if (!await _src.enabled()) {
      error = 'off';
      notifyListeners();
      await _src.requestEnable();
      return false;
    }
    _listen();
    found.clear();
    scanning = true;
    notifyListeners();
    await _src.scan(15);
    return true;
  }

  Future<void> stopScan() async {
    if (!scanning) return;
    scanning = false;
    await _src.stopScan(); // dispose-metodista kutsuttaessa ilmoitus vasta tämän jälkeen
    notifyListeners();
  }

  /// Valitsee vyön tälle puhelimelle ja yhdistää heti (näkyy syke).
  Future<void> choose(HrDevice d) async {
    await stopScan();
    address = d.address;
    name = d.name;
    await _saveDevice();
    await connect();
  }

  /// Unohtaa vyön (yhteys poikki).
  Future<void> forget() async {
    await disconnect();
    address = null;
    name = null;
    battery = null;
    await _saveDevice();
    notifyListeners();
  }

  Future<void> connect() async {
    final a = address;
    if (a == null || !available) return;
    if (!await ensurePermissions()) return;
    _listen();
    if (state == HrState.none) {
      state = HrState.connecting;
      notifyListeners();
    }
    await _src.connect(a);
  }

  Future<void> disconnect() async {
    if (!available) return;
    await _src.disconnect();
    state = HrState.none;
    _bpm = null;
    _bpmAt = null;
    _held.clear();
    notifyListeners();
  }

  // Treenien istunnot: sama treeni voi avata istunnon useasti (idempotentti). Istunto voi olla tauolla (treenistä
  // poistuttu kesken), jolloin sykkeet säilyvät mutta yhteys katkaistaan, jos muita aktiivisia ei ole.
  final Map<String, _Session> _sessions = {};
  final Map<String, HrStats?> _ended = {};

  bool get recording => _sessions.values.any((s) => s.active);

  /// Viimeksi aloitettu tai jatkettu treeni (näkymät, jotka eivät tunne treenin avainta, esim. sarjan kirjaus).
  String? currentKey;

  /// Treeni alkaa tai jatkuu: yhdistää vyöhön (jos valittu) ja kerää sykkeitä.
  Future<void> begin(String key) async {
    if (address == null) return;
    _sessions.putIfAbsent(key, _Session.new).active = true;
    currentKey = key;
    notifyListeners();
    await connect();
  }

  /// Treenistä poistuttiin kesken: sykkeet säilyvät, yhteys katkeaa, jos mikään treeni ei ole auki.
  Future<void> pause(String key) async {
    final s = _sessions[key];
    if (s == null || !s.active) return;
    s.active = false;
    // Kutsutaan näkymän dispose-metodista: ilmoitus vasta, kun puu ei ole lukittu.
    await Future<void>.delayed(Duration.zero);
    if (!recording) {
      _stale?.cancel();
      _stale = null;
    }
    if (!recording && state != HrState.none) await disconnect();
    notifyListeners();
  }

  /// Treeni päättyy: keskisyke ja maksimi (null, jos sykettä ei saatu). Viimeisen jälkeen yhteys katkaistaan.
  Future<HrStats?> end(String key) async {
    final s = _sessions.remove(key);
    if (!recording) {
      _stale?.cancel(); // ei enää treeniä, jonka näkymiä päivittää
      _stale = null;
    }
    if (s == null) return null; // istuntoa ei ollut (ei vyötä tai jo päätetty)
    final stats = s.stats;
    _ended[key] = stats;
    // Voidaan kutsua dispose-metodista: ilmoitus vasta, kun puu ei ole lukittu.
    await Future<void>.delayed(Duration.zero);
    if (!recording && state != HrState.none) await disconnect();
    notifyListeners();
    return stats;
  }

  /// Toisen näkymän päättämän istunnon tulos (esim. GPS-tallennus → liikunta), kerran.
  HrStats? take(String key) => _ended.remove(key);

  /// Istunnon tilanne kesken treenin.
  HrStats? peek(String key) => _sessions[key]?.stats;
}

class _Session {
  bool active = true;
  final samples = <(DateTime, int)>[];
  int _sum = 0, _n = 0, _max = 0;
  void add(int bpm, DateTime t) {
    samples.add((t, bpm));
    _sum += bpm;
    _n++;
    if (bpm > _max) _max = bpm;
  }

  HrStats? get stats => _n == 0 ? null : HrStats((_sum / _n).round(), _max, _n, HrSeries.fromSamples(samples));
}

final hr = HeartRateMonitor();

/// Tilarivi, kun lukemaa ei ole (null = syke näkyy normaalisti).
String? hrStatusText() {
  if (hr.contact == false) return t('Ei ihokontaktia: kostuta elektrodit');
  if (hr.lost) return t('Yhteys katkesi, yhdistetään…');
  if (hr.state == HrState.connecting) return t('Yhdistetään sykevyöhön…');
  if (hr.bpm == null) return t('Odotetaan sykettä…');
  return null;
}
