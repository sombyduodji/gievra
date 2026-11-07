#!/usr/bin/env python3
"""Gievran esittelyvideo valmentajalle: emulaattorilla nauhoitetut kohtaukset + suomenkieliset selitykset.

Vaaka 1920×1080: puhelin vasemmalla, selitys oikealla, alussa otsikko ja lopussa yhteenveto.
Kohtaukset nauhoitetaan demosovelluksesta (--dart-define=DEMO=true) adb screenrecordilla tiedostoiksi
s1.mp4 … s6.mp4. Tarvitsee ffmpegin (imageio-ffmpeg käy) ja Pillowin.

  python3 tools/showcase_video.py --scenes KANSIO --ffmpeg FFMPEG --out Gievra-esittely.mp4
"""
import argparse
import os
import subprocess
import tempfile
import textwrap

from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG = (246, 244, 239)
TEXT = (23, 25, 29)
MUTED = (93, 99, 109)
SAMI = [(213, 43, 30), (0, 114, 41), (255, 206, 0), (0, 53, 173)]
FONT = "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"
BOLD = "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (tiedosto, otsikko, selitys) — kirjoitettu valmentajalle: mitä ominaisuus tekee ja miksi.
TRAINER = [
    ("s1", "Etusivu",
     "Päivän treeni ehdotetaan ohjelmasta ja palautumisesta (eilen kuormittuneet lihasryhmät). "
     "Viikon treenit, viikkoputki ja kalenteri. Treenit tallentuvat tavallisiksi .md-tiedostoiksi "
     "asiakkaan omaan kansioon: ei tiliä, ei pilveä."),
    ("s2", "Ohjelma ja viikon kuorma",
     "Ohjelma rakennetaan tavoitteen, kokemuksen, treenipäivien ja keston mukaan. Tarkistus kertoo "
     "työntö/veto-tasapainon, liikemallit ja järjestyksen sekä sarjat viikossa lihasryhmittäin "
     "suhteessa suositukseen (lihaskasvu 10–20 sarjaa/vk; epäsuora kuorma puolikkaana)."),
    ("s3", "Sarjan kirjaus",
     "Lämmittelysarjat täytetään työpainon mukaan (esim. 20, 32,5 ja 45 kg ennen 62,5 kg:n työsarjoja). Painoehdotus "
     "tulee edellisestä kerrasta. Sarja tallentuu vastaamalla »jäikö varaa?« (reps in reserve). "
     "Palautusajastin: kevyet lämmittelyt lyhyesti, raskaat sarjat pidempään."),
    ("s4", "Treeni valmis ja palaute",
     "Kun treeni tuntui raskaalta, kysytään liikekohtainen tuntuma ja syyt (väsymys, huono uni, "
     "stressi, kipu). Seuraavan kerran painoehdotus ottaa ne huomioon eikä nosta kuormaa "
     "huonon päivän perusteella."),
    ("s5", "Juoksun kehitys",
     "Kestävyydelle oma näkymä, erillään salista: kilometrit ja keskivauhti viikoittain, kevyiden "
     "lenkkien vauhti ja syke neljän viikon jaksoissa, ennätykset sekä lenkkityypit "
     "(kevyt, pitkä, vauhtikestävyys, intervallit …) kellon sykkeineen."),
    ("s6", "Vammatila",
     "20 kehon aluetta: vältettävät ja muokattavat liikkeet, sopivat korvaavat liikkeet, "
     "kipuasteikko (kipua enintään 3–5/10, rauhoittuu seuraavaan aamuun) ja punaiset liput. "
     "Ei tee diagnoosia eikä korvaa fysioterapeuttia."),
]

