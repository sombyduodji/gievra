# Gievra – kehittäjän muistiinpanot

Gievra (pohjoissaamea: vahva) on maksuton treenipäiväkirja kuntosalille ja liikuntaan. Android-paketti `fi.somby.gievra`.

Maksuton kuntosalin treenipäiväkirja saamelaisella teemalla. Treenit tallentuvat tavallisina
Markdown-tiedostoina, joten ne aukeavat millä tahansa tekstieditorilla ja kulkevat laitteelta toiselle
Nextcloudin, Seafilen, ownCloudin tai Driven kautta. Flutter: Android ensin, myöhemmin AppImage ja .exe.

## Tiedostot

Treenikansio (valitaan ☰ → Asetukset → Treenikansio):

```
Treenit/
  asetukset.md          nimi, teema, painon lisäys, vinkit, laitteet, omat liikkeet, mittaustavat, vammat, tauot
  ohjelma.md            treeniohjelma (aloituskysely tai ☰ → Ohjelma ja tavoitteet), muokattavissa käsin
  2026/
    2026-11-06.md       yksi tiedosto päivää kohden
```

Treeni (`lib/models.dart`, esimerkki `mockup/esimerkki-2026-11-06.md`):

```markdown
---
date: 2026-11-06
title: Jalkapäivä
warmup: Crosstrainer, 10 min
bodyweight: 86,5
start: 17:30
duration: 62 min
feeling: 4 🙂 Hyvä
day: Koko keho A
tags: [treeni]
---

# Jalkapäivä 2026-11-06

## Lämmittely
- Crosstrainer: 10 min

## Takakyykky
1. 100 kg × 5
2. 125 kg × 5 RIR 1-2 🏆 ennätys

## Lankku
1. 45 s

## Muistiinpanot
vapaata tekstiä
```

Lukija sietää käsin kirjoitettua: `- 100kg x 5` käy myös, tuntemattomat rivit ohitetaan.

## Ominaisuudet

- Ensimmäisellä käynnistyksellä kysytään nimi, tervehdys vuorokaudenajan mukaan ("Bures! Hyvää iltaa, …").
- Kalenteri (kuukaudet myös pohjoissaameksi), pisteet treenin tyypin mukaan.
- Uusi treeni: päivämäärä, lämmittely tai ohitus, muokattavat lämmittelylaitteet, liikeluettelo
  (voimanosto, jalat, rinta, selkä, olkapäät, kädet, keskivartalo, kehonpaino, kahvakuula) ja omat liikkeet.
  Kehonpaino-ohjelma toimii ilman salia: vain kehonpainoliikkeitä (lähde StrengthLog).
- Sarjat isoilla +/- -säätimillä, edellinen kerta näkyvissä, ennätykset 🏆, automaattinen tallennus.
- Edistyminen (arvioitu 1RM) ja kevennysviikkovinkit, pois päältä asetuksista (`lib/insights.dart`).
- Aloituskysely (ohitettavissa, uudelleen ☰-valikosta): tavoite, kokemus, välineet (vapaat painot, laitteet,
  kahvakuulat, kehonpaino), päivät, kesto, toistoalue (suositus / raskaampi / kevyempi), vammat → ohjelma
  (`lib/program.dart`, lähteet `docs/tutkimus/ohjelmat.md`).
- Aloituskysely voi lähteä treenihistoriasta (`lib/history_profile.dart`): tuo FitNotes, varmuuskopio tai .md,
  ja tyyli, päivät, kokemus, toistot, kesto, välineet ja suosikkiliikkeet esitäytetään perusteineen.
- Valitse liikkeet itse: ohjelma rakennetaan valittujen ympärille (saman liikemallin paikka tai lisäys),
  ohjelman omat lisäliikkeet karsitaan ensin, jos aika ei riitä.
- Treenityyli tallentuu asetukset.md:hen (`## Treenityyli`), joten varmuuskopio ja synkronointi tuovat sen
  mukana; varmuuskopion zip tuo myös ohjelma.md:n, jos laitteella ei ole ohjelmaa.
