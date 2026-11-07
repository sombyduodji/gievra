import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_engine.dart';

// Google Drive REST v3 -etäkansio. Oikeus: drive.file (vain sovelluksen itse luomat tiedostot),
// joten Google ei vaadi sovellukselle tarkastusta. Rakenne Drivessa:
//   Treenipäiväkirja/asetukset.md, ohjelma.md, 2026/2026-11-06.md ...
// Poisto siirtää tiedoston Driven roskakoriin (palautettavissa 30 päivää).

const driveScope = 'https://www.googleapis.com/auth/drive.file';
const driveFolderName = 'Gievra';
const _folderMime = 'application/vnd.google-apps.folder';
const _api = 'https://www.googleapis.com/drive/v3/files';
const _upload = 'https://www.googleapis.com/upload/drive/v3/files';
const _fields = 'id,name,md5Checksum,modifiedTime,mimeType';

class DriveAuthException implements Exception {
  final String message;
  const DriveAuthException(this.message);
  @override
  String toString() => message;
}

class DriveRemote implements Remote {
  /// Palauttaa voimassa olevan pääsytunnuksen. [refresh]: edellinen hylättiin (401).
  final Future<String?> Function({bool refresh}) token;
  final http.Client client;
  String? rootId;
  final Map<String, String> _yearIds = {};
  DriveRemote(this.token, {http.Client? client, this.rootId}) : client = client ?? http.Client();

  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> headers) req) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final t = await token(refresh: attempt > 0);
      if (t == null) throw const DriveAuthException('Kirjautuminen vanhentui: yhdistä Google Driveen uudelleen');
      final res = await req({'Authorization': 'Bearer $t'});
      if (res.statusCode == 401 && attempt == 0) continue;
      if (res.statusCode >= 400) throw Exception('Drive ${res.statusCode}: ${res.body.split('\n').first}');
      return res;
    }
    throw const DriveAuthException('Kirjautuminen epäonnistui');
  }

  String _q(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<List<Map<String, dynamic>>> _children(String parentId, {bool folders = false}) async {
    final out = <Map<String, dynamic>>[];
    String? page;
    do {
      final q = "'${_q(parentId)}' in parents and trashed = false and mimeType ${folders ? '=' : '!='} '$_folderMime'";
      final uri = Uri.parse(_api).replace(
        queryParameters: {
          'q': q,
          'fields': 'nextPageToken,files($_fields)',
          'pageSize': '1000',
          'spaces': 'drive',
          'pageToken': ?page,
        },
      );
      final res = await _send((h) => client.get(uri, headers: h));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      out.addAll((j['files'] as List).cast<Map<String, dynamic>>());
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<String> _createFolder(String name, String parent) async {
    final res = await _send(
      (h) => client.post(
        Uri.parse('$_api?fields=id'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'mimeType': _folderMime,
          'parents': [parent],
        }),
      ),
    );
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }

  /// Sovelluksen kansio Driven juuressa (vanhin, jos niitä on syntynyt useampi).
  Future<String> ensureRoot() async {
    if (rootId != null) return rootId!;
    final uri = Uri.parse(_api).replace(
      queryParameters: {
        'q': "name = '${_q(driveFolderName)}' and mimeType = '$_folderMime' and 'root' in parents and trashed = false",
        'fields': 'files(id)',
        'orderBy': 'createdTime',
        'spaces': 'drive',
      },
    );
    final res = await _send((h) => client.get(uri, headers: h));
    final files = (jsonDecode(res.body) as Map<String, dynamic>)['files'] as List;
    return rootId = files.isNotEmpty ? files.first['id'] as String : await _createFolder(driveFolderName, 'root');
  }

  Future<void> _loadYears() async {
    final root = await ensureRoot();
    for (final f in await _children(root, folders: true)) {
      _yearIds.putIfAbsent(f['name'] as String, () => f['id'] as String);
    }
  }

  Future<String?> _dirId(String dir, {bool create = false}) async {
    if (dir.isEmpty) return ensureRoot();
    if (!_yearIds.containsKey(dir)) await _loadYears();
    if (!_yearIds.containsKey(dir) && create) _yearIds[dir] = await _createFolder(dir, await ensureRoot());
    return _yearIds[dir];
  }

  RemoteFile _rf(String dir, Map<String, dynamic> j) => RemoteFile(
    j['id'] as String,
    dir.isEmpty ? j['name'] as String : '$dir/${j['name']}',
    j['md5Checksum'] as String? ?? '',
    DateTime.tryParse(j['modifiedTime'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  Future<Set<String>> yearDirs() async {
    await _loadYears();
    return {..._yearIds.keys.where((k) => RegExp(r'^\d{4}$').hasMatch(k))};
  }

  @override
  Future<List<RemoteFile>> list(Set<String> dirs) async {
    final out = <RemoteFile>[];
    for (final dir in dirs) {
      final id = await _dirId(dir);
      if (id == null) continue;
      out.addAll((await _children(id)).map((j) => _rf(dir, j)));
    }
    return out;
  }

  @override
  Future<String> read(RemoteFile f) async {
    final res = await _send((h) => client.get(Uri.parse('$_api/${f.id}?alt=media'), headers: h));
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  @override
  Future<RemoteFile> write(String path, String content, {RemoteFile? existing}) async {
    final dir = path.contains('/') ? path.split('/').first : '';
    final name = path.split('/').last;
    final http.Response res;
    if (existing != null) {
      res = await _send(
        (h) => client.patch(
          Uri.parse('$_upload/${existing.id}?uploadType=media&fields=$_fields'),
          headers: {...h, 'Content-Type': 'text/markdown; charset=utf-8'},
          body: utf8.encode(content),
        ),
      );
    } else {
      final parent = await _dirId(dir, create: true);
      const boundary = 'treenipaivakirja-raja';
      final body = [
        '--$boundary',
        'Content-Type: application/json; charset=UTF-8',
        '',
        jsonEncode({
          'name': name,
          'parents': [parent],
          'mimeType': 'text/markdown',
        }),
        '--$boundary',
        'Content-Type: text/markdown; charset=UTF-8',
        '',
        content,
        '--$boundary--',
      ].join('\r\n');
      res = await _send(
        (h) => client.post(
          Uri.parse('$_upload?uploadType=multipart&fields=$_fields'),
          headers: {...h, 'Content-Type': 'multipart/related; boundary=$boundary'},
          body: utf8.encode(body),
        ),
      );
    }
    return _rf(dir, jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<void> delete(RemoteFile f) async {
    await _send(
      (h) => client.patch(
        Uri.parse('$_api/${f.id}'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({'trashed': true}),
      ),
    );
  }
}
