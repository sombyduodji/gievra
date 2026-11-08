#!/usr/bin/env python3
"""Leikkaa PMTiles-kartasta (esim. Protomapsin päivittäinen OpenStreetMap-maailmankartta) alueen omaksi tiedostoksi.

Lukee vain tarvittavat osat HTTP Range -pyynnöillä tai paikallisesta tiedostosta. Ei ulkopuolisia kirjastoja.
PMTiles v3 -määrittely: https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md

Esimerkit:
  tools/map_extract.py https://build.protomaps.com/20261107.pmtiles suomi.pmtiles --poly finland.poly
  tools/map_extract.py suomi.pmtiles etela.pmtiles --poly finland.poly --box 19,59.5,32,61.7 --dry-run

Kartan tiedot: © OpenStreetMap contributors (ODbL). Protomaps basemap.
"""
import argparse
import bisect
import gzip
import io
import json
import math
import os
import struct
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# ---------- lähde: URL tai tiedosto ----------


class Source:
    def __init__(self, src):
        self.src = src
        self.url = src.startswith('http')
        self.f = None if self.url else open(src, 'rb')
        self.bytes_read = 0

    def read(self, off, length):
        self.bytes_read += length
        if not self.url:
            return os.pread(self.f.fileno(), length, off)  # säieturvallinen
        for attempt in range(5):
            try:
                req = urllib.request.Request(self.src, headers={
                    'Range': f'bytes={off}-{off + length - 1}', 'User-Agent': 'gievra-map-extract/1'})
                with urllib.request.urlopen(req, timeout=60) as r:
                    data = r.read()
                if len(data) != length:
                    raise IOError(f'lyhyt vastaus {len(data)} != {length}')
                return data
            except Exception as e:  # noqa: BLE001
                if attempt == 4:
                    raise
                time.sleep(2 * (attempt + 1))
                print(f'  uusi yritys ({e})', file=sys.stderr)

# ---------- PMTiles-rakenteet ----------


def zxy_to_id(z, x, y):
    acc = ((1 << (2 * z)) - 1) // 3
    n = 1 << z
    d = 0
    s = n >> 1
    while s > 0:
        rx = 1 if x & s else 0
        ry = 1 if y & s else 0
        d += s * s * ((3 * rx) ^ ry)
        if ry == 0:
            if rx == 1:
                x = n - 1 - x
                y = n - 1 - y
            x, y = y, x
        s >>= 1
    return acc + d


def id_to_zxy(tid):
    z = 0
    acc = 0
    while True:
        cnt = 1 << (2 * z)
        if tid < acc + cnt:
            break
        acc += cnt
        z += 1
    d = tid - acc
    n = 1 << z
    x = y = 0
    s = 1
    t = d
    while s < n:
        rx = 1 & (t // 2)
        ry = 1 & (t ^ rx)
        if ry == 0:
            if rx == 1:
                x = s - 1 - x
                y = s - 1 - y
            x, y = y, x
        x += s * rx
        y += s * ry
        t //= 4
        s *= 2
    return z, x, y


def read_varint(b, pos):
    v = shift = 0
    while True:
        c = b[pos]
        pos += 1
        v |= (c & 0x7F) << shift
        if c < 0x80:
            return v, pos
        shift += 7


def write_varint(out, v):
    while v >= 0x80:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)


def decompress(data, comp):
    if comp in (0, 1):
        return data
    if comp == 2:
        return gzip.decompress(data)
    raise SystemExit(f'pakkaus {comp} ei tuettu')


def parse_dir(b):
    n, p = read_varint(b, 0)
    ids, runs, lens, offs = [], [], [], []
    last = 0
    for _ in range(n):
        v, p = read_varint(b, p)
        last += v
        ids.append(last)
    for _ in range(n):
        v, p = read_varint(b, p)
        runs.append(v)
    for _ in range(n):
        v, p = read_varint(b, p)
        lens.append(v)
    for i in range(n):
        v, p = read_varint(b, p)
        offs.append(offs[i - 1] + lens[i - 1] if v == 0 and i > 0 else v - 1)
    return list(zip(ids, offs, lens, runs))


def serialize_dir(entries):
    out = bytearray()
    write_varint(out, len(entries))
    last = 0
    for tid, _, _, _ in entries:
        write_varint(out, tid - last)
        last = tid
    for e in entries:
        write_varint(out, e[3])
    for e in entries:
        write_varint(out, e[2])
    for i, e in enumerate(entries):
        if i > 0 and e[1] == entries[i - 1][1] + entries[i - 1][2]:
            write_varint(out, 0)
        else:
            write_varint(out, e[1] + 1)
    return gzip.compress(bytes(out), compresslevel=9, mtime=0)