- Ohjelman muokkaus (`lib/program_edit.dart`, `lib/ui/program_view.dart`): liikkeen vaihto (sama liikemalli
  ensin), lisäys ja poisto, sarjat ja toistoalue; jokainen muutos arvioidaan (liikemalli, viikon kuorman muutos,
  vammat, kilpaliike). Viikon kuorma lihasryhmittäin suositusalueen kanssa, tämän viikon tehdyt sarjat.
- Seuraava treeni huomioi palautumisen: jos eilen kuormittui sama lihasryhmä, ehdotetaan toista päivää.
- Ohjelmapäivän voi nimetä (viikonpäivä, ylä/ala/työntö/veto); pysyvä nimi (`day:`) pitää vertailut ennallaan.
- Miltä tuntui? viidellä fiilisnapilla (😫 😕 😐 🙂 🤩); kolme raskasta peräkkäin -> lepovinkki.
- Teema: Auto (järjestelmän mukaan, oletus) / Tumma / Vaalea.
- Taaksepäin yhteensopiva: puuttuvat tai oudot kentät jäävät tyhjiksi (`test/compat_test.dart`).
- Treenin ajastin, Treeni valmis! ja vertailu saman treenin edelliseen kertaan
  (`lib/session_compare.dart`; kevennys-, sairaus- ja paluuviikot jätetään pois).
- Ohjelmien pätevyystarkistus (`lib/program_check.dart`, testi käy läpi kaikki 4 725 yhdistelmää):
  koko keho -päivässä alavartalo + työntö + veto, ylävartalopäivässä työntö + veto, viikossa vetoa
  0,9–2 × työntö ja soutua, kaikki päämallit, vähintään 4 sarjaa / päälihasryhmä, treenikohtainen yläraja,
  moninivelliikkeet ennen eristäviä.
- Vammatila: 20 aluetta, vältä / muokkaa / korvaa -listat, kipuasteikko ja punaiset liput
  (`lib/injury_data.dart`, generoitu `docs/tutkimus/vammatila.md`:stä).
- Näin teet: tikku-ukkoanimaatio (sivukuva, kaikki liikkeet, `lib/anim/`) ja 2–3 tekniikkavinkkiä jokaiselle
  liikkeelle (`lib/anim/cues.dart`, lähteet `docs/tutkimus/liikkeet.md`). Asennot kuviksi:
  `RENDER=1 flutter test --update-goldens test/anim/render_test.dart`.
- Mittaustavat: toistot, sekunnit (lankku), askeleet, edestakaiset (farmer walk), metrit.
- Sarjan tallennus yhdellä napautuksella: jäikö varaa (Ei yhtään / Muutama / Reilusti); aika- ja
  matkaliikkeissä "olisitko jaksanut pidempään / pidemmälle" (En yhtään / Vähän / Reilusti).
  Tallennetun sarjan voi korjata napauttamalla.
- Tauko: sairas tai loma, paluun jälkeen kevyemmät kuormat.
- Tuonti: FitNotes-varmuuskopio (.fitnotes), oma varmuuskopio (.zip), yksittäiset .md-tiedostot. Vienti: .zip.
- Valinnainen Google Drive -synkronointi (`lib/sync/`): tallennukset ja tuonnit lähtevät heti, käynnistyksessä
  haetaan PC:n tai toisen puhelimen muutokset viimeisiltä N päivältä, ristiriidat talteen. Käyttöönotto
  (Google Cloud -rekisteröinti): `docs/google-drive.md`.
- ☰-valikko: asetukset, ohjelmat, Tietoa, palaute, vikailmoitus, Osallistu ja tue.

## Kehitys

Työkalut: Flutter (stable), JDK 17 ja Android SDK. Versio: `python3 tools/version.py` (X.Y.Z.VVVVKKPP.N, ks.
`RELEASE_VERSION`), julkaisu-APK: `tools/build_apk.sh` (allekirjoitus `android/key.properties`, ei gitissä).

```
flutter test
FITNOTES=/polku/FitNotes_Backup.fitnotes flutter test   # myös oikea varmuuskopio
flutter build apk --debug
```

Android-emulaattori Dockerissa (kuva `packaging/android/`):

```
./emulaattori.sh kaynnista
./emulaattori.sh asenna          # build/app/outputs/flutter-apk/app-debug.apk
./emulaattori.sh kuva
./emulaattori.sh pysayta
```
