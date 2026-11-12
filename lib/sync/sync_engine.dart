import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Kaksisuuntainen synkronointi treenikansion ja etäkansion (Google Drive) välillä.
//
// Polut ovat suhteessa treenikansioon: "asetukset.md", "ohjelma.md", "2026/2026-11-06.md".
// Muutos tunnistetaan md5-tarkisteella: viimeisen synkronoinnin tarkiste tallennetaan manifestiin.
//  - vain paikallinen muuttui            -> lähetetään
//  - vain etä muuttui                    -> ladataan (myös toiselta puhelimelta tai PC:ltä)
//  - molemmat muuttuivat (ristiriita)    -> uudempi voittaa, toinen säilyy paikallisesti
//                                           nimellä ristiriita-<nimi>-<aika>.md (ei näy kalenterissa)
//  - poistettu toisella puolella         -> poistetaan toiseltakin, jos toista ei muutettu
// Synkronointi ei koskaan kaada sovellusta: virheet palautetaan tuloksessa.

class RemoteFile {
  final String id;
  final String path;
  final String md5;
  final DateTime modified;
  const RemoteFile(this.id, this.path, this.md5, this.modified);
}

/// Etäkansio (Drive tai testien muistikansio).
abstract class Remote {
  /// Tiedostot kansioissa [dirs] ('' = juuri, '2026' = vuosikansio).
  Future<List<RemoteFile>> list(Set<String> dirs);

  /// Vuosikansioiden nimet (kaikkien treenien synkronointiin).
  Future<Set<String>> yearDirs();
  Future<String> read(RemoteFile f);
  Future<RemoteFile> write(String path, String content, {RemoteFile? existing});
  Future<void> delete(RemoteFile f);
}

class SyncEntry {
  final String md5;
  final String? remoteId;
  const SyncEntry(this.md5, this.remoteId);
  Map<String, dynamic> toJson() => {'md5': md5, if (remoteId != null) 'id': remoteId};
  static SyncEntry fromJson(Map<String, dynamic> j) => SyncEntry(j['md5'] as String? ?? '', j['id'] as String?);
}

class SyncResult {
  final List<String> uploaded = [], downloaded = [], deletedLocal = [], deletedRemote = [], conflicts = [];
  final List<String> errors = [];
  bool get changedLocal => downloaded.isNotEmpty || deletedLocal.isNotEmpty;
  bool get ok => errors.isEmpty;
  String summary() {
    final parts = [
      if (downloaded.isNotEmpty) 'ladattu ${downloaded.length}',
      if (uploaded.isNotEmpty) 'lähetetty ${uploaded.length}',
      if (deletedLocal.isNotEmpty || deletedRemote.isNotEmpty)
        'poistettu ${deletedLocal.length + deletedRemote.length}',
      if (conflicts.isNotEmpty) 'ristiriitoja ${conflicts.length}',
    ];
    return parts.isEmpty ? 'Ajan tasalla' : parts.join(', ');
  }
}

String md5Of(String s) => md5.convert(utf8.encode(s)).toString();

/// Synkronoitavat tiedostot: asetukset, ohjelma, päivän askeleet, treenit (vvvv/vvvv-kk-pp.md) ja niiden GPS-reitit
/// (.gpx).
final _workoutRe = RegExp(r'^(\d{4})/(\d{4}-\d{2}-\d{2})(-\d+)?\.(md|gpx)$');
const rootFiles = {'asetukset.md', 'ohjelma.md', 'askeleet.md'};

bool isSyncable(String path) => rootFiles.contains(path) || _workoutRe.hasMatch(path);

DateTime? dateOfPath(String path) {
  final m = _workoutRe.firstMatch(path);
  return m == null ? null : DateTime.tryParse(m[2]!);
}

class SyncEngine {
  final Directory root;
  final Remote remote;
  final Map<String, SyncEntry> manifest;
  final String deviceName;
  SyncEngine(this.root, this.remote, this.manifest, {this.deviceName = 'puhelin'});

  File _file(String path) => File(p.joinAll([root.path, ...path.split('/')]));

