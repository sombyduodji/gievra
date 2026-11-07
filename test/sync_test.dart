import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/sync/sync_engine.dart';

/// Muistissa oleva etäkansio testejä varten.
class MemRemote implements Remote {
  final files = <String, (String, DateTime)>{};
  var _id = 0;
  final ids = <String, String>{};
  RemoteFile _rf(String path) =>
      RemoteFile(ids.putIfAbsent(path, () => 'id${_id++}'), path, md5Of(files[path]!.$1), files[path]!.$2);

  @override
  Future<List<RemoteFile>> list(Set<String> dirs) async => [
    for (final path in files.keys)
      if (dirs.contains(path.contains('/') ? path.split('/').first : '')) _rf(path),
  ];
  @override
  Future<Set<String>> yearDirs() async => {
    for (final x in files.keys)
      if (x.contains('/')) x.split('/').first,
  };
  @override
  Future<String> read(RemoteFile f) async => files[f.path]!.$1;
  @override
  Future<RemoteFile> write(String path, String content, {RemoteFile? existing}) async {
    files[path] = (content, DateTime.now());
    return _rf(path);
  }

  @override
  Future<void> delete(RemoteFile f) async => files.remove(f.path);
  void edit(String path, String content, {DateTime? at}) => files[path] = (content, at ?? DateTime.now());
}

void main() {
  late Directory phone, phone2;
  late MemRemote drive;
  setUp(() async {
    phone = await Directory.systemTemp.createTemp('puhelin');
    phone2 = await Directory.systemTemp.createTemp('puhelin2');
    drive = MemRemote();
  });
  tearDown(() async {
    await phone.delete(recursive: true);
    await phone2.delete(recursive: true);
  });

  Future<void> write(Directory d, String path, String s) async {
    final f = File('${d.path}/$path');
    await f.parent.create(recursive: true);
    await f.writeAsString(s);
  }

  String read(Directory d, String path) => File('${d.path}/$path').readAsStringSync();

  test('Lähetys, toiselle puhelimelle lataus ja PC:n muutos takaisin', () async {
    final m1 = <String, SyncEntry>{}, m2 = <String, SyncEntry>{};
    await write(phone, '2026/2026-11-06.md', 'A');
    await write(phone, 'asetukset.md', 'S');
    await write(phone, 'muistiinpano.txt', 'ei synkata');
    var r = await SyncEngine(phone, drive, m1).run();
    expect(r.uploaded, ['2026/2026-11-06.md', 'asetukset.md']);
    expect(drive.files.keys, isNot(contains('muistiinpano.txt')));

    r = await SyncEngine(phone2, drive, m2).run();
    expect(r.downloaded.length, 2);
    expect(read(phone2, '2026/2026-11-06.md'), 'A');

    drive.edit('2026/2026-11-06.md', 'A + PC:llä lisätty sarja'); // muokattu PC:llä
    r = await SyncEngine(phone, drive, m1).run(since: DateTime(2026, 11, 1));
    expect(r.downloaded, ['2026/2026-11-06.md']);
    expect(r.uploaded, isEmpty);
    expect(read(phone, '2026/2026-11-06.md'), 'A + PC:llä lisätty sarja');

    r = await SyncEngine(phone, drive, m1).run();
    expect(r.summary(), 'Ajan tasalla');
  });

  test('Vain viimeiset päivät ja vain annetut polut', () async {
    final m = <String, SyncEntry>{};
    await write(phone, '2025/2025-01-01.md', 'vanha');
    await write(phone, '2026/2026-11-06.md', 'uusi');
    var r = await SyncEngine(phone, drive, m).run(since: DateTime(2026, 10, 1));
    expect(r.uploaded, ['2026/2026-11-06.md']);
    await write(phone, '2026/2026-11-07.md', 'tänään');
    r = await SyncEngine(phone, drive, m).run(only: {'2026/2026-11-07.md'});
    expect(r.uploaded, ['2026/2026-11-07.md']);
  });

  test('Ristiriita: uudempi voittaa, vanhempi talteen', () async {
    final m = <String, SyncEntry>{};
    await write(phone, '2026/2026-11-06.md', 'alku');
    await SyncEngine(phone, drive, m).run();
    await write(phone, '2026/2026-11-06.md', 'puhelimen muutos');
    drive.edit('2026/2026-11-06.md', 'PC:n muutos', at: DateTime.now().add(const Duration(minutes: 5)));
    final r = await SyncEngine(phone, drive, m).run();
    expect(r.conflicts, ['2026/2026-11-06.md']);
    expect(read(phone, '2026/2026-11-06.md'), 'PC:n muutos');
    final copies = Directory('${phone.path}/2026')
        .listSync()
        .map((e) => e.path)
        .where((x) => x.contains('ristiriita-'));
    expect(copies.length, 1);
    expect(File(copies.first).readAsStringSync(), 'puhelimen muutos');
  });

  test('Poistot kulkevat molempiin suuntiin', () async {
    final m = <String, SyncEntry>{};
    await write(phone, '2026/2026-11-05.md', 'x');
    await write(phone, '2026/2026-11-06.md', 'y');
    await SyncEngine(phone, drive, m).run();
    await File('${phone.path}/2026/2026-11-05.md').delete();
    drive.files.remove('2026/2026-11-06.md');
    final r = await SyncEngine(phone, drive, m).run();
    expect(r.deletedRemote, ['2026/2026-11-05.md']);
    expect(r.deletedLocal, ['2026/2026-11-06.md']);
    expect(drive.files, isEmpty);
  });

  test('Etävirhe ei kaada: virhe palautetaan', () async {
    final r = await SyncEngine(Directory('${phone.path}/ei-ole'), _Broken(), {}).run();
    expect(r.ok, isFalse);
  });
}

class _Broken implements Remote {
  @override
  Future<List<RemoteFile>> list(Set<String> dirs) => throw const SocketException('ei verkkoa');
  @override
  Future<Set<String>> yearDirs() => throw const SocketException('ei verkkoa');
  @override
  Future<String> read(RemoteFile f) => throw UnimplementedError();
  @override
  Future<RemoteFile> write(String path, String content, {RemoteFile? existing}) => throw UnimplementedError();
  @override
  Future<void> delete(RemoteFile f) => throw UnimplementedError();
}
