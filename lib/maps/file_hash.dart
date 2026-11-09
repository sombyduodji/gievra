import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

// Tiedoston SHA-256 edistymisen kanssa. Androidissa laitteiston kiihdyttämä MessageDigest (MainActivity.kt,
// kanava fi.somby.gievra/hash): koko Suomen kartta (1,9 Gt) muutamassa sekunnissa. Muualla ja testeissä Dart.

const _channel = MethodChannel('fi.somby.gievra/hash');
final _listeners = <int, void Function(int)>{};
var _nextId = 0;
var _handlerSet = false;

/// Testejä varten: pakota Dart-toteutus.
bool forceDartHash = false;

Future<String> sha256OfFile(String path, {void Function(int bytes)? onProgress}) async {
  if (Platform.isAndroid && !forceDartHash) {
    if (!_handlerSet) {
      _handlerSet = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'progress') {
          final m = call.arguments as Map;
          _listeners[m['id'] as int]?.call((m['bytes'] as num).toInt());
        }
      });
    }
    final id = _nextId++;
    if (onProgress != null) _listeners[id] = onProgress;
    try {
      final hex = await _channel.invokeMethod<String>('sha256', {'path': path, 'id': id});
      if (hex != null) {
        onProgress?.call(await File(path).length());
        return hex;
      }
    } on MissingPluginException {
      // vanha natiivikoodi: Dart-toteutus alla
    } finally {
      _listeners.remove(id);
    }
  }
  final out = _DigestSink();
  final input = sha256.startChunkedConversion(out);
  var done = 0, reported = 0;
  await for (final chunk in File(path).openRead()) {
    input.add(chunk);
    done += chunk.length;
    if (done - reported >= 1 << 20) {
      reported = done;
      onProgress?.call(done);
      await Future<void>.delayed(Duration.zero); // käyttöliittymä ehtii piirtää
    }
  }
  input.close();
  onProgress?.call(done);
  return out.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
