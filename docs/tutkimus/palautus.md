# Palautus sarjojen välillä (palautusajastin)

☰ → Asetukset → Palautusajastin (oletus pois). Sarjan tallennus käynnistää ajastimen; −15 s / +15 s säätää ja ✕
ohittaa. Toteutus: `restSeconds()` ja `RestTimer` tiedostossa lib/rest.dart.

## Säännöt

| Tilanne | Palautus |
|---|---|
| Ohjelman liike | ohjelman oma tauko (`ohjelma.md`: `tauko 3 min`) |
| Vapaa treeni, moninivelliike, 1–5 toistoa tai ≥ 85 % arvioidusta maksimista | 3 min (≥ 90 %: 4 min) |
| Vapaa treeni, eristävä liike, 1–5 toistoa tai ≥ 85 % | 2 min |
| 6–12 toistoa | moninivel 2 min, eristävä 90 s |
| yli 12 toistoa | 60 s |
| Lämmittelysarja, aika- tai matkaliike | 60 s |
| Ei jäänyt varaa (0) | +30 s |
| Kevennysviikko | × 0,75 |

Tulos pyöristetään 15 sekuntiin, 45 s – 5 min. Arvioitu maksimi on paras e1RM (Epley) aiemmista työsarjoista.

## Lähteet

- de Salles BF ym. 2009. Rest interval between sets in strength training. *Sports Med* 39(9):765–777. Maksimivoimaan
  3–5 min; lyhyet tauot heikentävät seuraavien sarjojen toistoja.
- Schoenfeld BJ ym. 2016. Longer interset rest periods enhance muscle strength and hypertrophy in resistance-trained
  men. *J Strength Cond Res* 30(7):1805–1812. 3 min > 1 min voimassa ja lihaskasvussa.
- Grgic J ym. 2017. The effects of short versus long inter-set rest intervals in resistance training on measures of
  muscle hypertrophy: a systematic review. *Eur J Sport Sci* 17(8):983–993. Moninivelliikkeissä vähintään 2 min;
  eristävissä 60–90 s riittää.
- American College of Sports Medicine 2009. Progression models in resistance training for healthy adults. *Med Sci
  Sports Exerc* 41(3):687–708. Raskaat moninivelliikkeet 2–3 min, kevyemmät 1–2 min.
- Haff GG & Triplett NT (toim.) 2016. *Essentials of Strength Training and Conditioning*, 4. p. NSCA. Voima 2–5 min.

Kevennysviikon ja "ei varaa" -lisän määrät ovat sovelluksen konventioita (kevyempi kuorma vaatii vähemmän
palautumista; sarja uupumukseen asti vaatii enemmän), eivät suoria tutkimustuloksia.
