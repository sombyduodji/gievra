# Exercise catalog and template review (treenipäiväkirja)

**How the sources were checked:** ExRx.net blocked every fetch (HTTP 403), so no ExRx claim below was verified. I verified muscle claims on StrengthLog pages and the ACE library index. Finnish names were checked against Elixia.fi and search results from fitwill/lyfta, and spelling with Voikko. Anything marked **[konv.]** is coaching convention, not a sourced fact.

---

## 1. Category, colouring and measurement

### Category corrections
Only these need a change. Everything else is fine.

| Exercise | Now | Suggested | Why / source |
|---|---|---|---|
| Face pull | Selkä | **Olkapäät** | StrengthLog: primary muscles are the rear delts and rotator cuff; traps and side delts are secondary. Your TAK (rear delt) slot already uses it that way. |
| Olankohautus | Olkapäät | **Selkä** (optional) | StrengthLog: primary muscle is the upper traps. ACE's "Shoulders" group only has deltoid and rotator-cuff subgroups. Putting shrugs on shoulder day is also common **[konv.]**, so this one is optional. |
| Pystypunnerrus | Voimanosto | Olkapäät (optional) | Not a competition lift. Moving it changes nothing in practice (it stays coloured upper). **[konv.]** |

### Checked and correct as they are
- **Hip thrust** in Jalat: StrengthLog lists glutes as primary, adductors and quads as secondary. ACE has a separate Butt/Hips group, but the app has no glute category, so Jalat is right.
- **Kapea penkki** in Kädet: StrengthLog lists triceps as primary, chest and front delts as secondary.
- **Good morning** in Jalat: StrengthLog lists glutes, lower back and hamstrings as primary.
- **Rack pull** in Selkä: StrengthLog lists glutes and lower back as primary, with less quad work than a deadlift. The category is OK, but see colouring below.
- **Farmer walk** in Keskivartalo: StrengthLog lists grip, obliques, glutes and traps as primary, so it is really a full-body lift (ACE has a "Full Body/Integrated" group). Since the app has no such category, Keskivartalo is acceptable.
- **Kööpenhaminan lähennys** in Jalat: StrengthLog lists the adductors as primary.
- **Hyperextensio** in Selkä: StrengthLog lists glutes and lower back as primary.
- **Lattiapunnerrus** in Voimanosto: StrengthLog lists chest and front delts as primary, triceps as secondary.
- Dipit in Rinta, Ulkokierto taljassa in Olkapäät (rotator cuff, per ACE) and Suorin käsin ylätalja in Selkä are also fine.

### Body-group colouring
- **Rack pull is coloured upper (it sits in Selkä)**, but every other hinge (Maastaveto, Romanialainen, Good morning) is coloured legs. StrengthLog's primary muscles for it are glutes and lower back. I suggest a per-exercise override to **legs**.
- Hyperextensio (upper) and Push press (upper) are acceptable.
- Everything else matches the rule.

### Measurement types
- **Lankku / Kylkilankku = seconds**: correct.
- **Kööpenhaminan lähennys = reps**: OK. StrengthLog says it is done either as a timed hold or as dynamic reps, so consider allowing seconds too.
- **Farmer walk = round trips**: workable. The usual records are load per hand plus distance in metres or time in seconds **[konv.]**. Make sure the weight field is always shown.
- **Askelkyykkykävely = steps**: OK. Label whether the count is total steps or steps per leg.
- **Per-side exercises**: Käsipainosoutu, Bulgarialainen askelkyykky, Askelkyykky, Keskittynyt hauiskääntö, Vipunosto taljassa, Ulkokierto taljassa, Kööpenhaminan lähennys, Kylkilankku and Venäläinen twisti (reps per side) should be labelled "/puoli" **[konv.]**.
- **Leuanveto / Dipit**: added weight is fine, but assisted (negative) load isn't supported. Optional.

## 2. Finnish names (minimal changes)

| Name | Comment |
|---|---|
| Suorin jaloin maastaveto | Keep it. Note that Elixia.fi uses exactly this name for the *Romanian* deadlift, so users may mix the two up. The difference, per StrengthLog, is that the stiff-leg version goes floor to floor (bar rests on the floor between reps) and the RDL goes top to top. Make the cues say this (they do in section 5). |
| Hyperextensio | "-extensio" is not Finnish spelling; Voikko accepts **Hyperekstensio**. The plainest term is **"Selän ojennus"**. Lyfta does use "Hyperextensio", so this is low priority. |
| Ojentajadipit | Ambiguous. If it means the bench version, use **"Penkkidipit"** (Voikko OK; Lyfta uses "Penkki dip"). If it means triceps dips on parallel bars, keep the name and use the pose for that version. |
| Kaapeliristikkäis | "ristikkäis-" is only a word prefix, so the name looks unfinished. Suggest **"Ristikkäistalja"** (Voikko suggests "Ristikkäis-talja"). I could not verify how common it is in gyms. |
| Lattiapunnerrus | Easy to confuse with Punnerrus (push-up), which is also done on the floor. Fitwill uses "Tangopunnerrus lattialla"; **"Lattiapenkki"** also passes Voikko. Optional; I did not verify common gym usage. |
| Sumomaastaveto, Vinopenkki, Venäläinen twisti | Voikko rejects these, but they are normal gym jargon. Keep them. |

