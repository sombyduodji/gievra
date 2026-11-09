#!/usr/bin/env python3
"""Korkeustiedostot (.elev) karttapaketeittain: Maanmittauslaitoksen korkeusmalli 10 m (2019) keskiarvoistetaan
noin 25 m:n ruudukoksi WGS84-koordinaateissa kunnan rajaavan laatikon alueelle (+300 m reunus).

Ajetaan GDAL-kontissa (tools/elev_fetch.py lataa aineiston ensin):

  docker run --rm -u $(id -u) -v $PWD:/w -w /w ghcr.io/osgeo/gdal:ubuntu-small-3.9.3 \\
      python3 tools/elev_build.py build/elev/dem10m/dem10m_direct.vrt build/maps/release/kartat.json build/elev/release

.elev-muoto (little-endian), luetaan lib/maps/elevation.dart:
  0   8  b'GVELEV1\\0'
  8   4  leveys (sarakkeita), 12 4 korkeus (rivejä)
  16  8  länsireuna (°), 24 8 pohjoisreuna (°), 32 8 sarakkeen leveys (°), 40 8 rivin korkeus (°; rivit etelään)
  48  4  pakatun datan pituus (tavua)
  52  …  zlib(int16 ennustevirheet, ks. encode): korkeus puolen metrin yksikköinä riveittäin pohjoisesta;
         -32768 = ei tietoa (meri rajan ulkopuolella, naapurimaa)
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


def build(vrt, bbox, out):
    w, s, e, n = bbox
    mid = (s + n) / 2
    dlat = STEP_M / 111320.0
    dlon = STEP_M / (111320.0 * math.cos(math.radians(mid)))
    mlat = MARGIN_M / 111320.0
    mlon = MARGIN_M / (111320.0 * math.cos(math.radians(mid)))
    w, s, e, n = w - mlon, s - mlat, e + mlon, n + mlat
    cols = int(math.ceil((e - w) / dlon))
    rows = int(math.ceil((n - s) / dlat))
    ds = gdal.Warp(
        '', vrt, format='MEM', dstSRS='EPSG:4326', outputBounds=(w, n - rows * dlat, w + cols * dlon, n),
        width=cols, height=rows, resampleAlg='average', srcNodata=-9999, dstNodata=-9999, outputType=gdal.GDT_Float32,
        multithread=True,
    )
    a = ds.GetRasterBand(1).ReadAsArray()
    ds = None
    q = np.where(a <= -9000, NODATA, np.clip(np.round(a * 2), -32767, 32767)).astype(np.int16)  # 0,5 m
    valid = int((q != NODATA).sum())
    body = encode(q)
    head = b'GVELEV1\0' + struct.pack('<II4dI', cols, rows, w, n, dlon, dlat, len(body))
    with open(out + '.osa', 'wb') as f:
        f.write(head + body)
    os.replace(out + '.osa', out)
    return cols, rows, valid


def main():
    vrt, catalog, outdir = sys.argv[1:4]
    only = set(sys.argv[4:])
    os.makedirs(outdir, exist_ok=True)
    gdal.SetCacheMax(512 * 1024 * 1024)
    packs = json.load(open(catalog, encoding='utf-8'))['packs']
    for i, p in enumerate(packs):
        if only and p['id'] not in only:
            continue
        out = os.path.join(outdir, p['id'] + '.elev')
        if os.path.exists(out):
            continue
        cols, rows, valid = build(vrt, p['bbox'], out)
        print(f"{i + 1}/{len(packs)} {p['id']}: {cols}×{rows}, {100 * valid / (cols * rows):.0f} % tietoa, "
              f'{os.path.getsize(out) / 1024:.0f} kt', flush=True)


if __name__ == '__main__':
    main()
