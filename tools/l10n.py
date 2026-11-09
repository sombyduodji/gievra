#!/usr/bin/env python3
"""Gievran käännökset: poimii t('…')-tekstit koodista ja päivittää assets/l10n/<kieli>.po-tiedostot.

  python3 tools/l10n.py            päivitä .po-tiedostot ja tulosta tilanne
  python3 tools/l10n.py --check    tarkista: paikkamerkit, puuttuvat, pohjoissaamen oikeinkirjoitus (Divvun)
  python3 tools/l10n.py --missing  luettele kääntämättömät

msgid on suomenkielinen teksti sellaisenaan. Käännöksen voi tehdä millä tahansa .po-editorilla (Poedit,
Weblate) tai tekstieditorilla. Ks. docs/kaannokset.md.
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dartstr import Lit, _read_string, _skip_ws_comments, groups, lex, line_of  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ['se', 'en']
HEADER = {
    'se': 'Gievra – Treenipäiväkirja: pohjoissaame (davvisámegiella)\n'
          'msgid = suomenkielinen alkuteksti. {0}, {1}… ovat muuttujia (kommentissa #. mitä ne ovat).\n'
          'Hárjehusaid (liikkeiden) namat ja .md-fiillaid sisdoallu leat ain suomagillii.',
    'en': 'Gievra – Treenipäiväkirja: English\n'
          'msgid = Finnish source text. {0}, {1}… are variables (the #. comment says what they are).\n'
          'Exercise names come from lib/exercise_names_en.dart; .md file contents stay in Finnish.',
}


def _args(src, i):
    """src[i] = '[' -> lista argumenttilausekkeita ylimmällä tasolla."""
    depth, j, start, out = 0, i, i + 1, []
    while True:
        c = src[j]
        if c in '\'"':
            from dartstr import _read_string
            j, _ = _read_string(src, j)
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                last = src[start:j].strip()
                if last:
                    out.append(last)
                return out
        elif c == ',' and depth == 1:
            out.append(src[start:j].strip())
            start = j + 1
        j += 1


def extract():
    """Palauttaa {msgid: {'refs': [...], 'args': [...]}} lähdekoodin järjestyksessä."""
    found = {}
    for path in sorted(glob.glob(f'{ROOT}/lib/**/*.dart', recursive=True)):
        rel = os.path.relpath(path, ROOT)
        src = open(path, encoding='utf-8').read()
        for m in re.finditer(r'(?:(?<=l10n\.)|(?<![A-Za-z0-9_.$]))(?:t|fi)\(', src):
            i = _skip_ws_comments(src, m.end())
            # Myös merkkijonon ${...}-lausekkeiden sisällä olevat t()-kutsut: luetaan literaalit suoraan.
            lits, j = [], i
            while j < len(src) and (src[j] in '\'"' or (src[j] == 'r' and src[j + 1] in '\'"')):
                end, parts = _read_string(src, j)
                lits.append(Lit(j, end, src[j:end], parts))
                j = _skip_ws_comments(src, end)
            if not lits:
                continue
            g = (i, lits[-1].end, lits)
            if any(l.interpolated for l in lits):
                print(f'VAROITUS {rel}:{line_of(src, i)}: t() sisältää $-muuttujan, käytä {{0}}', file=sys.stderr)
                continue
            msgid = ''.join(l.value for l in lits)
            k = _skip_ws_comments(src, g[1])
            args = []
            if src[k] == ',':
                k = _skip_ws_comments(src, k + 1)
                if src[k] == '[':
                    args = _args(src, k)
            e = found.setdefault(msgid, {'refs': [], 'args': args})
            e['refs'].append(f'{rel}:{line_of(src, i)}')
            if args and not e['args']:
                e['args'] = args
        # Data-luettelot, jotka näytetään käännettyinä t(arvo)-kutsulla: merkintä "// l10n: data" ennen
        # luetteloa poimii kaikki tekstit lauseen loppuun (;) asti.
        for m in re.finditer(r'// l10n: data', src):
            end = src.find(';\n', m.end())
            for lit in lex(src[m.end():end]):
                v = lit.value
                if lit.interpolated or not re.search(r'[^\W\d_]{2,}', v):
                    continue
                e = found.setdefault(v, {'refs': [], 'args': []})
                e['refs'].append(f'{rel}:{line_of(src, m.end() + lit.start)}')
    # Vammatilan aineisto (lib/injury_data.dart, generoitu): käännettävät kentät näytetään t()-kutsulla
    # (nimi, selitys, jänneohje ja liikekohtaiset muutosohjeet); liikkeiden nimet ja tunnisteet eivät.
    inj = os.path.join(ROOT, 'lib', 'injury_data.dart')
    if os.path.exists(inj):
        for v, ln in injury_texts(open(inj, encoding='utf-8').read()):
            e = found.setdefault(v, {'refs': [], 'args': []})
            e['refs'].append(f'lib/injury_data.dart:{ln}')
    return found


def injury_texts(src):
    """InjuryRegion(id, nimi, selitys, [vältettävät], {liike: muutosohje}, {liike: korvaava}, jänneohje, [suositellut]):
    palauttaa (teksti, rivi) nimelle, selitykselle, jänneohjeelle ja muutosohjeille."""
    body_start = src.find('const injuryRegions')
    tok = re.compile(r'"((?:[^"\\]|\\.)*)"|([\[\]{}(),:])')
    out = []
    starts = [m.start() for m in re.finditer(r'InjuryRegion\(', src[body_start:])]
    for i, st in enumerate(starts):
        a = body_start + st + len('InjuryRegion')
        b = body_start + starts[i + 1] if i + 1 < len(starts) else len(src)
        depth, top, maps, inmap, prev = 0, [], 0, None, None
        for m in tok.finditer(src, a, b):
            lit, p = m.group(1), m.group(2)
            if p:
                if p in '([{':
                    depth += 1
                    if p == '{':
                        maps += 1
                        inmap = maps
                elif p in ')]}':
                    depth -= 1
                    if p == '}':
                        inmap = None
                prev = p
                continue
            val = lit.encode().decode('unicode_escape').encode('latin-1').decode('utf-8') if '\\' in lit else lit
            ln = src.count('\n', 0, m.start()) + 1
            if depth == 1:
                top.append((val, ln))
            elif inmap == 1 and prev == ':' and val.strip():
                out.append((val, ln))
            prev = 'lit'
        out += [x for k, x in enumerate(top) if k in (1, 2, 3) and x[0].strip()]
    return out


def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')


def po_str(key, s):
    if '\n' in s.rstrip('\n') or len(s) > 70:
        lines = s.split('\n')
        chunks = []
        for n, ln in enumerate(lines):
            ln = ln + ('\n' if n < len(lines) - 1 else '')
            # rivitä ~70 merkin kohdalta välilyönneistä
            while len(ln) > 70:
                cut = ln.rfind(' ', 0, 70)
                if cut <= 0:
                    break
                chunks.append(ln[:cut + 1])
                ln = ln[cut + 1:]
            if ln:
                chunks.append(ln)
        return f'{key} ""\n' + '\n'.join(f'"{esc(c)}"' for c in chunks)
    return f'{key} "{esc(s)}"'


def read_po(path):
    """{msgid: (msgstr, fuzzy, translator_comments)}"""
    if not os.path.exists(path):
        return {}
    sys.path.insert(0, ROOT)
    out = {}
    cur = {'id': None, 'str': None, 'fuzzy': False, 'tc': []}
    field = None

    def flush():
        if cur['id'] is not None:
            out[cur['id']] = (cur['str'] or '', cur['fuzzy'], cur['tc'])
        cur.update(id=None, str=None, fuzzy=False, tc=[])

    def unq(s):
        s = s.strip()[1:-1]
        return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m[1], m[1]), s)

    for raw in open(path, encoding='utf-8'):
        line = raw.rstrip('\n')
        if not line.strip():
            flush()
            field = None
            continue
        if line.startswith('#~'):
            continue
        if line.startswith('#,'):
            cur['fuzzy'] = 'fuzzy' in line
            continue
        if line.startswith('# '):
            cur['tc'].append(line)
            continue
        if line.startswith('#'):
            continue
        if line.startswith('msgid '):
            cur['id'] = unq(line[6:])
            field = 'id'
        elif line.startswith('msgstr '):
            cur['str'] = unq(line[7:])
            field = 'str'
        elif line.startswith('"'):
            cur[field] += unq(line)
    flush()
    out.pop('', None)
    return out


def write_po(lang, found, old):
    path = f'{ROOT}/assets/l10n/{lang}.po'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = ['# ' + l for l in HEADER[lang].split('\n')]
    out += ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', f'"Language: {lang}\\n"', '']
    for msgid, e in found.items():
        s, fuzzy, tc = old.get(msgid, ('', False, []))
        out += tc
        for n, a in enumerate(e['args']):
            out.append(f'#. {{{n}}} = {a}')
        out.append('#: ' + ' '.join(e['refs'][:4]) + (' …' if len(e['refs']) > 4 else ''))
        if fuzzy:
            out.append('#, fuzzy')
        out.append(po_str('msgid', msgid))
        out.append(po_str('msgstr', s))
        out.append('')
    gone = [k for k, v in old.items() if k not in found and v[0]]
    for k in gone:
        out.append('#~ ' + po_str('msgid', k).replace('\n', '\n#~ '))
        out.append('#~ ' + po_str('msgstr', old[k][0]).replace('\n', '\n#~ '))
        out.append('')
    open(path, 'w', encoding='utf-8').write('\n'.join(out))
    return path


def check(lang, found, po):
    problems = 0
    words = set()
    for msgid in found:
        s = po.get(msgid, ('',))[0]
        if not s:
            continue
        a, b = sorted(set(re.findall(r'\{\d+\}', msgid))), sorted(set(re.findall(r'\{\d+\}', s)))
        if a != b:
            print(f'PAIKKAMERKIT eroavat: {msgid!r} -> {s!r}')
            problems += 1
        clean = re.sub(r'\{\d+\}|https?://\S+|\S+@\S+|\.\w+\b', ' ', s)
        words.update(w for w in re.findall(r"[^\W\d_]+(?:-[^\W\d_]+)*", clean) if len(w) > 1)
    if lang == 'en' and words:
        # Englannin oikoluku: hunspell (en_GB ja en_US; sana kelpaa, jos jompikumpi tuntee sen).
        import subprocess
        bad = set(words)
        for d in ('en_GB', 'en_US'):
            try:
                out = subprocess.run(['hunspell', '-d', d, '-l'], input='\n'.join(sorted(bad)), capture_output=True,
                                     text=True, check=False).stdout.split()
                bad &= set(out)
            except FileNotFoundError:
                print('hunspell ei käytettävissä')
                bad = set()
        if bad:
            print(f'hunspell ei tunnista ({len(bad)}): ' + ', '.join(sorted(bad)))
    if lang == 'se' and words:
        try:
            import libvoikko
            v = libvoikko.Voikko('se')
            bad = sorted(w for w in words if not v.spell(w))
            if bad:
                print(f'Divvun ei tunnista ({len(bad)}): ' + ', '.join(bad))
        except Exception as e:  # noqa: BLE001
            print('Divvun-oikoluku ei käytettävissä:', e)
    return problems


def main():
    found = extract()
    for lang in LANGS:
        path = f'{ROOT}/assets/l10n/{lang}.po'
        old = read_po(path)
        write_po(lang, found, old)
        po = read_po(path)
        done = sum(1 for k in found if po.get(k, ('',))[0])
        print(f'{lang}: {done}/{len(found)} käännetty ({100 * done // max(1, len(found))} %) -> {os.path.relpath(path, ROOT)}')
        if '--missing' in sys.argv:
            for k, e in found.items():
                if not po.get(k, ('',))[0]:
                    print(f'  {e["refs"][0]}: {k!r}')
        if '--check' in sys.argv and check(lang, found, po):
            sys.exit(1)


if __name__ == '__main__':
    main()