All other names passed Voikko. "Low bar -kyykky" (space before the hyphen) is the correct form for a multi-word foreign compound.

## 3. Slots

**Concrete issues**
1. **Same exercise twice in one day.** On LA, LON = Romanialainen maastaveto, and POK's fallback is also Romanialainen maastaveto. On 3d C, PAK's third fallback is Bulgarialainen askelkyykky, which is already YKS's default. Recommend that slot resolution skips exercises already chosen that day.
2. **POK fallback.** A hinge is acceptable because the hamstrings still work at the hip (StrengthLog lists hamstrings as primary for the RDL). But it puts a heavy compound into an isolation slot. **Nordic hamstring** is a true knee-flexion exercise and is already in the catalog. Suggested order: Reiden koukistus, Nordic hamstring, Romanialainen maastaveto.
3. **RIE** ends with Rintaprässi laitteessa, which is a compound press. Suggest **Käsipainoaukaisu** as the third option instead.
4. **PEV**: add **Taukopenkki**, which is the bench variation closest to competition (the pause is required in competition) **[konv.]**. Suggested: Taukopenkki, Kapea penkki, Vinopenkki.
5. **MAV** has only two options. Add Suorin jaloin maastaveto and Good morning.
6. **KYV**: Hack-kyykky is closer to a squat than Jalkaprässi, so Etukyykky, Hack-kyykky, Jalkaprässi is a better order **[konv.]**.
7. **KAN**: Pallof press is an acceptable anti-rotation stand-in. Kylkilankku is closer to an offset carry **[konv.]**.

**Compound/isolation flags**
- POJ and POK as isolation: correct (single-joint).
- **Hip thrust is single-joint** (only the hip moves; per StrengthLog the knees stay at about 90° at the top). So PAK as isolation is correct for ordering. It is loaded heavily, though, so give it the longer rest of the two **[konv.]**.
- Fallbacks that are compounds inside isolation slots (Jalkaprässi in POJ, Kapea penkki in OJE): acceptable, but those get the short rest.
- All other flags are fine.

## 4. Template days

Simão et al. 2012 (Sports Medicine 42:251) found that the exercise done first in a session gets more reps and larger strength gains, so order should follow priority. A 2021 meta-analysis found hypertrophy is similar whatever the order. Your layouts follow this. Concrete issues only:

1. **Lower back loaded on consecutive days.** On 4d, Kulmasoutu (the VVE default) sits on UA and UB, each followed by a lower day with squat/RDL or deadlift. The same thing happens on 5d (Upper then Lower) and on 6d (each Pull day then a Legs day). Bent-over rows load the spinal erectors. Suggest that VVE on upper/pull days defaults to a supported row (Alatalja, Soutu laitteessa or Käsipainosoutu) at least once a week **[konv.]**.
2. **4d LB order.** Currently Maastaveto, Bulgarialainen, Jalkaprässi. Put the bilateral, heavier Jalkaprässi before the single-leg work: LON, KYY(leg press), YKS, POK, POH, KES **[konv.]**.
3. **Powerlifting D3**: volume squat + RDL + Kulmasoutu is three lifts that load the erectors, and D1 (heavy squat) comes next. Make VVE on powerlifting days Käsipainosoutu or Alatalja **[konv.]**.
4. **Powerlifting D2**: heavy deadlift comes before heavy bench. If bench is the priority that day, put KP before KM, which also matches competition order (squat, bench, deadlift) **[konv., minor]**.
5. Everything else is sensible: 3d A/B/C, 4d UA/UB/LA, 5d Push/Pull/Legs (a lighter second leg day without bilateral squat or hinge is fine), and powerlifting D1. With rest days in between, heavy squat (D1) and heavy deadlift (D2) are fine.

## 5. Cues and animation poses

**Angle conventions**
- **Trunk**: degrees of forward lean from vertical (0 = upright, 90 = horizontal, negative = leaning back).
- **Hip, knee**: flexion (0 = straight).
- **Shoulder**: flexion relative to the torso (0 = arm along the torso, 90 = arm perpendicular to the torso pointing forward or up, 180 = overhead in line with the torso, negative = behind the torso). For lying exercises, "arms vertical" equals 90.
- **Elbow**: flexion (0 = straight).
- **FV** means the motion is mainly sideways or rotational, so a side view shows little. Animate those from the front or top.
- All values are approximate **[konv.]**.

