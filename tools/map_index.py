#!/usr/bin/env python3
"""Maaluettelo maat.json: maat ja niiden karttaluetteloiden osoitteet GitHubin karttajulkaisuissa.

  tools/map_index.py fi=kartat-2026-11/kartat.json se=kartat-pohjola-2026-11/se.json ... > maat.json

Sovellus hakee tämän (lib/maps/map_store.dart, mapIndexUrl) ja sen jälkeen jokaisen maan luettelon.
"""
import argparse
import json
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('countries', nargs='+', help='maa=tagi/tiedosto')
    ap.add_argument('--repo', default='sombyduodji/gievra')
    a = ap.parse_args()
    out = {'format': 2, 'countries': []}
    for c in a.countries:
        cc, path = c.split('=', 1)
        out['countries'].append({'id': cc, 'catalog': f'https://github.com/{a.repo}/releases/download/{path}'})
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
    print()


if __name__ == '__main__':
    main()