  Future<Map<String, File>> _localFiles(bool Function(String) want) async {
    final out = <String, File>{};
    if (!await root.exists()) return out;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: root.path).split(p.separator).join('/');
      if (isSyncable(rel) && want(rel)) out[rel] = e;
    }
    return out;
  }

  /// Synkronoi tiedostot. [since]: vain treenit tästä päivästä alkaen (null = kaikki).
  /// [only]: vain nämä polut (tallennuksen jälkeinen lähetys).
  Future<SyncResult> run({DateTime? since, Set<String>? only}) async {
    final r = SyncResult();
    bool want(String path) {
      if (only != null) return only.contains(path);
      final d = dateOfPath(path);
      return d == null || since == null || !d.isBefore(since);
    }

    try {
      final local = await _localFiles(want);
      final Set<String> dirs;
      if (only != null) {
        dirs = {for (final x in only) x.contains('/') ? x.split('/').first : ''};
      } else if (since == null) {
        dirs = {'', ...await remote.yearDirs()};
      } else {
        dirs = {'', for (var y = since.year; y <= DateTime.now().year + 1; y++) '$y'};
      }
      final remoteFiles = {
        for (final f in await remote.list(dirs))
          if (isSyncable(f.path) && want(f.path)) f.path: f,
      };
      final paths = {...local.keys, ...remoteFiles.keys, ...manifest.keys.where(want)};
      for (final path in paths.toList()..sort()) {
        try {
          await _syncOne(path, local[path], remoteFiles[path], r);
        } catch (e) {
          r.errors.add('$path: $e');
        }
      }
    } catch (e) {
      r.errors.add('$e');
    }
    return r;
  }

  Future<void> _syncOne(String path, File? lf, RemoteFile? rf, SyncResult r) async {
    final m = manifest[path];
    final content = lf == null ? null : await lf.readAsString();
    final lmd5 = content == null ? null : md5Of(content);
    final localChanged = m == null ? lf != null : lmd5 != m.md5;
    final remoteChanged = m == null ? rf != null : (rf?.md5 != m.md5);

    if (lf == null && rf == null) {
      manifest.remove(path);
      return;
    }
    if (lmd5 != null && rf != null && lmd5 == rf.md5) {
      manifest[path] = SyncEntry(lmd5, rf.id); // sama sisältö molemmissa
      return;
    }
    if (localChanged && !remoteChanged) {
      if (lf == null) {
        await remote.delete(rf!);
        manifest.remove(path);
        r.deletedRemote.add(path);
      } else {
        final w = await remote.write(path, content!, existing: rf);
        manifest[path] = SyncEntry(lmd5!, w.id);
        r.uploaded.add(path);
      }
      return;
    }
    if (remoteChanged && !localChanged) {
      if (rf == null) {
        await lf!.delete();
        manifest.remove(path);
        r.deletedLocal.add(path);
      } else {
        await _download(path, rf);
        r.downloaded.add(path);
      }
      return;
    }
    // Molemmat muuttuneet (tai ensimmäinen synkronointi eri sisällöllä): uudempi voittaa.
    final localTime = lf == null ? DateTime.fromMillisecondsSinceEpoch(0) : await lf.lastModified();
    final remoteWins = rf != null && (lf == null || rf.modified.isAfter(localTime));
    if (remoteWins) {
      if (content != null) await _conflictCopy(path, content);
      await _download(path, rf);
      r.downloaded.add(path);
    } else {
      if (rf != null) await _conflictCopy(path, await remote.read(rf));
      final w = await remote.write(path, content!, existing: rf);
      manifest[path] = SyncEntry(lmd5!, w.id);
      r.uploaded.add(path);
    }
    r.conflicts.add(path);
  }

  Future<void> _download(String path, RemoteFile rf) async {
    final text = await remote.read(rf);
    final f = _file(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(text);
    manifest[path] = SyncEntry(md5Of(text), rf.id);
  }

  /// Hävinnyt versio talteen samaan kansioon. Nimi ei ala päivämäärällä, joten kalenteri ei lue sitä.
  Future<void> _conflictCopy(String path, String content) async {
    final f = _file(path);
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
    final copy = File(
      p.join(
        f.parent.path,
        'ristiriita-${p.basenameWithoutExtension(f.path)}-$stamp-$deviceName${p.extension(f.path)}',
      ),
    );
    await copy.parent.create(recursive: true);
    await copy.writeAsString(content);
  }
}
