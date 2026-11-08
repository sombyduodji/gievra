#!/usr/bin/env python3
"""Iso-Britannian paikallishallinnon alueet (Local Authority Districts, ONS) karttapakettien jakoon: GeoJSON, jossa
name ja region (Englannissa alue, muuten Scotland, Wales tai Northern Ireland).

  tools/ons_bounds.py uk-lad.geojson uk-rgn.json > gb.geojson

Lähteet (ONS Open Geography Portal, Open Government Licence v3.0):
  Local_Authority_Districts_December_2024_Boundaries_UK_BUC (FeatureServer, f=geojson)
  LAD24_RGN24_EN_LU (FeatureServer, f=json)
"""
import json
import sys

NATIONS = {'S': 'Scotland', 'W': 'Wales', 'N': 'Northern Ireland'}


def main():
    lad, lookup = sys.argv[1], sys.argv[2]
    rgn = {f['attributes']['LAD24CD']: f['attributes']['RGN24NM'] for f in json.load(open(lookup))['features']}
    feats = []
    for f in json.load(open(lad))['features']:
        pr = f['properties']
        code = pr['LAD24CD']
        region = rgn.get(code) or NATIONS.get(code[0], '')
        if not region:
            print(f'alue puuttuu: {code} {pr["LAD24NM"]}', file=sys.stderr)
        feats.append({'type': 'Feature', 'geometry': f['geometry'],
                      'properties': {'name': pr['LAD24NM'], 'ref': code, 'region': region}})
    feats.sort(key=lambda f: (f['properties']['region'], f['properties']['name']))
    json.dump({'type': 'FeatureCollection', 'features': feats}, sys.stdout, ensure_ascii=False)
    print(f'{len(feats)} aluetta', file=sys.stderr)


if __name__ == '__main__':
    main()
