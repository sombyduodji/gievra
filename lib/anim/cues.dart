// Tekniikkavinkit, lähde: docs/tutkimus/liikkeet.md (StrengthLog, ACE, Elixia; muotoilu valmennuskäytäntöä).
// Tarkistettu 2026-11-07: kaikki 122 liikettä, 22 korjattu (tekniikka ja kieli).

const exerciseCues = <String, List<String>>{
  "Takakyykky": [
    "Jalat hartioiden leveydellä, varpaat hieman ulos",
    "Lantio taakse ja alas, polvet varpaiden suuntaan",
    "Selkä neutraalina, paino koko jalkapohjalla",
  ],
  "Penkkipunnerrus": [
    "Lapaluut yhteen ja alas, pieni kaari selkään",
    "Tanko rinnan alaosaan, kyynärpäät ~45° kyljistä",
    "Jalat tukevasti lattiassa, paina tanko olkapäiden ylle",
  ],
  "Maastaveto": [
    "Tanko jalkapöydän keskikohdan päällä, sääret lähellä",
    "Selkä neutraali, ota löysät pois tangosta",
    "Työnnä lattiaa, lantio ja hartiat nousevat yhtä aikaa",
  ],
  "Sumomaastaveto": [
    "Leveä haara-asento, varpaat ulos",
    "Ote hartioiden levyinen jalkojen välistä",
    "Polvet ulos, rinta pystyssä, lantio lähellä tankoa",
  ],
  "Etukyykky": [
    "Tanko etuolkapäillä, kyynärpäät korkealla eteen",
    "Vartalo mahdollisimman pystyssä",
    "Polvet saavat liikkua varpaiden yli",
  ],
  "Taukopenkki": [
    "Laske tanko rinnalle ja pysäytä 1–2 s",
    "Pidä jännitys tauon ajan, älä upota tankoa",
    "Paina vasta, kun tanko on täysin pysähtynyt",
  ],
  "Pystypunnerrus": [
    "Ote hieman hartioita leveämpi, kyynärvarret pystyssä",
    "Pakarat ja vatsa tiukkana, ei taaksekallistusta",
    "Tanko suoraan ylös, pää läpi lopussa",
  ],
  "Low bar -kyykky": [
    "Tanko takaolkapäiden päällä lapaluun harjun alla",
    "Enemmän eteenkallistusta, lantio taakse",
    "Ranteet suorina, tanko jalkaterän keskikohdan yllä",
  ],
  "Box-kyykky": [
    "Istu hallitusti laatikolle, sääret lähes pystyssä",
    "Pysy jännittyneenä, älä rentoudu laatikolla",
    "Nouse räjähtävästi, rinta ja lantio nousevat yhtä aikaa",
  ],
  "Lattiapunnerrus": [
    "Makaa lattialla, polvet koukussa tai jalat suorina",
    "Laske, kunnes olkavarret koskettavat lattiaa",
    "Lyhyt pysäytys alhaalla, sitten paina",
  ],
  "Jalkaprässi": [
    "Jalat lantion leveydellä keskellä alustaa",
    "Laske niin syvälle kuin lantio ja alaselkä pysyvät penkissä",
    "Älä lukitse polvia ääriasentoon",
  ],
  "Romanialainen maastaveto": [
    "Polvet kevyesti koukussa (~15°), kulma pysyy samana",
    "Lantio taakse, tanko liukuu reisiä pitkin",
    "Laske niin alas kuin selkä pysyy suorana",
  ],
  "Suorin jaloin maastaveto": [
    "Lähde lattiasta, polvet lähes suorina",
    "Liike tulee lonkasta, selkä neutraali",
    "Tanko käy lattiassa joka toistolla",
  ],
  "Askelkyykky": [
    "Pitkä askel eteen, vartalo pystyssä",
    "Takapolvi lähes lattiaan, etupolvi varpaiden suuntaan",
    "Ponnista etujalan kantapäällä takaisin",
  ],
  "Bulgarialainen askelkyykky": [
    "Takajalan jalkapöytä penkillä",
    "Etujalka riittävän edessä, paino etujalalla",
    "Laske suoraan alas, lantio suorassa",
  ],
  "Askelkyykkykävely": [
    "Astu eteen vuorojaloin, älä palaa taaksepäin",
    "Takapolvi lähes lattiaan",
    "Vartalo pystyssä, katse eteen",
  ],
  "Reiden ojennus": [
    "Polvinivel laitteen akselin kohdalla",
    "Ojenna jalat suoriksi ja purista hetki",
    "Laske hallitusti, älä heilauta",
  ],
  "Reiden koukistus": [
    "Polvi akselin kohdalla, tyyny nilkan yläpuolella",
    "Koukista täysin, lantio pysyy alustassa",
    "Palauta hitaasti lähes suoraksi",
  ],
  "Hip thrust": [
    "Yläselkä penkin reunaa vasten, tanko lantiolla",
    "Leuka ja kylkiluut alas, nosta lantio",
    "Yläasennossa sääret pystyssä, polvet ~90°",
  ],
  "Pohjenousu seisten": [
    "Päkiät korokkeella, kantapäät vapaasti alas",
    "Nouse mahdollisimman korkealle",
    "Polvet suorina, laske hitaasti venytykseen",
  ],
  "Pohjenousu istuen": [
    "Polvet 90°, tyyny reisien päällä",
    "Nouse päkiöillä ylös ja purista",
    "Laske kantapäät syvälle",
  ],
  "Hack-kyykky": [
    "Selkä ja hartiat tiukasti tyynyjä vasten",
    "Jalat hieman edessä lantion levyisenä",
    "Laske syvälle, paina koko jalkapohjalla",
  ],
  "Goblet-kyykky": [
    "Käsipaino rinnan edessä, kyynärpäät alas",
    "Istu syvälle kantapäiden väliin",
    "Rinta ylhäällä, kyynärpäät polvien sisäpuolella",
  ],
  "Smith-kyykky": [
    "Jalat hieman tangon etupuolella",
    "Avaa koukut kiertämällä, selkä tiukkana",
    "Laske reidet vähintään vaakatasoon",
  ],
  "Lonkan loitonnus": [
    "Selkä tyynyä vasten, tyynyt polvien ulkopuolella",
    "Työnnä polvet ulos hallitusti",
    "Palauta hitaasti, älä kolauta painoja",
  ],
  "Lonkan lähennys": ["Tyynyt polvien sisäpuolella", "Purista reidet yhteen hallitusti", "Avaa hitaasti venytykseen"],
  "Good morning": [
    "Tanko yläselällä kuten kyykyssä",
    "Polvet kevyesti koukussa, lantio taakse",
    "Laske niin alas kuin selkä pysyy neutraalina, enintään vaakaan",
  ],
  "Nordic hamstring": [
    "Polvet pehmeällä alustalla, nilkat lukittuina tuen alle",
    "Vartalo suorana polvista päähän, lantio ojennettuna",
    "Laske hitaasti eteen, ota kiinni käsillä",
  ],
  "Kööpenhaminan lähennys": [
    "Kylkimakuu, ylempi jalka penkillä",
    "Nosta lantio, alempi jalka penkin alle",
    "Vartalo suorana, ei notkahdusta",
  ],
  "Pistoolikyykky": [
    "Seiso yhdellä jalalla, toinen jalka suorana eteen",
    "Laske hallitusti alas, polvi varpaiden suuntaan",
    "Aloita tuella (penkki tai TRX), jos tasapaino ei riitä",
  ],
  "Lantionnosto": [
    "Selinmakuu, polvet koukussa, kantapäät lähellä pakaroita",
    "Paina kantapäillä ja nosta lantio, kunnes vartalo on suorana",
    "Purista pakarat yläasennossa, älä notkista selkää",
  ],
  "Vinopenkki": [
    "Penkki 30–45° kulmaan",
    "Laske tanko ylärintaan solisluiden alle",
    "Lapaluut yhteen, kyynärpäät ~45° kyljistä",
  ],
  "Käsipainopenkki": [
    "Käsipainot rinnan sivuilla, kämmenet jalkoihin päin",
    "Laske syvälle, kyynärpäät ~45° kyljistä",
    "Paina ylös ja hieman yhteen",
  ],
  "Vinokäsipainopenkki": ["Penkki 30–45° kulmaan", "Käsipainot ylärinnan sivuille", "Paina ylös hartioiden linjaan"],
  "Kaapeliristikkäis": [
    "Seiso taljojen välissä, pieni askel eteen",
    "Kyynärpäät hieman koukussa, kulma pysyy",
    "Tuo kädet kaaressa yhteen rinnan eteen",
  ],
  "Dipit": [
    "Kädet nojapuilla, aloita kädet suorina",
    "Kallista vartaloa hieman eteen",
    "Laske, kunnes olkavarret ovat vaakatasossa, paina ylös",
  ],
  "Punnerrus": [
    "Kädet hieman hartioita leveämmälle",
    "Vartalo suorana päästä kantapäihin",
    "Rinta lähes lattiaan, kyynärpäät ~45°",
  ],
  "Peck deck": [
    "Säädä istuin niin, että kahvat ovat rinnan korkeudella",
    "Kyynärpäät hieman koukussa, rinta ylhäällä",
    "Tuo kahvat yhteen, palauta venytykseen",
  ],
  "Käsipainoaukaisu": [
    "Käsipainot rinnan yllä, kämmenet vastakkain",
    "Avaa kaarella sivuille, kyynärpäät hieman koukussa",
    "Laske vain hartioiden tasolle",
  ],
  "Rintaprässi laitteessa": [
    "Säädä istuin: kahvat rinnan keskikohdalla",
    "Lapaluut tyynyä vasten, rinta ylhäällä",
    "Paina lähes suoriksi, palauta hallitusti",
  ],
  "Smith-vinopenkki": [
    "Penkki 30–45° Smithin alle",
    "Tanko laskeutuu ylärintaan",
    "Lapaluut yhteen, paina suoraan ylös",
  ],
  "Leuanveto": [
    "Myötäote hieman hartioita leveämpi",
    "Aloita painamalla lapaluut alas",
    "Leuka tangon yli, laske kädet suoriksi",
  ],
  "Leuanveto vastaotteella": [
    "Vastaote hartioiden levyisenä",
    "Rinta kohti tankoa, kyynärpäät kylkiin",
    "Laske hallitusti kädet suoriksi",
  ],
  "Ylätalja": [
    "Reidet tukien alle, ote hieman hartioita leveämpi",
    "Vedä tanko solisluihin, rinta ylös",
    "Kyynärpäät alas, älä nykäise vartalolla",
  ],
  "Kulmasoutu": [
    "Ylävartalo 45°:sta lähes vaakatasoon, selkä neutraalina",
    "Vedä tanko alarintaan tai vatsaan, kyynärpäät taakse",
    "Vartalon kulma pysyy koko sarjan",
  ],
  "Alatalja": ["Istu suorana, polvet hieman koukussa", "Vedä kahva vatsaan, lapaluut yhteen", "Älä keinu vartalolla"],
  "Käsipainosoutu": [
    "Toinen käsi ja polvi penkillä, selkä suorana",
    "Vedä käsipaino lantion suuntaan",
    "Kyynärpää lähellä kylkeä, ei kiertoa",
  ],
  "Rintatuettu kulmasoutu käsipainoilla": [
    "Vatsallaan vinopenkillä (30–45°), rinta tukea vasten, jalat maassa",
    "Vedä kyynärpäät ylös ja taakse, lapaluut yhteen",
    "Rinta pysyy penkissä, laske hallitusti suoriksi käsiksi",
  ],
  "T-tankosoutu": [
    "Tanko jalkojen välissä, kahva rinnan alla",
    "Selkä suorana ~45°, polvet koukussa",
    "Vedä kahva rintaan, purista lapaluut",
  ],
  "Pendlay-soutu": [
    "Vartalo lähes vaakatasossa, tanko lattiassa",
    "Räjähtävä veto alarintaan",
    "Laske tanko lattiaan joka toistolla",
  ],
  "Selän ojennus": [
    "Tyyny reisien yläosassa, lantio vapaasti reunan yli",
    "Laske ylävartalo hallitusti lonkasta, selkä neutraalina",
    "Nouse suoraan linjaan, älä yliojenna",
  ],
  "Olankohautus": [
    "Kädet suorina, tanko reisien edessä",
    "Nosta hartiat suoraan korvia kohti",
    "Pidä hetki ylhäällä, laske täyteen venytykseen",
  ],
  "Suorin käsin ylätalja": [
    "Seiso taljan edessä, pieni eteenkallistus",
    "Kädet lähes suorina, kyynärkulma pysyy",
    "Vedä tanko reisiin hartiat alhaalla",
  ],
  "Rack pull": [
    "Tanko telineessä polvien kohdalla",
    "Selkä neutraali, hartiat tangon päällä",
    "Ojenna lantio ja polvet, älä yliojenna",
  ],
  "Soutu laitteessa": [
    "Rinta tyynyä vasten, istuin säädetty",
    "Vedä kahvat kylkiin, lapaluut yhteen",
    "Palauta hallitusti kädet suoriksi",
  ],
  "Australialainen leuanveto": [
    "Tanko tai renkaat vyötärön korkeudella, vartalo suorana tangon alla",
    "Vedä rinta tankoon, lapaluut yhteen",
    "Mitä vaakatasoisempi vartalo, sitä raskaampi liike",
  ],
  "Käsipainopystypunnerrus": [
    "Käsipainot hartioiden korkeudella, kämmenet eteen",
    "Vatsa tiukkana, ei taaksekallistusta",
    "Paina ylös ja hieman yhteen",
  ],
  "Vipunosto sivulle": [
    "Kyynärpäät hieman koukussa, kädet sivuille",
    "Nosta hartioiden korkeudelle, ei korkeammalle",
    "Älä heilauta, laske hitaasti",
  ],
  "Vipunosto eteen": [
    "Kädet lähes suorina",
    "Nosta eteen hartioiden korkeudelle",
    "Vartalo paikallaan, laske hallitusti",
  ],
  "Takaolkavipunosto": [
    "Ylävartalo lähes vaakaan, selkä suorana",
    "Nosta kädet sivuille kyynärpäät edellä",
    "Laske hitaasti, ei heilautusta",
  ],
  "Arnold-punnerrus": [
    "Aloita käsipainot leuan edessä, kämmenet itseen",
    "Kierrä kämmenet eteen samalla kun painat",
    "Laske samaa reittiä kiertäen",
  ],
  "Pystysoutu": [
    "Ote hartioiden levyinen, tanko lähellä vartaloa",
    "Kyynärpäät johtavat ylös",
    "Kyynärpäät enintään hartioiden korkeudelle",
  ],
  "Face pull": [
    "Talja kasvojen korkeudelle tai hieman pään yläpuolelle, köysi ylhäältä",
    "Vedä köyttä otsaa kohti, kyynärpäät korkealla ja ulos",
    "Kädet erilleen korvien viereen kuin laittaisit aurinkolasit päähän",
  ],
  "Push press": [
    "Tanko etuolkapäillä, ote kuin pystypunnerruksessa",
    "Pieni nopea polvien koukistus, vartalo pystyssä",
    "Räjähdä jaloilla ja paina suoraan ylös",
  ],
  "Vipunosto taljassa": [
    "Talja alhaalla, kahva vastakkaisessa kädessä",
    "Nosta käsi sivulle hartian korkeudelle",
    "Laske hitaasti, vastus pysyy",
  ],
  "Olkapääprässi laitteessa": [
    "Kahvat hartioiden korkeudella",
    "Selkä tukevasti tyynyä vasten",
    "Paina lähes suoriksi, laske hallitusti",
  ],
  "Ulkokierto taljassa": [
    "Talja kyynärpään korkeudella, seiso sivuttain",
    "Kyynärpää kyljessä, kulma 90°",
    "Kierrä kättä ulospäin, ei vartalon kiertoa",
  ],
  "Pike-punnerrus": [
    "Lantio korkealla, vartalo ylösalaisin V-asennossa",
    "Laske pää käsien väliin, kyynärpäät taakse",
    "Paina takaisin ylös, olkapäät tekevät työn",
  ],
  "Hauiskääntö tangolla": [
    "Ote hartioiden levyinen, kyynärpäät kyljissä",
    "Koukista tanko hartioiden korkeudelle",
    "Ei heilutusta, laske kädet suoriksi",
  ],
  "Hauiskääntö käsipainoilla": [
    "Kyynärpäät kyljissä",
    "Käännä kämmenet ylös nostaessasi",
    "Laske hitaasti kädet suoriksi",
  ],
  "Vasarakääntö": ["Kämmenet vastakkain koko liikkeen", "Kyynärpäät paikallaan kyljissä", "Laske hallitusti alas"],
  "Scott-kääntö": [
    "Olkavarret tiukasti tyynyä vasten",
    "Laske lähes suoraksi, ei rajua lukitusta",
    "Koukista ylös, olkapäät rentona",
  ],
  "Hauiskääntö taljassa": [
    "Seiso lähellä taljaa, kyynärpäät kyljissä",
    "Koukista kahva hartioille",
    "Laske hitaasti, vastus pysyy",
  ],
  "Keskittynyt hauiskääntö": [
    "Istu, kyynärpää reiden sisäsyrjää vasten",
    "Koukista paino olkapäätä kohti",
    "Olkavarsi paikallaan, laske hitaasti",
  ],
  "Ojentajapunnerrus taljassa": [
    "Kyynärpäät kyljissä, olkavarret paikallaan",
    "Ojenna kädet suoriksi alas",
    "Palauta, kunnes kyynärkulma on ~90°",
  ],
  "Ranskalainen punnerrus": [
    "Makaa penkillä, tanko otsan yllä kädet suorina",
    "Laske otsalle koukistamalla vain kyynärpäitä",
    "Olkavarret pysyvät paikallaan",
  ],
  "Kapea penkki": ["Ote hartioiden levyinen", "Kyynärpäät lähellä kylkiä", "Tanko rinnan alaosaan, paina suoriksi"],
  "Ojentajapunnerrus pään yli": [
    "Kädet pään yllä, kyynärpäät osoittavat ylös",
    "Laske paino pään taakse venytykseen",
    "Ojenna suoriksi, olkavarret paikallaan",
  ],
  "Penkkidipit": [
    "Kädet penkin reunalla takana, sormet eteen",
    "Laske, kunnes kyynärpäät ovat ~90°",
    "Selkä lähellä penkkiä, paina suoriksi",
  ],
  "Ranteen koukistus": [
    "Kyynärvarret reisien päällä, kämmenet ylös",
    "Anna tangon rullata sormille",
    "Koukista ranne ylös, kyynärvarsi paikallaan",
  ],
  "Ranteen ojennus": ["Kämmenet alas, kyynärvarret tuettuina", "Nosta rystyset ylös", "Kevyt paino, laske hitaasti"],
  "Lankku": [
    "Kyynärpäät hartioiden alla",
    "Vartalo suorana, pakarat ja vatsa tiukkana",
    "Älä anna lantion notkahtaa tai nousta",
  ],
  "Vatsarutistus": [
    "Selinmakuu, polvet koukussa ~90°",
    "Rullaa lapaluut irti, alaselkä alustassa",
    "Uloshengitys ylös, laske hallitusti",
  ],
  "Jalannosto roikkuen": [
    "Roiku kädet suorina, hartiat aktiivisina",
    "Nosta jalat ja rullaa lantio ylös",
    "Laske hallitusti, ei heiluntaa",
  ],
  "Ab wheel": [
    "Polvillaan, rulla hartioiden alla, vatsa tiukkana",
    "Rullaa eteen vain niin pitkälle kuin alaselkä ei notkahda",
    "Vedä takaisin vatsalla, ei lantiolla",
  ],
  "Pallof press": [
    "Seiso sivuttain taljaan, kahva rinnalla",
    "Paina suoriksi eteen, vastusta kiertoa",
    "Pidä 1–2 s, tuo takaisin",
  ],
  "Venäläinen twisti": [
    "Istu, vartalo ~45° taaksepäin, selkä suorana",
    "Jalat lattiassa tai ilmassa",
    "Kierrä ylävartaloa puolelta toiselle",
  ],
  "Kaapelirutistus": [
    "Polvillaan taljan edessä, köysi pään sivuilla",
    "Rutista vatsalla, kyynärpäät kohti polvia",
    "Lantio paikallaan, älä istu kantapäille",
  ],
  "Kylkilankku": [
    "Kyynärpää hartian alla, vartalo suorana",
    "Lantio ylhäällä, ei notkahdusta",
    "Jalat päällekkäin tai porrastettuina",
  ],
  "Farmer walk": [
    "Raskaat painot sivuilla, kädet suorina",
    "Hartiat alas ja taakse, vartalo pystyssä",
    "Lyhyet nopeat askeleet, tiukka ote",
  ],
  "Kyykky kehonpainolla": [
    "Jalat hartioiden leveydellä, kädet eteen tasapainoksi",
    "Lantio taakse ja alas, kunnes reidet ovat vaakatasossa",
    "Paino koko jalkapohjalla, polvet varpaiden suuntaan",
  ],
  "Hyppykyykky": [
    "Kyykky reisien vaakatasoon, kädet taakse",
    "Räjähdä ylös ja heilauta kädet eteen",
    "Laskeudu pehmeästi päkiöille ja suoraan seuraavaan kyykkyyn",
  ],
  "Sissy-kyykky": [
    "Ota tuesta kiinni, nouse päkiöille",
    "Polvet eteen ja vartalo taakse samalla linjalla polvista hartioihin",
    "Laske hallitusti niin alas kuin polvet sallivat ja ojenna takaisin",
  ],
  "Käänteinen nordic": [
    "Polvillaan, sääret lattiassa, vartalo pystyssä",
    "Kallistu taaksepäin vartalo ja reidet suorana linjana",
    "Palaa etureisillä ylös, lantio ei saa taittua",
  ],
  "Askelnousu": [
    "Koko jalkapohja korokkeelle, polvi varpaiden suuntaan",
    "Nouse ylös etujalan voimalla, älä ponnista takajalalla",
    "Laskeudu hallitusti samaa reittiä",
  ],
  "Jalat koholla punnerrus": [
    "Jalat penkillä tai korokkeella, kädet hartioiden alla",
    "Vartalo suorana, laske rinta lähelle lattiaa",
    "Mitä korkeammalla jalat, sitä enemmän työ siirtyy ylärintaan ja olkapäihin",
  ],
  "Timanttipunnerrus": [
    "Kädet yhdessä rinnan alla, peukalot ja etusormet timantin muodossa",
    "Kyynärpäät vartalon vierellä taaksepäin",
    "Vartalo suorana koko liikkeen ajan",
  ],
  "Ojentajaojennus kehonpainolla": [
    "Kädet tangolla tai penkillä otsan korkeudella, vartalo suorana kallistettuna",
    "Laske otsa kohti tankoa koukistamalla vain kyynärpäitä",
    "Ojenna kädet suoriksi; mitä matalampi tanko, sitä raskaampi liike",
  ],
  "Kehonpainohauiskääntö": [
    "Vastaote matalasta tangosta tai renkaista, vartalo suorana kallistettuna",
    "Koukista kyynärpäät ja vedä otsa kohti käsiä",
    "Olkavarret paikallaan, vain kyynärnivel liikkuu",
  ],
  "Käsilläseisontapunnerrus": [
    "Käsilläseisonta seinää vasten, kädet hieman hartioita leveämmällä",
    "Laske pää hallitusti lattiaa kohti, kyynärpäät hieman eteen",
    "Opettele ensin pike-punnerrus ja käsilläseisonta seinää vasten",
  ],
  "Y-T-W-nostot makuulla": [
    "Vatsallaan, otsa lattiassa, peukalot ylöspäin",
    "Nosta kädet Y-, T- ja W-asentoihin lapaluita yhteen puristaen",
    "Pidä hetki ylhäällä, niska neutraalina",
  ],
  "Yhden jalan lantionnosto": [
    "Selinmakuu, toinen jalka suorana ilmassa",
    "Paina tukijalan kantapäällä ja nosta lantio suoraksi linjaksi",
    "Lantio ei saa kallistua sivulle, purista pakaraa ylhäällä",
  ],
  "Reiden koukistus kehonpainolla": [
    "Selinmakuu, kantapäät liukualustalla tai pyyhkeen päällä, lantio ylhäällä",
    "Vedä kantapäät pakaroita kohti lantio koholla",
    "Liu'uta jalat hallitusti takaisin suoriksi",
  ],
  "Veneasento": [
    "Selinmakuu, alaselkä painettuna lattiaan",
    "Nosta hartiat ja suorat jalat irti lattiasta, kädet pään yli",
    "Pidä asento; helpota koukistamalla polvia",
  ],
  "Dead bug": [
    "Selinmakuu, kädet suoraan ylös, polvet 90°",
    "Ojenna vastakkainen käsi ja jalka hitaasti lähes lattiaan",
    "Alaselkä pysyy lattiassa koko ajan, vaihda puolta",
  ],
  "Superman-nosto": [
    "Vatsallaan, kädet suorina pään yli",
    "Nosta kädet, rinta ja jalat hetkeksi irti lattiasta",
    "Katse lattiaan, niska neutraalina, laske hallitusti",
  ],
  "Burpee": [
    "Kyykky, kädet lattiaan ja hyppää jalat taakse punnerrusasentoon",
    "Punnerrus (valinnainen), jalat takaisin käsien viereen",
    "Hyppää ylös kädet pään yli ja laskeudu pehmeästi",
  ],
  "Kahvakuulaheilautus": [
    "Lonkkasarana, ei kyykky: lantio taakse, sääret lähes pystyssä",
    "Räjähtävä lantion ojennus heittää kuulan rinnan korkeudelle",
    "Kädet ovat vain koukut, pakarat ja vatsa tiukkana yläasennossa",
  ],
  "Yhden käden heilautus": [
    "Kuten heilautus, mutta yhdellä kädellä",
    "Älä anna vartalon kiertyä, olkapää pysyy paikallaan",
    "Vapaa käsi sivulla tasapainona",
  ],
  "Kahvakuulamaastaveto": [
    "Kuula jalkojen välissä, keskijalan kohdalla",
    "Selkä neutraalina, lantio taakse, ota kahvasta kiinni",
    "Työnnä lattiaa ja nouse suoraksi, purista pakarat",
  ],
  "Kahvakuulan rinnalleveto": [
    "Heilauta kuula jalkojen välistä ja vedä se lähellä vartaloa",
    "Käsi kiertyy kuulan ympäri, ettei kuula kolahda ranteeseen",
    "Kuula lepää etuasennossa: kyynärpää kyljessä, ranne suorana",
  ],
  "Kahvakuulapystypunnerrus": [
    "Aloita etuasennosta, ranne suorana",
    "Paina ylös, kyynärvarsi pystyssä koko ajan",
    "Ei taaksekallistusta, pakarat ja vatsa tiukkana",
  ],
  "Rinnalleveto ja punnerrus": [
    "Rinnalleveto etuasentoon, pysäytä hetkeksi",
    "Paina suoraan ylös, vatsa ja pakarat tiukkana",
    "Laske etuasentoon ja takaisin jalkojen väliin",
  ],
  "Kahvakuulatempaus": [
    "Heilautuksesta yhtenä liikkeenä suoraan pään yli",
    "Pidä kuula lähellä vartaloa ja työnnä käsi läpi lopussa",
    "Opettele heilautus ja rinnalleveto ensin",
  ],
  "Tuplakahvakuulaheilautus": [
    "Kuulat jalkojen välissä, jalat hieman leveämmällä kuin yhdellä kuulalla",
    "Lantio taakse ja räjähdä eteen, kädet vain ohjaavat",
    "Pysäytä kuulat rinnan korkeudelle, selkä neutraalina",
  ],
  "Tuplakahvakuulamaastaveto": [
    "Kuulat jalkojen vieressä, keskijalan kohdalla",
    "Lantio taakse, selkä neutraalina, tartu molempiin kahvoihin",
    "Työnnä lattiaa ja nouse suoraksi, kuulat lähellä vartaloa",
  ],
  "Tuplakahvakuulan rinnalleveto": [
    "Heilauta molemmat kuulat jalkojen välistä yhtä aikaa",
    "Vedä kuulat lähellä vartaloa ja kierrä kädet niiden ympäri",
    "Etuasento: kyynärpäät kyljissä, ranteet suorina",
  ],
  "Tuplakahvakuulapystypunnerrus": [
    "Aloita etuasennosta, kuulat ja ranteet suorassa linjassa",
    "Paina molemmat ylös, kyynärvarret pystyssä",
    "Pakarat ja vatsa tiukkana, ei taaksekallistusta",
  ],
  "Tuplakahvakuulatyöntö": [
    "Etuasennosta pieni polvikoukku ja räjähdä ylös",
    "Pudottaudu kuulien alle toisella polvikoukulla, kädet suoriksi",
    "Nouse suoraksi kuulat pään päällä, laske etuasentoon",
  ],
  "Tuplakahvakuulan rinnalleveto ja punnerrus": [
    "Rinnalleveto molemmilla kuulilla etuasentoon",
    "Paina suoraan ylös, vatsa ja pakarat tiukkana",
    "Laske etuasentoon ja heilauta takaisin jalkojen väliin",
  ],
  "Tuplakahvakuulasoutu": [
    "Kallista ylävartalo eteen, selkä neutraalina, polvet koukussa",
    "Vedä kuulat kohti lantiota, kyynärpäät lähellä kylkiä",
    "Lapaluut yhteen ylhäällä, laske hallitusti",
  ],
  "Tuplakahvakuulalattiapunnerrus": [
    "Selinmakuu, polvet koukussa, kuulat etuasennossa rinnan päällä",
    "Paina molemmat ylös, ranteet suorina",
    "Laske kunnes olkavarret koskettavat lattiaa",
  ],
  "Tuplakahvakuula-askelkyykky": [
    "Kuulat etuasennossa tai käsissä sivuilla",
    "Astu taakse ja laske takapolvi lähelle lattiaa",
    "Työnnä etujalan kantapäästä takaisin ylös, vartalo pystyssä",
  ],
  "Kahvakuulan sumomaastaveto": [
    "Jalat leveällä, varpaat ulos, kuula keskellä jalkojen välissä",
    "Lantio taakse ja alas, selkä neutraalina, polvet varpaiden suuntaan",
    "Työnnä lattiaa ja nouse suoraksi, kuula lähellä vartaloa",
  ],
  "Kahvakuulan sumoveto": [
    "Sumoasento, kuula jalkojen välissä kahdella kädellä",
    "Nouse räjähtävästi ja vedä kuula leuan korkeudelle, kyynärpäät ylös ja ulos",
    "Laske hallitusti takaisin, selkä neutraalina",
  ],
  "Kahvakuulahauiskääntö": [
    "Pidä kuulaa kahvasta tai sarvista, kyynärpäät kyljissä",
    "Koukista kyynärpäät ja nosta kuula rintaa kohti",
    "Laske hallitusti, älä heilauta vartalolla",
  ],
  "Kahvakuula-askelkyykky": [
    "Kuula etuasennossa tai kädessä sivulla",
    "Astu eteen tai taakse ja laske takapolvi lähelle lattiaa",
    "Työnnä etujalan kantapäästä ylös, vartalo pystyssä",
  ],
  "Lentokone": [
    "Seiso yhdellä jalalla, kallista vartalo eteen kuin yhden jalan maastavedossa",
    "Kierrä lantiota hitaasti auki ja takaisin kiinni tukijalan päällä",
    "Pidä tukipolvi kevyesti koukussa; aloita ilman painoa tai kevyellä kuulalla",
  ],
  "Kahvakuulan etukyykky": [
    "Kaksi kuulaa etuasennossa, kyynärpäät alhaalla",
    "Istu kantapäiden väliin, rinta ylhäällä",
    "Polvet varpaiden suuntaan, nouse koko jalkapohjalla",
  ],
  "Kahvakuula-thruster": [
    "Etukyykky etuasennossa olevilla kuulilla",
    "Ylös noustessa jatka vauhti suoraan punnerrukseen",
    "Laske kuulat etuasentoon ja seuraava toisto",
  ],
  "Yhden jalan maastaveto": [
    "Paino tukijalalla, polvi kevyesti koukussa",
    "Kallista vartaloa eteen, takajalka nousee vartalon jatkeeksi",
    "Lantio suorassa, älä anna sen kiertyä auki",
  ],
  "Kahvakuulasoutu": [
    "Vapaa käsi penkillä tai polvella, selkä suorana",
    "Vedä kuula lantiota kohti, kyynärpää lähellä kylkeä",
    "Laske hallitusti, älä kierrä vartaloa",
  ],
  "Renegade-soutu": [
    "Punnerrusasento kuulien tai käsipainojen päällä",
    "Jalat leveällä, vedä yksi kuula kerrallaan kylkeen",
    "Lantio pysyy paikallaan, ei kiertoa",
  ],
  "Kahvakuulalattiapunnerrus": [
    "Selinmakuu lattialla, kuula etuasennossa",
    "Paina suoraan ylös, ranne suorana",
    "Laske, kunnes olkavarsi koskettaa lattiaa",
  ],
  "Turkkilainen ylösnousu": [
    "Kuula suoralla kädellä ylhäällä koko liikkeen ajan, katse kuulaan",
    "Nouse vaiheittain: kyynärpää, käsi, lantio ylös, jalka alle, seisomaan",
    "Opettele ensin ilman painoa tai kengällä kämmenellä",
  ],
  "Tuulimylly": [
    "Kuula ylhäällä suoralla kädellä, jalat hartioiden levyisinä",
    "Lantio työntyy kuulan puolelle, vartalo kallistuu alas toisen jalan viereen",
    "Katse kuulaan, ylempi käsi pysyy pystysuorana",
  ],
  "Matkalaukkukanto": [
    "Raskas kuula yhdessä kädessä sivulla",
    "Vartalo suorana, älä kallistu kuulan puolelle",
    "Lyhyet askeleet, vaihda kättä matkan välein",
  ],
  "Vinopunnerrus": [
    "Kädet penkin tai tason reunalla hartioiden levyisinä",
    "Vartalo suorana kantapäistä päähän, laske rinta reunaan",
    "Mitä matalampi taso, sitä raskaampi; siirry lopulta lattialle",
  ],
  "Polvipunnerrus": [
    "Polvet lattiassa, vartalo suorana polvista päähän",
    "Kädet hartioiden alla, kyynärpäät ~45° kyljistä",
    "Laske rinta lähelle lattiaa ja paina ylös",
  ],
  "Negatiivinen leuanveto": [
    "Hyppää tai nouse korokkeelta ylös leuka tangon yli",
    "Laskeudu hitaasti 3–5 sekunnissa kädet suoriksi",
    "Hartiat aktiivisina koko laskun ajan",
  ],
  "Kuminauhaleuanveto": [
    "Kuminauha tangon ympäri, polvi tai jalka nauhan päälle",
    "Vedä rinta kohti tankoa lapaluut alas",
    "Vaihda ohuempaan nauhaan, kun toistot kulkevat helposti",
  ],
  "Roikunta": [
    "Ota tangosta kiinni hartioiden levyisellä otteella",
    "Roiku kädet suorina, vartalo rentona tai hartiat aktiivisina",
    "Pidä aika; vahvistaa otetta ja olkapäitä leuanvetoon",
  ],
  "Lapaluuveto roikkuen": [
    "Roiku tangossa kädet suorina",
    "Vedä lapaluut alas ja yhteen ilman kyynärpäiden koukistusta",
    "Vartalo nousee vain muutaman sentin, laske hallitusti",
  ],
  "Seinäistunta": [
    "Selkä seinää vasten, liu'u alas, kunnes reidet ovat vaakatasossa",
    "Polvet nilkkojen yläpuolella, paino kantapäillä",
    "Pidä asento; helpota nousemalla ylemmäs",
  ],
  "Lintukoira": [
    "Konttausasento, kädet hartioiden ja polvet lantion alla",
    "Ojenna vastakkainen käsi ja jalka suoriksi, selkä neutraalina",
    "Pidä hetki, lantio ei kierry, vaihda puolta",
  ],
  "Vuorikiipeilijä": [
    "Punnerrusasento, kädet hartioiden alla",
    "Tuo polvet vuorotellen rintaa kohti",
    "Lantio matalana, vatsa tiukkana, rauhallinen tahti ensin",
  ],
  "Karhukävely": [
    "Konttausasento, polvet hieman irti lattiasta",
    "Kävele eteen vastakkainen käsi ja jalka yhtä aikaa",
    "Selkä suorana ja lantio matalana, polvet pysyvät irti",
  ],
  "Yhden jalan pohjenousu": [
    "Seiso yhdellä jalalla korokkeen reunalla, ota tuesta kiinni",
    "Laske kantapää alas venytykseen",
    "Nouse päkiälle niin korkealle kuin pääset",
  ],
};
