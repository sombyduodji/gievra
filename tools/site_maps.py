#!/usr/bin/env python3
"""Kotisivun karttahaun luettelo site/kartat.json karttajulkaisujen luetteloista.

  tools/site_maps.py                      # hakee maat.json:n ja maiden luettelot GitHubista
  tools/site_maps.py --dir build/maps/cat # tai paikallisista tiedostoista (maat.json + luettelot samassa kansiossa)

Selain ei voi lukea GitHubin julkaisutiedostoja suoraan (ei CORS-otsakkeita), joten kotisivu käyttää tätä
kevyttä luetteloa: nimi, muut nimet, alue, koko ja latausosoite, ei aluerajoja. Aja uudelleen, kun
karttajulkaisu päivittyy, ja commitoi site/kartat.json ja site/kartat-tarkisteet.json.

kartat-tarkisteet.json: kaikkien karttajulkaisujen (myös vanhojen) .pmtiles-tiedostojen SHA-256 GitHubin omista
tarkisteista (API:n digest-kenttä). Sovellus tuo sen kuten kartan ja tarkistaa kartat sillä ilman verkkoa.
"""
import argparse
import json
import os
import sys
import time
import urllib.request

INDEX = 'https://github.com/sombyduodji/gievra/releases/download/kartat-2026-11/maat.json'
RELEASES = 'https://api.github.com/repos/sombyduodji/gievra/releases?per_page=100&page={}'
FINLAND = {'fi': 'Suomi', 'en': 'Finland', 'se': 'Suopma', 'local': 'Suomi'}


def get(url, local_dir):
    if local_dir:
        return json.load(open(os.path.join(local_dir, url.rsplit('/', 1)[1]), encoding='utf-8'))
    for i in range(5):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'gievra-site-maps'})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:  # GitHub vastaa välillä 502/504
            if i == 4:
                raise
            print(f'{url}: {e}, uusi yritys', file=sys.stderr)
            time.sleep(5 * (i + 1))


def checksums():
    """[[tiedosto, sha256, koko, tagi], ...] kaikista karttajulkaisuista (GitHubin digest-kenttä)."""
    out = []
    for page in range(1, 20):
        req = urllib.request.Request(RELEASES.format(page), headers={
            'User-Agent': 'gievra-site-maps', 'Accept': 'application/vnd.github+json'})
        with urllib.request.urlopen(req, timeout=60) as r:
            releases = json.load(r)
        for rel in releases:
            if not rel['tag_name'].startswith('kartat'):
                continue
            for a in rel['assets']:
                d = a.get('digest') or ''
                if a['name'].endswith('.pmtiles') and d.startswith('sha256:'):
                    out.append([a['name'], d[7:], a['size'], rel['tag_name']])
        if len(releases) < 100:
            break
    out.sort(key=lambda e: (e[0], e[3]))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dir', help='paikallinen kansio, jossa maat.json ja maiden luettelot')
    ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), '..', 'site', 'kartat.json'))
    ap.add_argument('--sums', default=os.path.join(os.path.dirname(__file__), '..', 'site', 'kartat-tarkisteet.json'))
    a = ap.parse_args()
    index = get(INDEX, a.dir)
    out = {'format': 1, 'countries': []}
    dates = set()
    for c in index['countries']:
        cat = get(c['catalog'], a.dir)
        dates.add(cat.get('osmDate', ''))
        names = cat.get('names') or FINLAND
        packs = []
        for p in sorted(cat['packs'], key=lambda p: p['name']):
            alt = [p[k] for k in ('sv', 'se', 'en') if p.get(k) and p[k] != p['name']]
            packs.append([p['name'], ' · '.join(alt), p.get('region', ''), p['size'], p['file']])
        ov = cat['overview']
        out['countries'].append({
            'id': c['id'], 'names': names, 'unit': cat.get('unit', 'kunta'), 'base': cat['base'],
            'overview': [ov['file'], ov['size']], 'packs': packs,
        })
    out['osmDate'] = max(dates)
    with open(a.out, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')
    sums = checksums()
    with open(a.sums, 'w', encoding='utf-8') as f:
        json.dump({'format': 'gievra-kartat-tarkisteet', 'version': 1, 'osmDate': out['osmDate'], 'files': sums},
                  f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')
    print(f'{a.sums}: {len(sums)} tarkistetta')
    n = sum(len(c['packs']) for c in out['countries'])
    print(f'{a.out}: {len(out["countries"])} maata, {n} karttaa, {os.path.getsize(a.out) // 1024} kt')


if __name__ == '__main__':
    main()
