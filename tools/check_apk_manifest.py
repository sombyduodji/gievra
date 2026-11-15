#!/usr/bin/env python3
"""Koonnin jälkeen: valmiin APK:n yhdistetyn manifestin luvat ja ulkoa avattavat osat (myös liitännäisten lisäämät).

Kaatuu, jos lista muuttuu. Tarkista silloin, onko uusi lupa tai osa tarpeen, ja päivitä
tools/apk_manifest_expected.txt tarkoituksella. Lähdemanifestin vastine: test/manifest_test.dart.
Käyttö: check_apk_manifest.py APK [--write]
"""
import glob, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXPECTED = os.path.join(HERE, 'apk_manifest_expected.txt')


def aapt2():
    sdk = os.environ.get('ANDROID_HOME') or os.path.expanduser('~/sdk/android')
    tools = sorted(glob.glob(os.path.join(sdk, 'build-tools', '*', 'aapt2')))
    if not tools:
        sys.exit('aapt2 puuttuu')
    return tools[-1]


def summary(apk):
    dump = subprocess.run([aapt2(), 'dump', 'xmltree', '--file', 'AndroidManifest.xml', apk],
                          check=True, capture_output=True, text=True).stdout
    out, cur = [], None
    kinds = ('uses-permission', 'activity', 'activity-alias', 'service', 'receiver', 'provider')

    def flush():
        if not cur:
            return
        kind, a = cur
        if kind == 'uses-permission':
            out.append(f"permission {a['name']}")
        elif a.get('exported') == 'true':
            guard = f" [{a['permission']}]" if 'permission' in a else ''
            out.append(f"exported {kind} {a['name']}{guard}")

    for line in dump.splitlines():
        m = re.match(r'\s*E: (\S+)', line)
        if m:
            flush()
            cur = (m.group(1), {}) if m.group(1) in kinds else None
            continue
        if cur:
            a = re.match(r'\s*A: http://schemas.android.com/apk/res/android:(\w+)\(0x\w+\)=(?:"([^"]*)"|(\S+))', line)
            if a and a.group(1) not in cur[1]:
                cur[1][a.group(1)] = a.group(2) if a.group(2) is not None else a.group(3)
    flush()
    return sorted(set(out))


def main():
    got = summary(sys.argv[1])
    if '--write' in sys.argv:
        open(EXPECTED, 'w').write('\n'.join(got) + '\n')
        return
    want = [l for l in open(EXPECTED).read().splitlines() if l and not l.startswith('#')]
    new, gone = sorted(set(got) - set(want)), sorted(set(want) - set(got))
    if new or gone:
        print('APK:n manifesti muuttui (tools/apk_manifest_expected.txt):', file=sys.stderr)
        for l in new:
            print(f'  + {l}', file=sys.stderr)
        for l in gone:
            print(f'  - {l}', file=sys.stderr)
        sys.exit(1)
    print(f'Manifesti OK ({len(got)} riviä)')


main()