### Voimanosto
| Exercise | Cues | Start → End (side view) |
|---|---|---|
| Takakyykky | Jalat hartioiden leveydellä, varpaat hieman ulos / Lantio taakse ja alas, polvet varpaiden suuntaan / Selkä neutraalina, paino koko jalkapohjalla | Standing, barbell on upper traps, elbows bent behind the bar, all joints 0. → Trunk 40–45, hip 115, knee 115 (thighs at or below parallel). Rack. |
| Penkkipunnerrus | Lapaluut yhteen ja alas, pieni kaari selkään / Tanko rinnan alaosaan, kyynärpäät ~45° kyljistä / Jalat tukevasti lattiassa, paina tanko olkapäiden ylle | Lying on a flat bench, knees 90, feet on the floor, arms vertical, elbow 0. → Bar on lower chest, upper arm about level with the torso, elbow 90–100. |
| Maastaveto | Tanko jalkapöydän keskikohdan päällä, sääret lähellä / Selkä neutraali, ota löysät pois tangosta / Työnnä lattiaa, lantio ja hartiat nousevat yhtä aikaa | Barbell on the floor, trunk 50–60, hip 95, knee 65, arms hanging straight. → Standing upright, all 0, bar at thighs. |
| Sumomaastaveto | Leveä haara-asento, varpaat ulos / Ote hartioiden levyinen jalkojen välistä / Polvet ulos, rinta pystyssä, lantio lähellä tankoa | Barbell on the floor, trunk 30–40, hip 90, knee 80, legs wide and turned out. → Standing. Side view hides the stance; a 3/4 view is better. |
| Etukyykky | Tanko etuolkapäillä, kyynärpäät korkealla eteen / Vartalo mahdollisimman pystyssä / Polvet saavat liikkua varpaiden yli | Standing, bar on front delts, shoulder 90, elbow about 145 (front-rack grip). → Trunk 20–25, hip 115, knee 125–130. |
| Taukopenkki | Laske tanko rinnalle ja pysäytä 1–2 s / Pidä jännitys tauon ajan, älä upota tankoa / Paina vasta kun tanko on täysin pysähtynyt | Same as Penkkipunnerrus, with a 1–2 s hold at the bottom. |
| Pystypunnerrus | Ote hieman hartioita leveämpi, kyynärvarret pystyssä / Pakarat ja vatsa tiukkana, ei taaksekallistusta / Tanko suoraan ylös, pää läpi lopussa | Standing, bar at the collarbones, shoulder 40–60, elbow about 130, trunk 0 to −5. → Bar overhead above the mid-foot, shoulder 175, elbow 0. |
| Low bar -kyykky | Tanko lapojen päällä takaolkapäiden alla / Enemmän eteenkallistusta, lantio taakse / Ranteet suorina, tanko jalkaterän keskikohdan yllä | Standing, bar lower on the back. → Trunk 45–55, hip 120, knee 100–110. |
| Box-kyykky | Istu hallitusti laatikolle, sääret lähes pystyssä / Pysy jännittyneenä, älä rentoudu laatikolla / Nouse lantio edellä räjähtävästi | Standing, wide stance. → Sitting on a box at parallel height, trunk 40–50, hip 100, knee 90. |
| Lattiapunnerrus | Makaa lattialla, polvet koukussa tai jalat suorina / Laske kunnes olkavarret koskevat lattiaan / Lyhyt pysäytys alhaalla, sitten paina | Lying on the floor, arms vertical, knees 90 or straight. → Upper arms resting on the floor, elbow 90. Barbell. |

