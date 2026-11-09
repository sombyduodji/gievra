#!/usr/bin/env python3
"""Copernicus DEM GLO-30 -ruudut (1° × 1°, Cloud Optimized GeoTIFF) AWS:n avoimesta ämpäristä copernicus-dem-30m:
lataa tiedostossa luetellut ruudut kansioon ja jatkaa keskeytyneestä. Tilillistä ei tarvita.

  tools/elev_fetch_cop.py build/elev/cop/need.txt build/elev/cop/tiles

Lisenssi: Copernicus DEM GLO-30 (Copernicus WorldDEM-30), vapaa käyttö, jakelu ja muokkaus; muokatun aineiston
mukana ilmoitus "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH
2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved" sekä vastuuvapauslauseke.
"""
import concurrent.futures as cf
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from elev_fetch import get  # noqa: E402

BASE = 'https://copernicus-dem-30m.s3.amazonaws.com/'


def main():
    names = [n.strip() for n in open(sys.argv[1]) if n.strip()]
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    jobs = [(f'{BASE}{n}/{n}.tif', os.path.join(out, n + '.tif')) for n in names]
    done = 0
    with cf.ThreadPoolExecutor(6) as ex:
        for res in ex.map(lambda j: get(*j), jobs):
            done += 1
            if res.startswith('virhe'):
                print(res, flush=True)
            if done % 50 == 0:
                print(f'{done}/{len(jobs)}', flush=True)
    print(f'valmis {done}/{len(jobs)}')


if __name__ == '__main__':
    main()
