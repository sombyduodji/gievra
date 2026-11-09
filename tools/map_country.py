#!/usr/bin/env python3
"""Yhden maan karttapaketit ja luettelo (muoto 2): maan kartta (z0–15, tools/map_extract.py) jaetaan paikallisiin
alueisiin (kunnat, kommuner, council areas, provinciat …), tehdään yleiskartta (z0–10) ja luettelo <maa>.json.

  tools/map_country.py se build/maps/eu/country/sweden.pmtiles build/maps/eu/bounds/se.geojson \\
      build/maps/eu/poly/sweden.poly build/maps/eu/release/pohjola --tag kartat-pohjola-2026-11

Rajojen GeoJSON: ominaisuudet name ja region (tools/osm_bounds.py tai muu lähde). Paketit nimetään
<maa>-<nimi>.pmtiles (vain a–z, 0–9 ja -). Kartat: © OpenStreetMap contributors, ODbL.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from map_catalog import carry_old, sha256, simplify  # noqa: E402
from map_extract import geojson_rings  # noqa: E402

# Maiden nimet sovelluksen kielillä (fi, en, se) ja paikallisesti.
COUNTRIES = {
    'fi': {'fi': 'Suomi', 'en': 'Finland', 'se': 'Suopma', 'local': 'Suomi'},
    'se': {'fi': 'Ruotsi', 'en': 'Sweden', 'se': 'Ruoŧŧa', 'local': 'Sverige'},
    'no': {'fi': 'Norja', 'en': 'Norway', 'se': 'Norga', 'local': 'Norge'},
    'dk': {'fi': 'Tanska', 'en': 'Denmark', 'se': 'Dánmárku', 'local': 'Danmark'},
    'is': {'fi': 'Islanti', 'en': 'Iceland', 'se': 'Islánda', 'local': 'Ísland'},
    'gb': {'fi': 'Iso-Britannia', 'en': 'United Kingdom', 'se': 'Stuorra-Británnia', 'local': 'United Kingdom'},
    'es': {'fi': 'Espanja', 'en': 'Spain', 'se': 'Spánja', 'local': 'España'},
}
# Mitä paketit ovat (sovellus näyttää: "Valitse kunnat" tms.).
UNITS = {'se': 'kommun', 'no': 'kommune', 'dk': 'kommune', 'is': 'sveitarfélag', 'gb': 'council', 'es': 'provincia'}
GITHUB_MAX = 2 * 1024 ** 3 - 1  # GitHubin julkaisun tiedosto alle 2 GiB

_EXTRA = {'ø': 'o', 'æ': 'ae', 'å': 'a', 'ß': 'ss', 'þ': 'th', 'ð': 'd', 'ł': 'l', 'đ': 'd', 'ŧ': 't', 'ŋ': 'n',
          'œ': 'oe', 'ı': 'i'}


def ascii_slug(s):
    t = ''.join(_EXTRA.get(c, c) for c in s.lower())
    t = unicodedata.normalize('NFKD', t).encode('ascii', 'ignore').decode()
    return '-'.join(w for w in ''.join(c if c.isalnum() else '-' for c in t).split('-') if w)


def run(args):
    print('  $ ' + ' '.join(str(a) for a in args[1:4]) + ' …', file=sys.stderr, flush=True)
    subprocess.run(args, check=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('country', choices=sorted(COUNTRIES))
    ap.add_argument('source', help='maan kartta (z0–15)')
    ap.add_argument('bounds', help='alueet GeoJSON (name, region)')
    ap.add_argument('poly', help='maan raja (.poly) yleiskarttaa varten')
    ap.add_argument('out', help='julkaisukansio')
    ap.add_argument('--tag', required=True)
    ap.add_argument('--osm-date', default='2026-11-07')
    ap.add_argument('--repo', default='sombyduodji/gievra')
    ap.add_argument('--boundaries', default='© OpenStreetMap contributors (ODbL)', help='rajojen lähde')
    ap.add_argument('--tolerance', type=float, default=0.004)
    ap.add_argument('--extra', action='append', default=[], metavar='LÄHDE:RAJAT',
                    help='lisäalueet toisesta kartasta (esim. Kanariansaaret: canarias.pmtiles:es-canarias.geojson)')
    ap.add_argument('--overview-source', help='yleiskartan lähde (oletus: maan kartta), esim. Protomaps-planeetta')
    ap.add_argument('--catalog-only', action='store_true', help='älä pilko uudelleen, tee vain luettelo')
    ap.add_argument('--previous', help='edellisen julkaisun <maa>.json: sen tarkisteet sha256Old-listaan')
    a = ap.parse_args()
    cc = a.country
    tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'map_extract.py')
    os.makedirs(a.out, exist_ok=True)

    feats = json.load(open(a.bounds))['features']
    groups = [(a.source, feats)]
    for e in a.extra:
        src, geo = e.rsplit(':', 1)
        more = json.load(open(geo))['features']
        groups.append((src, more))
        feats = feats + more
    # Tunnisteet: <maa>-<nimi>; saman nimiset erotellaan alueen nimellä (esim. Herøy, Nordland / Møre og Romsdal).
    count = {}
    for f in feats:
        count[ascii_slug(f['properties']['name'])] = count.get(ascii_slug(f['properties']['name']), 0) + 1
    ids = set()
    for f in feats:
        pr = f['properties']
        base = ascii_slug(pr['name'])
        pid = f'{cc}-{base}' if count[base] == 1 else f'{cc}-{base}-{ascii_slug(pr.get("region") or pr.get("ref"))}'
        n = 2
        while pid in ids:
            pid, n = f'{pid}-{n}', n + 1
        ids.add(pid)
        pr['id'] = pid

    if not a.catalog_only:
        for src, part in groups:
            with tempfile.NamedTemporaryFile('w', suffix='.geojson', delete=False) as tmp:
                json.dump({'type': 'FeatureCollection', 'features': part}, tmp)
            run([sys.executable, tool, src, a.out, '--geojson', tmp.name, '--name-field', 'id', '--minzoom', '11'])
            os.unlink(tmp.name)
        # Yleiskartan raja: useampi .poly (pilkuin) yhdistetään yhdeksi tiedostoksi.
        polys = a.poly.split(',')
        poly = polys[0]
        if len(polys) > 1:
            with tempfile.NamedTemporaryFile('w', suffix='.poly', delete=False) as tmp:
                tmp.write('yhdistetty\n')
                for pf in polys:
                    lines = open(pf).read().strip().splitlines()
                    tmp.write('\n'.join(lines[1:-1]) + '\n')
                tmp.write('END\n')
            poly = tmp.name
        run([sys.executable, tool, a.overview_source or a.source, os.path.join(a.out, f'{cc}-yleiskartta.pmtiles'),
             '--poly', poly, '--maxzoom', '10'])
    whole = os.path.join(a.out, f'{cc}-koko.pmtiles')
    if not a.catalog_only and os.path.getsize(a.source) <= GITHUB_MAX and not os.path.exists(whole):
        os.link(a.source, whole) if os.stat(a.source).st_dev == os.stat(a.out).st_dev else run(['cp', a.source, whole])

    def entry(file):
        path = os.path.join(a.out, file)
        return {'file': file, 'size': os.path.getsize(path), 'sha256': sha256(path)}

    packs = []
    for f in feats:
        pr = f['properties']
        file = pr['id'] + '.pmtiles'
        if not os.path.exists(os.path.join(a.out, file)):
            print(f'puuttuu: {file}', file=sys.stderr)
            continue
        rings = geojson_rings(f['geometry'])
        shape = []
        for r in rings:
            s = simplify(r, a.tolerance)
            if len(s) >= 4:
                shape.append([[round(x, 4), round(y, 4)] for x, y in s])
        if not shape:  # pieni alue: laatikko riittää
            lo, la = [p[0] for r in rings for p in r], [p[1] for r in rings for p in r]
            shape = [[[min(lo), min(la)], [max(lo), min(la)], [max(lo), max(la)], [min(lo), max(la)], [min(lo), min(la)]]]
        lons = [p[0] for r in rings for p in r]
        lats = [p[1] for r in rings for p in r]
        e = entry(file)
        e.update({'id': pr['id'], 'name': pr['name'], 'en': pr.get('en') if pr.get('en') != pr['name'] else None,
                  'region': pr.get('region') or '',
                  'bbox': [round(min(lons), 4), round(min(lats), 4), round(max(lons), 4), round(max(lats), 4)],
                  'shape': shape})
        packs.append({k: v for k, v in e.items() if v is not None})
    packs.sort(key=lambda p: (p['region'], p['name']))
    out = {
        'format': 2,
        'country': cc,
        'names': COUNTRIES[cc],
        'unit': UNITS.get(cc, ''),
        'tag': a.tag,
        'osmDate': a.osm_date,
        'base': f'https://github.com/{a.repo}/releases/download/{a.tag}/',
        'attribution': '© OpenStreetMap contributors',
        'license': 'ODbL 1.0',
        'boundaries': a.boundaries,
        'overview': entry(f'{cc}-yleiskartta.pmtiles'),
        'regions': sorted({p['region'] for p in packs}),
        'packs': packs,
    }
    if os.path.exists(whole):
        out['all'] = entry(f'{cc}-koko.pmtiles')
    carry_old(out, a.previous)
    with open(os.path.join(a.out, f'{cc}.json'), 'w') as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(',', ':'))
    total = sum(p['size'] for p in packs)
    print(f'{cc}: {len(packs)} pakettia, {total / 1e9:.2f} GB, yleiskartta {out["overview"]["size"] / 1e6:.0f} MB',
          file=sys.stderr)


if __name__ == '__main__':
    main()
