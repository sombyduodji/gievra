import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treenipaivakirja/sync/drive_remote.dart';
import 'package:treenipaivakirja/sync/sync_engine.dart';

/// Pieni Drive v3 -jäljitelmä: vain ne kutsut, joita DriveRemote käyttää.
class FakeDrive {
  final files = <String, Map<String, dynamic>>{};
  var _n = 0;
  var expireNext = false;
  final requests = <String>[];

  Map<String, dynamic> _meta(String id) {
    final f = files[id]!;
    return {
      'id': id,
      'name': f['name'],
      'mimeType': f['mimeType'],
      'modifiedTime': (f['modified'] as DateTime).toUtc().toIso8601String(),
      if (f['content'] != null) 'md5Checksum': md5.convert(f['content'] as List<int>).toString(),
    };
  }

  String _new(String name, String parent, String mime, [List<int>? content]) {
    final id = 'f${_n++}';
    files[id] = {
      'name': name,
      'parents': [parent],
      'mimeType': mime,
      'content': content,
      'modified': DateTime.now(),
      'trashed': false,
    };
    return id;
  }

  Future<http.Response> handle(http.Request req) async {
    requests.add('${req.method} ${req.url.path}');
    if (req.headers['Authorization'] != 'Bearer ok') return http.Response('{"error":"auth"}', 401);
    if (expireNext) {
      expireNext = false;
      return http.Response('{"error":"expired"}', 401);
    }
    final path = req.url.path;
    final json = {'content-type': 'application/json'};
    if (req.method == 'GET' && path == '/drive/v3/files') {
      final q = req.url.queryParameters['q']!;
      final parent = RegExp(r"'([^']+)' in parents").firstMatch(q)![1]!;
      final name = RegExp(r"name = '([^']+)'").firstMatch(q)?[1];
      final wantFolder = q.contains("mimeType = 'application/vnd.google-apps.folder'");
      final noFolder = q.contains("mimeType != 'application/vnd.google-apps.folder'");
      final hits = files.entries.where((e) {
        final f = e.value;
        final isFolder = f['mimeType'] == 'application/vnd.google-apps.folder';
        return (f['parents'] as List).contains(parent) &&
            f['trashed'] == false &&
            (name == null || f['name'] == name) &&
            (!wantFolder || isFolder) &&
            (!noFolder || !isFolder);
      });
      return http.Response(
        jsonEncode({
          'files': [for (final e in hits) _meta(e.key)],
        }),
        200,
        headers: json,
      );
    }
    if (req.method == 'POST' && path == '/drive/v3/files') {
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'id': _new(b['name'], (b['parents'] as List).first, b['mimeType'])}), 200);
    }
    if (req.method == 'POST' && path == '/upload/drive/v3/files') {
      final parts = utf8.decode(req.bodyBytes).split('\r\n');
      final meta = jsonDecode(parts[3]) as Map<String, dynamic>;
      final content = parts.sublist(7, parts.length - 1).join('\r\n');
      final id = _new(meta['name'], (meta['parents'] as List).first, 'text/markdown', utf8.encode(content));
      return http.Response(jsonEncode(_meta(id)), 200, headers: json);
    }
    final m = RegExp(r'/files/([^/]+)$').firstMatch(path);
    if (m != null && files.containsKey(m[1])) {
      final id = m[1]!;
      if (req.method == 'PATCH' && path.startsWith('/upload')) {
        files[id]!['content'] = req.bodyBytes;
        files[id]!['modified'] = DateTime.now();
        return http.Response(jsonEncode(_meta(id)), 200, headers: json);
      }
      if (req.method == 'PATCH') {
        files[id]!['trashed'] = true;
        return http.Response('{}', 200);
      }
      if (req.method == 'GET' && req.url.queryParameters['alt'] == 'media') {
        return http.Response.bytes(files[id]!['content'] as List<int>, 200);
      }
    }
    return http.Response('not found $path', 404);
  }
}

void main() {
  test('DriveRemote: kansiot, lähetys, päivitys, luku, poisto ja vanhentunut tunnus', () async {
    final fake = FakeDrive();
    var refreshed = 0;
    final remote = DriveRemote(({bool refresh = false}) async {
      if (refresh) refreshed++;
      return 'ok';
    }, client: MockClient(fake.handle));
    final dir = await Directory.systemTemp.createTemp('drive');
    final file = File('${dir.path}/2026/2026-11-06.md')..createSync(recursive: true);
    file.writeAsStringSync('# Jalkapäivä\n1. 100 kg × 5\n');
    File('${dir.path}/asetukset.md').writeAsStringSync('---\nname: Elle\n---\n');
    final manifest = <String, SyncEntry>{};

    var r = await SyncEngine(dir, remote, manifest).run();
    expect(r.errors, isEmpty);
    expect(r.uploaded.toSet(), {'2026/2026-11-06.md', 'asetukset.md'});
    final names = fake.files.values.map((f) => f['name']).toSet();
    expect(names, containsAll([driveFolderName, '2026', '2026-11-06.md', 'asetukset.md']));

    // Toinen ajo: md5 täsmää, ei siirtoja.
    r = await SyncEngine(
      dir,
      DriveRemote(({bool refresh = false}) async => 'ok', client: MockClient(fake.handle)),
      manifest,
    ).run();
    expect(r.summary(), 'Ajan tasalla');

    // Muokkaus PC:llä -> lataus; vanhentunut tunnus -> uusi tunnus ja uusi yritys.
    final id = fake.files.entries.firstWhere((e) => e.value['name'] == '2026-11-06.md').key;
    fake.files[id]!['content'] = utf8.encode('# Jalkapäivä\n1. 100 kg × 5\n2. 105 kg × 3\n');
    fake.files[id]!['modified'] = DateTime.now().add(const Duration(minutes: 1));
    fake.expireNext = true;
    r = await SyncEngine(dir, remote, manifest).run(since: DateTime(2026, 11, 1));
    expect(r.errors, isEmpty);
    expect(refreshed, 1);
    expect(r.downloaded, ['2026/2026-11-06.md']);
    expect(file.readAsStringSync(), contains('105 kg × 3'));

    // Paikallinen muutos -> PATCH samaan tiedostoon; poisto -> Driven roskakoriin.
    file.writeAsStringSync('muutettu ääkkösin');
    r = await SyncEngine(dir, remote, manifest).run();
    expect(r.uploaded, ['2026/2026-11-06.md']);
    expect(utf8.decode(fake.files[id]!['content'] as List<int>), 'muutettu ääkkösin');
    file.deleteSync();
    r = await SyncEngine(dir, remote, manifest).run();
    expect(r.deletedRemote, ['2026/2026-11-06.md']);
    expect(fake.files[id]!['trashed'], isTrue);
    await dir.delete(recursive: true);
  });

  test('Ilman tunnusta: selkeä virhe, ei kaatumista', () async {
    final dir = await Directory.systemTemp.createTemp('drive');
    File('${dir.path}/asetukset.md').writeAsStringSync('x');
    final r = await SyncEngine(
      dir,
      DriveRemote(({bool refresh = false}) async => null, client: MockClient(FakeDrive().handle)),
      {},
    ).run();
    expect(r.ok, isFalse);
    expect(r.errors.first, contains('yhdistä'));
    await dir.delete(recursive: true);
  });
}
