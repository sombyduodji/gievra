# Google Drive -synkronoinnin käyttöönotto

> Tila 0.1.1: synkronointimoottori ja Drive-asiakas ovat koodissa ja testattu, mutta kirjautuminen on poistettu
> julkaisusta (ei Googlen suljettuja kirjastoja APK:ssa). Palautus: lisää `google_sign_in` ja `DriveAuth`-toteutus
> (`lib/sync/sync_service.dart`; aiempi toteutus git-historiassa, commit ennen 0.1.1), sitten lippu. Synkronointi on piilotettu (`syncReleased = false` tiedostossa
> `lib/app_info.dart`). Ennen julkaisua: lisää Android-asiakkaat paketille `fi.somby.gievra` (debug- ja julkaisuavaimen
> SHA-1) ja vaihda lippu päälle. Drive-kansion nimi on nyt `Gievra`.

Synkronointi on sovelluksessa valmiina (`lib/sync/`), mutta Google vaatii, että sovellus rekisteröidään
Google Cloudiin ennen kuin kirjautuminen toimii. Tämä tehdään kerran, noin 15 minuuttia. Rekisteröinti
on ilmainen.

Oikeus on `drive.file`: sovellus näkee vain itse luomansa tiedostot. Se ei ole "arkaluonteinen" oikeus,
joten Googlen tarkastusta ei tarvita.

## 1. Projekti ja Drive API

1. Avaa https://console.cloud.google.com/ omalla Google-tililläsi.
2. Yläpalkki → projektivalikko → **New project**, nimi esim. `Treenipaivakirja` → Create.
3. **APIs & Services → Library** → hae `Google Drive API` → **Enable**.

## 2. Kirjautumisnäkymä (OAuth consent screen / Google Auth Platform)

1. **APIs & Services → OAuth consent screen** (uudessa näkymässä *Google Auth Platform → Branding*) → Get started.
2. App name `Treenipäiväkirja`, user support email: oma osoitteesi.
3. Audience: **External**.
4. Contact information: oma osoitteesi → Create.
5. **Data access → Add or remove scopes** → valitse `.../auth/drive.file` → Save.
6. **Audience → Test users → Add users**: lisää omat Google-tilisi (myös toisen puhelimen tili).
   Testitilassa enintään 100 käyttäjää. Kun sovellus julkaistaan, paina **Publish app**; drive.file ei vaadi tarkastusta.

## 3. Tunnukset (Credentials / Clients)

Tarvitaan kaksi OAuth-asiakasta.

**Android-asiakas** (kertoo Googlelle, että kirjautuminen tulee juuri tästä sovelluksesta):

- Create credentials → OAuth client ID → Application type **Android**
- Package name: `fi.somby.gievra` (0.1.1 alkaen; aiemmat asiakkaat olivat `fi.somby.treenipaivakirja`)
- SHA-1 certificate fingerprint: `A5:87:B2:23:77:B2:C6:00:A6:26:37:D5:F1:F2:36:3C:9A:91:CD:36`
  (debug-avain `~/.android/debug.keystore`)

**Web-asiakas** (sovellus pyytää Drive-oikeuden tällä tunnuksella):

- Create credentials → OAuth client ID → Application type **Web application**, nimi esim. `Treenipaivakirja web`
- Ei redirect-osoitteita → Create
- Kopioi **Client ID** (muotoa `1234567890-abc…apps.googleusercontent.com`)

## 4. Tunnus sovellukseen

Anna Web-asiakkaan Client ID Claudelle tai kirjoita se tiedostoon `lib/app_info.dart`:

```dart
const String? googleWebClientId = '1234567890-abc….apps.googleusercontent.com';
```

Client ID ei ole salaisuus (se näkyy jokaisessa sovelluksessa). Client secretiä ei tarvita eikä
sitä pidä laittaa sovellukseen.

## Myöhemmin

- **Julkaisuversio (0.1.0 alkaen):** julkaisu-APK allekirjoitetaan julkaisuavaimella
  julkaisuavain (polku ja salasana `android/key.properties`, ei gitissä). Sille tarvitaan
  oma Android-asiakas: package `fi.somby.gievra`, SHA-1
  `F6:D9:71:64:33:DC:72:7F:CE:3D:D4:F8:9F:C5:11:83:A8:5F:8F:FC`. Jos sovellus menee Google Playhin,
  Play App Signingin SHA-1 lisätään myös.
- **Avaimen varmuuskopio:** jos julkaisuavain katoaa, päivityksiä ei voi asentaa vanhan päälle (käyttäjien
  pitää poistaa sovellus ensin). Säilytä `.jks` ja salasana turvassa, esim. salasanamanagerissa.
- **Muut koneet:** toisella koneella käännetty debug-APK käyttää sen koneen debug-avainta. Lisää sen
  SHA-1 omaksi Android-asiakkaakseen tai käännä samalla koneella.
- **Työpöytäversio (AppImage / .exe):** käyttää samaa projektia (Desktop-tyyppinen OAuth-asiakas), joten se
  näkee puhelimen luomat tiedostot ja puhelin sen luomat.

## Miten synkronointi toimii

- Drivessa: `Treenipäiväkirja/asetukset.md`, `ohjelma.md`, `2026/2026-11-06.md` … (sama rakenne kuin puhelimessa).
- Tallennus, treeni valmis, tuonti, asetukset ja ohjelma lähetetään noin 3 sekunnin päästä muutoksesta.
- Käynnistyksessä (valinnainen) haetaan PC:n tai toisen puhelimen muutokset viimeisiltä N päivältä.
- Muutos tunnistetaan md5-tarkisteesta. Jos sama tiedosto muuttui molemmissa, uudempi voittaa ja toinen
  säilyy puhelimessa nimellä `ristiriita-…md`. Drivessa poistetut menevät roskakoriin.
- PC:llä kokonaan uutena tehtyä tiedostoa sovellus ei näe (drive.file). Lataa se puhelimeen ja tuo:
  Tuonti ja varmuuskopio → Tuo .md-tiedostoja. Sen jälkeen se synkronoituu.