### Jalat
| Exercise | Cues | Start → End |
|---|---|---|
| Jalkaprässi | Jalat lantion levyisenä keskellä alustaa / Laske kunnes lantio meinaa irrota penkistä / Älä lukitse polvia ääriasentoon | 45° sled machine, back pad reclined, hip 40, knee 10, hands on the handles. → Hip 110–120, knee 90–100. |
| Romanialainen maastaveto | Polvet kevyesti koukussa (~15°), kulma pysyy samana / Lantio taakse, tanko liukuu reisiä pitkin / Laske niin alas kuin selkä pysyy suorana | Standing, barbell at thighs, knee 15. → Trunk 70–80, hip 85, knee 15, bar just below the knee or at mid-shin. |
| Suorin jaloin maastaveto | Lähde lattiasta, polvet lähes suorina / Liike tulee lonkasta, selkä neutraali / Tanko käy lattiassa joka toistolla | Barbell on the floor, trunk 80–90, hip 95, knee 15–20. → Standing. |
| Askelkyykky | Pitkä askel eteen, vartalo pystyssä / Takapolvi lähes lattiaan, etupolvi varpaiden suuntaan / Työnnä etukantapäästä takaisin | Standing, dumbbells at the sides. → Front hip 90, front knee 90, rear hip 0–10, rear knee 90, trunk 0–10. |
| Bulgarialainen askelkyykky | Takajalan jalkapöytä penkillä / Etujalka riittävän edessä, paino etujalalla / Laske suoraan alas, lantio suorassa | Split stance, rear foot on a flat bench, front knee 15, rear knee 40. → Front knee 90–100, front hip 90, trunk 10–20, rear knee 105. Dumbbells. |
| Askelkyykkykävely | Astu eteen vuorojaloin, älä palaa taaksepäin / Takapolvi lähes lattiaan / Vartalo pystyssä, katse eteen | Same poses as Askelkyykky, but the figure moves forward and alternates legs. |
| Reiden ojennus | Polvinivel laitteen akselin kohdalla / Ojenna jalat suoriksi ja purista hetki / Laske hallitusti, älä heilauta | Seated machine, hip 95, knee 90, hands on the handles. → Knee 0–10. |
| Reiden koukistus | Polvi akselin kohdalla, tyyny nilkan yläpuolella / Koukista täysin, lantio pysyy alustassa / Palauta hitaasti lähes suoraksi | Lying machine, face down, hip 15, knee 5. → Knee 110–125. (For the seated version: hip 90, knee 10 → 120.) |
| Hip thrust | Yläselkä penkin reunaa vasten, tanko lantiolla / Leuka ja kylkiluut alas, nosta lantio / Yläasennossa sääret pystyssä, polvet ~90° | Shoulders on a flat bench, hips low, hip 90–100, knee about 120, barbell on the hips (with a pad). → Hip 0, knee 90, trunk and thighs horizontal. |
| Pohjenousu seisten | Päkiät korokkeella, kantapäät vapaasti alas / Nouse mahdollisimman korkealle / Polvet suorina, laske hitaasti venytykseen | Standing on a step, ankle dorsiflexed about 15. → Ankle plantar-flexed 35–40. Machine or dumbbell. |
| Pohjenousu istuen | Polvet 90°, tyyny reisien päällä / Nouse päkiöillä ylös ja purista / Laske kantapäät syvälle | Seated machine, hip 90, knee 90, ankle 15 dorsiflexed. → Ankle 35 plantar-flexed. |
| Hack-kyykky | Selkä ja hartiat tiukasti tyynyjä vasten / Jalat hieman edessä lantion levyisenä / Laske syvälle, paina koko jalkapohjalla | Machine, back on a pad leaning back about 45, hip 10, knee 10. → Hip 110, knee 110–120. (Somewhat uncertain.) |
| Goblet-kyykky | Käsipaino rinnan edessä, kyynärpäät alas / Istu syvälle kantapäiden väliin / Rinta ylhäällä, kyynärpäät polvien sisäpuolella | Standing, dumbbell held at the chest, shoulder 30, elbow 140. → Trunk 15–25, hip 115, knee 125. |
| Smith-kyykky | Jalat hieman tangon etupuolella / Avaa koukut kiertämällä, selkä tiukkana / Laske reidet vähintään vaakatasoon | Smith machine, standing. → Trunk 15–30, hip 100, knee 105. |
| Lonkan loitonnus | Selkä tyynyä vasten, tyynyt polvien ulkopuolella / Työnnä polvet ulos hallitusti / Palauta hitaasti, älä kolauta painoja | FV. Seated machine, hip 90, knee 90, thighs together → hip abducted 40–45. |
| Lonkan lähennys | Tyynyt polvien sisäpuolella / Purista reidet yhteen hallitusti / Avaa hitaasti venytykseen | FV. Abducted 45 → thighs together. |
| Good morning | Tanko yläselällä kuten kyykyssä / Polvet kevyesti koukussa, lantio taakse / Selkä neutraali, laske lähes vaakaan | Standing, barbell on the back. → Trunk 70–80, hip 80, knee 15–20. |
| Nordic hamstring | Polvet pehmeällä alustalla, nilkat kiinni / Vartalo suorana polvista päähän / Laske hitaasti eteen, ota kiinni käsillä | Kneeling upright, knee 90, hip 0, ankles held by a partner or anchor. → Body almost horizontal, knee 0–20, hip 0, hands catching the floor. Bodyweight. |
| Kööpenhaminan lähennys | Kylkimakuu, ylempi jalka penkillä / Nosta lantio, alempi jalka penkin alle / Vartalo suorana, ei notkahdusta | FV. Lying on one side on the forearm, hip on the floor, top leg on a flat bench. → Body in a straight line, bottom leg lifted up under the bench. |

