#!/usr/bin/env python3
"""Gievran logo: yksinkertainen kahvakuulan siluetti tummalla pohjalla (vaihtoehto 2, 2026-11-07).

Tuottaa:
  assets/logo_icon.png                    1024 px, pyöristetty tumma pohja (README, työpöytä)
  assets/logo_app.png                     384 px, sama sovelluksen sisälle
  android/app/src/main/res/mipmap-*/      ic_launcher.png, ic_launcher_foreground.png (mukautuva kuvake)
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml, values/ic_launcher_background.xml
Aiemmat luonnokset (realistinen kahvakuula ym.) ovat git-historiassa.
Käyttö: python3 tools/make_logo.py
"""
import os

from PIL import Image, ImageDraw

BG = (38, 42, 48)
FG = (236, 233, 226)
S = 4  # ylinäytteistys


def mark(size: int, scale: float = 1.0, color=FG) -> Image.Image:
    """Kahvakuula läpinäkyvällä pohjalla; scale pienentää keskipisteen ympäri (turva-alue)."""
    n = size * S
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def P(x, y):
        return (n * (.5 + (x - .5) * scale), n * (.5 + (y - .5) * scale))

    d.ellipse([P(.27, .38), P(.73, .84)], fill=color)
    d.rounded_rectangle([P(.34, .18), P(.66, .52)], radius=n * .14 * scale, outline=color, width=int(n * .075 * scale))
    # Litteä pohja
    cut = Image.new("L", (n, n), 0)
    ImageDraw.Draw(cut).rectangle([P(0, .82), P(1, 1)], fill=255)
    im.paste((0, 0, 0, 0), (0, 0), cut)
    return im.resize((size, size), Image.LANCZOS)


def icon(size: int, radius: float = .22) -> Image.Image:
    n = size * S
    bg = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(bg).rounded_rectangle([0, 0, n - 1, n - 1], radius=n * radius, fill=BG)
    bg = bg.resize((size, size), Image.LANCZOS)
    bg.alpha_composite(mark(size))
    return bg


root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(f"{root}/assets", exist_ok=True)
icon(1024).save(f"{root}/assets/logo_icon.png")
icon(384).save(f"{root}/assets/logo_app.png")
old = f"{root}/assets/logo.png"
if os.path.exists(old):
    os.remove(old)

res = f"{root}/android/app/src/main/res"
for dpi, legacy, adaptive in (("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216), ("xxhdpi", 144, 324),
                              ("xxxhdpi", 192, 432)):
    icon(legacy).save(f"{res}/mipmap-{dpi}/ic_launcher.png")
    # Mukautuva kuvake: 108 dp, josta näkyy keskimmäinen 72 dp -> merkki 0,66 koossa.
    mark(adaptive, .66).save(f"{res}/mipmap-{dpi}/ic_launcher_foreground.png")
    bgfile = f"{res}/mipmap-{dpi}/ic_launcher_background.png"
    if os.path.exists(bgfile):
        os.remove(bgfile)
os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
with open(f"{res}/mipmap-anydpi-v26/ic_launcher.xml", "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')
with open(f"{res}/values/ic_launcher_background.xml", "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="ic_launcher_background">#{BG[0]:02X}{BG[1]:02X}{BG[2]:02X}</color>\n</resources>\n')
print("ok")