HDR = struct.Struct('<7sB QQ QQ QQ QQ QQQ BBBBBB iiii B ii')


def parse_header(b):
    f = HDR.unpack(b[:127])
    keys = ['magic', 'version', 'root_off', 'root_len', 'meta_off', 'meta_len', 'leaf_off', 'leaf_len',
            'data_off', 'data_len', 'n_addressed', 'n_entries', 'n_contents', 'clustered', 'icomp', 'tcomp',
            'ttype', 'minz', 'maxz', 'minlon', 'minlat', 'maxlon', 'maxlat', 'cz', 'clon', 'clat']
    h = dict(zip(keys, f))
    if h['magic'] != b'PMTiles' or h['version'] != 3:
        raise SystemExit('ei PMTiles v3 -tiedosto')
    return h

# ---------- alue: .poly-raja ja laatikko ----------


def read_poly(path):
    rings, cur = [], None
    with open(path) as f:
        lines = [l.strip() for l in f][1:]
    for l in lines:
        if not l:
            continue
        if cur is None:
            if l == 'END':
                break
            cur = []
        elif l == 'END':
            rings.append(cur)
            cur = None
        else:
            lon, lat = map(float, l.split())
            cur.append((lon, lat))
    return rings


def lat_to_y(lat, n):
    r = math.radians(lat)
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n


def lon_to_x(lon, n):
    return (lon + 180) / 360 * n


def y_to_lat(y, n):
    return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))


def needed_tiles(rings, box, maxz, buffer_m):
    """Kaikki laatat z0..maxz, jotka osuvat alueeseen (puskurin kanssa). Palauttaa järjestetyn id-listan."""
    ids = []
    for z in range(maxz + 1):
        n = 1 << z
        tiles = set()
        if rings:
            all_lat = [p[1] for r in rings for p in r]
            lat_hi, lat_lo = max(all_lat), min(all_lat)
            ymin = max(0, int(lat_to_y(max(all_lat), n)) - 1)
            ymax = min(n - 1, int(lat_to_y(min(all_lat), n)) + 1)
        else:
            ymin, ymax = int(lat_to_y(box[3], n)), int(lat_to_y(box[1], n))
        for ty in range(ymin, ymax + 1):
            lat_mid = y_to_lat(ty + 0.5, n)
            tile_w = 40075016 * math.cos(math.radians(lat_mid)) / n
            k = max(1, math.ceil(buffer_m / tile_w))
            spans = []
            if rings:
                # vaakaviivat (parillinen/pariton -sääntö, reiät mukaan lukien);
                # näytteet rivin ja alueen leveyspiirivälien yhteiseltä osalta (pienillä zoomeilla laatta on
                # koko aluetta korkeampi)
                top, bot = min(lat_hi, y_to_lat(ty, n)), max(lat_lo, y_to_lat(ty + 1, n))
                if top < bot:
                    continue
                for fy in (0.01, 0.25, 0.5, 0.75, 0.99):
                    lat = top - (top - bot) * fy
                    xs = []
                    for r in rings:
                        for i in range(len(r)):
                            (x1, y1), (x2, y2) = r[i], r[(i + 1) % len(r)]
                            if (y1 <= lat < y2) or (y2 <= lat < y1):
                                xs.append(x1 + (lat - y1) / (y2 - y1) * (x2 - x1))
                    xs.sort()
                    for a, b in zip(xs[0::2], xs[1::2]):
                        spans.append((lon_to_x(a, n), lon_to_x(b, n)))
                # pystysuunnan puskuri: myös naapuririvien leveys
            else:
                spans.append((lon_to_x(box[0], n), lon_to_x(box[2], n)))
            for a, b in spans:
                for tx in range(max(0, int(a) - k), min(n - 1, int(b) + k) + 1):
                    for dy in range(-k, k + 1) if rings else (0,):
                        yy = ty + dy
                        if 0 <= yy < n:
                            tiles.add((tx, yy))
        if box and rings:
            # laatta mukaan, jos se osuu laatikkoon (puskurilla laajennettuna): alueet menevät reunoilla limittäin
            dlat = buffer_m / 111320
            dlon = dlat / math.cos(math.radians((box[1] + box[3]) / 2))
            x0, x1 = lon_to_x(box[0] - dlon, n), lon_to_x(box[2] + dlon, n)
            y0, y1 = lat_to_y(min(85, box[3] + dlat), n), lat_to_y(box[1] - dlat, n)
            tiles = {(x, y) for x, y in tiles if x + 1 > x0 and x < x1 and y + 1 > y0 and y < y1}
        ids.extend(zxy_to_id(z, x, y) for x, y in tiles)
        print(f'  z{z}: {len(tiles)} laattaa', file=sys.stderr)
    ids.sort()
    return ids