# Käyttäjälle (Gievran kotisivu): mitä sovelluksella tehdään.
USER = [
    ("s1", "Treenipäiväkirja taskussa",
     "Etusivu kertoo päivän treenin ohjelmastasi, viikon treenit ja kalenterin. Ei tiliä eikä mainoksia: "
     "treenit tallentuvat tavallisiksi tiedostoiksi omaan kansioosi, ja sovellus toimii ilman verkkoa."),
    ("s2", "Valmis treeniohjelma",
     "Vastaa muutamaan kysymykseen (tavoite, kokemus, päivät, kesto), niin saat tutkimuksiin perustuvan "
     "ohjelman: voimanosto, lihaskasvu, kunto, kahvakuula tai kehonpaino. Viikon kuorma näyttää, saako "
     "jokainen lihasryhmä tarpeeksi."),
    ("s3", "Sarja yhdellä napautuksella",
     "Lämmittelysarjat ja paino ovat valmiina. Tee sarja ja vastaa »jäikö varaa?«, niin seuraavan kerran "
     "ehdotus osuu kohdalleen. Palautusajastin kertoo, milloin jatketaan."),
    ("u_watch", "Älykellon tiedot käsin",
     "Kalorit, keski- ja maksimisyke ja kesto kirjoitetaan kellosta itse. Gievra ei vielä yhdisty "
     "älykelloon tai Health Connectiin. Garmin Connectin suoritukset voi tuoda CSV-tiedostona."),
    ("u_run", "Juoksu ja muu liikunta",
     "Valitse lenkin tyyppi (kevyt, pitkä, intervallit …), kirjoita aika ja matka: vauhti ja "
     "keskinopeus lasketaan heti, ja tallennus vertaa edelliseen samanlaiseen lenkkiin."),
    ("s5", "Näe kehityksesi",
     "Juoksulla on oma kehitysnäkymä: kilometrit ja vauhti viikoittain, kevyiden lenkkien vauhti ja "
     "syke sekä ennätykset. Salitreeneillä omat tilastonsa ja ennätykset."),
]
SCENES = TRAINER


def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)


def band(d, y, h=10, x0=0, x1=W):
    w = (x1 - x0) / 4
    for i, c in enumerate(SAMI):
        d.rectangle([x0 + i * w, y, x0 + (i + 1) * w, y + h], fill=c)


def wrap(d, text, f, width):
    lines, line = [], ""
    for word in text.split():
        t = (line + " " + word).strip()
        if d.textlength(t, font=f) <= width:
            line = t
        else:
            lines.append(line)
            line = word
    return lines + [line]


def scene_bg(path, n, title, body):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    band(d, 0)
    x = 820
    d.text((x, 150), f"{n}/{len(SCENES)}", font=font(30, True), fill=MUTED)
    d.text((x, 195), title, font=font(64, True), fill=TEXT)
    y = 310
    for line in wrap(d, body, font(38), 1000):
        d.text((x, y), line, font=font(38), fill=TEXT)
        y += 58
    d.text((x, H - 90), "Gievra – Treenipäiväkirja · demo-tiedot", font=font(26), fill=MUTED)
    band(d, H - 10)
    im.save(path)


