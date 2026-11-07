# Evidence base and parameter spec for the training program generator

**How to read this.**
- **[PR]** means a peer-reviewed source. **[PRE]** means a preprint that has not been peer reviewed. **[COACH]** means a coaching convention (a book, a coach's site or a popular program). **[SYNTH]** means my own synthesis or derivation, which no source states directly.
- Source IDs (S1…, C1…) point to section 5.
- I opened full text for S1 (preprint), S2, S8 and S24. For most others I read the full abstract through the Europe PMC API.
- "Sets" are hard working sets, taken to within about 0–4 RIR. Warm-up sets don't count.
- **Set counting (use this in code):** count **direct sets as 1.0 and indirect sets as 0.5**, the "fractional" method. Pelland et al. found it fit the data best (S1).
  - Penkkipunnerrus = rinta 1, ojentaja 0.5, etuolka 0.5
  - Soutu = selkä 1, hauis 0.5, takaolka 0.5
  - Kyykky = etureisi 1, pakara 0.5
  - Maastaveto / RDL = takareisi 1, pakara 1, selän ojentajat 0.5
  - Leuanveto = selkä 1, hauis 0.5
  - Pystypunnerrus = olkapää 1, ojentaja 0.5

---

## 0. Key evidence in one screen (what the numbers below rest on)

| Topic | Finding | Source |
|---|---|---|
| Weekly volume → hypertrophy | Gains rise with weekly sets, with diminishing returns. Above about **31 fractional sets per muscle per week**, no further benefit was detectable. | S1 [PR]; the ~31 figure is quoted from S1 in S2 [PRE] |
| Weekly volume → strength | Diminishing returns are much stronger than for hypertrophy. Little detectable benefit beyond about **3 fractional sets/week**, though studies were short. | S1, S2 |
| Per-session volume | Hypertrophy stopped showing detectable benefit at **~11 fractional sets per muscle per session**. Strength stopped at **~2 direct sets of the tested lift per session**. | S2 [PRE] |
| Frequency → hypertrophy | With volume equated, frequency has no meaningful effect (S6). S5 found twice a week beat once a week. S1 found frequency's effect on hypertrophy to be about +0.32 %/day (CrI −0.14…0.82), i.e. negligible. | S5, S6, S1 |
| Frequency → strength | Each extra weekly session added about **+3.27 % strength gain** (CrI 2.74–3.84), with diminishing returns beyond about 3×/week. Grgic found ES 0.74 / 0.82 / 0.93 / 1.08 for 1 / 2 / 3 / 4+ sessions per week, but the effect was mostly explained by volume. | S1/S2, S7 |
| Old volume categories | <5, 5–9 and 10+ sets/muscle/week, with 10+ the best. Higher volume was better up to 30+ sets/week in trained men over 8 weeks (1, 3 or 5 sets per exercise, 3×/week). Strength was the same at all three volumes. | S3, S4 |
| Minimum dose | **≥4 sets/muscle/week at 6–15 RM** (S33). One set of 6–12 reps at 70–85 % 1RM, 2–3×/week, still increases squat and bench 1RM in trained men (S14). | S33, S14 |
| Maintenance | Strength and size can be kept for up to 32 weeks with **1 session/week and 1 set per exercise, if load is kept**. | S32 |
| Load | Hypertrophy is similar from about 30 % to 85 % 1RM when sets go close to failure. Strength is best with heavy loads, **>80 % 1RM**. | S9, S10, S11 |
| Load by training status | Strength gains peaked at **60 % 1RM, 3 days/week in untrained** lifters and **80 % 1RM, 2 days/week in trained** lifters. Four sets per muscle group was best. | S12 |
| Proximity to failure | **Hypertrophy improves as sets end closer to failure. Strength is flat across RIR.** Training to failure is not needed: momentary failure vs non-failure ES 0.12, n.s. | S16, S15 |
| RIR accuracy | Lifters underpredict their remaining reps by about **0.95 reps**. Predictions are better near failure and at ≤12 reps. | S17 |
| RPE vs %1RM | Both work. RPE-based loading gave a small 1RM advantage in most lifters. | S20 |
| Periodization | Periodized programs beat non-periodized ones for 1RM (ES 0.43), and undulating models did best. Hypertrophy is not affected. | S21 |
| Load vs rep progression | Adding reps works as well as adding load for hypertrophy; adding load is slightly better for 1RM. | S35 |
| Rest | ACSM: **2–3 min for heavy compounds, 1–2 min for assistance work**. In a trial, 3 min rest beat 1 min for both strength and size. | S8, S34 |
| ACSM frequency | Novice **2–3 d/week full body**, intermediate **3–4 d/week** (4 when using an upper/lower split), advanced **4–6 d/week**. | S8 |
| ACSM load increase | Add **2–10 %** when the lifter can do **1–2 reps over target in two consecutive sessions**. | S8 |
| Deload | Athletes deload every **5.6 ± 2.3 weeks** for **6.4 ± 1.7 days**. They cut volume (sets and reps), lower load somewhat and raise RIR, but **keep frequency**. A full week off at mid-program **hurt strength** and did not affect hypertrophy. | S37, S38, S36 |
| Taper (powerlifting) | Cut volume **30–70 %**, keep intensity at **≥85 %** (or lower it slightly in meet week), over **1–2 weeks**. Then **2–7 days** of training cessation. In elite NZ lifters, volume peaked 5.2 ± 1.7 weeks out, intensity peaked 1.9 ± 0.8 weeks out, volume was cut 58.9 ± 8.4 %, the last session was 3.7 ± 1.6 days out, accessories were dropped about 2 weeks out, and a week or more off went badly. | S24, S23 |
| Fat loss | Lose **0.5–1 % bodyweight per week**. At 0.7 %/wk lifters gained more lean mass and upper-body strength than at 1.4 %/wk. A deficit of about **500 kcal/day** prevented lean-mass gains (strength was not affected). | S26, S30, S29 |
| Protein | Gains plateau around **1.6 g/kg/day** (S28). ISSN: 1.4–2.0 g/kg/day, and **2.3–3.1 g/kg of lean body mass** in a deficit. | S28, S27, S26 |
| Cardio | Concurrent training does **not** blunt hypertrophy (SMD −0.01) or maximal strength (−0.06). It does blunt explosive strength (−0.28), mainly when done in the same session. Contest-prep guidance: use the minimum cardio needed. | S31, S25 |
| Contest-prep training | Train each muscle **≥2×/week**. Do most work at **6–12 reps, 70–80 % 1RM**, about **40–70 reps per muscle per session**, with **1–3 min** rest. Limit failure on heavy compounds and save it for isolation work. | S25 |
| General health | 150–300 min/week of moderate aerobic activity (or 75–150 min vigorous), plus muscle strengthening ≥2 days/week. | S40 |

---

## 1. Parameter table: goal × experience

**Conventions used in the table**
- "Sets/muscle/wk" are fractional sets.
- "Start → cap" means: begin the first mesocycle at the start value, add sets across mesocycles (rules in section 4), and never exceed the cap.
- Load is the app's working e1RM, defined in section 4, R0.
- Every value is [SYNTH], built from the sources in the right-hand column.

### 1a. Hypertrophy (bodybuilding)

| | Beginner (<1 yr) | Intermediate (1–3 yr) | Advanced (3+ yr) | Basis |
|---|---|---|---|---|
| Sets/muscle/week | 8 → 12 | 12 → 18 | 16 → 22 (optionally up to 25 for lagging muscles) | S1, S3, S4, S33; nobody should go above ~31 (S1) |
| Per-session cap per muscle | 6 | 8 | 10 | S2 (~11) |
| Frequency per muscle | 2–3 (full body) | 2 | 2–3, chosen so the per-session cap holds | S5, S6, S8, S25 |
| Reps, compounds | 6–12 | 6–12 (occasionally 5–8) | 5–12, with some 3–6 work | S8, S10, S25 |
| Reps, isolation | 10–15 | 10–20 | 10–20 (up to 30 allowed) | S9, S10, S33 |
| Load guide | Compounds about 65–80 %; isolation by RIR | 65–82 % | 65–85 % | S8 (70–85 %), S9 |
| RIR target | Compounds 2–3, isolation 1–2 | Compounds 1–3, isolation 0–2 | Compounds 1–2, isolation 0–1 (last set may go to failure) | S15, S16, S25 |
| Rest | Compounds 2–3 min, isolation 1–1.5 min | Compounds 2–3 min, isolation 1–2 min | Same as intermediate | S8, S34 |
| Progression | Double progression on everything; add load quickly | Double progression with RIR autoregulation, plus volume across mesocycles | Same, but load steps every 2–4 weeks are normal | S8, S35, C2 |
| Deload | Not scheduled; reactive only (fallback every 8–10 wk) [COACH/weak] | Every 6 wk (range 5–8) | Every 4–6 wk | S37, S38 |

### 1b. Powerlifting

| | Beginner | Intermediate | Advanced | Basis |
|---|---|---|---|---|
| Sets per competition lift per week (squat / bench / deadlift) | 6–9 / 6–9 / 2–4 | 8–12 / 10–15 / 4–8 | 10–16 / 12–20 / 6–10 | S1, S2, S7, S13; bench gets more volume and frequency than deadlift [COACH] |
| Frequency per lift | Squat 2–3, bench 3, deadlift 1–2 (alternating) | Squat 2, bench 3, deadlift 1–2 (plus 1 variation) | Squat 2–3, bench 3–4, deadlift 1–2 | S1 (frequency helps strength), S7, S8 |
| Main-lift reps | 5 (3×5) | 2–8, periodized | 1–8, periodized | S8 (1–12 RM, 80–100 % for advanced), S11 |
| Load | 75–85 % (by linear progression) | 70–90 %, blocks in section 3 | 65–95 % | S11, S12 (80 % in trained) |
| RPE target | Main lifts RPE 7–8; never grind | RPE 6–8.5 (top sets to 9) | RPE 6–9 (a single at RPE 9–9.5 when testing) | S16 (strength is flat across RIR, so failure isn't needed), S18, S20 |
| Accessories | 2–3 movements, 2–3×8–12, RIR 2 | 6–10 sets per muscle per week, RIR 1–2 | 6–12 sets per muscle per week | [COACH], S1 |
| Rest | Main lifts 3–5 min, accessories 1.5–2 min | Same | Same | S8 (≥2–3 min), S34 |
| Progression | Session-to-session linear progression (section 4, R2) | Weekly block / DUP progression (section 3) | Block periodization with a meet taper | S21, S22 |
| Deload | Reactive: 10 % reset on a stall | Every 4–6 wk (week 5 in section 3) | Every 4–5 wk, plus a taper | S37, S24 |
| Taper (if a meet date is set) | – | 1–2 wk, volume −30–70 %, ≥85 % | Same | S23, S24 |

### 1c. Fat loss

Training's job in a deficit is to keep muscle and strength. **Keep the load (intensity); volume is the variable that may drop** (S32, S25, S29).

| | Beginner | Intermediate | Advanced | Basis |
|---|---|---|---|---|
| Sets/muscle/week | 8–10 | 10–16 (keep the previous phase's volume, or cut it by up to a third if recovery suffers) | 12–18 | S25, S32, S33 |
| Frequency per muscle | 2–3 | 2 | 2 | S25 |
| Reps | Compounds 6–12, isolation 10–15 | Same; keep 1–2 heavy sets of 4–6 per main lift each week to hold strength | Same | S25, S11 |
| RIR | 2–3 | Compounds 1–3, isolation 0–2 | Same | S25 (limit failure on heavy compounds) |
| Rest | Compounds 2–3 min, isolation 1–2 min. Supersets are allowed to save time. | Same | Same | S8, S33 |
| Progression | Double progression; keeping the same loads counts as success | Same | Same | [SYNTH] |
| Deload | Every 4–6 wk (fatigue accumulates faster in a deficit) [COACH/weak] | Same | Same | S37 |
| Cardio | 2–3×20–40 min easy (cycling or walking) | 2–4×20–40 min | Minimum needed | S25, S31 |
| Nutrition (brief) | Lose 0.5–1 % bodyweight per week; deficit ≤ ~500 kcal/day; protein 1.6–2.2 g/kg | Same | Same | S26, S29, S30, S27, S28 |

**Cardio placement:** do cardio after lifting, or at least 3 h apart; avoid running right before leg sessions (S31).

### 1d. General fitness

| | Beginner | Intermediate | Advanced | Basis |
|---|---|---|---|---|
| Sets/muscle/week | 4 → 8 | 6 → 12 | 10 → 15 | S33 (min 4), S8 |
| Frequency | 2–3 full body | 2–3 | 2–3 | S8, S40 |
| Reps / load | 8–12 at 60–70 % | 6–12, plus some 4–6 | 5–15 | S8 (novice 60–70 % × 8–12) |
| RIR | 2–4 | 2–3 | 1–3 | S16, S17 |
| Rest | 1.5–2 min; supersets OK | 1.5–3 min | 1.5–3 min | S8, S33 |
| Progression | Double progression | Same | Same | S8 |
| Deload | Reactive only | Every 6–8 wk | Every 6–8 wk | [COACH/weak] |
| Aerobic | 150–300 min/week moderate, counted from user input or added as Kestävyys slots | Same | Same | S40 |

### 1e. "Just wing it"
- Use the general-fitness intermediate parameters for every experience level, with RIR 2 and double progression.
- Pick the split by day count (section 2, hypertrophy column).
- Skip volume ramping. Deload only reactively (section 4, R7). [SYNTH]

### 1f. Session-length budget [SYNTH]

**Formula:** `max_work_sets = floor((T_min − W) / (rest_avg + 0.75))`
- W = warm-up time: 8 min, plus 4 min for each heavy compound after the first.
- rest_avg = weighted average rest for the session.

| Session length | Sets at 2 min avg rest | Sets at 3 min avg rest (powerlifting) |
|---|---|---|
| 30 min | 8 | 5–6 |
| 45 min | 13 | 9 |
| 60 min | 18 | 13 |
| 75 min | 24 | 17 |
| 90 min | 29 | 21 |

**If the weekly set target exceeds days × max_work_sets:**
1. Pair antagonists or isolation exercises as supersets. This roughly halves time per set pair (S33), so count about 0.6 time units per set.
2. If that is still not enough, lower the weekly target to what fits, but never below 4 sets per muscle (S33).
3. Drop sets in this order: isolation for the smallest muscles first, main lifts last.

---

## 2. Splits by days per week, as movement-pattern slots

### 2a. Slot catalog (default exercise suggestions, in priority order)

| Slot ID | Slot (FI) | Default suggestions | Fractional muscle credit |
|---|---|---|---|
| KYY | Kyykky-pääliike | Takakyykky, Etukyykky, Jalkaprässi | etureisi 1, pakara 0.5 |
| LON | Lonkkasarana-pääliike | Maastaveto, Romanialainen maastaveto, Hip thrust | takareisi 1, pakara 1, alaselkä 0.5 |
| YKS | Yksijalkainen | Bulgarialainen askelkyykky, Jalkaprässi | etureisi 1, pakara 0.5 (counts 1 when the stride is long) |
| POJ | Polven ojennus | Reiden ojennus, Jalkaprässi | etureisi 1 |
| POK | Polven koukistus | Reiden koukistus, Romanialainen maastaveto | takareisi 1 |
| PAK | Pakara / lonkan ojennus | Hip thrust, Romanialainen maastaveto, Bulgarialainen askelkyykky | pakara 1, takareisi 0.5 |
| POH | Pohje | Pohjenousu seisten | pohje 1 |
| VTY | Vaakatyöntö | Penkkipunnerrus, Käsipainopenkki, Dipit | rinta 1, ojentaja 0.5, etuolka 0.5 |
| VIN | Vino työntö | Vinopenkki, Vinokäsipainopenkki | rinta 1, etuolka 0.5, ojentaja 0.5 |
| PTY | Pystytyöntö | Pystypunnerrus, Käsipainopystypunnerrus | olkapää 1, ojentaja 0.5 |
| VVE | Vaakaveto | Kulmasoutu, Alatalja, Käsipainosoutu | selkä 1, hauis 0.5, takaolka 0.5 |
| PVE | Pystyveto | Leuanveto, Ylätalja | selkä 1, hauis 0.5 |
| RIE | Rinta-eristys | Kaapeliristikkäis, Dipit | rinta 1 |
| OSI | Olkapää sivu | Vipunosto sivulle | olkapää (sivu) 1 |
| TAK | Takaolka / lapa | Face pull, Takaolkavipunosto | takaolka 1 |
| HAU | Hauis | Hauiskääntö tangolla, Vasarakääntö | hauis 1 |
| OJE | Ojentaja | Ojentajapunnerrus taljassa, Ranskalainen punnerrus, Kapea penkki | ojentaja 1 |
| KES | Keskivartalo | Lankku, Jalannosto roikkuen, Pallof press | vatsa 1 |
| KAN | Kanto / ote | Farmer walk | ote, keskivartalo (not counted toward muscle volume) |
| KK | Kilpakyykky | Takakyykky | etureisi 1, pakara 0.5 |
| KP | Kilpapenkki | Penkkipunnerrus | rinta 1, ojentaja 0.5, etuolka 0.5 |
| KM | Kilpamaastaveto | Maastaveto | takareisi 1, pakara 1, alaselkä 0.5 |
| KYV | Kyykkyvariaatio | Etukyykky, Jalkaprässi | etureisi 1 |
| PEV | Penkkivariaatio | Kapea penkki, Vinopenkki, Käsipainopenkki | rinta 1, ojentaja 0.5–1 |
| MAV | Maastavetovariaatio | Romanialainen maastaveto, Hip thrust | takareisi 1, pakara 1 |
| KEST | Kestävyys | Not in catalog; suggest adding Kävely, Pyöräily, Soutulaite | – |

**Ordering rule** (ACSM, S8): main compounds first, then multi-joint accessories, then isolation, then core and carries.

**Format of the templates below:** `slot sets×reps`.
- Defaults are for **intermediate** lifters. Scale sets by **×0.7 for beginners** and **×1.25 for advanced**, rounding to whole sets with a minimum of 2.
- After scaling, recompute weekly fractional sets per muscle and adjust them toward the target in section 1.
- If a beginner picks 5–6 days, generate a **3–4-day lifting plan** (ACSM: novices 2–3 d full body, S8). Fill the other days with KEST or optional mobility work and explain why. [SYNTH]

### 2b. Hypertrophy (also "Just wing it", and the base template for fat loss)

**2 d — Full body A/B (Mon/Thu).** Volume is capped by session length, so this suits beginners.
- A: KYY 3×6–10 · VTY 3×6–10 · VVE 3×8–12 · POK 2×10–15 · OSI 2×12–20 · HAU 2×10–15
- B: LON 3×6–10 · PVE 3×8–12 · VIN 3×8–12 · YKS 2×8–12 · OJE 2×10–15 · TAK 2×12–20 · POH 2×10–15

**3 d — Full body A/B/C (Mon/Wed/Fri).**
- A: KYY 3×6–10 · VTY 3×6–10 · VVE 3×8–12 · POK 2×10–15 · OSI 2×12–20 · HAU 2×10–15
- B: LON 3×6–10 · PTY 3×6–10 · PVE 3×8–12 · POJ 2×10–15 · POH 2×10–15 · OJE 2×10–15
- C: YKS 3×8–12 · VIN 3×8–12 · VVE 3×10–12 · PAK 2×8–12 · TAK 2×12–20 · KES 2

**4 d — Upper/Lower ×2 (Mon/Tue/Thu/Fri).** This is the standard intermediate split (S8).
- Upper A: VTY 4×6–8 · VVE 4×6–10 · PTY 3×6–10 · PVE 3×8–12 · HAU 3×8–12 · OJE 3×10–15
- Lower A: KYY 4×6–8 · LON (RDL) 3×8–10 · POJ 3×10–15 · POK 3×10–15 · POH 3×10–15 · KES 2
- Upper B: VIN 3×8–12 · PVE 4×8–12 · VVE 3×10–12 · RIE 3×12–15 · OSI 4×12–20 · TAK 3×12–20
- Lower B: LON (Maastaveto / Hip thrust) 3×5–8 · YKS 3×8–12 · KYY (Jalkaprässi) 3×10–12 · POK 3×10–15 · POH 3×10–15 · KES 2
- Weekly fractional sets: about 12 chest, 14 back, 13 quads, 13 hamstrings, 11+ side delts.

**5 d — Upper / Lower / Push / Pull / Legs (Mon/Tue/Wed/Fri/Sat).**
- Upper: VTY 3×6–8 · VVE 3×6–10 · PTY 2×8–10 · PVE 3×8–12 · HAU 2 · OJE 2
- Lower: KYY 4×6–8 · LON 3×6–10 · POK 3×10–15 · POH 3
- Push: VIN 3×8–12 · PTY 3×8–12 · RIE 3×12–15 · OSI 4×12–20 · OJE 3×10–15
- Pull: PVE 4×8–12 · VVE 3×10–12 · TAK 3×12–20 · HAU 3×10–15 · KAN 2
- Legs: YKS 3×8–12 · POJ 3×10–15 · PAK 3×8–12 · POK 3×10–15 · POH 3 · KES 2

**6 d — Push/Pull/Legs ×2 (Mon–Sat).** For intermediate and advanced lifters only. Use 3 sets per slot (intermediate) or 4 (advanced).
- Push 1: VTY 6–8 reps · PTY 8–10 · RIE 12–15 · OSI 12–20 · OJE 10–15
- Pull 1: PVE 6–10 · VVE (Kulmasoutu) 8–10 · TAK 12–20 · HAU 8–12
- Legs 1: KYY 6–8 · LON (RDL) 8–10 · POJ 10–15 · POH 10–15 · KES
- Push 2: VIN 8–12 · VTY (Käsipainopenkki) 10–12 · OSI 12–20 · OJE 12–15
- Pull 2: VVE (Alatalja) 10–12 · PVE (Ylätalja) 10–15 · TAK 15–20 · HAU (Vasarakääntö) 10–15
- Legs 2: LON (Hip thrust / Maastaveto) 5–10 · YKS 8–12 · POK 10–15 · POH 10–15 · KES
- Check the per-session cap: with 3 sets each, no muscle exceeds about 8 fractional sets in one session.

### 2c. Powerlifting

Main-lift prescriptions come from section 3. In the templates, "H" is the heavy day and "V" the volume day.

**2 d (Mon/Thu).**
- A: KK (H) · KP (H) · MAV 3×6–8 · VVE 3×8–10 · KES 2
- B: KM (H) · KP (V) · KYV 3×6–8 · PVE 3×8–10 · OJE 2

**3 d — DUP full body (Mon/Wed/Fri).** This is the default for beginners and intermediates.
- D1: KK (H) · KP (V) · VVE 3×8–10 · POK 2×10–12 · KES 2
- D2: KM (H) · KP (H) · PVE 3×8–10 · OJE 2×10–12 · TAK 2×15
- D3: KK (V) · PEV (Kapea penkki) 3×6–8 · MAV (RDL) 3×6–8 · VVE 3×10 · HAU 2

**4 d — Upper/lower powerlifting split (Mon/Tue/Thu/Fri).**
- D1: KK (H) · MAV 3×6–8 · POJ 2×10–12 · KES 2
- D2: KP (H) · VVE 4×6–10 · PTY 3×6–8 · OJE 2×10–12
- D3: KM (H) · KYV 3×5–8 · POK 3×10–12 · KAN 3
- D4: KP (V) · PEV 3×6–8 · PVE 3×8–10 · TAK 3×15 · HAU 2

**5 d (Mon/Tue/Wed/Fri/Sat).** The 4-day split plus D5: KP (technique, 4×3 @ ~70 % / RPE 6) · PTY 3×8 · VVE 3×10 · OSI 3×15. Squat and deadlift volume stays as in the 4-day split.

**6 d (advanced only).**
- Squat 3×/week: H, V, and technique (5×2 @ 70 %).
- Bench 4×/week: H, V, PEV, and technique.
- Deadlift 1× plus 1 MAV.
- Spread the work so no session exceeds the time budget.
- Beginners or intermediates who pick 6 days get the 4-day plan plus 2 optional KEST / accessory days.

### 2d. Fat loss
- Use the hypertrophy templates (2b) with volume at the **lower bound** for the experience level, and keep 1–2 heavy sets (4–6 reps) of KYY / LON / VTY each week.
- 2–3 days: full body. Add KEST 20–30 min after 1–2 of the sessions (S31: separate cardio from lifting, or put it after).
- 4 days: Upper/Lower ×2, plus KEST after Lower B or on a separate day.
- 5 days: 4 lifting days (Upper/Lower ×2) plus 1 KEST day of 30–45 min easy.
- 6 days: 4 lifting days (Upper/Lower ×2) plus 2 KEST days, or the 5-day Upper/Lower/Push/Pull/Legs plan plus 1 KEST day for advanced lifters.
- Rationale: fatigue tolerance is lower in a deficit, and S25 recommends the lowest cardio dose that achieves the fat loss. [SYNTH]

### 2e. General fitness
- 2 d: Full body A/B (as in 2b) plus KAN 2–3×30–40 m and KES on both days.
- 3 d: Full body A/B/C plus KAN on one day.
- 4 d: 3 full-body days plus 1 KEST day (30–45 min moderate), or Upper/Lower ×2.
- 5–6 d: 3 full-body days plus 2–3 KEST days.
- The app should show weekly aerobic minutes against the 150–300 min target (S40).

---

## 3. Concrete progression examples

### 3a. Powerlifting, intermediate, 3 days/week (DUP template 2c), 10 weeks

**Structure:** 4-week accumulation, then a deload, then 4-week intensification, then taper and test.

**Rules for the whole cycle**
- %1RM values are relative to the working e1RM (R0).
- The RPE value is a cap. If the prescribed % would exceed the RPE cap, lower the load by about 3 % for each RPE point over (R4), then continue.
- Basis: block and DUP structures (S21, S22), RPE loading (S20), deload timing (S37), taper (S23, S24). Specific numbers are [SYNTH/COACH].

**Heavy (H) day, squat and bench.** Deadlift H uses the same %s with one set fewer.

| Week | Phase | Sets×reps | %1RM | RPE cap | Notes |
|---|---|---|---|---|---|
| 1 | Accumulation | 5×5 | 72.5 | 7 | |
| 2 | Accumulation | 5×5 | 75 | 7.5 | |
| 3 | Accumulation | 5×4 | 77.5 | 8 | |
| 4 | Accumulation | 5×4 | 80 | 8 | Last set may be AMRAP capped at RPE 9, to update e1RM |
| 5 | Deload (5–7 days) | 3×3 | 70 | ≤6 | Sets −50 %; frequency kept (S37, S36) |
| 6 | Intensification | 4×3 | 82.5 | 8 | |
| 7 | Intensification | 4×3 | 85 | 8 | |
| 8 | Intensification | 4×2 | 87.5 | 8.5 | |
| 9 | Intensification | 1×1 @ 90 + 3×2 | 90 / 82.5 | 8.5 | Top single plus back-off sets |
| 10 | Taper and test | Mon: 1×1 @ 90, 2×2 @ 80. Wed: 2×2 @ 75 (bench only), no deadlift. Sat: test. | – | ≤8 before the test | Volume −60 %; ≥85 % kept on the top single (S24). Test day: work up to a single @ RPE 9–9.5, or AMRAP at 87.5 %. |

**Volume (V) day, squat and bench.**

| Week | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| Sets×reps @ % | 4×8 @ 65 | 4×8 @ 67.5 | 4×7 @ 70 | 4×6 @ 72.5 | 2×6 @ 60 | 3×6 @ 72.5 | 3×5 @ 75 | 3×5 @ 77.5 | 3×4 @ 77.5 |
| RPE cap | 7 | 7 | 7.5 | 8 | 6 | 7.5 | 8 | 8 | 7.5 |

**Variations and accessories**
- PEV and MAV: 3×6–8 at RPE 7–8 in weeks 1–4, 3×5–6 at RPE 8 in weeks 6–9.
- Accessories are dropped in week 10, about 2 weeks before the test, as in Pritchard (S23).

**Weekly direct sets per lift in weeks 1–4:** squat 9 (H 5 + V 4), bench 9 + 3 PEV, deadlift 4 + 3 MAV. All within the intermediate ranges in 1b.

**For a real meet date:** place week 10 so the last heavy session (≥85–90 %) falls **3–4 days** before the meet (S23, 3.7 ± 1.6 days). Do only light technique work or rest for the final 2–3 days (S24: 2–7 days of cessation).

**Next cycle**
- Recompute the working e1RM from weeks 8–10.
- Start the new cycle with week 1 at 72.5 % of the *new* e1RM.
- If e1RM did not rise by at least 1 %, add one set to the V day for each lift (+1 set/week) next cycle.
- Advanced lifters: same shape, but with 3-week blocks (deload every 4 weeks), %s about 2.5 % higher in intensification, and optionally a single @ RPE 8 each week.

**Beginner powerlifters:** use linear progression (3b) on KK, KP and KM until R6 triggers, then move to this cycle.

### 3b. Beginner linear progression, 3 d/week full body A/B alternating

**Structure** (Starting Strength / StrongLifts style, C1 and C3):
- A: Takakyykky 3×5 · Penkkipunnerrus 3×5 · Kulmasoutu 3×8 · accessories (POK, HAU) 2×10–12
- B: Takakyykky 3×5 · Pystypunnerrus 3×5 · Maastaveto 1×5 (2×5 if the user is weak) · Ylätalja 3×8–10 · accessories (OJE, KES)

**Starting load**
- With known lifts: about 70 % of the user's e1RM, which is roughly RPE 6 for 3×5.
- Otherwise: the empty bar or the lightest load that gives clean reps at RIR ≥3. [SYNTH]

**Increments**
- Lower body: squat +5 kg per session for the first 2–3 weeks, then +2.5 kg. Deadlift +5 kg per session until RPE 8 is reached, then +2.5 kg.
- Upper body: +2.5 kg per session for bench, overhead press and row. Use +1.25 kg if microplates exist; switch to it once 5×5… once sets reach RPE 8.
- Accessories: double progression.
- [COACH] (C1, C2). The ACSM range is 2–10 % (S8).

**Example: start at squat 60 / bench 40 / press 30 / deadlift 70 kg**

| Week | Day | Squat 3×5 | Bench 3×5 | Press 3×5 | Deadlift 1×5 |
|---|---|---|---|---|---|
| 1 | A | 60 | 40 | – | – |
| 1 | B | 65 | – | 30 | 70 |
| 1 | A | 70 | 42.5 | – | – |
| 2 | B | 75 | – | 32.5 | 75 |
| 2 | A | 77.5 | 45 | – | – |
| 2 | B | 80 | – | 35 | 80 |
| 3–… | | +2.5 per session | +2.5 per exposure | +2.5 (or +1.25) per exposure | +5, later +2.5 |

On failure, apply R5 and R6.

**Hypertrophy and general-fitness beginners** use the same mechanism, but with double progression (R1) at 3×8–12 instead of fixed 3×5.

---

## 4. Rules (pseudo-rules)

**R0 — Working e1RM (input for every %1RM calculation)** [SYNTH]
- Per exercise, compute `e1RM = load × (1 + (reps + RIR) / 30)`. This is Epley with RIR added to the rep count.
- Only use sets with reps ≤ 10 and logged RPE ≥ 7. If RPE was not logged, assume RIR = 0 for AMRAP sets and RIR = 2 otherwise.
- `working_e1RM` = the median of the top 3 e1RM values from the last 28 days. On onboarding, use the user's entered lift. On the first session with no data, use the conservative start loads in 3b.
- Use Epley because the app already does. Its error grows above about 10 reps.
- Load for a target: `%1RM(reps, RIR) = 1 / (1 + (reps + RIR) / 30)`. The table below follows from it (RPE = 10 − RIR, the Zourdos scale S18; RPE 10 is shown as RIR 0):

| reps \ RPE | 10 | 9 | 8 | 7 | 6 |
|---|---|---|---|---|---|
| 1 | 100 | 94 | 91 | 88 | 86 |
| 2 | 94 | 91 | 88 | 86 | 83 |
| 3 | 91 | 88 | 86 | 83 | 81 |
| 4 | 88 | 86 | 83 | 81 | 79 |
| 5 | 86 | 83 | 81 | 79 | 77 |
| 6 | 83 | 81 | 79 | 77 | 75 |
| 8 | 79 | 77 | 75 | 73 | 71 |
| 10 | 75 | 73 | 71 | 70 | 68 |
| 12 | 71 | 70 | 68 | 67 | 65 |

- Round loads to the user's smallest plate step: 2.5 kg for barbells, the next available dumbbell, 1.25 kg if microplates are available.

**R1 — Double progression** (hypertrophy, fat loss, general fitness, accessories). Basis: S8, S35, C2.
- Each exercise has a rep range [lo, hi], a set count n and a target RIR r.
- IF every working set reached hi at RIR ≥ r (RPE ≤ 10 − r) THEN next session load += step, and the rep target resets to lo.
  - Step for compound lifts: lower body 5 kg (beginner) or 2.5 kg (otherwise); upper body 2.5 kg (or 1.25 kg).
  - Step for isolation and dumbbell exercises: the next available weight, or +2–5 %.
  - Cap any step at 10 % of the load (S8).
- ELSE IF reps went up in at least one set compared with the last time at the same load THEN keep the load (this is progress).
- ELSE apply R5.
- Stricter ACSM variant (S8): increase the load only when the lifter did hi + 1–2 reps in **two consecutive** sessions.

**R2 — Beginner linear progression.**
- IF all sets × reps were completed at RPE ≤ 9 THEN next session load += increment (3b).
- IF RPE ≥ 9.5 on the last set but all reps were done THEN repeat the load once.
- When a step change is needed, ramp it in over a couple of sessions rather than all at once. [COACH]

**R3 — Weekly / percentage progression** (intermediate and advanced powerlifting).
- Follow the block table in 3a.
- IF the week's top set RPE is **more than 1 below** the cap on two consecutive H days THEN raise working_e1RM by 2.5 % (lower body) or 1.25 % (upper body). The table's %s then rise automatically.
- IF the RPE was **≥1 above** the cap on two consecutive sessions THEN lower working_e1RM by 2.5 %. [SYNTH]

**R4 — Within-session RPE autoregulation.** Basis: S18, S20, C2.
- After the first working set, compute `ΔRIR = actual_RIR − target_RIR`.
- IF |ΔRIR| ≥ 1 THEN `next_load = load × (1 + ΔRIR × k)`, with k ≈ 0.03 (about 2.5–3.5 % per rep for 3–10-rep sets; this follows from the Epley table). Use it for the remaining sets and round to the plate step.
- Because users underestimate their remaining reps by about 1 (S17), treat a reported RIR ≥ 4 as "≥ 4", not as an exact number.
- Fatigue stop (optional, advanced): IF the e1RM of a later set falls more than 5–7 % below the first set's e1RM THEN stop further sets of that exercise. [COACH/weak]

**R5 — Failed session or stall** (per exercise).
- Define a fail as missing the target reps on ≥1 set by ≥1 rep, or RPE more than 1 above the cap.
- 1st fail: repeat the same load and prescription next exposure.
- 2nd consecutive fail:
  - Beginner: repeat once more.
  - Otherwise: reduce the load 5 % (or drop one set) and rebuild with the normal increments.
- 3rd consecutive fail, beginner linear progression: **reset to −10 %** and progress again (C3).
- Exception: IF the fail coincided with a user-reported bad night, illness or a missed week THEN don't count it and repeat the session. [SYNTH]
- Fat loss: IF the lift is at the same load and reps as 2 weeks ago THEN count it as success, not a stall.

**R6 — Switching progression model.**
- IF a lift has needed 2 resets (R5, third fail) within 8 weeks, OR the lifter has trained ≥ 6 months with linear progression THEN switch that lift to weekly progression: 3a for powerlifting, R1 with weekly load steps for other goals. Expect novice progress to last about 6 months, possibly much longer (C2).
- Onboarding: IF experience = beginner AND entered e1RM ≥ about 1.25 × bodyweight squat or 1.0 × bodyweight bench THEN offer "start as intermediate". [SYNTH/weak]

**R7 — Deloads.**
- Scheduled: every N weeks, with N = beginner none (fallback 8–10), intermediate 6, advanced 4–5, fat loss 4–6 (S37: 5.6 ± 2.3 weeks).
- Reactive: IF any 2 of these occur within 7 days THEN deload now and restart the mesocycle clock:
  - e1RM on ≥ 2 main lifts more than 5 % below their 28-day median
  - RPE ≥ 1 above target at the same load in 2 sessions
  - the user reports joint pain or persistent soreness
  - ≥ 2 R5 fails across different lifts in one week
- Deload content (S37, S38, C2):
  - Length 5–7 days.
  - Sets −40–50 % (round down; minimum 1 per exercise).
  - Load −10 % (or unchanged for powerlifting main lifts at lower reps).
  - RIR +2 (target RIR ≥ 3–4).
  - Same sessions per week and same exercises.
- **Never schedule a deload as a full week off.** S36 found a full week off hurt strength.
- After a deload: resume at the mesocycle start values. For hypertrophy and fat loss, apply R8.

**R8 — Volume progression across mesocycles** (hypertrophy). [COACH/weak; the direction follows S1/S4, the step size is a convention]
- At the end of each mesocycle, per muscle:
  - IF that muscle's exercises progressed (R1 load or rep gains in ≥ 50 % of exposures) AND no reactive deload happened THEN keep the volume.
  - IF progress stalled but recovery is fine (no pain, RPE on target) THEN sets += 2/week, up to the cap in 1a.
  - IF a reactive deload happened or the user reports excessive soreness THEN sets −= 2.
- If the per-session cap (1a) would be exceeded, add a training day for that muscle or use the next template.

**R9 — Taper** (powerlifting with a meet date; S23, S24).
- Volume peaks 5–6 weeks out; intensity peaks about 2 weeks out.
- Taper length 1–2 weeks: volume −30–70 % (default −60 %), intensity ≥ 85 % on top sets, accessories dropped 2 weeks out.
- Last heavy session (single or double at ≥ 90 %) 3–4 days out, with the deadlift last heavy 5–7 days out ("deadlift recovers slowest", S23). Final 2–3 days: rest or very light technique work.
- **Never take more than 7 days completely off.**

**R10 — Fat loss guardrails** (show only as hints; the app is training-focused).
- IF bodyweight trend (7-day average) falls more than 1 %/week for 2 weeks OR e1RM falls more than 5 % on ≥ 2 lifts THEN suggest a smaller deficit (S26, S29, S30).
- Show a protein hint of 1.6–2.2 g/kg (S27, S28).

**R11 — Missed sessions.** [SYNTH]
- IF a session is missed THEN shift the schedule; never merge two sessions.
- IF the gap is ≥ 10 days THEN repeat the last completed week at −5 % load.
- IF the gap is ≥ 3 weeks THEN restart the current mesocycle at −10 % and recompute e1RM from new sets.

---

## 5. Sources

[PR] = peer-reviewed. "Opened" says how much of the source I actually read.

**Volume and frequency**
- **S1** [PR] Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. The Resistance Training Dose Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gains. *Sports Med* 2026;56:481–505. https://doi.org/10.1007/s40279-025-02344-w. Preprint: https://sportrxiv.org/index.php/server/preprint/view/460. Opened the abstract. The ~31-set and ~3-set PUOS figures and the +3.27 %/day frequency slope are quoted from S1 inside S2.
- **S2** [PRE, not peer reviewed] Remmert JF, Pelland JC, Robinson ZP, Hinson SR, Zourdos MC. Is There Too Much of a Good Thing? Meta-Regressions of the Effect of Per-Session Volume on Hypertrophy and Strength. SportRxiv 2025. https://sportrxiv.org/index.php/server/preprint/view/537. Opened the full text.
- **S3** [PR] Schoenfeld BJ, Ogborn D, Krieger JW. Dose-response relationship between weekly resistance training volume and increases in muscle mass. *J Sports Sci* 2017;35(11):1073–82. https://doi.org/10.1080/02640414.2016.1210197. Opened the abstract. The <5 / 5–9 / 10+ category figures come from a secondary summary.
- **S4** [PR] Schoenfeld BJ et al. Resistance Training Volume Enhances Muscle Hypertrophy but Not Strength in Trained Men. *Med Sci Sports Exerc* 2019;51(1):94–103. https://doi.org/10.1249/MSS.0000000000001764. Opened the abstract.
- **S5** [PR] Schoenfeld BJ, Ogborn D, Krieger JW. Effects of Resistance Training Frequency on Measures of Muscle Hypertrophy. *Sports Med* 2016;46(11):1689–97. https://doi.org/10.1007/s40279-016-0543-8. Opened the abstract.
- **S6** [PR] Schoenfeld BJ, Grgic J, Krieger J. How many times per week should a muscle be trained to maximize muscle hypertrophy? *J Sports Sci* 2019;37(11):1286–95. https://doi.org/10.1080/02640414.2018.1555906. Opened the abstract.
- **S7** [PR] Grgic J et al. Effect of Resistance Training Frequency on Gains in Muscular Strength. *Sports Med* 2018;48:1207–20. https://doi.org/10.1007/s40279-018-0872-x. Opened the abstract.
- **S13** [PR] Ralston GW et al. The Effect of Weekly Set Volume on Strength Gain: A Meta-Analysis. *Sports Med* 2017;47:2585–601. https://doi.org/10.1007/s40279-017-0762-7. Opened the abstract.
- **S14** [PR] Androulakis-Korakakis P, Fisher JP, Steele J. The Minimum Effective Training Dose Required to Increase 1RM Strength in Resistance-Trained Men. *Sports Med* 2020;50:751–65. https://doi.org/10.1007/s40279-019-01236-0. Opened the abstract.
- **S39** [PR] Baz-Valle E et al. Total Number of Sets as a Training Volume Quantification Method for Muscle Hypertrophy. *J Strength Cond Res* 2021;35(3):870–8. https://doi.org/10.1519/JSC.0000000000002776. Opened the abstract. Supports counting sets taken close to failure at 6–20+ reps.

**Position stands and load**
- **S8** [PR, position stand] American College of Sports Medicine. Progression Models in Resistance Training for Healthy Adults. *Med Sci Sports Exerc* 2009;41(3):687–708. https://doi.org/10.1249/MSS.0b013e3181915670; PDF https://sfu.ca/~ryand/kin343/ACSMresistance.pdf. Opened the full text, including Table 2 with evidence grades A–D.
- **S9** [PR] Schoenfeld BJ, Grgic J, Ogborn D, Krieger JW. Strength and Hypertrophy Adaptations Between Low- vs. High-Load Resistance Training. *J Strength Cond Res* 2017;31(12):3508–23. https://doi.org/10.1519/JSC.0000000000002200. Opened the abstract.
- **S10** [PR, narrative] Schoenfeld BJ, Grgic J, Van Every DW, Plotkin DL. Loading Recommendations for Muscle Strength, Hypertrophy, and Local Endurance: A Re-Examination of the Repetition Continuum. *Sports* 2021;9(2):32. https://doi.org/10.3390/sports9020032. Opened the abstract.
- **S11** [PR] Currier BS et al. Resistance training prescription for muscle strength and hypertrophy in healthy adults: a systematic review and Bayesian network meta-analysis. *Br J Sports Med* 2023;57:1211–20. https://doi.org/10.1136/bjsports-2023-106807. Opened the abstract.
- **S12** [PR, older] Rhea MR et al. A meta-analysis to determine the dose response for strength development. *Med Sci Sports Exerc* 2003;35(3):456–64. https://doi.org/10.1249/01.MSS.0000053727.63505.D4. Opened the abstract.

**Failure, RIR and RPE**
- **S15** [PR] Refalo MC, Helms ER, Trexler ET, Hamilton DL, Fyfe JJ. Influence of Resistance Training Proximity-to-Failure on Skeletal Muscle Hypertrophy. *Sports Med* 2023;53:649–65. https://doi.org/10.1007/s40279-022-01784-y. Opened the abstract.
- **S16** [PR, exploratory] Robinson ZP et al. Exploring the Dose–Response Relationship Between Estimated Resistance Training Proximity to Failure, Strength Gain, and Muscle Hypertrophy. *Sports Med* 2024;54:2209–31. https://doi.org/10.1007/s40279-024-02069-2. Opened the abstract.
- **S17** [PR] Halperin I et al. Accuracy in Predicting Repetitions to Task Failure in Resistance Exercise. *Sports Med* 2022;52:377–90. https://doi.org/10.1007/s40279-021-01559-x. Opened the abstract.
- **S18** [PR] Zourdos MC et al. Novel Resistance Training-Specific RPE Scale Measuring Repetitions in Reserve. *J Strength Cond Res* 2016;30(1):267–75. https://doi.org/10.1519/JSC.0000000000001049. Opened a search summary only (RPE 10 = 0 RIR, RPE 9 = 1 RIR, and so on).
- **S19** [PR, practitioner journal] Helms ER, Cronin J, Storey A, Zourdos MC. Application of the RIR-Based RPE Scale for Resistance Training. *Strength Cond J* 2016;38(4):42–9. https://doi.org/10.1519/SSC.0000000000000218. Opened the abstract only.
- **S20** [PR] Helms ER et al. RPE vs. Percentage 1RM Loading in Periodized Programs Matched for Sets and Repetitions. *Front Physiol* 2018;9:247. https://doi.org/10.3389/fphys.2018.00247. Opened the abstract.

**Periodization, taper, progression, rest, deload**
- **S21** [PR] Williams TD et al. Comparison of Periodized and Non-Periodized Resistance Training on Maximal Strength. *Sports Med* 2017;47:2083–100. https://doi.org/10.1007/s40279-017-0734-y. Opened a search summary.
- **S22** [PR] Zourdos MC et al. Modified Daily Undulating Periodization Model Produces Greater Performance Than a Traditional Configuration in Powerlifters. *J Strength Cond Res* 2016;30(3):784–91. https://doi.org/10.1519/JSC.0000000000001165. Opened the abstract. Supports the hypertrophy → power → strength day order within a week.
- **S23** [PR, interviews, n = 11] Pritchard HJ et al. Tapering Practices of New Zealand's Elite Raw Powerlifters. *J Strength Cond Res* 2016;30(7):1796–804. https://doi.org/10.1519/JSC.0000000000001292. Opened the abstract.
- **S24** [PR, narrative] Travis SK, Mujika I, Gentles JA, Stone MH, Bazyler CD. Tapering and Peaking Maximal Strength for Powerlifting Performance: A Review. *Sports* 2020;8(9):125. https://doi.org/10.3390/sports8090125. Opened the full text and conclusions.
- **S34** [PR, RCT, n = 21] Schoenfeld BJ et al. Longer Interset Rest Periods Enhance Muscle Strength and Hypertrophy in Resistance-Trained Men. *J Strength Cond Res* 2016;30(7):1805–12. https://doi.org/10.1519/JSC.0000000000001272. Opened the abstract.
- **S35** [PR, RCT] Plotkin D et al. Progressive overload without progressing load? *PeerJ* 2022;10:e14142. https://doi.org/10.7717/peerj.14142. Opened the abstract.
- **S36** [PR, RCT] Coleman M et al. Gaining more from doing less? The effects of a one-week deload period during supervised resistance training. *PeerJ* 2024;12:e16777. https://doi.org/10.7717/peerj.16777. Opened the abstract.
- **S37** [PR, survey] Rogerson D et al. Deloading Practices in Strength and Physique Sports: A Cross-sectional Survey. *Sports Med Open* 2024;10:26. https://doi.org/10.1186/s40798-024-00691-y. Opened the abstract.
- **S38** [PR, Delphi expert consensus] Bell L et al. Integrating Deloading into Strength and Physique Sports Training Programmes. *Sports Med Open* 2023;9:87. https://doi.org/10.1186/s40798-023-00633-0. Opened the abstract.

**Fat loss, nutrition, cardio, time efficiency, health**
- **S25** [PR, narrative] Helms ER, Fitschen PJ, Aragon AA, Cronin J, Schoenfeld BJ. Recommendations for natural bodybuilding contest preparation: resistance and cardiovascular training. *J Sports Med Phys Fitness* 2015;55(3):164–78. https://pubmed.ncbi.nlm.nih.gov/24998610/. Opened the abstract.
- **S26** [PR, narrative] Helms ER, Aragon AA, Fitschen PJ. Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. *J Int Soc Sports Nutr* 2014;11:20. https://doi.org/10.1186/1550-2783-11-20. Opened a search summary.
- **S27** [PR, position stand] Jäger R et al. ISSN Position Stand: protein and exercise. *J Int Soc Sports Nutr* 2017;14:20. https://doi.org/10.1186/s12970-017-0177-8. Opened the abstract.
- **S28** [PR] Morton RW et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength. *Br J Sports Med* 2018;52:376–84. https://doi.org/10.1136/bjsports-2017-097608. Opened the abstract.
- **S29** [PR] Murphy C, Koehler K. Energy deficiency impairs resistance training gains in lean mass but not strength. *Scand J Med Sci Sports* 2022;32:125–37. https://doi.org/10.1111/sms.14075. Opened the abstract.
- **S30** [PR, n = 23 elite athletes] Garthe I, Raastad T, Sundgot-Borgen J. Long-term effect of weight loss on body composition and performance in elite athletes. *Int J Sport Nutr Exerc Metab* 2011;21(5):426–35. https://doi.org/10.1123/ijsnem.21.5.426. Opened the abstract. The 0.7 % vs 1.4 %/week comparison comes from the companion intervention, as summarized in this abstract.
- **S31** [PR] Schumann M et al. Compatibility of Concurrent Aerobic and Strength Training for Skeletal Muscle Size and Function. *Sports Med* 2022;52:601–12. https://doi.org/10.1007/s40279-021-01587-7. Opened the abstract.
- **S32** [PR, narrative] Spiering BA, Mujika I, Sharp MA, Foulis SA. Maintaining Physical Performance: The Minimal Dose of Exercise Needed to Preserve Endurance and Strength Over Time. *J Strength Cond Res* 2021;35(5):1449–58. https://doi.org/10.1519/JSC.0000000000003964. Opened the abstract.
- **S33** [PR, narrative] Iversen VM, Norum M, Schoenfeld BJ, Fimland MS. No Time to Lift? Designing Time-Efficient Training Programs for Strength and Hypertrophy. *Sports Med* 2021;51:2079–95. https://doi.org/10.1007/s40279-021-01490-1. Opened the abstract.
- **S40** [PR, guideline] Bull FC et al. World Health Organization 2020 guidelines on physical activity and sedentary behaviour. *Br J Sports Med* 2020;54:1451–62. https://doi.org/10.1136/bjsports-2020-102955. Opened the abstract.

**Coaching conventions** (not peer-reviewed)
- **C1** [COACH] Barbell Logic, "Starting Strength Novice Linear Progression": https://barbell-logic.com/starting-strength-novice-linear-progression/. Opened. Gives the A/B layout, 3×5, squat and deadlift +5 lb per session, and training every 48–72 h.
- **C2** [COACH] Andy Morgan, RippedBody, "Progression": https://rippedbody.com/progression/. Opened. Gives linear-then-double progression, about 4 % load change per rep outside the range, deloads with sets −30–50 % and the same loads, and novice progress lasting from 6 months to years.
- **C3** [COACH, not verified from the official site] StrongLifts 5×5 rule: three consecutive failed sessions on a lift → −10 % on that lift only. Taken from secondary summaries, e.g. https://www.allthingsgym.com/summary-of-stronglifts-5x5/ (search result, not opened). The index page https://stronglifts.com/stronglifts-5x5/ was opened but does not state the rule.
- **Not used:** I could not open an NSCA source for the "2-for-2 rule" or the 2.5–5 lb upper / 5–10 lb lower increments. Search results attribute them only to exam-prep sites. Use ACSM S8 (2–10 %, 1–2 reps over target in 2 sessions) as the citable version.

---

## 6. Where the evidence is weak

1. **Volume caps for advanced lifters.** The ~31-set threshold (S1) is an estimate across all trainees and comes with growing uncertainty. Studies are mostly 6–12 weeks long in young men (79 % male in S1). Caps of 16–22 sets with an option of 25 are a cautious [SYNTH] choice. The per-session cap of ~11 sets comes from a preprint (S2).
2. **Strength volume.** The finding that very few sets are enough for strength (~2 direct sets per session, ~3 per week) comes from short studies. Powerlifting coaching practice uses far more. My ranges in 1b follow practice, not that finding.
3. **Frequency.** With volume equated, frequency hardly matters for hypertrophy (S6). **Choosing a split is therefore about convenience and per-session volume, not about outcomes.** For strength, frequency has some independent value (S1).
4. **RIR and RPE.** Proximity to failure in the meta-analyses (S16) is estimated, not measured. Users misjudge remaining reps by about 1 (S17). Treat RPE logs as noisy and smooth them over sessions.
5. **Deload timing and content.** The evidence is a survey (S37), an expert consensus (S38) and one RCT (S36). Intervals and percentages are conventions.
6. **Linear progression increments, the 10 % reset rule and the beginner-to-intermediate switch.** All of these are coaching conventions with no RCT support.
7. **Periodization.** The advantage partly reflects higher peak loads in the periodized groups (critique summarized alongside S21). Block or DUP structure is reasonable but not proven optimal. The %s in 3a are [SYNTH].
8. **Taper.** The evidence is mostly interviews and reviews (S23, S24). Use the ranges, not point values.
9. **Fat-loss volume.** No trial directly sets the optimal volume in a deficit. The "keep intensity, volume may fall" rule comes from maintenance data (S32) and expert review (S25).
10. **Epley at high reps.** %1RM values above about 10 reps are approximate, and the error grows with reps. Use RIR autoregulation (R4) rather than %1RM for isolation exercises.
