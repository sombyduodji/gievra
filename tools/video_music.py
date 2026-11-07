#!/usr/bin/env python3
"""Taustamusiikki esittelyvideoon: reipas, salimainen elektroninen biisi (124 BPM).

Syntetisoitu tällä skriptillä (oma työ, GPL-3.0 kuten sovellus): ei kolmannen osapuolen äänitiedostoja eikä
lisenssiehtoja. Basari ja virvelin tilalla taputus, hi-hatit, basso ja sointumatto (Am–F–C–G), alussa
rauhallinen johdanto ja lopussa häivytys.

  python3 tools/video_music.py --seconds 110 --out musiikki.wav
"""
import argparse
import wave

import numpy as np

RATE = 44100
BPM = 124
BEAT = 60 / BPM


def env(n, attack, decay):
    t = np.arange(n) / RATE
    return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-t / decay)


def kick():
    n = int(RATE * .35)
    t = np.arange(n) / RATE
    f = 45 + 110 * np.exp(-t / .03)  # nopea taajuuden lasku
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * env(n, .002, .12)


def clap(rng):
    n = int(RATE * .2)
    noise = rng.uniform(-1, 1, n)
    # Kaistanpäästö karkeasti: erotus tasoittaa matalat.
    noise = np.diff(np.concatenate([[0], noise]))
    e = env(n, .001, .06)
    for d in (.0, .012, .024):  # kolme nopeaa iskua
        i = int(d * RATE)
        e[i:] += .5 * env(n - i, .001, .05)
    return noise * e * .35


def hat(rng, open_=False):
    n = int(RATE * (.18 if open_ else .05))
    noise = rng.uniform(-1, 1, n)
    noise = np.diff(np.concatenate([[0], np.diff(np.concatenate([[0], noise]))]))  # korkeat
    return noise * env(n, .001, .06 if open_ else .015) * .12


def tone(freq, dur, wave_="saw", attack=.005, decay=.3, cutoff=None):
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    ph = (freq * t) % 1
    if wave_ == "saw":
        x = 2 * ph - 1
    elif wave_ == "square":
        x = np.where(ph < .5, 1.0, -1.0)
    else:
        x = np.sin(2 * np.pi * freq * t)
    if cutoff:  # yksinkertainen alipäästö (liukuva keskiarvo)
        k = max(1, int(RATE / cutoff))
        x = np.convolve(x, np.ones(k) / k, mode="same")
    return x * env(n, attack, decay)


def note(name):
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    octave = int(name[-1])
    return 440 * 2 ** ((names[name[0]] + (octave - 4) * 12 - 9) / 12)


def add(buf, x, at, gain=1.0):
    i = int(at * RATE)
    if i >= len(buf):
        return
    x = x[: len(buf) - i]
    buf[i:i + len(x)] += x * gain


def song(seconds):
    rng = np.random.default_rng(7)
    L = np.zeros(int(RATE * (seconds + 1)))
    R = np.zeros_like(L)
    chords = [("A2", ["A3", "C4", "E4"]), ("F2", ["F3", "A3", "C4"]), ("C3", ["C4", "E4", "G4"]),
              ("G2", ["G3", "B3", "D4"])]
    bars = int(seconds / (4 * BEAT)) + 1
    for bar in range(bars):
        t0 = bar * 4 * BEAT
        bass, pad = chords[bar % 4]
        intro = bar < 2
        for b in range(4):
            tb = t0 + b * BEAT
            if not intro:
                add(L, kick(), tb, .9)
                add(R, kick(), tb, .9)
                if b in (1, 3):
                    c = clap(rng)
                    add(L, c, tb, .8)
                    add(R, c, tb + .004, .8)
            for h in (0, .5):  # kahdeksasosat, avoin hi-hat taukoiskulla
                x = hat(rng, open_=h == .5 and b % 2 == 1)
                add(L, x, tb + h * BEAT, .9)
                add(R, x, tb + h * BEAT + .002, 1.1)
            # Basso kahdeksasosina, oktaavihyppy offbeatilla.
            for h, mult in ((0, 1), (.5, 2)):
                x = tone(note(bass) * mult, BEAT * .45, "square", decay=.12, cutoff=900)
                add(L, x, tb + h * BEAT, .22 if not intro else .12)
                add(R, x, tb + h * BEAT, .22 if not intro else .12)
        # Sointumatto koko tahdin ajan, hieman leveä stereo.
        for k, n_ in enumerate(pad):
            x = tone(note(n_), 4 * BEAT, "saw", attack=.25, decay=3.0, cutoff=1800)
            add(L, x, t0, .05 * (1.1 if k == 0 else .9))
            add(R, x, t0 + .01, .05 * (.9 if k == 0 else 1.1))
        # Melodia-arpeggio joka toisessa tahdissa johdannon jälkeen.
        if not intro and bar % 2 == 1:
            for s in range(8):
                n_ = pad[s % 3]
                x = tone(note(n_) * 2, BEAT * .4, "sine", decay=.15)
                add(L, x, t0 + s * BEAT / 2, .07)
                add(R, x, t0 + s * BEAT / 2 + .03, .07)
    out = np.stack([L, R], 1)[: int(RATE * seconds)]
    # Häivytys alussa 1 s ja lopussa 4 s, normalisointi.
    n = len(out)
    fade = np.ones(n)
    fade[: RATE] = np.linspace(0, 1, RATE)
    fade[-4 * RATE:] = np.linspace(1, 0, 4 * RATE)
    out = out * fade[:, None]
    return out / np.max(np.abs(out)) * .8


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, required=True)
    ap.add_argument("--out", default="musiikki.wav")
    a = ap.parse_args()
    s = song(a.seconds)
    with wave.open(a.out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((s * 32767).astype("<i2").tobytes())
    print(a.out)


if __name__ == "__main__":
    main()