def card(path, lines):
    """lines: (teksti, koko, lihavointi, väri)"""
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    band(d, 0, 14)
    band(d, H - 14, 14)
    logo = Image.open(os.path.join(ROOT, "assets/logo_icon.png")).convert("RGBA").resize((170, 170))
    total = 170 + 40 + sum(s * 1.5 for _, s, _, _ in lines)
    y = (H - total) / 2
    im.paste(logo, ((W - 170) // 2, int(y)), logo)
    y += 210
    for text, size, bold, color in lines:
        f = font(size, bold)
        for line in wrap(d, text, f, 1500):
            d.text(((W - d.textlength(line, font=f)) / 2, y), line, font=f, fill=color)
            y += size * 1.5
    im.save(path)


def run(ff, *args):
    subprocess.run([ff, "-loglevel", "error", "-y", *args], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", required=True)
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--out", default="Gievra-esittely.mp4")
    ap.add_argument("--audience", choices=["valmentaja", "kayttaja"], default="valmentaja")
    ap.add_argument("--music", help="taustamusiikki (wav), esim. tools/video_music.py")
    ap.add_argument("--speed", type=float, default=1.0, help="nauhoitusten nopeutus (esim. 1.3)")
    a = ap.parse_args()
    global SCENES
    SCENES = USER if a.audience == "kayttaja" else TRAINER
    user = a.audience == "kayttaja"
    tmp = tempfile.mkdtemp()
    enc = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", "-preset", "medium", "-crf", "20", "-an"]
    parts = []

    card(f"{tmp}/title.png", [
        ("Gievra – Treenipäiväkirja", 72, True, TEXT),
        ("Sinun treenisi, sinun tiedostosi." if user else "Esittely valmentajalle", 44, False, TEXT),
        ("Maksuton ja avoin · ei tiliä · ei mainoksia · toimii ilman verkkoa", 32, False, MUTED),
    ])
    run(a.ffmpeg, "-loop", "1", "-t", "4", "-i", f"{tmp}/title.png", *enc, f"{tmp}/p00.mp4")
    parts.append(f"{tmp}/p00.mp4")

    for n, (name, title, body) in enumerate(SCENES, 1):
        bg = f"{tmp}/{name}.png"
        scene_bg(bg, n, title, body)
        src = os.path.join(a.scenes, f"{name}.mp4")
        out = f"{tmp}/p{n:02d}.mp4"
        # Selitys luettavaksi ennen liikettä: 2 s pysäytyskuva alussa, 1,5 s lopussa.
        run(a.ffmpeg, "-loop", "1", "-i", bg, "-i", src, "-filter_complex",
            f"[1:v]setpts=PTS/{a.speed},scale=-2:1000,tpad=start_mode=clone:start_duration=2:stop_mode=clone:stop_duration=1.5,"
            "setsar=1[ph];[0:v][ph]overlay=120:40:shortest=1,format=yuv420p",
            *enc, out)
        parts.append(out)

    card(f"{tmp}/end.png", [
        ("Kokeile selaimessa tai lataa Androidille", 52, True, TEXT),
        ("Verkkodemossa voit kokeilla kaikkea ja tehdä oman treeniohjelman. Sovellus on maksuton ja avoin "
         "(GPL-3.0), eikä siinä ole tiliä, mainoksia tai seurantaa.", 34, False, TEXT),
        ("Kehitysvaiheessa: palaute ja ideat ovat erittäin tervetulleita.", 30, False, MUTED),
        ("sombyduodji.github.io/gievra · treeni@somby.fi", 36, True, (181, 36, 26)),
    ] if user else [
        ("Ohjelmapohjat valmentajalta asiakkaalle", 52, True, TEXT),
        ("Tee ohjelma selaimessa ja lähetä se .gmd-tiedostona: Androidilla se aukeaa suoraan Gievralla, "
         "eikä asiakkaan treenihistoria katoa.", 34, False, TEXT),
        ("Liikeohjeet, animaatiot ja ohjelmat perustuvat tutkimuksiin ja avoimiin oppikirjoihin. "
         "Ammattilaisen tarkistus ja palaute ovat erittäin tervetulleita.", 30, False, MUTED),
        ("sombyduodji.github.io/gievra · treeni@somby.fi", 36, True, (181, 36, 26)),
    ])
    run(a.ffmpeg, "-loop", "1", "-t", "7", "-i", f"{tmp}/end.png", *enc, f"{tmp}/p99.mp4")
    parts.append(f"{tmp}/p99.mp4")

    with open(f"{tmp}/list.txt", "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    if a.music:
        run(a.ffmpeg, "-f", "concat", "-safe", "0", "-i", f"{tmp}/list.txt", "-i", a.music, "-map", "0:v", "-map",
            "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart", a.out)
    else:
        run(a.ffmpeg, "-f", "concat", "-safe", "0", "-i", f"{tmp}/list.txt", "-c", "copy", "-movflags",
            "+faststart", a.out)
    print(a.out)


if __name__ == "__main__":
    main()
