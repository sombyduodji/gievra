#!/usr/bin/env python3
"""Saamennosten tarkistustaulukko (xlsx) natiivipuhujille.

Välilehdet tärkeysjärjestyksessä:
  Ohjeet                       mitä täytetään ja miten, esimerkkirivi
  Yhteenveto                   montako riviä tarkistettu (kaavat)
  UI – valikot ja painikkeet   lyhyet tekstit päivittäin käytetyissä näkymissä (valikko, asetukset, etusivu, treeni)
  UI – muut tekstit            muut käyttöliittymätekstit (ohjelmakysely, tilastot, tuonti, ohjeet ja ilmoitukset)
  Ohjelmat ja vinkit           ohjelmien, tarkistuksen ja ehdotusten tekstit
  Kahvakuula / Vapaat painot / Laitteet ja taljat / Kehonpaino   liikkeiden nimet (vielä suomeksi sovelluksessa)
  Lajit                        urheilulajit

Lähteet: assets/l10n/se.po (käyttöliittymä) ja sovelluksen liike- ja lajiluettelot (export.json, ks. --moves).
Käyttö: python3 tools/translation_sheet.py --moves export.json --out Gievra-saamennokset.xlsx
"""
import argparse
import json
import os
import re

from openpyxl import Workbook
from openpyxl.comments import Comment
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = "Arial"
HEAD_FILL = PatternFill("solid", fgColor="262A30")
INPUT_FILL = PatternFill("solid", fgColor="FFF4C2")  # täytettävät solut (keltainen)
EXAMPLE_FILL = PatternFill("solid", fgColor="E8F3EA")
THIN = Side(style="thin", color="D9D6CF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)

# Tiedosto -> näkymä, jossa teksti näkyy (järjestys = tärkeys).
SCREENS = [
    ("lib/ui/drawer.dart", "Valikko ja asetukset"),
    ("lib/ui/home.dart", "Etusivu"),
    ("lib/ui/onboarding.dart", "Ensimmäinen käynnistys"),
    ("lib/ui/workout.dart", "Treeni"),
    ("lib/ui/set_logger.dart", "Sarjan kirjaus"),
    ("lib/ui/new_workout.dart", "Uusi treeni"),
    ("lib/ui/rest_banner.dart", "Palautusajastin"),
    ("lib/rest.dart", "Palautusajastin"),
    ("lib/ui/watch.dart", "Kellon tiedot"),
    ("lib/ui/move_feedback.dart", "Palaute treenistä"),
    ("lib/ui/move_select.dart", "Liikkeen valinta"),
    ("lib/ui/picker.dart", "Liikkeen valinta"),
    ("lib/ui/activity.dart", "Liikunta"),
    ("lib/ui/intro.dart", "Ohjelmakysely"),
    ("lib/ui/program_screen.dart", "Ohjelma"),
    ("lib/ui/program_view.dart", "Ohjelma"),
    ("lib/ui/programs_screen.dart", "Ohjelmat"),
    ("lib/ui/program_template.dart", "Ohjelmapohjat"),
    ("lib/ui/stats_screen.dart", "Tilastot"),
    ("lib/ui/injury_screen.dart", "Vammatila"),
    ("lib/ui/import_export.dart", "Tuonti ja varmuuskopio"),
    ("lib/ui/bug_report.dart", "Ilmoita ongelmasta"),
    ("lib/ui/share.dart", "Jakaminen"),
    ("lib/share_text.dart", "Jakaminen"),
    ("lib/ui/licenses_screen.dart", "Lisenssit"),
    ("lib/ui/widgets.dart", "Yleiset"),
    ("lib/models.dart", "Yleiset"),
    ("lib/stats.dart", "Tilastot"),
    ("lib/sports.dart", "Liikunta"),
    ("lib/exercises.dart", "Liikkeet ja lihasryhmät"),
    ("lib/main.dart", "Yleiset"),
    ("lib/l10n.dart", "Yleiset"),
]
SCREEN = dict(SCREENS)
ORDER = {f: i for i, (f, _) in enumerate(SCREENS)}
# Ohjelmien ja ehdotusten tekstit (ei suoraan valikoissa).
PROGRAM_FILES = {"lib/program.dart", "lib/program_check.dart", "lib/progression.dart", "lib/program_edit.dart",
                 "lib/history_profile.dart", "lib/session_compare.dart", "lib/insights.dart", "lib/injury_data.dart"}
CORE = {"lib/ui/drawer.dart", "lib/ui/home.dart", "lib/ui/onboarding.dart", "lib/ui/workout.dart",
        "lib/ui/set_logger.dart", "lib/ui/new_workout.dart", "lib/ui/rest_banner.dart", "lib/rest.dart",
        "lib/ui/watch.dart", "lib/ui/move_feedback.dart", "lib/ui/move_select.dart", "lib/ui/picker.dart",
        "lib/ui/widgets.dart", "lib/main.dart"}
HIDDEN_FILES = {"lib/ui/sync_screen.dart"}  # synkronointi ei ole vielä julkaistu


def read_po(path):
    text = open(path, encoding="utf-8").read()
    out = []
    for block in text.split("\n\n"):
        if block.lstrip().startswith("#~"):
            continue
        mid = re.search(r"^msgid ((?:\".*\"\n?)+)", block, re.M)
        mstr = re.search(r"^msgstr ((?:\".*\"\n?)+)", block, re.M)
        if not mid:
            continue
        unq = lambda m: "".join(re.findall(r'"(.*)"', m)).replace('\\"', '"').replace("\\n", "\n")
        msgid = unq(mid.group(1))
        if not msgid:
            continue
        files = sorted({x.split(":")[0] for line in re.findall(r"^#: (.*)$", block, re.M) for x in line.split()})
        out.append((msgid, unq(mstr.group(1)) if mstr else "", files))
    return out


def is_short(s):
    """Valikko, painike, asetus tai otsikko: lyhyt eikä kokonainen virke."""
    return len(s) <= 42 and "\n" not in s and s.count(" ") <= 5 and not s.rstrip().endswith(".")


def style_header(ws, headers, widths):
    ws.append(headers)
    for i, w in enumerate(widths, 1):
        c = ws.cell(row=1, column=i)
        c.font = Font(name=FONT, bold=True, color="FFFFFF")
        c.fill = HEAD_FILL
        c.alignment = Alignment(wrap_text=True, vertical="center")
        ws.column_dimensions[c.column_letter].width = w
    ws.row_dimensions[1].height = 34
    ws.freeze_panes = "A2"


def body(ws, row, inputs):
    for c in ws[row]:
        c.font = Font(name=FONT, size=10)
        c.alignment = Alignment(wrap_text=True, vertical="top")
        c.border = BORDER
    for col in inputs:
        ws.cell(row=row, column=col).fill = INPUT_FILL


def ui_sheet(wb, title, rows):
    ws = wb.create_sheet(title)
    style_header(ws, [
        "Nro",
        "Missä sovelluksessa\nGos prográmmas",
        "Suomeksi (alkuperäinen)\nSuomagillii",
        "Nykyinen saamennos (konekäännös)\nDálá jorgalus",
        "Onko oikein?\nLea go riekta?",
        "Oikea saamennos (jos ei)\nRievttes jorgalus",
        "Kommentti\nKommeanta",
        "Tarkistaja\nDárkkisteaddji",
    ], [6, 22, 46, 46, 14, 46, 30, 14])
    dv = DataValidation(type="list", formula1='"Kyllä,Ei,En tiedä"', allow_blank=True,
                        error="Valitse Kyllä, Ei tai En tiedä.", errorTitle="Onko oikein?")
    ws.add_data_validation(dv)
    for i, (fi, se, where) in enumerate(rows, 1):
        ws.append([i, where, fi, se or "(puuttuu)", None, None, None, None])
        r = ws.max_row
        body(ws, r, [5, 6, 7, 8])
        if not se:
            ws.cell(row=r, column=4).font = Font(name=FONT, size=10, italic=True, color="9A9A9A")
        dv.add(f"E{r}")
    ws.auto_filter.ref = f"A1:H{ws.max_row}"
    return ws


def name_sheet(wb, title, rows, extra_head="Englanniksi\nEŋgelasgillii"):
    ws = wb.create_sheet(title)
    style_header(ws, [
        "Nro",
        "Ryhmä\nJoavku",
        "Suomeksi\nSuomagillii",
        extra_head,
        "Saamenkielinen nimi\nSámegiel namma",
        "Varmuus\nSihkarvuohta",
        "Kommentti\nKommeanta",
        "Tarkistaja\nDárkkisteaddji",
    ], [6, 18, 32, 30, 34, 14, 34, 14])
    dv = DataValidation(type="list", formula1='"Vakiintunut,Ehdotus"', allow_blank=True)
    ws.add_data_validation(dv)
    for i, (group, fi, en) in enumerate(rows, 1):
        ws.append([i, group, fi, en, None, None, None, None])
        r = ws.max_row
        body(ws, r, [5, 6, 7, 8])
        dv.add(f"F{r}")
    ws.auto_filter.ref = f"A1:H{ws.max_row}"
    return ws


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--moves", required=True, help="liike- ja lajiluettelo (export.json)")
    ap.add_argument("--out", default="Gievra-saamennokset.xlsx")
    a = ap.parse_args()

    entries = read_po(os.path.join(ROOT, "assets/l10n/se.po"))
    ui_short, ui_long, prog = [], [], []
    for fi, se, files in entries:
        files = [f for f in files if f in SCREEN or f in PROGRAM_FILES or f in HIDDEN_FILES]
        if not files or all(f in HIDDEN_FILES for f in files):
            continue
        ui = sorted((f for f in files if f in SCREEN), key=lambda f: ORDER[f])
        if not ui:
            prog.append((fi, se, "Ohjelmat ja ehdotukset", 99))
            continue
        where = ", ".join(dict.fromkeys(SCREEN[f] for f in ui))
        rank = ORDER[ui[0]]
        # Ensimmäinen välilehti: lyhyet tekstit päivittäin käytetyissä näkymissä (valikko, asetukset, treeni …).
        core = any(f in CORE for f in ui)
        (ui_short if is_short(fi) and core else ui_long).append((fi, se, where, rank))
    key = lambda x: (x[3], len(x[0]))
    data = json.load(open(a.moves, encoding="utf-8"))

    example_se = next((se for fi, se, _ in entries if fi == "Tallenna vastaamatta"), "") or "(puuttuu)"
    wb = Workbook()
    info = wb.active
    info.title = "Ohjeet"
    info.column_dimensions["A"].width = 110
    lines = [
        ("Gievra – saamennosten tarkistus · Gievra – sámegiel jorgalusaid dárkkisteapmi", True),
        ("", False),
        ("Gievra-treenipäiväkirjan pohjoissaamenkielinen käyttöliittymä on toistaiseksi konekäännös. Tällä "
         "taulukolla natiivipuhujat voivat tarkistaa ja korjata sen. Liikkeiden ja lajien nimet ovat sovelluksessa "
         "vielä suomeksi: niille kaivataan saamenkieliset nimet.", False),
        ("", False),
        ("Näin täytät:", True),
        ("1. Aloita välilehdestä »UI – valikot ja painikkeet«: ne näkyvät sovelluksessa eniten.", False),
        ("2. Lue suomenkielinen alkuperäinen ja nykyinen saamennos. Valitse »Onko oikein?« -sarakkeeseen Kyllä, Ei "
         "tai En tiedä.", False),
        ("3. Jos saamennos ei ole oikein, kirjoita oikea »Oikea saamennos« -sarakkeeseen. Kommenttiin voi kirjoittaa "
         "esimerkiksi murre-eroista tai vaihtoehdoista.", False),
        ("4. Kirjoita nimikirjaimesi »Tarkistaja«-sarakkeeseen, jotta tiedetään, kuka rivin on katsonut.", False),
        ("5. Liike- ja lajivälilehdillä kirjoita saamenkielinen nimi ja valitse, onko se vakiintunut vai ehdotus.", False),
        ("", False),
        ("Keltaiset solut täytetään; muut sarakkeet tulevat sovelluksesta, älä muuta niitä.", True),
        ("Merkinnät {0}, {1} … ovat paikkoja luvuille tai nimille (esim. »{0} sarjaa« → »5 sarjaa«). Pidä ne "
         "mukana korjatussa tekstissä, järjestys saa vaihtua.", False),
        ("(puuttuu) = tekstille ei ole vielä saamennosta: kirjoita se »Oikea saamennos« -sarakkeeseen.", False),
        ("", False),
        ("Esimerkkirivi (miltä täytetty rivi näyttää):", True),
    ]
    for t, bold in lines:
        info.append([t])
        c = info.cell(row=info.max_row, column=1)
        c.font = Font(name=FONT, bold=bold, size=12 if info.max_row == 1 else 10)
        c.alignment = Alignment(wrap_text=True, vertical="top")
    ex = info.max_row + 1
    for col, (h, v) in enumerate([
        ("Suomeksi", "Tallenna vastaamatta"), ("Nykyinen saamennos", example_se),
        ("Onko oikein?", "Ei"), ("Oikea saamennos", "(korjattu muoto tähän)"),
        ("Kommentti", "Esimerkki: miksi muutettu"), ("Tarkistaja", "AB"),
    ]):
        info.cell(row=ex, column=col + 2, value=h).font = Font(name=FONT, bold=True, size=10)
        cell = info.cell(row=ex + 1, column=col + 2, value=v)
        cell.font = Font(name=FONT, size=10)
        cell.fill = EXAMPLE_FILL
        info.column_dimensions[cell.column_letter].width = 24
    info.cell(row=ex + 3, column=1, value="Palautus: lähetä täytetty taulukko osoitteeseen treeni@somby.fi tai "
              "muokkaa jaettua taulukkoa suoraan. Giitu!").font = Font(name=FONT, size=10)

    summary = wb.create_sheet("Yhteenveto")
    sheets = []
    sheets.append(ui_sheet(wb, "UI – valikot ja painikkeet",
                           [(f, s, w) for f, s, w, _ in sorted(ui_short, key=key)]))
    sheets.append(ui_sheet(wb, "UI – muut tekstit", [(f, s, w) for f, s, w, _ in sorted(ui_long, key=key)]))
    sheets.append(ui_sheet(wb, "Ohjelmat ja vinkit", [(f, s, w) for f, s, w, _ in sorted(prog, key=key)]))

    moves = data["moves"]
    eqs = lambda m: set(m["eq"])
    groups = {"Kahvakuula": [], "Vapaat painot": [], "Laitteet ja taljat": [], "Kehonpaino": []}
    for m in moves:
        e = eqs(m)
        if m["cat"] == "Kahvakuula":
            g = "Kahvakuula"
        elif m["cat"] == "Kehonpaino" or e == {"kehonpaino"}:
            g = "Kehonpaino"
        elif e & {"tanko", "kasipaino"}:
            g = "Vapaat painot"
        else:
            g = "Laitteet ja taljat"
        groups[g].append((m["cat"], m["fi"], m["en"]))
    for g, rows in groups.items():
        sheets.append(name_sheet(wb, g, rows))
    sheets.append(name_sheet(wb, "Lajit", [(s["group"], s["fi"], "") for s in data["sports"]],
                             extra_head="Huom.\nMearkkašupmi"))

    # Yhteenveto: kaavat laskevat tilanteen täytön mukaan.
    style_header(summary, ["Välilehti", "Rivejä", "Tarkistettu", "Korjattavaa (Ei)", "Valmis %"], [32, 10, 12, 16, 10])
    summary.freeze_panes = None
    for ws in sheets:
        q = f"'{ws.title}'"
        n = ws.max_row
        is_ui = ws.cell(row=1, column=5).value.startswith("Onko")
        done = f"=COUNTA({q}!E2:E{n})"
        fix = f'=COUNTIF({q}!E2:E{n},"Ei")' if is_ui else "=0"
        summary.append([ws.title, f"=COUNTA({q}!C2:C{n})", done, fix, None])
        r = summary.max_row
        summary.cell(row=r, column=5, value=f"=IF(B{r}=0,0,C{r}/B{r})").number_format = "0%"
        for c in summary[r]:
            c.font = Font(name=FONT, size=10)
            c.border = BORDER
    tot = summary.max_row + 1
    summary.append(["Yhteensä", f"=SUM(B2:B{tot - 1})", f"=SUM(C2:C{tot - 1})", f"=SUM(D2:D{tot - 1})", None])
    summary.cell(row=tot, column=5, value=f"=IF(B{tot}=0,0,C{tot}/B{tot})").number_format = "0%"
    for c in summary[tot]:
        c.font = Font(name=FONT, size=10, bold=True)
        c.border = BORDER
    summary.cell(row=tot + 2, column=1, value="Tarkistettu = rivit, joilla »Onko oikein?« (UI) tai "
                 "»Saamenkielinen nimi« (liikkeet, lajit) on täytetty.").font = Font(name=FONT, size=9, italic=True)
    summary.cell(row=1, column=1).comment = Comment("Lasketaan kaavoilla välilehtien täytöstä.", "Gievra")

    wb.save(a.out)
    print(a.out, {ws.title: ws.max_row - 1 for ws in sheets})


if __name__ == "__main__":
    main()
