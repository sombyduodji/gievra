#!/usr/bin/env python3
"""Hallinnolliset rajat (kunnat ja maakunnat tai vastaavat) OpenStreetMap-aineistosta GeoJSONiksi karttapakettien
jakoa varten. Vain maan omat alueet: alueen sisäpiste on maan rajan (admin_level=2) sisällä.

  ~/.cache/gievra-geo/bin/python tools/osm_bounds.py sweden.osm.pbf --level 7 --region-level 4 > se.geojson

Tarvitsee pyosmiumin ja shapelyn (pip install osmium shapely). Rajat: © OpenStreetMap contributors, ODbL.
"""
import argparse
import json
import os
import sys
import tempfile

import osmium
from shapely import wkb
from shapely.geometry import mapping


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('pbf')
    ap.add_argument('--level', required=True, help='kuntataso (admin_level)')
    ap.add_argument('--region-level', required=True, help='aluetaso (admin_level), jolla kunnat ryhmitellään')
    ap.add_argument('--country', default=None, help='maan ISO-koodi (ISO3166-1), jos tiedostossa on useampi maa')
    ap.add_argument('--iso-prefix', default=None,
                    help='rajaa ISO3166-2-koodilla (esim. ES-), kun maan oma raja ei kokoonnu otteesta')
    ap.add_argument('--poly', default=None,
                    help='maan raja Geofabrikin .poly-tiedostosta, kun maan oma raja ei kokoonnu otteesta')
    ap.add_argument('--tolerance', type=float, default=0.0005, help='rajan yksinkertaistus asteina')
    a = ap.parse_args()

    fab = osmium.geom.WKBFactory()
    levels = {'2', a.level, a.region_level}
    areas = []
    # Solmujen sijainnit levylle (sparse_file_array): muisti pysyy pienenä myös isoilla mailla.
    # Levylle .pbf:n viereen: /tmp voi olla muistissa (tmpfs), jolloin iso indeksi kaataa ohjelman.
    idx = tempfile.NamedTemporaryFile(prefix='gievra-nodes-', dir=os.path.dirname(os.path.abspath(a.pbf)), delete=False)
    fp = (osmium.FileProcessor(a.pbf)
          .with_locations(f'sparse_file_array,{idx.name}')
          .with_areas(osmium.filter.TagFilter(('boundary', 'administrative'))))
    for o in fp.with_filter(osmium.filter.EntityFilter(osmium.osm.AREA)):
        if o.from_way():
            continue
        lv = o.tags.get('admin_level')
        if o.tags.get('boundary') != 'administrative' or lv not in levels:
            continue
        try:
            g = wkb.loads(fab.create_multipolygon(o), hex=True)
        except Exception as e:  # noqa: BLE001 (rikkinäinen tai vajaa relaatio)
            print(f'ohitettu {o.tags.get("name")}: {e}', file=sys.stderr)
            continue
        if not g.is_valid:
            g = g.buffer(0)
        areas.append({'level': lv, 'name': o.tags.get('name') or '', 'iso': o.tags.get('ISO3166-1') or '',
                      'iso2': o.tags.get('ISO3166-2') or '', 'en': o.tags.get('name:en'), 'geom': g,
                      'ref': o.tags.get('ref') or o.tags.get('ref:INE') or o.tags.get('ref:kommunenummer')
                      or o.tags.get('ref:se:kommun:kod') or ''})

    os.unlink(idx.name)
    if a.iso_prefix:
        def mine(x):
            return x['iso2'].startswith(a.iso_prefix)
    elif a.poly:
        from shapely.geometry import Polygon
        from shapely.ops import unary_union
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from map_extract import read_poly
        country = unary_union([Polygon(r).buffer(0) for r in read_poly(a.poly)])

        def mine(x):
            return country.contains(x['geom'].representative_point())
    else:
        countries = [x for x in areas if x['level'] == '2' and (a.country is None or x['iso'] == a.country)]
        if not countries:
            raise SystemExit('maan rajaa (admin_level=2) ei löytynyt')
        country = max(countries, key=lambda x: x['geom'].area)['geom']
        print(f'maa: {max(countries, key=lambda x: x["geom"].area)["name"]}', file=sys.stderr)

        def mine(x):
            return country.contains(x['geom'].representative_point())

    regions = [x for x in areas if x['level'] == a.region_level and mine(x)]
    feats = []
    for x in areas:
        if x['level'] != a.level or not mine(x):
            continue
        p = x['geom'].representative_point()
        reg = next((r for r in regions if r['geom'].contains(p)), None)
        g = x['geom'].simplify(a.tolerance, preserve_topology=True)
        feats.append({'type': 'Feature', 'properties': {
            'name': x['name'], 'ref': x['ref'], 'region': reg['name'] if reg else '',
            'region_en': (reg or {}).get('en'), 'en': x['en']}, 'geometry': mapping(g)})
    feats.sort(key=lambda f: (f['properties']['region'], f['properties']['name']))
    json.dump({'type': 'FeatureCollection', 'features': feats}, sys.stdout, ensure_ascii=False)
    print(f'{len(feats)} aluetta, {len(regions)} ryhmää', file=sys.stderr)


if __name__ == '__main__':
    main()
