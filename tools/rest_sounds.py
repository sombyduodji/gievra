#!/usr/bin/env python3
"""Palautusajastimen äänet (android/app/src/main/res/raw/rest_*.wav).

Syntetisoitu tällä skriptillä: ei kolmannen osapuolen äänitiedostoja eikä lisenssejä (oma työ, GPL-3.0 kuten
sovellus). Lyhyitä ja pehmeitä: nopea nousu, eksponentiaalinen vaimeneminen, ei säröä.

  python3 tools/rest_sounds.py
"""
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "android/app/src/main/res/raw")


def tone(freq, dur, decay, partials=((1, 1.0),), glide=0.0):
    t = np.arange(int(RATE * dur)) / RATE
    f = freq * (1 + glide * t / dur)  # liukuma (boop)
    phase = 2 * np.pi * np.cumsum(f) / RATE
    s = sum(a * np.sin(k * phase) for k, a in partials)
    env = np.exp(-t / decay) * np.minimum(1, t / 0.008)  # 8 ms nousu: ei naksahdusta
    return s * env


def seq(*parts):
    """(alkuaika s, ääni) -> yksi raita."""
    end = max(start + len(x) / RATE for start, x in parts)
    out = np.zeros(int(RATE * end) + 1)
    for start, x in parts:
        i = int(RATE * start)
        out[i:i + len(x)] += x
    return out


def save(name, s, gain=0.55):
    s = s / np.max(np.abs(s)) * gain
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, f"rest_{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((s * 32767).astype("<i2").tobytes())


bell = ((1, 1.0), (2, 0.25), (3, 0.08))
# Pling: kaksi nousevaa kellosäveltä (E6 -> A6).
save("pling", seq((0, tone(1318.5, 0.6, 0.18, bell)), (0.14, tone(1760, 0.9, 0.25, bell))))
# Boop: pehmeä matala sävel, joka liukuu hieman alas.
save("boop", seq((0, tone(440, 0.45, 0.12, ((1, 1.0), (2, 0.12)), glide=-0.25)),
                 (0.22, tone(330, 0.5, 0.14, ((1, 1.0), (2, 0.12)), glide=-0.2))))
# Kilahdus: pehmeä kolmisointu (C6, E6, G6) peräkkäin.
save("chime", seq((0, tone(1046.5, 1.0, 0.3, bell)), (0.12, tone(1318.5, 1.0, 0.3, bell)),
                  (0.24, tone(1568, 1.2, 0.35, bell))), gain=0.5)
print("ok", sorted(os.listdir(OUT)))
