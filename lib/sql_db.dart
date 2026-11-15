// Pieni SQLite-rajapinta FitNotes-tuonnille ja -viennille.
// Android: puhelimen oma SQLite kanavan kautta (SqliteBridge.kt), joten APK:ssa ei ole omaa libsqlite3.so:ta
// (pubspec.yaml: hooks.user_defines.sqlite3.source.android = process). Muut alustat ja testit: package:sqlite3.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart' as ffi;

abstract class SqlDb {
  Future<List<Map<String, Object?>>> select(String sql, [List<Object?> args = const []]);

  /// Suorittaa lauseen; palauttaa viimeksi lisätyn rivin id:n.
  Future<int> execute(String sql, [List<Object?> args = const []]);
  Future<void> executeMany(String sql, List<List<Object?>> rows);
  Future<void> begin();
  Future<void> commit();
  Future<void> close();
}

/// Testeissä voi pakottaa kanavan käyttöön (false) tai FFI:n (true). Oletus: FFI muualla kuin Androidissa.
bool? debugUseFfiSqlite;

Future<SqlDb> openSqlDb(String path, {bool readOnly = false}) async {
  if (debugUseFfiSqlite ?? !Platform.isAndroid) return _FfiDb(path, readOnly);
  final id = await _ch.invokeMethod<int>('open', {'path': path, 'readOnly': readOnly});
  return _ChannelDb(id!);
}

const _ch = MethodChannel('fi.somby.gievra/sqlite');

class _ChannelDb implements SqlDb {
  _ChannelDb(this.id);
  final int id;

  @override
  Future<List<Map<String, Object?>>> select(String sql, [List<Object?> args = const []]) async {
    final rows = await _ch.invokeListMethod<Map>('select', {'db': id, 'sql': sql, 'args': args});
    return [for (final r in rows ?? const []) r.cast<String, Object?>()];
  }

  @override
  Future<int> execute(String sql, [List<Object?> args = const []]) async =>
      (await _ch.invokeMethod<int>('execute', {'db': id, 'sql': sql, 'args': args}))!;

  @override
  Future<void> executeMany(String sql, List<List<Object?>> rows) =>
      _ch.invokeMethod('executeMany', {'db': id, 'sql': sql, 'rows': rows});

  @override
  Future<void> begin() => _ch.invokeMethod('begin', {'db': id});

  @override
  Future<void> commit() => _ch.invokeMethod('commit', {'db': id});

  @override
  Future<void> close() => _ch.invokeMethod('close', {'db': id});
}

class _FfiDb implements SqlDb {
  _FfiDb(String path, bool readOnly)
    : db = ffi.sqlite3.open(path, mode: readOnly ? ffi.OpenMode.readOnly : ffi.OpenMode.readWriteCreate);
  final ffi.Database db;

  @override
  Future<List<Map<String, Object?>>> select(String sql, [List<Object?> args = const []]) async => [
    for (final r in db.select(sql, args)) {for (final k in r.keys) k: r[k]},
  ];

  @override
  Future<int> execute(String sql, [List<Object?> args = const []]) async {
    db.execute(sql, args);
    return db.lastInsertRowId;
  }

  @override
  Future<void> executeMany(String sql, List<List<Object?>> rows) async {
    final st = db.prepare(sql);
    try {
      for (final r in rows) {
        st.execute(r);
      }
    } finally {
      st.close();
    }
  }

  @override
  Future<void> begin() async => db.execute('BEGIN');

  @override
  Future<void> commit() async => db.execute('COMMIT');

  @override
  Future<void> close() async => db.close();
}