# ---------- pääohjelma ----------


def geojson_rings(geom):
    polys = [geom['coordinates']] if geom['type'] == 'Polygon' else geom['coordinates']
    return [[(p[0], p[1]) for p in ring] for poly in polys for ring in poly]


def slug(s):
    t = s.lower()
    for a, b in (('ä', 'a'), ('ö', 'o'), ('å', 'a'), ('š', 's'), ('ž', 'z')):
        t = t.replace(a, b)
    return ''.join(c if c.isalnum() else '-' for c in t).strip('-')


def collect(src, h, root, want, threads):
    """Hakemistomerkinnät alueen laatoille; lehtihakemistot luetaan vain jos niiden id-väli osuu alueeseen."""
    found = []  # (tile_id, src_off, len)

    def walk(entries):
        leaves = []
        for i, (tid, off, ln, run) in enumerate(entries):
            nxt = entries[i + 1][0] if i + 1 < len(entries) else 1 << 62
            lo = bisect.bisect_left(want, tid)
            if run == 0:
                if lo < len(want) and want[lo] < nxt:
                    leaves.append((off, ln))
            else:
                hi = bisect.bisect_left(want, tid + run)
                for t in want[lo:hi]:
                    found.append((t, off, ln))
        if leaves:
            def get(l):
                return parse_dir(decompress(src.read(h['leaf_off'] + l[0], l[1]), h['icomp']))
            with ThreadPoolExecutor(threads) as ex:
                for sub in ex.map(get, leaves):
                    walk(sub)
    walk(root)
    found.sort()
    return found


