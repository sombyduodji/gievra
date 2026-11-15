#!/usr/bin/env python3
"""Puhelimen lokin Dart-pino luettavaksi (julkaisuversion symbolit ovat erillään, ks. tools/build_apk.sh).

`flutter symbolize` ei lue uutta pinomuotoa (_kDartSnapshotText), joten osoitteet puretaan NDK:n
llvm-symbolizerilla. Käyttö: symbolize.py VERSIO loki.txt   (VERSIO = symbols/-kansion nimi)
"""
import glob, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
version, log = sys.argv[1], sys.argv[2]
sym = os.path.join(ROOT, 'symbols', version, 'app.android-arm64.symbols')
tools = sorted(glob.glob(os.path.expanduser('~/sdk/android/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-symbolizer')))
if not os.path.exists(sym) or not tools:
    sys.exit(f'puuttuu: {sym if not os.path.exists(sym) else "llvm-symbolizer (NDK)"}')
for line in open(log, errors='replace'):
    m = re.search(r'#(\d+) abs [0-9a-f]+ virt ([0-9a-f]+)', line)
    if not m:
        if 'asynchronous suspension' in line:
            print('<async>')
        continue
    out = subprocess.run([tools[-1], f'--obj={sym}', '--functions', f'0x{m[2]}'], capture_output=True, text=True).stdout
    fn, loc = (out.splitlines() + ['', ''])[:2]
    print(f'#{m[1]} {fn}  {loc.replace(os.path.expanduser("~"), "~")}')
