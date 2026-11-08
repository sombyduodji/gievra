#!/usr/bin/env python3
"""Karttapakettien luettelo (kartat.json) sovellukselle: jokaisen kuntapaketin nimi, maakunta, koko, tarkiste,
rajaava laatikko ja yksinkertaistettu raja (sovellus valitsee niillä paketit etäisyyden perusteella, laitteella).

  tools/map_catalog.py build/maps/release build/maps/kunnat-2026.geojson build/maps/maakunnat-2026.geojson \\
      --tag kartat-2026-11 --osm-date 2026-11-07 > build/maps/release/kartat.json

Kunta- ja maakuntarajat: Tilastokeskus, CC BY 4.0. Kartat: © OpenStreetMap contributors, ODbL.
"""
import argparse
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from map_extract import geojson_rings, slug  # noqa: E402

# Saamelaisalueen kuntien pohjoissaamenkieliset nimet.
SAMI = {'Utsjoki': 'Ohcejohka', 'Inari': 'Anár', 'Enontekiö': 'Eanodat', 'Sodankylä': 'Soađegilli'}


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()


def simplify(pts, tol):
    """Douglas–Peucker (asteina); renkaan alku ja loppu säilyvät."""
    if len(pts) < 4:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        (ax, ay), (bx, by) = pts[a], pts[b]
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        best, idx = -1.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            if l2 == 0:
                d = (px - ax) ** 2 + (py - ay) ** 2
            else:
                t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
                d = (ax + t * dx - px) ** 2 + (ay + t * dy - py) ** 2
            if d > best:
                best, idx = d, i
        if idx >= 0 and best > tol * tol:
            keep[idx] = True
            stack += [(a, idx), (idx, b)]
    return [p for p, k in zip(pts, keep) if k]


def inside(lon, lat, rings):
    c = False
    for r in rings:
        for i in range(len(r)):
            (x1, y1), (x2, y2) = r[i], r[i - 1]
            if (y1 > lat) != (y2 > lat) and lon < (x2 - x1) * (lat - y1) / (y2 - y1) + x1:
                c = not c
    return c


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('packs')
    ap.add_argument('kunnat')
    ap.add_argument('maakunnat')
    ap.add_argument('--tag', required=True)
    ap.add_argument('--osm-date', required=True)
    ap.add_argument('--repo', default='sombyduodji/gievra')
    ap.add_argument('--tolerance', type=float, default=0.004, help='rajan yksinkertaistus asteina (oletus 0,004)')
    a = ap.parse_args()

    regions = [(f['properties']['nimi'], geojson_rings(f['geometry'])) for f in json.load(open(a.maakunnat))['features']]

    def entry(file):
        p = os.path.join(a.packs, file)
        return {'file': file, 'size': os.path.getsize(p), 'sha256': sha256(p)}

    packs = []
    for f in json.load(open(a.kunnat))['features']:
        pr = f['properties']
        name = pr['nimi']
        file = slug(name) + '.pmtiles'
        if not os.path.exists(os.path.join(a.packs, file)):
            print(f'puuttuu: {file}', file=sys.stderr)
            continue
        rings = geojson_rings(f['geometry'])
        # Saaret pois, jos ne ovat pieniä: yksinkertaistettu raja riittää valintaan.
        shape = []
        for r in rings:
            s = simplify(r, a.tolerance)
            if len(s) >= 4:
                shape.append([[round(x, 4), round(y, 4)] for x, y in s])
        lons = [p[0] for r in rings for p in r]
        lats = [p[1] for r in rings for p in r]
        # Maakunta: kunnan pisteiden enemmistö (raja-alueen pisteet voivat osua naapuriin).
        votes = {}
        sample = rings[max(range(len(rings)), key=lambda i: len(rings[i]))]
        for x, y in sample[:: max(1, len(sample) // 25)]:
            for rn, rr in regions:
                if inside(x, y, rr):
                    votes[rn] = votes.get(rn, 0) + 1
        cx, cy = sum(lons) / len(lons), sum(lats) / len(lats)
        for rn, rr in regions:
            if inside(cx, cy, rr):
                votes[rn] = votes.get(rn, 0) + 3
        region = max(votes, key=votes.get) if votes else ''
        e = entry(file)
        e.update({
            'id': slug(name),
            'name': name,
            'sv': pr.get('namn') if pr.get('namn') != name else None,
            'se': SAMI.get(name),
            'code': pr.get('kunta'),
            'region': region,
            'bbox': [round(min(lons), 4), round(min(lats), 4), round(max(lons), 4), round(max(lats), 4)],
            'shape': shape,
        })
        packs.append({k: v for k, v in e.items() if v is not None})
    packs.sort(key=lambda p: (p['region'], p['name']))
    out = {
        'format': 1,
        'tag': a.tag,
        'osmDate': a.osm_date,
        'base': f'https://github.com/{a.repo}/releases/download/{a.tag}/',
        'attribution': '© OpenStreetMap contributors',
        'license': 'ODbL 1.0',
        'overview': entry('yleiskartta.pmtiles'),
        'all': entry('suomi.pmtiles'),
        'regions': sorted({p['region'] for p in packs}),
        'packs': packs,
    }
    json.dump(out, sys.stdout, ensure_ascii=False, separators=(',', ':'))
    print(f'{len(packs)} kuntaa, {sum(p["size"] for p in packs) / 1e9:.2f} GB', file=sys.stderr)


if __name__ == '__main__':
    main()
