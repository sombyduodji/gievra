#!/usr/bin/env python3
"""Maanmittauslaitoksen korkeusmalli 10 m (2019) paikallisesti: lataa FUNETin peilistä VRT-hakemiston ja kaikki sen
GeoTIFF-ruudut (noin 1 500 kpl, 14 Gt) kansioon, jatkaa keskeytyneestä. Aineisto: © Maanmittauslaitos, CC BY 4.0.

  tools/elev_fetch.py build/elev/dem10m
"""
import concurrent.futures as cf
import os
import re
import sys
import time
import urllib.request

BASE = 'https://www.nic.funet.fi/index/geodata/mml/dem10m/'
UA = {'User-Agent': 'gievra-elev-fetch'}


def get(url, path):
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=120) as r:
                size = int(r.headers.get('Content-Length') or 0)
                if os.path.exists(path) and size and os.path.getsize(path) == size:
                    return 'ok'
                tmp = path + '.osa'
                with open(tmp, 'wb') as f:
                    while chunk := r.read(1 << 20):
                        f.write(chunk)
                if size and os.path.getsize(tmp) != size:
                    raise IOError('katkesi')
                os.replace(tmp, path)
                return 'new'
        except Exception as e:  # noqa: BLE001
            if attempt == 4:
                return f'virhe {e}'
            time.sleep(3 * (attempt + 1))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    vrt = os.path.join(out, 'dem10m_direct.vrt')
    get(BASE + 'dem10m_direct.vrt', vrt)
    files = sorted(set(re.findall(r'<SourceFilename relativeToVRT="1">([^<]+)</SourceFilename>', open(vrt).read())))
    jobs = []
    for rel in files:
        path = os.path.join(out, rel.replace('//', '/'))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        jobs.append((BASE + rel.replace('//', '/'), path))
    done = 0
    with cf.ThreadPoolExecutor(6) as ex:
        for res in ex.map(lambda j: get(*j), jobs):
            done += 1
            if res.startswith('virhe'):
                print(res, flush=True)
            if done % 100 == 0:
                print(f'{done}/{len(jobs)}', flush=True)
    print(f'valmis {done}/{len(jobs)}')


if __name__ == '__main__':
    main()
