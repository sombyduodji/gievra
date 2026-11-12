import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'import_export.dart';
import 'l10n.dart';
import 'models.dart';

/// Automaattinen varmuuskopio päivityksen jälkeen: sovelluksen oma, ei käyttäjän tekemä.
///
/// Kun uusi versio käynnistyy ensimmäisen kerran, treenikansion tiedostot pakataan kansion backup/-alikansioon
/// ennen kuin uusi versio ehtii muuttaa mitään (tiedostot ovat vielä edellisen version kirjoittamia). Kopio säilyy,
/// kunnes käyttäjä tekee oman täyden varmuuskopion ([deleteAll]). Kansiossa pidetään enintään [keep] kopiota.
/// backup/ ei kuulu treeneihin: sitä ei lueta, viedä, kopioida kansionvaihdossa eikä synkronoida.
class AutoBackup extends ChangeNotifier {
  static const dir = autoBackupDir;
  static const keep = 3;
  static const _prefix = 'gievra-automaattinen-';
  static const _prefKey = 'autoBackupBuild';

  /// Kopion nimestä aika ja versio, jolle päivitettiin: gievra-automaattinen-2026-11-12-0705-ennen-0.6.zip.
  static (DateTime, String)? parseName(String name) {
    final m = RegExp(r'^gievra-automaattinen-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})-ennen-(.+)\.zip$').firstMatch(name);
    if (m == null) return null;
    final n = [for (var i = 1; i <= 5; i++) int.parse(m[i]!)];
    return (DateTime(n[0], n[1], n[2], n[3], n[4]), m[6]!);
  }

  /// Näytettävä versio ilman koontitietoja: 0.5.9.1.20261111.35+muokattu → 0.5.9.1.
  static String shortVersion(String v) =>
      RegExp(r'^(\d+(?:\.\d+)*?)\.20\d{6}\.\d+').firstMatch(v)?[1] ?? v.split('+').first;

  /// Käyttäjä poistaa yksittäisen automaattisen kopion.
  Future<void> delete(File f) async {
    if (await f.exists()) await f.delete();
    notifyListeners();
  }

  bool running = false;
  String? error;

  /// Viimeksi tehty kopio (suhteellinen polku), ilmoitusta varten.
  String? last;

  Future<Directory> _dir() async => Directory(p.join((await store.rootDir()).path, dir));

  /// Automaattiset kopiot uusimmasta vanhimpaan.
  Future<List<File>> list() async {
    final d = await _dir();
    if (!await d.exists()) return [];
    final out = [
      await for (final e in d.list())
        if (e is File && p.basename(e.path).startsWith(_prefix) && e.path.endsWith('.zip')) e,
    ];
    out.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return out;
  }

  /// Ensimmäisellä käynnistyksellä uuden version jälkeen ([build] = versio ja koontinumero). Uusi asennus ilman
  /// treenejä ei tarvitse kopiota. Epäonnistunut kopio yritetään uudelleen seuraavalla käynnistyksellä.
  Future<void> runIfUpdated(String version, String build, {DateTime? now}) async {
    if (isDemo || running) return;
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_prefKey);
    if (previous == build) return;
    // Kansiota ei voitu lukea (esim. lupa puuttuu): ei merkitä tehdyksi, yritetään seuraavalla käynnistyksellä.
    if (store.error != null) return;
    if (store.workouts.isEmpty && store.unreadable.isEmpty) {
      await prefs.setString(_prefKey, build);
      return;
    }
    running = true;
    error = null;
    notifyListeners();
    try {
      final d = await _dir();
      await d.create(recursive: true);
      // Nimi: päivä, kellonaika ja versio, jolle päivitettiin; lajittuu aikajärjestykseen.
      final t0 = now ?? DateTime.now();
      final stamp = '${isoDate(t0)}-${t0.hour.toString().padLeft(2, '0')}${t0.minute.toString().padLeft(2, '0')}';
      final name = '$_prefix$stamp-ennen-$version.zip';
      final part = File(p.join(d.path, '$name.part'));
      await part.writeAsBytes(await exportZip(), flush: true);
      await part.rename(p.join(d.path, name));
      last = '$dir/$name';
      await _cleanup();
      await prefs.setString(_prefKey, build);
    } catch (e) {
      error = t('Automaattinen varmuuskopio epäonnistui: {0}', [errorText(e)]);
    } finally {
      running = false;
      notifyListeners();
    }
  }

  /// Vain [keep] uusinta automaattista kopiota; keskeneräiset (.part) pois.
  Future<void> _cleanup() async {
    for (final f in (await list()).skip(keep)) {
      await f.delete();
    }
    final d = await _dir();
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.part')) await e.delete();
    }
  }

  void dismissError() {
    error = null;
    notifyListeners();
  }

  /// Käyttäjän oma täysi varmuuskopio korvaa automaattiset.
  Future<void> deleteAll() async {
    for (final f in await list()) {
      await f.delete();
    }
    last = null;
    notifyListeners();
  }
}

final autoBackup = AutoBackup();
