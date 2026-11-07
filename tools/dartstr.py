"""Dart-lähdekoodin merkkijonojen lukija käännöstyökaluille (tools/l10n.py, tools/l10n_wrap.py).

lex(src) palauttaa merkkijonoliteraalit (alku, loppu, raaka teksti, arvo, interpoloinnit) ja ohittaa kommentit.
"""
import re

ESC = {'n': '\n', 't': '\t', 'r': '\r', "'": "'", '"': '"', '\\': '\\', '$': '$', 'b': '\b'}


class Lit:
    def __init__(self, start, end, raw, parts):
        self.start, self.end, self.raw = start, end, raw
        # parts: lista str (vakioteksti) tai ('expr', lähdeteksti)
        self.parts = parts

    @property
    def interpolated(self):
        return any(isinstance(p, tuple) for p in self.parts)

    @property
    def value(self):
        return ''.join(p if isinstance(p, str) else '${' + p[1] + '}' for p in self.parts)


def _skip_ws_comments(src, i):
    n = len(src)
    while i < n:
        if src[i].isspace():
            i += 1
        elif src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j + 1
        elif src.startswith('/*', i):
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
        else:
            break
    return i


def _read_string(src, i):
    """src[i] on lainausmerkki tai r. Palauttaa (loppu, parts)."""
    raw = False
    if src[i] == 'r':
        raw = True
        i += 1
    q = src[i]
    triple = src.startswith(q * 3, i)
    delim = q * 3 if triple else q
    i += len(delim)
    parts, buf = [], []
    n = len(src)
    while i < n:
        if src.startswith(delim, i):
            if buf:
                parts.append(''.join(buf))
            return i + len(delim), parts
        c = src[i]
        if c == '\\' and not raw:
            nx = src[i + 1]
            if nx == 'u':
                if src[i + 2] == '{':
                    j = src.index('}', i)
                    buf.append(chr(int(src[i + 3:j], 16)))
                    i = j + 1
                else:
                    buf.append(chr(int(src[i + 2:i + 6], 16)))
                    i += 6
                continue
            if nx == 'x':
                buf.append(chr(int(src[i + 2:i + 4], 16)))
                i += 4
                continue
            buf.append(ESC.get(nx, nx))
            i += 2
            continue
        if c == '$' and not raw:
            if buf:
                parts.append(''.join(buf))
                buf = []
            if src[i + 1] == '{':
                depth, j = 1, i + 2
                while depth:
                    ch = src[j]
                    if ch in '\'"':
                        j, _ = _read_string(src, j)
                        continue
                    if ch == '{':
                        depth += 1
                    elif ch == '}':
                        depth -= 1
                    j += 1
                parts.append(('expr', src[i + 2:j - 1]))
                i = j
            else:
                m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', src[i + 1:])
                if not m:  # esim. tietueen kenttä $2 lausekkeen sisällä
                    buf.append(c)
                    i += 1
                    continue
                parts.append(('expr', m.group(0)))
                i += 1 + len(m.group(0))
            continue
        buf.append(c)
        i += 1
    raise ValueError('päättymätön merkkijono')


def lex(src):
    """Kaikki merkkijonoliteraalit järjestyksessä. Vierekkäiset literaalit ('a' 'b') ovat erillisiä."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i) or src.startswith('/*', i):
            i = _skip_ws_comments(src, i)
            continue
        if c in '\'"' or (c == 'r' and i + 1 < n and src[i + 1] in '\'"' and not (src[i - 1].isalnum() or src[i - 1] == '_')):
            end, parts = _read_string(src, i)
            out.append(Lit(i, end, src[i:end], parts))
            i = end
            continue
        i += 1
    return out


def groups(src, lits):
    """Yhdistää vierekkäiset literaalit ('a' 'b') ryhmiksi: lista (alku, loppu, [Lit])."""
    res = []
    for l in lits:
        if res and _skip_ws_comments(src, res[-1][1]) == l.start:
            res[-1] = (res[-1][0], l.end, res[-1][2] + [l])
        else:
            res.append((l.start, l.end, [l]))
    return res


def line_of(src, pos):
    return src.count('\n', 0, pos) + 1