### Rinta
| Exercise | Cues | Start → End |
|---|---|---|
| Vinopenkki | Penkki 30–45° kulmaan / Laske tanko yläriintaan solisluiden alle / Lapaluut yhteen, kyynärpäät hieman kyljen alla | Incline bench at 30–45° (trunk leaned back 45–60), arms vertical, elbow 0. → Bar at the upper chest, elbow 90. Barbell. |
| Käsipainopenkki | Käsipainot rinnan sivuilla, kämmenet jalkoihin päin / Laske syvälle, kyynärpäät ~45° kyljistä / Paina ylös ja hieman yhteen | Flat bench, arms vertical. → Dumbbells at chest level, elbow 90, upper arm slightly below the bench line. |
| Vinokäsipainopenkki | Penkki 30–45° kulmaan / Käsipainot yläriinnan sivuille / Paina ylös hartioiden linjaan | Incline bench, otherwise the same as Käsipainopenkki. |
| Kaapeliristikkäis | Seiso taljojen välissä, pieni askel eteen / Kyynärpäät hieman koukussa, kulma pysyy / Tuo kädet kaaressa yhteen rinnan eteen | FV/top view. Between two cable stacks, trunk 10–20, arms out to the sides slightly behind the body, elbow 15–20. → Hands together in front of the chest (shoulder 90). |
| Dipit | Kädet nojapuilla, aloita kädet suorina / Kallista vartaloa hieman eteen / Laske kunnes olkavarret vaakatasossa, paina ylös | Parallel bars, trunk 10–20, arms straight (shoulder 0), knees 90. → Shoulder −60 to −70 (upper arms horizontal), elbow 90–100. Bodyweight. |
| Punnerrus | Kädet hieman hartioita leveämmälle / Vartalo suorana päästä kantapäihin / Rinta lähes lattiaan, kyynärpäät ~45° | Straight-arm plank, body about 75 from vertical, shoulder 80, elbow 0. → Chest near the floor, elbow 90–100. Bodyweight. |
| Peck deck | Istuin niin, että kahvat ovat rinnan korkeudella / Kyynärpäät hieman koukussa, rinta ylhäällä / Tuo kahvat yhteen, palauta venytykseen | FV/top view. Seated machine, hip 90, arms out to the sides. → Hands together in front. |
| Käsipainoaukaisu | Käsipainot rinnan yllä, kämmenet vastakkain / Avaa kaarella sivuille, kyynärpäät hieman koukussa / Laske vain hartioiden tasolle | FV. Flat bench, arms vertical, elbow 15. → Arms out to the sides at bench level, elbow 20–30. Dumbbells. |
| Rintaprässi laitteessa | Säädä istuin: kahvat rinnan keskikohdalla / Lapaluut tyynyä vasten, rinta ylhäällä / Paina lähes suoriksi, palauta hallitusti | Seated machine, trunk 0 to −10, hands beside the chest, elbow 90–100. → Arms straight forward, shoulder 90, elbow 5. |
| Smith-vinopenkki | Penkki 30–45° Smithin alle / Tanko laskeutuu yläriintaan / Lapaluut yhteen, paina suoraan ylös | Same as Vinopenkki, in a Smith machine. |

### Selkä
| Exercise | Cues | Start → End |
|---|---|---|
| Leuanveto | Myötäote hieman hartioita leveämpi / Aloita painamalla lapaluut alas / Leuka tangon yli, laske kädet suoriksi | Hanging from a pull-up bar, shoulder 175, elbow 0. → Chin above the bar, shoulder 30–45, elbow 130. The wide-grip pull is partly sideways. |
| Leuanveto vastaotteella | Vastaote hartioiden levyisenä / Rinta kohti tankoa, kyynärpäät kylkiin / Laske hallitusti kädet suoriksi | Hanging, palms facing you. → Shoulder 0–20, elbow 140. |
| Ylätalja | Reidet tukien alle, ote hieman hartioita leveämpi / Vedä tanko solisluihin, rinta ylös / Kyynärpäät alas, älä nykäise vartalolla | Seated at the cable stack, trunk −10 to −20, hip 90, knee 90, shoulder 170, elbow 0. → Bar at the upper chest, shoulder 30, elbow 125. |
| Kulmasoutu | Ylävartalo ~45° tai enemmän, selkä suorana / Vedä tanko alavatsaan, kyynärpäät taakse / Vartalon kulma pysyy koko sarjan | Trunk 45–70, hip 65, knee 20, arms hanging (shoulder ≈ trunk angle), elbow 0. → Bar at the lower abdomen, elbow 95, shoulder about −30. Barbell. |
| Alatalja | Istu suorana, polvet hieman koukussa / Vedä kahva vatsaan, lapaluut yhteen / Älä keinu vartalolla | Seated cable row, trunk 10, hip 85, knee 25, shoulder 90, elbow 0. → Trunk 0, handle at the navel, elbow 105, shoulder −25. V-handle. |
| Käsipainosoutu | Toinen käsi ja polvi penkillä, selkä suorana / Vedä käsipaino lantion suuntaan / Kyynärpää lähellä kylkeä, ei kiertoa | Trunk 80–90, one knee on a flat bench, working arm hanging (shoulder 90), elbow 0. → Dumbbell at the hip, elbow 95, shoulder −15. |
| T-tankosoutu | Tanko jalkojen välissä, kahva rinnan alla / Selkä suorana ~45°, polvet koukussa / Vedä kahva rintaan, purista lapaluut | T-bar or landmine handle, trunk 45, knee 25, arms hanging. → Handle at the chest, elbow 95. |
| Pendlay-soutu | Vartalo lähes vaakatasossa, tanko lattiassa / Räjähtävä veto alarintaan / Laske tanko lattiaan joka toistolla | Barbell on the floor, trunk 80–90, hip 95, knee 30. → Bar touches the lower chest, elbow 90, trunk unchanged. |
| Face pull | Talja kasvojen korkeudelle tai hieman pään yläpuolelle, köysi ylhäältä / Vedä köyttä otsaa kohti, kyynärpäät korkealla ja ulos / Kädet erilleen korvien viereen kuin laittaisit aurinkolasit päähän | Cable at face height or just above the head, rope, standing, arms reaching forward and up. → Hands pass the face and finish beside the head (ears/temples), elbows high, out and slightly back, arms rotated outward (90/90). Corrected 2026-11-08: the cable was at chest height and the hands ended in front of the face. |
| Hyperextensio | Lonkat tyynyn reunalla, nilkat tukien alla / Laske ylävartalo hallitusti, selkä suorana / Nouse suoraan linjaan, älä yliojenna | 45° back-extension bench, hip 90–100 with the trunk hanging down, hands crossed on the chest. → Body in a straight line along the 45° angle, hip 0. |
| Suorin käsin ylätalja | Seiso taljan edessä, pieni eteenkallistus / Kädet lähes suorina, kyynärkulma pysyy / Vedä tanko reisiin hartiat alhaalla | High cable, straight bar, trunk 20–30, shoulder 120, elbow 10–15. → Bar at the thighs, shoulder 0–10. |
| Rack pull | Tanko telineessä polvien kohdalla / Selkä neutraali, hartiat tangon päällä / Ojenna lantio ja polvet, älä yliojenna | Barbell on pins at knee height in a rack, trunk 35, hip 45, knee 25. → Standing. |
| Soutu laitteessa | Rinta tyynyä vasten, istuin säädetty / Vedä kahvat kylkiin, lapaluut yhteen / Palauta hallitusti kädet suoriksi | Seated machine with chest pad, trunk 0, shoulder 90, elbow 0. → Elbow 95, shoulder −25. |
| Rintatuettu kulmasoutu käsipainoilla | Vatsallaan vinopenkillä (30–45°), rinta tukea vasten, jalat maassa / Vedä kyynärpäät ylös ja taakse, lapaluut yhteen / Rinta pysyy penkissä, laske hallitusti suoriksi käsiksi | Prone on an incline bench at about 40°, chest on the pad, feet on the floor, dumbbells hanging from straight arms (neutral grip). → Elbows pulled up and back, elbow about 90, shoulder −60. Added 2026-11-08 at a user's request; sources below. |

