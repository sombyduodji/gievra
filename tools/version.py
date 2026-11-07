#!/usr/bin/env python3
"""Gievran versio gitin tiedoista (sama malli kuin Sátni FST:ssä).

Versio on muotoa X.Y.Z.VVVVKKPP.N: X.Y.Z tiedostosta RELEASE_VERSION (julkaisun tagi vX.Y.Z), VVVVKKPP
viimeisimmän commitin päivä ja N monesko sen päivän commit se on. Sama commit saa saman version jokaisella
koneella. Committaamattomat muutokset: loppuun "+muokattu".
Androidin versionCode: päivämäärä * 100 + N (0.1.2.20261107.3 -> 2026110703), siksi N enintään 99.

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
        dates = git("log", "--format=%cd", "--date=format:%Y%m%d", "HEAD").split()
        date, number = dates[0], dates.count(dates[0])
        modified = git("status", "--porcelain", "--untracked-files=no") != ""
    except (OSError, subprocess.CalledProcessError, RuntimeError, IndexError) as e:
        print(f"Varoitus: versiota ei saatu gitistä ({e}), numero 0", file=sys.stderr)
        date, number, modified = datetime.date.today().strftime("%Y%m%d"), 0, True
    if number > 99:
        sys.exit(f"Päivällä {date} on yli 99 committia, versionCode ei riitä")
    name = f"{release}.{date}.{number}" + ("+muokattu" if modified else "")
    return name, int(date) * 100 + number


if __name__ == "__main__":
    name, code = version()
    if "--flutter" in sys.argv:
        print(f"--build-name={name} --build-number={code}")
    else:
        print(f"Versio: {name} ({code})")
