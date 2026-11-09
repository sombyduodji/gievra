#!/usr/bin/env python3
"""Gievran versio gitin tiedoista (sama malli kuin Sátni FST:ssä).

Versio on muotoa X.Y.Z.VVVVKKPP.N: X.Y.Z tiedostosta RELEASE_VERSION (julkaisun tagi vX.Y.Z), VVVVKKPP
viimeisimmän commitin päivä ja N commitin kellonaika vartteina keskiyöstä (0–95). Sama commit saa saman version
jokaisella koneella. Committaamattomat muutokset: loppuun "+muokattu".
Androidin versionCode: päivämäärä * 100 + N (0.4.2.20261109.50 -> 2026110950).

N on kellonaika eikä päivän committien määrä (muutettu 9.11.2026), koska julkaisuhaara (julkaisu) on eri historia
kuin dev: julkaisun commiteja on päivässä vähän, dev-testiversioita paljon, ja julkaisu ei asentunut saman päivän
testiversion päälle (pienempi versionCode). Kellonaika kasvaa molemmissa haaroissa samassa järjestyksessä.

  python3 tools/version.py          tulostaa version ja versionCoden
  python3 tools/version.py --flutter   tulostaa flutter build -argumentit
"""
import datetime
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, check=True).stdout


def version():
    release = open(os.path.join(ROOT, "RELEASE_VERSION"), encoding="utf-8").read().strip()
    try:
        if git("rev-parse", "--is-shallow-repository").strip() == "true":
            raise RuntimeError("git-historia on vajaa (shallow clone)")
        date, hhmm = git("log", "-1", "--format=%cd", "--date=format:%Y%m%d %H%M", "HEAD").split()
        number = (int(hhmm[:2]) * 60 + int(hhmm[2:])) // 15
        modified = git("status", "--porcelain", "--untracked-files=no") != ""
    except (OSError, subprocess.CalledProcessError, RuntimeError, IndexError) as e:
        print(f"Varoitus: versiota ei saatu gitistä ({e}), numero 0", file=sys.stderr)
        date, number, modified = datetime.date.today().strftime("%Y%m%d"), 0, True
    name = f"{release}.{date}.{number}" + ("+muokattu" if modified else "")
    return name, int(date) * 100 + number


if __name__ == "__main__":
    name, code = version()
    if "--flutter" in sys.argv:
        print(f"--build-name={name} --build-number={code}")
    else:
        print(f"Versio: {name} ({code})")