### Olkapäät
| Exercise | Cues | Start → End |
|---|---|---|
| Käsipainopystypunnerrus | Käsipainot hartioiden korkeudella, kämmenet eteen / Vatsa tiukkana, ei taaksekallistusta / Paina ylös ja hieman yhteen | Mostly FV. Upright bench, upper arms out to the sides about horizontal, elbow 90. → Arms overhead, elbow 0. |
| Vipunosto sivulle | Kyynärpäät hieman koukussa, kädet sivuille / Nosta hartioiden korkeudelle, ei korkeammalle / Älä heilauta, laske hitaasti | FV. Standing with dumbbells, arms raised out to the sides 0 → 90, elbow 10–20. |
| Vipunosto eteen | Kädet lähes suorina / Nosta eteen silmien tasolle / Vartalo paikallaan, laske hallitusti | Standing with dumbbells, shoulder 0 → 90, elbow 5–10. |
| Takaolkavipunosto | Ylävartalo lähes vaakaan, selkä suorana / Nosta kädet sivuille kyynärpäät edellä / Laske hitaasti, ei heilautusta | FV/top view. Trunk 70–80, hip 75, knee 20, arms hanging. → Arms out to the sides at about trunk level, elbow 15. Dumbbells. |
| Arnold-punnerrus | Aloita käsipainot leuan edessä, kämmenet itseen / Kierrä kämmenet eteen samalla kun painat / Laske samaa reittiä kiertäen | Seated, elbows in front of the body, shoulder 30–45, elbow 140. → Overhead, elbow 0. The palm rotation is hard to show on a stick figure. |
| Pystysoutu | Ote hartioiden levyinen, tanko lähellä vartaloa / Kyynärpäät johtavat ylös / Ei hartioita korkeammalle | Standing, barbell or EZ bar at the thighs. → Bar at the lower chest, elbows raised to shoulder height, elbow 125. |
| Olankohautus | Kädet suorina, tanko reisien edessä / Nosta hartiat suoraan korvia kohti / Pidä hetki ylhäällä, laske täyteen venytykseen | All joints 0. Only the shoulder girdle moves, rising 5–10 cm. Barbell or dumbbells. |
| Push press | Tanko etuolkapäillä, ote kuin pystypunnerruksessa / Pieni nopea polvien koukistus, vartalo pystyssä / Räjähdä jaloilla ja paina suoraan ylös | Start as in Pystypunnerrus. Dip to knee 25, hip 10, trunk 0. → Legs straight, arms overhead. |
| Vipunosto taljassa | Talja alhaalla, kahva vastakkaisessa kädessä / Nosta käsi sivulle hartian korkeudelle / Laske hitaasti, vastus pysyy | FV. Low cable, one arm, from slightly across the body (−15) → 90 out to the side, elbow 10. |
| Olkapääprässi laitteessa | Kahvat hartioiden korkeudella / Selkä tukevasti tyynyä vasten / Paina lähes suoriksi, laske hallitusti | Seated machine, upper arms about horizontal, elbow 90. → Overhead, elbow 5. |
| Ulkokierto taljassa | Talja kyynärpään korkeudella, seiso sivuttain / Kyynärpää kyljessä, kulma 90° / Kierrä kättä ulospäin, ei vartalon kiertoa | Top view. Elbow 90 at the side, forearm rotates from across the belly to 45–60 outward. Cable D-handle. |

