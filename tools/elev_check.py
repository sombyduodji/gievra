#!/usr/bin/env python3
"""Tarkistaa .elev-tiedostot (versio 2): otsake, hakemisto ja jokainen lohko puretaan; tulostaa satunnaisia pisteitä
(lon lat korkeus tiedosto) vertailua varten (gdallocationinfo -wgs84 lähteestä).

  tools/elev_check.py KANSIO [NÄYTTEITÄ] > pisteet.txt
"""
import glob
import os
import random
import struct
import sys
import zlib

import numpy as np


def blocks(path):
    b = open(path, 'rb').read()
    assert b[:8] == b'GVELEV2\0', 'otsake'
    w, h, west, north, dlon, dlat, B, n = struct.unpack('<II4dII', b[8:56])
    assert len(b) == 56 + n, 'pituus'
    bx, by = (w + B - 1) // B, (h + B - 1) // B
    nb = bx * by
    idx = struct.unpack(f'<{nb + 1}I', b[56:56 + 4 * (nb + 1)])
    start = 56 + 4 * (nb + 1)
    out = {}
    for i in range(nb):
        r = np.frombuffer(zlib.decompress(b[start + idx[i]:start + idx[i + 1]]), '<i2').astype(np.int32)
        cw = min(B, w - (i % bx) * B)
        ch = min(B, h - (i // bx) * B)
        r = r.reshape(ch, cw)
        q = np.zeros_like(r)
        q[0] = np.cumsum(r[0])
        for y in range(1, ch):
            q[y] = q[y - 1] + np.cumsum(r[y])
        out[i] = ((q + 32768) % 65536) - 32768
    return (w, h, west, north, dlon, dlat, B, bx), out


def main():
    files = sorted(glob.glob(os.path.join(sys.argv[1], '*.elev')))
    k = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    random.seed(1)
    bad = 0
    for f in files:
        if os.path.getsize(f) == 0:
            continue
        try:
            (w, h, west, north, dlon, dlat, B, bx), bl = blocks(f)
        except Exception as e:  # noqa: BLE001
            print(f'VIRHE {f}: {e}', file=sys.stderr)
            bad += 1
            continue
        for _ in range(k):
            x, y = random.randrange(w), random.randrange(h)
            v = bl[(y // B) * bx + x // B][y % B, x % B]
            if v != -32768:
                print(f'{west + (x + .5) * dlon:.6f} {north - (y + .5) * dlat:.6f} {v / 2} {os.path.basename(f)}')
    print(f'{len(files)} tiedostoa, {bad} virheellistä', file=sys.stderr)


if __name__ == '__main__':
    main()
