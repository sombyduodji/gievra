import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../l10n.dart' as l10n;

// PMTiles v3 -karttatiedoston lukija (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md). Sama muoto
// kuin tools/map_extract.py kirjoittaa. Vain tiedostosta, ei verkosta; hakemistot välimuistissa.

int zxyToTileId(int z, int x, int y) {
  var acc = ((1 << (2 * z)) - 1) ~/ 3;
  final n = 1 << z;
  var d = 0;
  var s = n >> 1;
  while (s > 0) {
    final rx = (x & s) != 0 ? 1 : 0;
    final ry = (y & s) != 0 ? 1 : 0;
    d += s * s * ((3 * rx) ^ ry);
    if (ry == 0) {
      if (rx == 1) {
        x = n - 1 - x;
        y = n - 1 - y;
      }
      final t = x;
      x = y;
      y = t;
    }
    s >>= 1;
  }
  return acc + d;
}

class _Entry {
  final int tileId, offset, length, runLength;
  const _Entry(this.tileId, this.offset, this.length, this.runLength);
}

List<_Entry> _parseDir(List<int> b) {
  var pos = 0;
  int varint() {
    var v = 0, shift = 0;
    while (true) {
      final c = b[pos++];
      v |= (c & 0x7f) << shift;
      if (c < 0x80) return v;
      shift += 7;
    }
  }

  final n = varint();
  final ids = List<int>.filled(n, 0), runs = List<int>.filled(n, 0), lens = List<int>.filled(n, 0);
  final offs = List<int>.filled(n, 0);
  var last = 0;
  for (var i = 0; i < n; i++) {
    last += varint();
    ids[i] = last;
  }
  for (var i = 0; i < n; i++) {
    runs[i] = varint();
  }
  for (var i = 0; i < n; i++) {
    lens[i] = varint();
  }
  for (var i = 0; i < n; i++) {
    final v = varint();
    offs[i] = v == 0 && i > 0 ? offs[i - 1] + lens[i - 1] : v - 1;
  }
  return [for (var i = 0; i < n; i++) _Entry(ids[i], offs[i], lens[i], runs[i])];
}

class PmTilesFile {
  final String path;
  final RandomAccessFile _raf;
  late final int _rootOff, _rootLen, _leafOff, _dataOff, _icomp, _tcomp;
  late final int minZoom, maxZoom;

  /// Tiedoston vähimmäispituus otsakkeen mukaan (hakemistot, metatiedot ja laattadata): lyhyempi = keskeneräinen.
  late final int requiredLength;

  /// Rajaava laatikko asteina (w, s, e, n).
  late final (double, double, double, double) bounds;
  late final List<_Entry> _root;

  /// Alihakemistot kaikille avoimille tiedostoille yhteisessä välimuistissa (avain: tiedosto ja kohta), jossa on
  /// enintään [_maxLeafEntries] merkintää yhteensä: muistin käyttö ei riipu ladattujen karttojen määrästä (koko maa
  /// yhtenä tiedostona tai satoja kuntia). Vanhimmat käytetyt poistetaan ensin.
  static final _leaves = <String, List<_Entry>>{};
  static var _leafEntries = 0;
  static const _maxLeafEntries = 150000; // noin 7 Mt
  Future<void> _lock = Future.value();

  PmTilesFile._(this.path, this._raf);

  static Future<PmTilesFile> open(String path) async {
    final f = PmTilesFile._(path, await File(path).open());
    await f._init();
    return f;
  }

  Future<Uint8List> _read(int off, int len) {
    // RandomAccessFile ei salli päällekkäisiä lukuja: jonoon.
    final c = Completer<Uint8List>();
    _lock = _lock.then((_) async {
      try {
        await _raf.setPosition(off);
        c.complete(await _raf.read(len));
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  List<int> _decompress(List<int> b, int comp) => switch (comp) {
    0 || 1 => b,
    2 => gzip.decode(b),
    _ => throw UnsupportedError('PMTiles-pakkaus $comp'),
  };

  Future<void> _init() async {
    final h = ByteData.sublistView(await _read(0, 127));
    String magic = String.fromCharCodes(Uint8List.sublistView(h, 0, 7));
    if (magic != 'PMTiles' || h.getUint8(7) != 3) throw FormatException(l10n.fi('ei PMTiles v3 -tiedosto'));
    int u64(int o) => h.getUint64(o, Endian.little);
    _rootOff = u64(8);
    _rootLen = u64(16);
    _leafOff = u64(40);
    _dataOff = u64(56);
    requiredLength = [
      for (final o in [8, 24, 40, 56]) u64(o) + u64(o + 8),
    ].reduce((a, b) => a > b ? a : b);
    _icomp = h.getUint8(97);
    _tcomp = h.getUint8(98);
    minZoom = h.getUint8(100);
    maxZoom = h.getUint8(101);
    double deg(int o) => h.getInt32(o, Endian.little) / 1e7;
    bounds = (deg(102), deg(106), deg(110), deg(114));
    _root = _parseDir(_decompress(await _read(_rootOff, _rootLen), _icomp));
  }

  static _Entry? _find(List<_Entry> es, int id) {
    var lo = 0, hi = es.length - 1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (es[m].tileId <= id) {
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    if (hi < 0) return null;
    final e = es[hi];
    if (e.runLength == 0) return e; // lehtihakemisto
    return id < e.tileId + e.runLength ? e : null;
  }

  /// Laatta (pakkaamaton MVT) tai null, jos sitä ei ole tässä tiedostossa.
  Future<Uint8List?> tile(int z, int x, int y) async {
    if (z < minZoom || z > maxZoom) return null;
    final id = zxyToTileId(z, x, y);
    var dir = _root;
    for (var depth = 0; depth < 4; depth++) {
      final e = _find(dir, id);
      if (e == null) return null;
      if (e.runLength > 0) {
        final b = await _read(_dataOff + e.offset, e.length);
        final out = _decompress(b, _tcomp);
        return out is Uint8List ? out : Uint8List.fromList(out);
      }
      final key = '$path:${e.offset}';
      var leaf = _leaves.remove(key);
      if (leaf == null) {
        leaf = _parseDir(_decompress(await _read(_leafOff + e.offset, e.length), _icomp));
        _leafEntries += leaf.length;
        while (_leafEntries > _maxLeafEntries && _leaves.isNotEmpty) {
          final oldest = _leaves.keys.first;
          _leafEntries -= _leaves.remove(oldest)!.length;
        }
      }
      _leaves[key] = leaf; // viimeksi käytetty loppuun
      dir = leaf;
    }
    return null;
  }

  Future<void> close() {
    // Tiedoston alihakemistot pois välimuistista (esim. kartta poistettu tai päivitetty).
    _leaves.removeWhere((k, v) {
      final mine = k.startsWith('$path:');
      if (mine) _leafEntries -= v.length;
      return mine;
    });
    return _raf.close();
  }
}