### Kädet
| Exercise | Cues | Start → End |
|---|---|---|
| Hauiskääntö tangolla | Ote hartioiden levyinen, kyynärpäät kyljissä / Koukista tanko hartioiden korkeudelle / Ei heilutusta, laske kädet suoriksi | Standing, barbell, elbow 5. → Elbow 135, shoulder 10–15. |
| Hauiskääntö käsipainoilla | Kyynärpäät kyljissä / Käännä kämmenet ylös nostaessa / Laske hitaasti kädet suoriksi | Same angles, dumbbells. |
| Vasarakääntö | Kämmenet vastakkain koko liikkeen / Kyynärpäät paikallaan kyljissä / Laske hallitusti alas | Same angles, neutral grip. |
| Scott-kääntö | Olkavarret tiukasti tyynyä vasten / Laske lähes suoraksi, ei rajua lukitusta / Koukista ylös, olkapäät rentona | Seated at a preacher bench, upper arm on the pad at shoulder 45, elbow 15. → Elbow 125. EZ bar. |
| Hauiskääntö taljassa | Seiso lähellä taljaa, kyynärpäät kyljissä / Koukista kahva hartioille / Laske hitaasti, vastus pysyy | Low cable with bar, same angles as Hauiskääntö tangolla. |
| Keskittynyt hauiskääntö | Istu, kyynärpää reiden sisäsyrjää vasten / Koukista paino olkapäätä kohti / Olkavarsi paikallaan, laske hitaasti | Seated on a bench, trunk 30–45, arm hanging, elbow 5. → Elbow 135. Dumbbell. |
| Ojentajapunnerrus taljassa | Kyynärpäät kyljissä, olkavarret paikallaan / Ojenna kädet suoriksi alas / Palauta kunnes kyynärkulma ~90° | High cable with rope or bar, standing, trunk 5–15, elbow 100. → Elbow 0. |
| Ranskalainen punnerrus | Makaa penkillä, tanko otsan yllä kädet suorina / Laske otsalle koukistamalla vain kyynärpäitä / Olkavarret pysyvät paikallaan | Flat bench, EZ bar, shoulder about 100, elbow 0. → Elbow 110. |
| Kapea penkki | Ote hartioiden levyinen / Kyynärpäät lähellä kylkiä / Tanko rinnan alaosaan, paina suoriksi | Same as Penkkipunnerrus with a narrow grip and elbows tucked, elbow at the bottom 95. |
| Ojentajapunnerrus pään yli | Kädet pään yllä, kyynärpäät osoittavat ylös / Laske paino pään taakse venytykseen / Ojenna suoriksi, olkavarret paikallaan | Standing or seated, dumbbell or rope, shoulder 165, elbow 130. → Elbow 0. |
| Ojentajadipit | Kädet penkin reunalla takana, sormet eteen / Laske kunnes kyynärpäät ~90° / Selkä lähellä penkkiä, paina suoriksi | Bench version: hands on the bench behind you, arms straight (shoulder −25), hip 85, legs straight. → Elbow 90, shoulder −70, hips lower. (If the parallel-bar version is meant: trunk 0–5, otherwise like Dipit.) |
| Ranteen koukistus | Kyynärvarret reisien päällä, kämmenet ylös / Anna tangon rullata sormille / Koukista ranne ylös, kyynärvarsi paikallaan | Seated, forearms on the thighs, wrist extended 50. → Wrist flexed 50. Barbell. Use a zoomed view. |
| Ranteen ojennus | Kämmenet alas, kyynärvarret tuettuina / Nosta rystyset ylös / Kevyt paino, laske hitaasti | Wrist flexed 40 → extended 45. |

