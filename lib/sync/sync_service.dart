import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../models.dart';
import 'drive_remote.dart';
import 'sync_engine.dart';

// Valinnainen Google Drive -synkronointi. Asetukset ovat laitekohtaisia (SharedPreferences),
// eivät asetukset.md:ssä, koska jokainen laite päättää itse, synkronoiko se.
//  - jokainen tallennus lähetetään muutaman sekunnin viiveellä (treeni valmis, muokkaus, asetukset, ohjelma)
//  - käynnistyksessä (valinnainen) tarkistetaan PC:n tai toisen puhelimen muutokset viimeisiltä N päivältä
//  - ilman verkkoa muutokset jäävät jonoon ja lähtevät seuraavalla kerralla

class SyncService extends ChangeNotifier {
  SharedPreferences? _p;
  bool enabled = false;
  bool onStartup = true;
  int days = 30; // 0 = kaikki
  String? email;
  DateTime? lastSync;
  String? status;
  bool busy = false;
  final Set<String> _pending = {};
  Map<String, SyncEntry> _manifest = {};
  Timer? _debounce;
  bool _rerun = false;
  String? _token;

  /// Kirjautuminen on erillinen osa, jotta julkaisu ei sisällä Googlen suljettuja kirjastoja ennen kuin
  /// synkronointi julkaistaan. null = ei kirjautumista tässä käännöksessä.
  DriveAuth? auth;

  bool get configured => googleWebClientId != null && auth != null;

  Future<void> load() async {
    final sp = _p = await SharedPreferences.getInstance();
    enabled = sp.getBool('syncEnabled') ?? false;
    onStartup = sp.getBool('syncOnStartup') ?? true;
    days = sp.getInt('syncDays') ?? 30;
    email = sp.getString('syncEmail');
    lastSync = DateTime.tryParse(sp.getString('syncLast') ?? '');
    status = sp.getString('syncStatus');
    _pending.addAll(sp.getStringList('syncPending') ?? const []);
    try {
      final j = jsonDecode(sp.getString('syncManifest') ?? '{}') as Map<String, dynamic>;
      _manifest = {for (final e in j.entries) e.key: SyncEntry.fromJson(e.value as Map<String, dynamic>)};
    } catch (_) {
      _manifest = {};
    }
    if (syncReleased) onLocalChange = changed;
  }

  Future<void> _save() async {
    final sp = _p;
    if (sp == null) return;
    await sp.setBool('syncEnabled', enabled);
    await sp.setBool('syncOnStartup', onStartup);
    await sp.setInt('syncDays', days);
    if (email != null) await sp.setString('syncEmail', email!);
    if (lastSync != null) await sp.setString('syncLast', lastSync!.toIso8601String());
    if (status != null) await sp.setString('syncStatus', status!);
    await sp.setStringList('syncPending', _pending.toList());
    await sp.setString('syncManifest', jsonEncode({for (final e in _manifest.entries) e.key: e.value.toJson()}));
  }

  void setOnStartup(bool v) {
    onStartup = v;
    _save();
    notifyListeners();
  }

  void setDays(int v) {
    days = v;
    _save();
    notifyListeners();
  }

  /// Käyttäjän painallus: tilin valinta puhelimen tileistä ja Drive-oikeus. Ei salasanan kirjoittamista.
  Future<String?> connect() async {
    final a = auth;
    if (!configured || a == null) return 'Google Drive -yhteyttä ei ole vielä otettu käyttöön tässä versiossa.';
    try {
      final (mail, token) = await a.connect();
      if (token == null) return null; // peruttu
      _token = token;
      email = mail;
      enabled = true;
      await _save();
      notifyListeners();
      await syncNow();
      return null;
    } catch (e) {
      return 'Kirjautuminen epäonnistui: $e';
    }
  }

  Future<void> disconnect() async {
    enabled = false;
    email = null;
    _token = null;
    _manifest = {};
    _pending.clear();
    status = null;
    await _p?.remove('syncEmail');
    await _save();
    try {
      await auth?.disconnect();
    } catch (_) {}
    notifyListeners();
  }

  /// Pääsytunnus ilman käyttäjän toimia. null = pitää yhdistää uudelleen.
  Future<String?> _getToken({bool refresh = false}) async {
    if (!refresh && _token != null) return _token;
    try {
      return _token = await auth?.token(refresh: refresh, old: _token);
    } catch (_) {
      return null;
    }
  }

  /// Tallennuksen koukku: polku jonoon ja lähetys pienellä viiveellä.
  void changed(String path) {
    if (!enabled || !isSyncable(path)) return;
    _pending.add(path);
    _save();
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => _run(only: {..._pending}));
  }

  /// Käynnistyksen tarkistus (asetuksen mukaan).
  Future<void> startup() async {
    if (!enabled || !onStartup) {
      if (enabled && _pending.isNotEmpty) await _run(only: {..._pending});
      return;
    }
    await syncNow();
  }

  /// Viimeiset [days] päivää (tai kaikki) ja jonossa olevat.
  Future<SyncResult?> syncNow({bool all = false}) async {
    final since = all || days == 0 ? null : addDays(dateOnly(DateTime.now()), -days);
    final r = await _run(since: since);
    if (_pending.isNotEmpty) await _run(only: {..._pending});
    return r;
  }

  Future<SyncResult?> _run({DateTime? since, Set<String>? only}) async {
    if (!enabled) return null;
    if (busy) {
      _rerun = true;
      return null;
    }
    busy = true;
    status = 'Synkronoidaan…';
    notifyListeners();
    SyncResult? r;
    try {
      final rid = _p?.getString('syncRootId');
      final remote = DriveRemote(_getToken, rootId: rid);
      final engine = SyncEngine(await store.rootDir(), remote, _manifest);
      r = await engine.run(since: since, only: only);
      if (remote.rootId != null && remote.rootId != rid) await _p?.setString('syncRootId', remote.rootId!);
      if (r.ok) {
        _pending.removeWhere((x) {
          if (only != null) return only.contains(x);
          final d = dateOfPath(x);
          return d == null || since == null || !d.isBefore(since);
        });
        lastSync = DateTime.now();
        status = r.summary();
      } else {
        status = r.errors.first.contains('SocketException') || r.errors.first.contains('ClientException')
            ? 'Ei verkkoyhteyttä, muutokset lähtevät myöhemmin'
            : 'Virhe: ${r.errors.first}';
      }
      if (r.changedLocal) {
        await settings.loadFromFolder();
        await store.reload();
      }
    } catch (e) {
      status = 'Virhe: $e';
    } finally {
      busy = false;
      await _save();
      notifyListeners();
    }
    if (_rerun) {
      _rerun = false;
      if (_pending.isNotEmpty) await _run(only: {..._pending});
    }
    return r;
  }
}

final sync = SyncService();

/// Google-kirjautuminen Drive-oikeudella (drive.file). Toteutus lisätään, kun synkronointi julkaistaan:
/// aiempi versio käytti google_sign_in 7 -pakettia (git-historia, docs/google-drive.md).
abstract class DriveAuth {
  /// Käyttäjän valitsema tili ja pääsytunnus; tunnus null = käyttäjä perui.
  Future<(String?, String?)> connect();

  /// Uusi tai välimuistissa oleva tunnus ilman käyttäjän toimia; [old] hylättiin (401), jos refresh.
  Future<String?> token({bool refresh = false, String? old});
  Future<void> disconnect();
}