def write_pmtiles(src, h, found, output, bounds, minz, maxz, threads, quiet=False):
    uniq = sorted({(off, ln) for _, off, ln in found})
    total = sum(ln for _, ln in uniq)
    # Uudet siirtymät samassa järjestyksessä kuin lähteessä (lähde on klusteroitu, joten tulos on myös).
    new_off = {}
    pos = 0
    for off, ln in uniq:
        new_off[off] = pos
        pos += ln
    tmp = output + '.data.tmp'
    # Yhdistä lähekkäiset haut (väli < 256 kt, enintään 16 MB kerralla).
    groups, cur = [], []
    for off, ln in uniq:
        if cur and (off - (cur[-1][0] + cur[-1][1]) > 262144 or off + ln - cur[0][0] > 16 << 20):
            groups.append(cur)
            cur = []
        cur.append((off, ln))
    if cur:
        groups.append(cur)
    if not quiet:
        print(f'Ladataan {len(groups)} osana…', file=sys.stderr)

    def fetch(g):
        blob = src.read(h['data_off'] + g[0][0], g[-1][0] + g[-1][1] - g[0][0])
        return [blob[o - g[0][0]:o - g[0][0] + l] for o, l in g]

    done = 0
    t0 = time.time()
    with open(tmp, 'wb') as out, ThreadPoolExecutor(threads) as ex:
        for parts in ex.map(fetch, groups):
            for p in parts:
                out.write(p)
            done += 1
            if not quiet and (done % 50 == 0 or done == len(groups)):
                mb = out.tell() / 1e6
                print(f'  {done}/{len(groups)} osaa, {mb:.0f} MB, {mb / max(1e-3, time.time() - t0):.1f} MB/s',
                      file=sys.stderr)
    assert os.path.getsize(tmp) == total

    # Hakemistot: peräkkäiset samaa sisältöä olevat laatat yhdeksi run-merkinnäksi.
    entries = []
    for tid, off, ln in found:
        no = new_off[off]
        if entries and entries[-1][1] == no and entries[-1][0] + entries[-1][3] == tid:
            e = entries[-1]
            entries[-1] = (e[0], e[1], e[2], e[3] + 1)
        else:
            entries.append((tid, no, ln, 1))
    leaf_size = 4096
    while True:
        leaves = bytearray()
        if len(entries) <= leaf_size:
            root_b = serialize_dir(entries)
        else:
            root_entries = []
            for i in range(0, len(entries), leaf_size):
                chunk = entries[i:i + leaf_size]
                b = serialize_dir(chunk)
                root_entries.append((chunk[0][0], len(leaves), len(b), 0))
                leaves += b
            root_b = serialize_dir(root_entries)
        if 127 + len(root_b) <= 16384:
            break
        leaf_size *= 2

    meta = decompress(src.read(h['meta_off'], h['meta_len']), h['icomp'])
    meta_b = gzip.compress(meta, compresslevel=9, mtime=0)
    w, s, e, n = bounds
    root_off = 127
    meta_off = root_off + len(root_b)
    leaf_off = meta_off + len(meta_b)
    data_off = leaf_off + len(leaves)
    hdr = HDR.pack(b'PMTiles', 3, root_off, len(root_b), meta_off, len(meta_b), leaf_off, len(leaves),
                   data_off, total, len(found), len(entries), len(uniq), 1, 2, h['tcomp'], h['ttype'], minz, maxz,
                   int(w * 1e7), int(s * 1e7), int(e * 1e7), int(n * 1e7),
                   max(minz, min(12, maxz)), int((w + e) / 2 * 1e7), int((s + n) / 2 * 1e7))
    with open(output, 'wb') as out:
        out.write(hdr)
        out.write(root_b)
        out.write(meta_b)
        out.write(leaves)
        with open(tmp, 'rb') as d:
            while True:
                c = d.read(8 << 20)
                if not c:
                    break
                out.write(c)
    os.remove(tmp)
    return os.path.getsize(output)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('source')
    ap.add_argument('output', help='tiedosto, tai --geojson-tilassa kansio')
    ap.add_argument('--poly', help='Geofabrikin .poly-raja')
    ap.add_argument('--box', help='minlon,minlat,maxlon,maxlat (rajaa --poly-alueen tähän laatikkoon)')
    ap.add_argument('--geojson', help='aluejako (esim. Tilastokeskuksen kunnat): yksi tiedosto kustakin alueesta')
    ap.add_argument('--name-field', default='nimi')
    ap.add_argument('--minzoom', type=int, default=0)
    ap.add_argument('--maxzoom', type=int, default=15)
    ap.add_argument('--buffer', type=float, default=3000, help='reunan puskuri metreinä (oletus 3000)')
    ap.add_argument('--dry-run', action='store_true', help='laske vain koko')
    ap.add_argument('--threads', type=int, default=8)
    a = ap.parse_args()

    src = Source(a.source)
    h = parse_header(src.read(0, 16384))
    root = parse_dir(decompress(src.read(h['root_off'], h['root_len']), h['icomp']))
    minz, maxz = max(a.minzoom, h['minz']), min(a.maxzoom, h['maxz'])
    print(f'Lähde: z{h["minz"]}–{h["maxz"]}, {h["n_addressed"]} laattaa.', file=sys.stderr)

    targets = []  # (nimi, renkaat, laatikko, tiedosto)
    if a.geojson:
        os.makedirs(a.output, exist_ok=True)
        for f in json.load(open(a.geojson))['features']:
            name = f['properties'][a.name_field]
            targets.append((name, geojson_rings(f['geometry']), None, os.path.join(a.output, slug(name) + '.pmtiles')))
    else:
        box = [float(v) for v in a.box.split(',')] if a.box else None
        rings = read_poly(a.poly) if a.poly else None
        if not rings and not box:
            raise SystemExit('anna --poly, --box tai --geojson')
        os.makedirs(os.path.dirname(a.output) or '.', exist_ok=True)
        targets.append((a.output, rings, box, a.output))

    sizes = []
    for name, rings, box, out in targets:
        quiet = len(targets) > 1
        if quiet:
            _err, sys.stderr = sys.stderr, io.StringIO()
        try:
            want = [t for t in needed_tiles(rings, box, maxz, a.buffer) if id_to_zxy(t)[0] >= minz]
            found = collect(src, h, root, want, a.threads)
            lons = [p[0] for r in rings for p in r] if rings else [box[0], box[2]]
            lats = [p[1] for r in rings for p in r] if rings else [box[1], box[3]]
            if box and rings:
                lons = [max(box[0], min(lons)), min(box[2], max(lons))]
                lats = [max(box[1], min(lats)), min(box[3], max(lats))]
            bounds = (min(lons), min(lats), max(lons), max(lats))
            uniq_bytes = sum(ln for off, ln in {(o, l) for _, o, l in found})
            if a.dry_run:
                size = uniq_bytes
            else:
                size = write_pmtiles(src, h, found, out, bounds, minz, maxz, a.threads, quiet)
        finally:
            if quiet:
                sys.stderr = _err
        sizes.append((name, len(found), size))
        print(f'{name}\t{len(found)}\t{size / 1e6:.1f} MB', flush=True)
    if len(sizes) > 1:
        tot = sum(s for _, _, s in sizes)
        print(f'YHTEENSÄ\t{sum(n for _, n, _ in sizes)}\t{tot / 1e6:.1f} MB', flush=True)


if __name__ == '__main__':
    main()