### Keskivartalo
| Exercise | Cues | Start → End |
|---|---|---|
| Lankku | Kyynärpäät hartioiden alla / Vartalo suorana, pakarat ja vatsa tiukkana / Älä anna lantion notkahtaa tai nousta | Static hold: body about 80 from vertical, hip 0, knee 0, shoulder 90, elbow 90. Animate breathing only. |
| Vatsarutistus | Selinmakuu, polvet koukussa ~90° / Rullaa lapaluut irti, alaselkä alustassa / Uloshengitys ylös, laske hallitusti | Lying on the back, hip 50, knee 90, trunk flat. → Upper trunk curled about 30 off the floor. |
| Jalannosto roikkuen | Roiku kädet suorina / Nosta jalat, kallista lantiota / Laske hallitusti, ei heiluntaa | Hanging from a pull-up bar, shoulder 175, hip 0. → Hip 90–110 with legs straight (knee-raise version: hip 100, knee 90). |
| Ab wheel | Polvillaan, rulla hartioiden alla / Rullaa eteen vatsa tiukkana / Vedä takaisin vatsalla, ei lantiolla | Kneeling, hip 95, arms vertical (shoulder 80), elbow 0. → Body about horizontal, hip 10–20, shoulder 165. |
| Pallof press | Seiso sivuttain taljaan, kahva rinnalla / Paina suoriksi eteen, vastusta kiertoa / Pidä 1–2 s, tuo takaisin | Cable at chest height, D-handle, knee 10, shoulder 35, elbow 120. → Shoulder 90, elbow 0. A front view shows the cable pulling sideways. |
| Venäläinen twisti | Istu, vartalo ~45° taaksepäin, selkä suorana / Jalat lattiassa tai ilmassa / Kierrä ylävartaloa puolelta toiselle | FV. Seated, trunk −45, knee 90, holding a plate or ball. Rotate the trunk about ±45. |
| Kaapelirutistus | Polvillaan taljan edessä, köysi pään sivuilla / Rutista vatsalla, kyynärpäät kohti polvia / Lantio paikallaan, älä istu kantapäille | High cable with rope, kneeling, trunk 30, hip 45, hands at the head. → Rounded trunk about 75, hip about 55. |
| Kylkilankku | Kyynärpää hartian alla, vartalo suorana / Lantio ylhäällä, ei notkahdusta / Jalat päällekkäin tai porrastettuina | FV, static hold: lying on one side on the forearm, body in a straight line. |
| Farmer walk | Raskaat painot sivuilla, kädet suorina / Hartiat alas ja taakse, vartalo pystyssä / Lyhyet nopeat askeleet, tiukka ote | Upright, all joints about 0. Walking cycle with hip and knee ±25. Dumbbells, kettlebells or farmer handles. |

## 6. Sources

**Pages I opened:**
- StrengthLog, one page per exercise:
  - https://www.strengthlog.com/hip-thrust/
  - https://www.strengthlog.com/face-pull/
  - https://www.strengthlog.com/good-morning/
  - https://www.strengthlog.com/close-grip-bench-press/
  - https://www.strengthlog.com/rack-pull/
  - https://www.strengthlog.com/farmers-walk/
  - https://www.strengthlog.com/barbell-shrug/
  - https://www.strengthlog.com/back-extension/
  - https://www.strengthlog.com/copenhagen-plank/
  - https://www.strengthlog.com/stiff-legged-deadlift/
  - https://www.strengthlog.com/romanian-deadlift/
  - https://www.strengthlog.com/floor-press/
- ACE body-part categories: https://www.acefitness.org/resources/everyone/exercise-library/
- Elixia.fi (the Finnish RDL name): https://www.elixia.fi/harjoitukset/romanian-deadlift

**Chest-supported dumbbell row (added 2026-11-08), search-result summaries:** bench 30–45°, chest stays on the pad, neutral grip, elbows up and back, flaring the elbows and lifting the chest off the pad are common errors.
  - https://www.hevyapp.com/exercises/chest-supported-incline-row-dumbbell/
  - https://www.coachweb.com/back-exercises/9105/incline-bench-row
  - https://gravitus.com/guides/exercises/chest-supported-row
  - https://sweat.com/exercises/chest-supported-dumbbell-row

**Face pull (corrected 2026-11-08), search-result summaries:** pulley at face height or just above the head (higher = more lower trapezius), pull toward the forehead not the chin, elbows high and out, hands separate to beside the ears with external rotation; common errors: pulling to the chest, turning it into a rope curl, leaning back.
  - https://powerliftingtechnique.com/face-pulls/
  - https://www.gymshark.com/blog/article/how-to-do-face-pulls
  - https://www.garagegymreviews.com/face-pulls
  - https://weighttraining.guide/exercises/cable-face-pull

**Seen only as search-result summaries (not opened):**
- Simão et al. 2012, Exercise Order in Resistance Training, Sports Medicine 42(3):251–265. Listed at https://read.qxmd.com/read/22292516/exercise-order-in-resistance-training and https://link.springer.com/article/10.2165%2F11597240-000000000-00000. The 2021 meta-analysis (Eur J Sport Sci) appeared in the same search summary.
- fitwill.app/fi and lyfta.app/fi: Finnish exercise names ("Penkki dip", "Hyperextensio", "Tangopunnerrus lattialla").

**Failed:** ExRx.net returned HTTP 403 on every page, so none of its compound/isolation classifications were verified.

**Coaching convention, not sourced:**
- All joint angles in section 5 and all Finnish cue wording.
- The exercise-order and back-to-back lower-back points in section 4.
- The rest-time advice for Hip thrust.
- The measurement-unit suggestions (distance or time for Farmer walk, "/puoli" labels).

**Least certain poses:** Hack-kyykky (machine angle), Arnold-punnerrus (rotation), Kaapelirutistus, and every exercise marked FV (a side view shows them poorly).
