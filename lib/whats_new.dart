import 'package:flutter/material.dart';

// "Uutta tässä versiossa": vain uudet ominaisuudet (ei korjauksia), näytetään kerran päivityksen jälkeen.
// Lisää uuden version kohdat listan alkuun; tekstit suomeksi (käännökset .po-tiedostoissa).

class NewFeature {
  final String version;
  final IconData icon;
  final String title, text;
  const NewFeature(this.version, this.icon, this.title, this.text);
}

// l10n: data
const whatsNew = <NewFeature>[
  NewFeature(
    '0.7.5.2',
    Icons.build_outlined,
    'Korjauksia sarjan kirjaukseen',
    'Muutettu paino ja toistot säilyvät myös ennen liikkeen ensimmäistä sarjaa. Paras 6 vk -tilassa näkyy myös ohjelman tavoite. Tauon jälkeen kehonpainoliikkeisiin ei ehdoteta lisäpainoa, ja kuorman ollessa ennallaan lukee "normaalit kuormat". Suurella tekstillä sanat eivät katkea kesken.',
  ),
  NewFeature(
    '0.7.5.2',
    Icons.bedtime_outlined,
    'Vanha yö harmaana',
    'Jos tämän yön yösyke tai HRV ei vielä ole Health Connectissa, Palautuminen ja Yöarvot näyttävät edellisen yön harmaana eivätkä väritä sitä tämän päivän arvoksi.',
  ),
  NewFeature(
    '0.7.5',
    Icons.fitness_center,
    'Selkeämpi sarjan kirjaus',
    'Tavoite, ehdotus ja edellinen kerta omilla riveillään, luvut samassa linjassa. Edellinen kerta näyttää parhaan sarjan. Kahden käsipainon liikkeissä paino kättä kohden, kahvakuulissa kuulaa kohden.',
  ),
  NewFeature(
    '0.7.5',
    Icons.tune,
    'Painoehdotus valittavissa',
    'Asetukset → Harjoittelu → Painoehdotus: Ehdotus (kuten ennen), Paras 6 vk (paras sarja kuuden viikon ajalta) tai Pois. Paino alkaa valmiiksi oikeasta kohdasta.',
  ),
  NewFeature(
    '0.7.5',
    Icons.edit_note,
    'Muutettu paino säilyy',
    'Jos muutat seuraavan sarjan painoa tai toistoja ja käyt välillä liikelistassa, arvot ovat tallessa, kun palaat liikkeeseen.',
  ),
  NewFeature(
    '0.7.5',
    Icons.bedtime_outlined,
    'Yön uni ei vielä synkronoitu',
    'Jos tämän yön uni ei vielä ole Health Connectissa, Uni-kortti näyttää edellisen yön harmaana omalla nimellään ja kertoo, että kellon tai sormuksen sovelluksen avaaminen päivittää tiedon.',
  ),
  NewFeature(
    '0.7.4.1',
    Icons.emoji_events_outlined,
    'Ennätykset korteiksi',
    'Tilastot → Ennätykset: jokaisella liikkeellä paras nosto (painavin sarja) ja arvioitu 1 toiston maksimi nyt rinnakkain. Sama tulos uudelleen ei ole uusi ennätys.',
  ),
  NewFeature(
    '0.7.4',
    Icons.bedtime_outlined,
    'Univaiheet',
    'Napauta unta (Palautuminen-ruutu, Uni-kortin viime yö tai kalenterin päivä): näet yön kevyen, syvän ja REM-unen sekä hereillä olon Health Connectista.',
  ),
  NewFeature(
    '0.7.4',
    Icons.insights,
    'Uni ja palautuminen tilastoissa',
    'Uusi välilehti Tilastoissa, kun Uni- tai Palautuminen-kortti on käytössä: jakson uni, nukkumaanmeno ja herätys, säännöllisyys, yöt pylväinä, univaiheet keskimäärin sekä yösyke ja HRV käyrinä.',
  ),
  NewFeature(
    '0.7.3',
    Icons.monitor_heart_outlined,
    'Kaikki treenit Health Connectista',
    'Lisää → Tuonti, vienti ja varmuuskopio → Tuo Health Connectista tuo kerralla kellon tai muun sovelluksen harjoitukset, myös sovelluksesta, jolla ei ole omaa vientiä. Valitset tuotavat; jo Gievrassa olevia ei tuoda toiste, ja niihin voi täydentää puuttuvat tiedot.',
  ),
  NewFeature(
    '0.7.3',
    Icons.bar_chart,
    'Viikon kuorma osineen',
    'Olkapään, selän ja muiden osien riveillä näkyy nyt myös tämän viikon sarjat sinisenä palkkina: tehty / suunniteltu.',
  ),
  NewFeature(
    '0.7.2.2',
    Icons.monitor_heart_outlined,
    'Rasitus sykkeestä',
    'Rasitusta ei enää kysytä: kun liikunnassa on sykettä, se lasketaan ja näkyy syke-kortissa, ja viikon reippaat minuutit tulevat sykkeestä. Maksimisykkeeksi riittää syntymävuosi.',
  ),
  NewFeature(
    '0.7.2.2',
    Icons.sentiment_satisfied_alt,
    'Vähemmän kysymyksiä',
    'Hymiö tallentaa yhdellä napautuksella kaikissa lajeissa. Vain Raskas tai Tahmea kysyy, mikä painoi.',
  ),
  NewFeature(
    '0.7.2.1',
    Icons.flag_outlined,
    'Yhteenveto heti treenin jälkeen',
    'Treeni valmis! ja GPS-liikunnan Lopeta ja tallenna tallentavat heti ja avaavat tiiviin yhteenvedon. Valitse fiilis tai Ohita, niin olet etusivulla. Reittiä voi korjata yhteenvedosta.',
  ),
  NewFeature(
    '0.7.2.1',
    Icons.watch_outlined,
    'Kellon tiedot yhteenvedossa',
    'Yhteenveto odottaa kellon tietoja ja kertoo, kun sykettä, kaloreita tai askeleita on tullut Health Connectiin. Napauta ja valitse, mitkä lisätään.',
  ),
  NewFeature(
    '0.7.2',
    Icons.monitor_heart_outlined,
    'Yöarvot unen lähteestä',
    'Yösyke ja HRV lasketaan vain valitsemastasi unen lähteestä, ja alin syke 5 minuutin jaksosta kuten esim. Ouran sovelluksessa.',
  ),
  NewFeature(
    '0.7.2',
    Icons.notifications_off_outlined,
    'Ilmoitukset estetty',
    'Jos ilmoitukset on estetty, Palautusajastin-asetukset kertovat sen, ja painike vie sovelluksen asetuksiin.',
  ),
  NewFeature(
    '0.7.2',
    Icons.accessibility_new,
    'Parempi ruudunlukijan tuki',
    'TalkBack lukee sarjan painon ja toistot, kertoo tallennetun sarjan ja kalenterin päivät kokonaisina, ja tehdyn sarjan voi poistaa toiminnoista.',
  ),
  NewFeature(
    '0.7.1',
    Icons.fitness_center,
    'Etusivu pelkälle treenaajalle',
    'Ilman terveys- ja hyvinvointitoimintoja etusivulla treeniputki ohjelmasi treenipäivistä, viikon sarjat ja treeniaika sekä voiman kehitys heti ensimmäisestä treenistä.',
  ),
  NewFeature(
    '0.7',
    Icons.show_chart,
    'Palautumisen käyrät',
    'Napauta Palautuminen-ruutua: arvo 30 päivältä tai 12 viikolta, oma tavallinen vaihtelusi vihreänä vyönä ja asteikko.',
  ),
  NewFeature(
    '0.7',
    Icons.bedtime_outlined,
    'Unen lähde',
    'Jos kaksi laitetta (esim. sormus ja kello) kirjaa saman yön, Uni-kortti kysyy kerran, kumpaa käytetään. Yksittäisen yön lähteen voi vaihtaa kalenterin päivästä.',
  ),
  NewFeature(
    '0.7',
    Icons.fitness_center,
    'Paremmat ohjelmaehdotukset',
    'Liikkeet valituilla välineillä kaikissa yhdistelmissä; vammatilassa vaivalle hyvin siedetyt liikkeet ensin.',
  ),
  NewFeature(
    '0.6.9.2',
    Icons.monitor_heart_outlined,
    'Palautuminen uudistettu',
    'Ruudut värireunoin (vihreä, keltainen, punainen) omaan tasoosi verrattuna; ⚠-ruudusta neuvo. Mukana HRV, hengitys, happi, lämpö, uni ja kuormitus, jos kello tai sormus niitä tallentaa. Ruudut ja järjestys: Asetukset → Etusivu.',
  ),
  NewFeature(
    '0.6.9.2',
    Icons.bedtime_outlined,
    'Uni-kortti',
    'Viime yö, viikon keskiarvo ja säännöllisyys omaan tavalliseen uneesi verrattuna. Valinnainen: Asetukset → Etusivu.',
  ),
  NewFeature(
    '0.6.9.2',
    Icons.trending_up,
    'Kehitys Tilastoissa',
    'Yösyke, HRV ja uni 12 viikolta: Tilastot → Kehitys → Palautuminen ja uni.',
  ),
  NewFeature(
    '0.6.9.2',
    Icons.directions_run,
    'Juoksun kehitystavoitteet ja oma askeltavoite',
    'Vauhdin kehitys ja vauhti samalla sykkeellä omiin tavoitteisiin; askeltavoite Asetukset → Etusivu.',
  ),
  NewFeature(
    '0.6.9.2',
    Icons.fitness_center,
    'Hex bar ja liikekohtainen tanko',
    'Hex barin paino asetuksiin; levylaskuri muistaa tangon liikkeittäin.',
  ),
  NewFeature(
    '0.6.9.1',
    Icons.dashboard_customize_outlined,
    'Uusia etusivun kortteja',
    'Seuraava treeni ohjelmasta Aloita-painikkeella, Viikkoputki (montako viikkoa peräkkäin WHO:n suositukset täyttyivät; tauot eivät katkaise) ja Palautuminen: yön alin syke kellosta verrattuna tavalliseen tasoosi (Health Connect, vain sykkeen luku). Päälle, pois ja järjestys: Asetukset → Etusivu.',
  ),
  NewFeature(
    '0.6.9.1',
    Icons.fitness_center,
    'Lihaskuntopäivät yhtenä renkaana',
    'Salipäivät lasketaan lihaskuntopäiviin. Tavoite on ohjelmasi päivät viikossa, ilman ohjelmaa WHO:n vähimmäismäärä 2. Uusi liike: Reiden koukistus istuen.',
  ),
  NewFeature(
    '0.6.9',
    Icons.home_outlined,
    'Uusi etusivu',
    'Sali | Liikunta -painike avaa valinnan etusivun päälle: ohjelman päivät, viimeksi käytetyt lajit ja kellon harjoitukset. Viikko tai kuukausi renkaineen ja kalenterissa päivän askeleet.',
  ),
  NewFeature(
    '0.6.9',
    Icons.flag_outlined,
    'Omat tavoitteet ja kortit',
    'Asetukset → Etusivu: WHO:n suositusten lisäksi enintään kolme omaa tavoitetta (salipäivät, matka, aika tai kerrat) sekä kortit omassa järjestyksessä: Viimeksi, Voiman kehitys, Juoksun kehitys ja Kehonpaino.',
  ),
  NewFeature(
    '0.6.9',
    Icons.directions_run,
    'Juoksun kehitys matkoittain',
    'Vauhti ja syke viimeiset 4 viikkoa vs. 8 viikkoa ennen, omilla matkaryhmillä (oletus alle 5, 5–10 ja yli 10 km).',
  ),
  NewFeature(
    '0.6.9',
    Icons.local_fire_department_outlined,
    'Lämmittelysarjat',
    'Tallenna lämmittelysarjana -painike painoliikkeissä ensimmäiseen työsarjaan asti. Lämmittely ei vaikuta tavoitteeseen, ehdotuksiin eikä ennätyksiin, ja sarjan voi merkitä lämmittelyksi jälkikäteen.',
  ),
  NewFeature(
    '0.6.8',
    Icons.dashboard_outlined,
    'Uusi ulkoasu',
    'Alapalkki: Tänään, Ohjelma, Tilastot ja Lisää. Etusivulla Sali- ja Liikunta-valinta, päivän ehdotus ja viikon renkaat.',
  ),
  NewFeature(
    '0.6.8',
    Icons.directions_walk,
    'Treeni jatkuu taustalla',
    'Takaisin kesken liikunnan ei enää kysy tallennusta: ajanotto, GPS ja sykevyö jatkavat. Alapalkin yläpuolelta ja etusivun Jatka treeniä -painikkeesta palaat treeniin.',
  ),
  NewFeature(
    '0.6.8',
    Icons.local_fire_department_outlined,
    'Kalorit renkaana',
    'Kokonaiskulutus ja aktiiviset kalorit erikseen. Kävelyn kalorit lasketaan vauhdista ja pituudesta, myös ilman sykevyötä.',
  ),
  NewFeature(
    '0.6.8',
    Icons.insights,
    'Tilastot välilehdillä',
    'Viikko, Kehitys, Ennätykset, Kalenteri ja Askeleet omina välilehtinään. Paino ja pituus kuvaajalla.',
  ),
  NewFeature(
    '0.6.8',
    Icons.healing,
    'Vammatila ja tauko',
    'Vammatila keventää merkittyjen liikkeiden painoehdotusta ja tarjoaa korvaavan liikkeen. Tauolle voi valita viimeisen päivän tai merkitä tulevan loman etukäteen.',
  ),
  NewFeature(
    '0.6.8',
    Icons.notifications_none,
    'Ohjaus ilmoituksesta',
    'Palautukseen −15 s, +15 s ja Ohita, liikuntaan Tauko ja Jatka. Palautuksen voi mitata ajalla tai sykkeellä.',
  ),
  NewFeature(
    '0.6.8',
    Icons.search,
    'Haku asetuksissa',
    'Asetuksista löytää haulla. Health Connectin tiedot päivitetään tieto kerrallaan, ja päivityksen voi perua.',
  ),
  NewFeature(
    '0.6.7.2',
    Icons.swap_horiz,
    'Tämä tai tuo -liikkeet',
    'Ohjelman liikkeelle voi lisätä vaihtoehtoja (esim. penkki tai taukopenkki). Treenissä valitset, minkä teet tänään; jokaisella oma historia ja painoehdotus.',
  ),
  NewFeature(
    '0.6.7.2',
    Icons.drag_indicator,
    'Ohjelman muokkaus',
    'Liikkeiden järjestys vetämällä tai Siirrä ylös / alas, ja päiviä voi lisätä ja poistaa. Ohjelman ja treenin voi jakaa kuvana (WhatsApp ym.).',
  ),
  NewFeature(
    '0.6.7.2',
    Icons.bar_chart,
    'Tarkempi viikon kuorma',
    'Olkapää ja selkä osineen, käsivarret ja jalat ryhminä, pohkeet, kyynärvarret, lähentäjät ja keskivartalo omina riveinään.',
  ),
  NewFeature(
    '0.6.7.2',
    Icons.play_circle_outline,
    'Liikeohje liikettä valitessa',
    'Liikevalitsimen ▶ näyttää animaation ja vinkit ennen valintaa. Uudet liikkeet: kapea taukopenkki ja vinopenkki tauolla.',
  ),
  NewFeature(
    '0.6.7.2',
    Icons.lightbulb_outline,
    'Omat liikkeet',
    'Omalle liikkeelle valitaan lihakset, jolloin se näkyy viikon kuormassa. Liikkeen voi ehdottaa Gievraan (💡) ja poistaa pitkällä painalluksella.',
  ),
  NewFeature(
    '0.6.7.1',
    Icons.pool,
    'Uinnin vauhti 100 metrille',
    'Uinnin vauhdin voi näyttää muodossa min/100 m: Asetukset → Harjoittelu → Uinnin vauhti.',
  ),
  NewFeature(
    '0.6.7.1',
    Icons.speed,
    'Matkan ja ajan tarkistus',
    'Jos käsin syötetty matka ja aika tekevät lajille mahdottoman nopeuden (esim. 1 km ajassa 0:10), Gievra pyytää tarkistamaan ne ennen tallennusta.',
  ),
  NewFeature(
    '0.6.7',
    Icons.fitness_center,
    'Käsipainot yhteispainona',
    'Kahden käsipainon liikkeissä syötät nyt molempien käsipainojen yhteispainon, ja alla näkyy kummankin käden paino. Etusivu pyytää tarkistamaan kerran, olivatko vanhat painot yhteensä vai käsipainoa kohden.',
  ),
  NewFeature(
    '0.6.7',
    Icons.history,
    'Aiempi salitreeni yhteenvetona',
    'Kalenterista avattu salitreeni näyttää yhteenvedon liikkeineen ja sarjoineen. Muokkaa avaa liikelistan.',
  ),
  NewFeature(
    '0.6.7',
    Icons.view_agenda_outlined,
    'Selkeämpi sarjan kirjaus',
    'Paino, toistot ja tallennus ovat omana korttinaan, ja Merkitse liike valmiiksi on tehtyjen sarjojen alla, jottei sitä paina vahingossa.',
  ),
  NewFeature(
    '0.6.7',
    Icons.hexagon_outlined,
    'Farmer walk hex barilla',
    'Oma liike kuusikulmatangolla tehtävälle farmer walkille. Vanhat Farmer walk -kerrat voi siirtää siihen käsipainojen tarkistuksessa.',
  ),
  NewFeature(
    '0.6.6',
    Icons.show_chart,
    'Kellon sykekäyrä',
    'Health Connectista haettu syke tallentuu nyt käyränä ja sykealueina, kuten sykevyöllä. Vanhoihin treeneihin: hae kellon tiedot uudelleen.',
  ),
  NewFeature(
    '0.6.6',
    Icons.space_dashboard_outlined,
    'Uusi etusivu',
    'Tänään-kortissa Sali ja Liikunta ovat rinnakkain: useammin tekemäsi on leveämpi, ja Liikunta-puolella on viimeksi tekemäsi lajin kuvake. Kesken oleva salitreeni jatkuu Jatka-painikkeesta. Sama pari on myös kalenterin päivässä.',
  ),
  NewFeature(
    '0.6.6',
    Icons.flag_circle_outlined,
    'Uusi Treeni valmis -ikkuna',
    'Rasitus arvioidaan sykkeestä tai vauhdista (voit vaihtaa), salitreenin ennätykset ja painojen nousut näkyvät heti, ja voit merkitä liikkeet, jotka tuntuivat liian raskailta.',
  ),
  NewFeature(
    '0.6.6',
    Icons.visibility_outlined,
    'Tallennettu liikunta',
    'Vanha liikunta aukeaa yhteenvetona: aika, matka, vauhti, reitti ja syke. Muokkaa-painike avaa muokkauksen.',
  ),
  NewFeature(
    '0.6.6',
    Icons.directions_car_outlined,
    'Kyyti tunnistetaan',
    'Jos GPS-kävelyssä tai -juoksussa on autolla tai bussilla ajettu pätkä, Gievra kysyy, poistetaanko se matkasta ja ajasta.',
  ),
  NewFeature(
    '0.6.6',
    Icons.file_open_outlined,
    'Avaa Gievralla',
    'FitNotes-varmuuskopion, Gievran varmuuskopion (.zip), Garminin CSV:n ja .md-treenit voi avata Gievralla suoraan tiedostoista, sähköpostista tai Jaa-valikosta.',
  ),
  NewFeature(
    '0.6.6',
    Icons.battery_charging_full,
    'Treeni pysyy käynnissä',
    'Käynnissä olevan treenin ilmoitus pitää nyt Gievran käynnissä, kun näyttö on pois päältä: palautuksen ilmoitus tulee ajallaan. Älä sulje treenin ilmoitusta treenin aikana. Varmista myös, että Gievra saa toimia taustalla: Asetukset → Yleiset → Toiminta taustalla.',
  ),
  NewFeature(
    '0.6.6',
    Icons.favorite,
    'Palautus sykkeen mukaan',
    'Sykevyön kanssa palautusajastin voi odottaa, kunnes syke on laskenut, ja ilmoittaa silloin. Palautuksen ilmoitus on nyt lyhyt ponnahdus, joka poistuu itsestään. Asetukset → Keho ja laitteet → Sykevyö.',
  ),
  NewFeature(
    '0.6.6',
    Icons.monitor_heart_outlined,
    'Sykevyö',
    'Sykevyö Bluetoothilla (esim. Polar H10, Verity Sense, Garmin HRM): syke näkyy treenin ja palautuksen aikana, ja treeniin tallentuvat sykekäyrä, sykealueet ja tutkituilla menetelmillä lasketut kalorit. Asetukset → Keho ja laitteet → Sykevyö.',
  ),
  NewFeature(
    '0.6.6',
    Icons.format_size,
    'Tekstin koko',
    'Tekstin koon voi nyt valita. Sinun tekstisi pysyi ennallaan (Pieni). Isompi teksti: Asetukset → Yleiset → Tekstin koko → Normaali tai Suuri.',
  ),
  NewFeature(
    '0.6.5',
    Icons.donut_large,
    'Askeleet kalenterissa',
    'Vihreä rengas kalenterin päivämäärän ympärillä on sen päivän askeleet: täysi rengas on 10 000 askelta. Napauta päivää, niin näet tarkan määrän.',
  ),
  NewFeature(
    '0.6.5',
    Icons.favorite_border,
    'Viikon liikunta',
    'Etusivun kortin Viikko-puoli: reipasta liikuntaa 150 minuutin tavoitetta vasten (kova minuutti lasketaan kahdesti) ja lihaskuntopäivät, kuten WHO suosittelee.',
  ),
  NewFeature(
    '0.6.5',
    Icons.flag_outlined,
    'Treeni valmis ja fiilis',
    'Treenin ja liikunnan lopussa yksi painike, ja fiilis (liikunnassa myös rasitus) kysytään samassa ikkunassa. Uusi yhteenveto näyttää vain täytetyt tiedot.',
  ),
  NewFeature(
    '0.6.5',
    Icons.touch_app_outlined,
    'Liikkeen pitkä painallus',
    'Paina liikettä pitkään: lisää supersarjaan, pura supersarja tai poista liike tästä treenistä.',
  ),
  NewFeature(
    '0.6.5',
    Icons.timer_outlined,
    'Seuraava sarja palautuksessa',
    'Palautusajastin näyttää seuraavan sarjan painon ja toistot, joten voit vaihtaa painot tauon aikana.',
  ),
  NewFeature(
    '0.6.5',
    Icons.sports,
    'Uusi lajivalinta ja ajanotto',
    'Lajit hakuna ja ryhminä, viimeisimmät ensin. Ilman GPS:ää valitse Ajanotto (aloita, tauko, lopeta) tai Syötä itse.',
  ),
  NewFeature(
    '0.6.5',
    Icons.location_on_outlined,
    'GPS: 5 sekunnin laskenta',
    'Tallennus alkaa 5 sekunnin laskennan jälkeen, joten ehdit laittaa puhelimen taskuun. Ohita laskenta aloittaa heti.',
  ),
  NewFeature(
    '0.6.4',
    Icons.directions_walk,
    'Päivän askeleet',
    'Askeleet päivittäin Health Connectista (esim. puhelin ja Oura) ilman päällekkäisyyksiä; kävelymaton askeleet lisätään. Etusivun kortissa, kalenterissa renkaana ja tilastojen Askeleet-välilehdellä. Ota käyttöön: Asetukset → Keho ja laitteet → Päivän askeleet.',
  ),
  NewFeature(
    '0.6.4',
    Icons.today,
    'Päivän yhteenveto',
    'Kalenterin päivän napautus näyttää päivän treenit, ajan, matkan ja askeleet. Pyyhkäise sivulle vaihtaaksesi päivää.',
  ),
  NewFeature(
    '0.6.4',
    Icons.directions_run,
    'Juoksu etusivun kortissa',
    'Etusivun kortissa Edistyminen, Juoksu ja Askeleet: pyyhkäise tai valitse otsikosta. Juoksu näkyy, kun juoksuja on tallennettu.',
  ),
  NewFeature(
    '0.6.3',
    Icons.fitness_center,
    'Levylaskuri',
    'Tankoliikkeissä painon alla näkyy levyt puolta kohden. Napauta: kuva tangosta ja omat levyt.',
  ),
  NewFeature(
    '0.6.3',
    Icons.percent,
    'Prosenttia maksimista',
    'Sarjan kirjauksen %-painike näyttää painot 50–95 % arvioidusta maksimista. Ohjelmassa painon voi antaa prosentteina.',
  ),
  NewFeature(
    '0.6.3',
    Icons.link,
    'Supersarjat ja kiertoharjoittelu',
    'Liikkeet vuorotellen, tauko vasta kierroksen jälkeen. Ohjelmassa liikkeen kohdalla Supersarja A–D, treenissä ⋮ → Supersarjat.',
  ),
  NewFeature(
    '0.6.3',
    Icons.trending_down,
    'Pudotus- ja AMRAP-sarjat',
    'Sarjan tyyppi tallennuspainikkeiden yläpuolella: pudotus (kevyempi paino heti perään) tai AMRAP (niin monta toistoa kuin jaksat).',
  ),
  NewFeature(
    '0.6.3',
    Icons.timer_outlined,
    'Ajastin aikaliikkeisiin',
    'Lankku ja muut sekunteina mitattavat liikkeet: Aloita ajastin laskee alas ja ilmoittaa äänellä.',
  ),
  NewFeature(
    '0.6.3',
    Icons.auto_graph,
    'Tarkemmat painoehdotukset',
    'Tankoliikkeissä paino nousee 5 tai 10 kg ja toistot palaavat alueelle; toistoja ei lisätä loputtomiin. Kahvakuulalla seuraava kuula vasta, kun sillä onnistuu tarpeeksi toistoja.',
  ),
];

/// Versioiden vertailu numeroina: 0.6.10 > 0.6.9, 0.6 < 0.6.1.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Uudet ominaisuudet, joita ei ole vielä näytetty: version [seen] jälkeen, enintään nykyinen [current].
List<NewFeature> unseenFeatures(String current, String seen) => [
  for (final f in whatsNew)
    if (compareVersions(f.version, seen) > 0 && compareVersions(f.version, current) <= 0) f,
];

/// Uusimman version ominaisuudet, joka on enintään [current] (Tietoa-näkymän "Uutta tässä versiossa").
List<NewFeature> latestFeatures(String current) {
  final shown = whatsNew.where((f) => compareVersions(f.version, current) <= 0).toList();
  if (shown.isEmpty) return const [];
  final v = shown.first.version;
  return shown.where((f) => f.version == v).toList();
}
