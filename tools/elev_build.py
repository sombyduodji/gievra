#!/usr/bin/env python3
"""Korkeustiedostot (.elev) karttapaketeittain: Maanmittauslaitoksen korkeusmalli 10 m (2019) keskiarvoistetaan
noin 25 m:n ruudukoksi WGS84-koordinaateissa kunnan rajaavan laatikon alueelle (+300 m reunus).

Ajetaan GDAL-kontissa (tools/elev_fetch.py lataa aineiston ensin):

  docker run --rm -u $(id -u) -v $PWD:/w -w /w ghcr.io/osgeo/gdal:ubuntu-small-3.9.3 \\
      python3 tools/elev_build.py build/elev/dem10m/dem10m_direct.vrt build/maps/release/kartat.json build/elev/release

.elev-muoto, versio 2 (little-endian), luetaan lib/maps/elevation.dart:
  0   8  b'GVELEV2\0'
  8   4  leveys (sarakkeita), 12 4 korkeus (rivejä)
  16  8  länsireuna (°), 24 8 pohjoisreuna (°), 32 8 sarakkeen leveys (°), 40 8 rivin korkeus (°; rivit etelään)
  48  4  lohkon koko B (256), 52 4 loppuosan pituus (hakemisto + lohkot)
  56  …  hakemisto: (lohkoja + 1) × uint32 lohkojen alkukohdat hakemiston jälkeen; sitten lohkot riveittäin
         (B × B, reunoilla pienempi), kukin zlib(int16 ennustevirheet, ks. encode). Korkeus puolen metrin
         yksikköinä; -32768 = ei tietoa. Lohkoista luetaan vain ne, joiden yli reitti kulkee (vähän muistia
         isoillakin alueilla, esim. Inari).
Aineisto: © Maanmittauslaitos, Korkeusmalli 10 m (2019), CC BY 4.0.
"""
import json
import math
import os
import struct
import sys
import zlib

import numpy as np
from osgeo import gdal

gdal.UseExceptions()
STEP_M = 25.0
MARGIN_M = 300.0
NODATA = -32768


def encode(q: np.ndarray) -> bytes:
    """Ennustevirheet: jokainen arvo − (vasen + yläpuolinen − vasen yläkulma), ensimmäisellä rivillä − vasen,
    ensimmäisessä sarakkeessa − yläpuolinen. Laskut int16-kiertäen (lib/maps/elevation.dart tekee saman)."""
    q = q.astype(np.int32)
    L = np.zeros_like(q)
    L[:, 1:] = q[:, :-1]
    U = np.zeros_like(q)
    U[1:, :] = q[:-1, :]
    UL = np.zeros_like(q)
    UL[1:, 1:] = q[:-1, :-1]
    pred = L + U - UL
    pred[0, :] = L[0, :]
    pred[1:, 0] = U[1:, 0]
    r = ((q - pred + 32768) % 65536 - 32768).astype('<i2')
    return zlib.compress(r.tobytes(), 9)


BLOCK = 256


def build(vrt, bbox, out, step_m=None, src_nodata=-9999):
    w, s, e, n = bbox
    mid = (s + n) / 2
    step = step_m or STEP_M
    dlat = step / 111320.0
    dlon = step / (111320.0 * math.cos(math.radians(mid)))
    mlat = MARGIN_M / 111320.0
    mlon = MARGIN_M / (111320.0 * math.cos(math.radians(mid)))
    w, s, e, n = w - mlon, s - mlat, e + mlon, n + mlat
    cols = int(math.ceil((e - w) / dlon))
    rows = int(math.ceil((n - s) / dlat))
    parts = []
    valid = 0
    # Kaistoittain (BLOCK riviä kerrallaan): muisti pysyy pienenä isoillakin alueilla (esim. Huippuvuoret).
    for by in range(0, rows, BLOCK):
        bh = min(BLOCK, rows - by)
        top = n - by * dlat
        ds = gdal.Warp(
            '', vrt, format='MEM', dstSRS='EPSG:4326', outputBounds=(w, top - bh * dlat, w + cols * dlon, top),
            width=cols, height=bh, resampleAlg='average', srcNodata=src_nodata, dstNodata=-9999,
            outputType=gdal.GDT_Float32, multithread=True,
        )
        a = ds.GetRasterBand(1).ReadAsArray()
        ds = None
        q = np.where(a <= -9000, NODATA, np.clip(np.round(a * 2), -32767, 32767)).astype(np.int16)  # 0,5 m
        valid += int((q != NODATA).sum())
        for bx in range(0, cols, BLOCK):
            parts.append(encode(q[:, bx:bx + BLOCK]))
    offs = [0]
    for b in parts:
        offs.append(offs[-1] + len(b))
    body = struct.pack(f'<{len(offs)}I', *offs) + b''.join(parts)
    head = b'GVELEV2\0' + struct.pack('<II4dII', cols, rows, w, n, dlon, dlat, BLOCK, len(body))
    tmp = f'{out}.{os.getpid()}.osa'  # rinnakkaiset ajot eivät kirjoita samaan väliaikaiseen tiedostoon
    with open(tmp, 'wb') as f:
        f.write(head + body)
    os.replace(tmp, out)
    return cols, rows, valid


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('vrt')
    ap.add_argument('catalog')
    ap.add_argument('outdir')
    ap.add_argument('only', nargs='*', help='vain nämä tunnisteet')
    ap.add_argument('--step', type=float, default=STEP_M, help='ruudun koko metreinä (Suomi 25, Copernicus 30)')
    ap.add_argument('--src-nodata', type=float, default=-9999)
    a = ap.parse_args()
    only = set(a.only)
    os.makedirs(a.outdir, exist_ok=True)
    gdal.SetCacheMax(512 * 1024 * 1024)
    packs = json.load(open(a.catalog, encoding='utf-8'))['packs']
    for i, p in enumerate(packs):
        if only and p['id'] not in only:
            continue
        out = os.path.join(a.outdir, p['id'] + '.elev')
        if os.path.exists(out):
            continue
        cols, rows, valid = build(a.vrt, p['bbox'], out, a.step, a.src_nodata)
        print(f"{i + 1}/{len(packs)} {p['id']}: {cols}×{rows}, {100 * valid / (cols * rows):.0f} % tietoa, "
              f'{os.path.getsize(out) / 1024:.0f} kt', flush=True)


if __name__ == '__main__':
    main()
