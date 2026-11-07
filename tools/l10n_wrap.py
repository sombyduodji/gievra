#!/usr/bin/env python3
"""Kertakäyttöinen apu: käärii käyttöliittymätiedostojen suomenkieliset tekstit t('…')-kutsuihin.

  python3 tools/l10n_wrap.py lib/ui/home.dart ...

Merkkijono kääritään, jos se näyttää luonnolliselta kieleltä eikä ole tunniste (map-avain, vertailu, case,
RegExp, tiedostopolku, liikkeen nimi). $-muuttujat muuttuvat paikkamerkeiksi {0}, {1}…
Lopuksi poistetaan const-avainsanat, joista analysaattori valittaa (kääritty teksti ei ole vakio).
Tarkista tulos aina git diffillä.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dartstr import _skip_ws_comments, groups, lex  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FN = os.environ.get('L10N_FN', 't')  # esim. l10n.t tai l10n.fi
LINES = os.environ.get('L10N_LINES')  # esim. 680-880: kääri vain nämä rivit

NON_UI_BEFORE = re.compile(
    r'(?:==|!=|\bcase|\bimport|\bexport|\bpart|RegExp\(|startsWith\(|endsWith\(|contains\(|indexOf\(|split\(|'
    r'replaceAll\(|replaceFirst\(|File\(|Directory\(|join\(|Uri\.parse\(|DateFormat\(|_open\(|launchUrl\(|'
    r'getString\(|setString\(|getBool\(|setBool\(|key:|Key\(|ValueKey\(|\bt\(|\bfi\(|fill\(|named\(|heroTag:|restorationId:|'
    r'fileName:|mimeType:|exerciseByName\(|measureOf\(|catOf\(|family\(|\[)\s*$'
)


def exercise_names():
    src = open(f'{ROOT}/lib/exercises.dart', encoding='utf-8').read()
    names = set()
    for g in groups(src, lex(src)):
        v = ''.join(l.value for l in g[2])
        names.add(v)
    return names


def looks_ui(v):
    letters = re.findall(r'[A-Za-zÅÄÖåäöÁáČčĐđŊŋŠšŦŧŽž]{3,}', v)
    if not letters:
        return False
    if re.fullmatch(r'[a-z_][A-Za-z0-9_]*', v):  # tunniste
        return False
    if re.fullmatch(r'[\w./-]+\.(md|zip|png|db|fitnotes|json|txt|csv)', v):
        return False
    return ' ' in v.strip() or v[:1].isupper() or v.endswith(('…', '?', '!', '.'))


def wrap_file(path, names):
    src = open(path, encoding='utf-8').read()
    out, last, n, skipped = [], 0, 0, []
    lo, hi = (int(x) for x in LINES.split('-')) if LINES else (0, 10**9)
    for start, end, lits in groups(src, lex(src)):
        if not lo <= src.count('\n', 0, start) + 1 <= hi:
            continue
        before = src[max(0, start - 60):start]
        after_i = _skip_ws_comments(src, end)
        after = src[after_i:after_i + 2]
        plain = ''.join(l.value for l in lits)
        text_only = ''.join(p for l in lits for p in l.parts if isinstance(p, str))
        ternary = before.rstrip().endswith('?')
        if (not looks_ui(text_only) or NON_UI_BEFORE.search(before) or (after.startswith(':') and not ternary)
                or after.startswith('==')):
            continue
        if not any(l.interpolated for l in lits) and plain in names:
            continue
        # Rakennetaan malli ja argumentit
        tmpl, args = [], []
        bad = False
        for l in lits:
            for p in l.parts:
                if isinstance(p, str):
                    tmpl.append(p)
                else:
                    expr = p[1]
                    if "'" in expr or '"' in expr:
                        bad = True
                    tmpl.append('{%d}' % len(args))
                    args.append(expr)
        if bad:
            skipped.append(plain)
            continue
        t = ''.join(tmpl)
        lit = "'" + t.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n') + "'"
        if len(lit) > 100:  # pitkät tekstit useammalle riville
            words = re.split(r'(?<= )', t)
            chunks, cur = [], ''
            for w in words:
                if len(cur) + len(w) > 90 and cur:
                    chunks.append(cur)
                    cur = ''
                cur += w
            chunks.append(cur)
            lit = ' '.join("'" + c.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n') + "'"
                           for c in chunks)
        rep = f'{FN}({lit}' + (f', [{", ".join(args)}]' if args else '') + ')'
        out.append(src[last:start])
        out.append(rep)
        last = end
        n += 1
    out.append(src[last:])
    new = ''.join(out)
    if n:
        rel = os.path.relpath(os.path.join(ROOT, 'lib', 'l10n.dart'), os.path.dirname(path))
        imp = f"import '{rel}'" + (' as l10n;' if FN.startswith('l10n.') else ';')
        if "l10n.dart'" not in new:
            # viimeisen importin perään
            ms = list(re.finditer(r"^import '[^']+';\n", new, re.M))
            pos = ms[-1].end() if ms else 0
            new = new[:pos] + imp + '\n' + new[pos:]
        open(path, 'w', encoding='utf-8').write(new)
    return n, skipped


def fix_consts(paths):
    """Poistaa const-sanat, jotka estävät t()-kutsut. Toistetaan, kunnes virheet loppuvat."""
    for _ in range(40):
        r = subprocess.run(['dart', 'analyze', '--format=machine', *paths], capture_output=True, text=True, cwd=ROOT)
        errs = []
        for line in r.stdout.splitlines() + r.stderr.splitlines():
            f = line.split('|')
            if len(f) >= 8 and f[0] == 'ERROR' and f[2] in (
                'CONST_WITH_NON_CONSTANT_ARGUMENT', 'INVALID_CONSTANT', 'NON_CONSTANT_LIST_ELEMENT',
                'CONST_EVAL_METHOD_INVOCATION', 'NON_CONSTANT_DEFAULT_VALUE', 'CONST_INITIALIZED_WITH_NON_CONSTANT_VALUE',
                'NON_CONSTANT_MAP_VALUE', 'CONST_CONSTRUCTOR_PARAM_TYPE_MISMATCH', 'NON_CONSTANT_CASE_EXPRESSION'):
                errs.append((f[3], int(f[4]), int(f[5]), f[2]))
        if not errs:
            return True
        by_file = {}
        for path, ln, col, code in errs:
            by_file.setdefault(path, []).append((ln, col))
        changed = False
        for path, locs in by_file.items():
            src = open(path, encoding='utf-8').read()
            lines = src.split('\n')
            offs = []
            for ln, col in locs:
                offs.append(sum(len(x) + 1 for x in lines[:ln - 1]) + col - 1)
            kill = set()
            for off in offs:
                # lähin edeltävä 'const ', jonka sulkeiden sisällä virhe on
                for m in reversed(list(re.finditer(r'\bconst\s+', src[:off]))):
                    seg = src[m.end():off]
                    depth = seg.count('(') + seg.count('[') + seg.count('{') - seg.count(')') - seg.count(']') - seg.count('}')
                    if depth > 0 or m.end() == off:
                        kill.add((m.start(), m.end()))
                        break
            for s, e in sorted(kill, reverse=True):
                src = src[:s] + src[e:]
                changed = True
            open(path, 'w', encoding='utf-8').write(src)
        if not changed:
            for e in errs[:20]:
                print('KORJAA KÄSIN:', e)
            return False
    return False


if __name__ == '__main__':
    names = exercise_names()
    files = [os.path.abspath(p) for p in sys.argv[1:]]
    for f in files:
        n, sk = wrap_file(f, names)
        print(f'{os.path.relpath(f, ROOT)}: {n} tekstiä', ('; ohitettu (lainausmerkit ${}:ssä): ' + json.dumps(sk, ensure_ascii=False)) if sk else '')
    print('const-korjaus:', 'ok' if fix_consts(files) else 'jäi virheitä')
