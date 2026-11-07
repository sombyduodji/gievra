# Verkkoversio (demo ja ohjelmatyökalu)

Sama sovellus käännettynä selaimeen (Flutter web). Verkossa se on **demo**:

- esimerkkitreenit (neljä viikkoa, kolmen päivän ohjelma), etusivu, kalenteri, tilastot ja treenin kirjaus toimivat
- mitään ei tallenneta: ei tiedostoja, ei selaimen muistia; sivun päivitys palauttaa demon alkuun
- **ohjelmatyökalu**: ☰ → Ohjelma ja tavoitteet → Tee uusi ohjelma → Tallenna pohja lataa ohjelmapohjan
  (`.gmd`), jonka voi lähettää toiselle ja tuoda sovellukseen
- pois päältä verkossa: treenikansio, tuonti ja varmuuskopio, synkronointi, vikailmoitus, FitNotes (SQLite)

Toteutus: `isDemo` (`kIsWeb`) ja `MemoryTrainingFiles` (lib/app_state.dart), esimerkkitiedot lib/demo.dart,
FitNotes-tietokanta vain natiivisti (lib/fitnotes_db.dart, verkossa lib/fitnotes_db_stub.dart).

## Kääntäminen

```bash
flutter build web --release --no-web-resources-cdn --base-href /gievra/ $(python3 tools/version.py --flutter)
```

`--no-web-resources-cdn` ja `web/fonts/` (ks. web/fonts/README.md): sovellus, fontit ja emojit tulevat
omalta palvelimelta, ei Googlen CDN:stä; sivu ei ota yhteyttä Googleen. Fontit: Noto (SIL OFL 1.1) ja
Roboto (Apache 2.0), lisenssit web/fonts/-kansiossa.

`--base-href` on GitHub Pagesin polku (`https://<käyttäjä>.github.io/gievra/`). Paikallinen testi:

```bash
python3 -m http.server 8090 --directory build/web
```

## GitHub Pages

Kun repo on julkinen GitHubissa, helpoin tapa on GitHub Actions -työnkulku, joka kääntää `build/web`-kansion
ja julkaisee sen Pagesiin (Settings → Pages → Source: GitHub Actions). Vaihtoehto: käännä paikallisesti ja
työnnä `build/web` `gh-pages`-haaraan. Verkkoversio ei tarvitse palvelinta eikä tietokantaa.

## Ohjelmapohja (.gmd)

`.gmd` = Gievra + Markdown. Sama muoto kuin treenikansion `ohjelma.md`, mutta ilman henkilökohtaisia tietoja:

```markdown
---
template: gievra-1
name: Kaverin voimaohjelma
author: Elle
goal: voimanosto
experience: keski
days: 3
minutes: 60
deloadEvery: 5
---

# Ohjelma: Voimanosto · 3 päivää viikossa

## Voima A
- Takakyykky | raskas | varaa 2 | tauko 4 min | KK
- Penkkipunnerrus | 5 × 5 | varaa 1–3 | tauko 3 min | KP
```

- Ei aloituspäivää (`start:`) eikä maksimeja (`maxes:`): tuonnissa ohjelma alkaa tuontipäivänä ja omat maksimit säilyvät.
- Androidilla `.gmd`-tiedosto aukeaa Gievralla (Avaa sovelluksella, Jaa → Gievra).
- Tallennetut omat ohjelmat ovat treenikansion `ohjelmat/`-kansiossa (`.gmd`, maksimien ja aloituspäivän kanssa).
