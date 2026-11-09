#!/usr/bin/env python3
"""Lisää karttaluetteloon (kartat.json) korkeustiedostot: jokaiselle kunnalle, jolle kansiossa on <id>.elev, kenttä
"elev": {file, size, sha256} ja edellisen luettelon tarkisteet (sha256Old), sekä aineiston nimeäminen.

  tools/elev_catalog.py build/maps/release/kartat.json build/elev/release [--previous vanha.json] > uusi.json
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from map_catalog import sha256  # noqa: E402

ELEV_ATTRIBUTION = 'Korkeusmalli 10 m © Maanmittauslaitos 2019, CC BY 4.0'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('catalog')
    ap.add_argument('elevdir')
    ap.add_argument('--previous', help='edellinen luettelo: korkeustiedostojen vanhat tarkisteet sha256Old-listaan')
    a = ap.parse_args()
    out = json.load(open(a.catalog, encoding='utf-8'))
    old = {}
    if a.previous:
        for p in json.load(open(a.previous, encoding='utf-8')).get('packs', []):
            if e := p.get('elev'):
                old[e['file']] = [e['sha256'], *e.get('sha256Old', [])]
    n = total = 0
    for p in out['packs']:
        f = p['id'] + '.elev'
        path = os.path.join(a.elevdir, f)
        if not os.path.exists(path):
            p.pop('elev', None)
            print(f'ei korkeustietoja: {f}', file=sys.stderr)
            continue
        e = {'file': f, 'size': os.path.getsize(path), 'sha256': sha256(path)}
        hist = [h for h in dict.fromkeys(old.get(f, [])) if h != e['sha256']][:5]
        if hist:
            e['sha256Old'] = hist
        p['elev'] = e
        n += 1
        total += e['size']
    out['elevAttribution'] = ELEV_ATTRIBUTION
    json.dump(out, sys.stdout, ensure_ascii=False, separators=(',', ':'))
    print(f'{n} korkeustiedostoa, {total / 1e6:.0f} Mt', file=sys.stderr)


if __name__ == '__main__':
    main()
