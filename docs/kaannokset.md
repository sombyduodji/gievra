# Käännökset (pohjoissaame)

Gievran käyttöliittymä on suomeksi ja kokeellisesti pohjoissaameksi (davvisámegiella). Kielen voi
vaihtaa ensimmäisellä käynnistyksellä tai ☰ → Asetukset → Kieli · Giella. Valinta on laitekohtainen.

## Mitä käännetään ja mitä ei

- **Käännetään:** käyttöliittymän tekstit (napit, otsikot, ohjeet, ilmoitukset), päiväykset, viikonpäivät,
  kuukaudet, lihasryhmät ja liikekategoriat, ohjelman vaiheet ja painoehdotusten perustelut.
- **Pysyy suomeksi:** liikkeiden nimet (Maastaveto, Takakyykky…), lajien nimet (Juoksu, Salibandy…),
  liikeohjeet, `.md`-tiedostojen sisältö ja tiedostomuoto, jaettu yhteenveto. Liikkeille ja lajeille ei ole
  vakiintuneita saamenkielisiä nimiä; ne käännetään myöhemmin natiivipuhujan kanssa.
- **Vielä suomeksi:** pitkät ohjelman selitystekstit (ohjelman tarkistus, historiasta päätellyt perustelut,
  vammatilan ohjeet, tilastojen huomiot) ja piilotettu Drive-synkronointi.

## Tiedostot

- `assets/l10n/se.po`: gettext-muotoinen käännöstiedosto. `msgid` on suomenkielinen teksti, `msgstr`
  saamenkielinen. Avautuu Poeditilla, Weblatella tai tekstieditorilla. Tyhjä `msgstr` = näkyy suomeksi.
- `#. {0} = …` -kommentti kertoo, mitä muuttuja on. Paikkamerkit `{0}`, `{1}` saavat olla käännöksessä
  eri järjestyksessä.
- `lib/l10n.dart`: `t('suomeksi')`-funktio. Uusi teksti kirjoitetaan koodiin suomeksi `t()`-kutsuun.

## Työkalut

```bash
python3 tools/l10n.py            # päivittää se.po:n koodin perusteella ja näyttää tilanteen
python3 tools/l10n.py --missing  # kääntämättömät
python3 tools/l10n.py --check    # paikkamerkit ja Divvun-oikoluku
```

Tarkistuksessa käytettiin GiellaLT:n pohjoissaamen oikolukijaa (Divvun, libvoikko `se`) ja
`giella-sme`-analysaattoria/generaattoria taivutusmuotojen tarkistamiseen. Ne eivät tarkista
merkitystä tai tyyliä.

## Tila (2026-11-07)

Ensimmäinen käännösluonnos, **ei vielä natiivipuhujan tarkistama**. Kaikki sanat ovat oikolukijan
hyväksymiä (paitsi tuotenimet ja suomenkieliset liikenimet), mutta sanavalinnat ja lauserakenteet pitää
tarkistaa. Erityisesti alla olevan sanaston termit.

## Sanasto (ehdotus, tarkistettava)

| Suomi | Pohjoissaame | Huom. |
|---|---|---|
| treeni, harjoittelu | hárjehallan | |
| liike | hárjehus | |
| sarja | ráidu | |
| toisto | geardduheapmi | |
| paino | deaddu | |
| maksimi (1RM) | eanemus deaddu | *máksima* = maksu, ei käytetä |
| volyymi | voluma | |
| jäikö varaa? | báziigo vel fápmu? | RIR |
| kevennysviikko | geahpedanvahkku | |
| lämmittely | liegganeapmi | |
| tauko (sarjojen välissä) | vuoiŋŋasteapmi | |
| tauko (sairas/loma) | boddu | |
| vammatila | roasmmohuvvan | |
| ennätys | rekorda | |
| fiilis / miltä tuntui? | dovdu / mo dovddai? | |
| ohjelma | prográmma | myös "sovellus" |
| asetukset | ásahusat | |
| tiedosto / kansio | fiila / máhppa | |
| varmuuskopio | sihkkarvurken | |
| tuonti / vienti | viežžan / doalvun | |
| laite (salilla) | rusttet | |
| laite (puhelin) | ovttadat | |
| voimanosto | fápmolokten | |
| lihaskasvu | deahkkešattolašvuohta | |
| tallenna / peruuta / poista | vurke / gaskkalduhte / sihko | |
| ohita / seuraava / takaisin | njuikes / boahtte / ruovttoluotta | |
