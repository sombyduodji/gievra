import 'exercises.dart';
import 'injuries.dart';
import 'insights.dart' show weekStart;
import 'models.dart';
import 'program.dart';
import 'program_check.dart';
import 'l10n.dart' as l10n;

// Ohjelman muokkaus ja viikkokuorma:
//  - liikkeen vaihto: sama liikemalli korvaa hyvin, eri malli muuttaa viikon lihasryhmäkuormaa (arvio näytetään)
//  - sarjat ja toistoalue liikekohtaisesti; lihaskasvu toimii laajalla toistoalueella, kun sarjat viedään lähelle
//    uupumusta (Schoenfeld ym. 2017, 2021: ~5–30 toistoa), voima kehittyy parhaiten raskailla painoilla (1–6)
//  - viikkokuorma: sarjoja lihasryhmää kohden viikossa. Minimiannos 4 (Iversen ym. 2021); lihaskasvussa
//    10–20 tuottaa yleensä eniten (Schoenfeld ym. 2017 annos-vaste; Pelland ym. 2026: hyöty tasaantuu)
//  - palautuminen: samaa lihasryhmää raskaasti noin 48 h välein (ACSM 2009)

String slotName(String slot) => slots[slot]?.name ?? l10n.t('ei tunnettua liikemallia');

/// Vaihtoehdot: ensin sama liikemalli (korvaa hyvin), sitten muut liikkeet.
List<String> _flatExercises() => allExercises().values.expand((x) => x).toSet().toList();

(List<String>, List<String>) swapCandidates(PlanItem it) {
  final fam = family(it.slot);
  final all = _flatExercises();
  final same = <String>[
    ...?slots[it.slot]?.defaults,
    for (final x in all)
      if (family(slotOf(x)) == fam) x,
  ].where((x) => x != it.exercise).toSet().toList();
  final other = all.where((x) => x != it.exercise && !same.contains(x)).toList();
  return (same, other);
}

Map<String, double> _musclesOf(String slot) => slotMuscles[slot] ?? const {};

String _fmt(double v) => fmtNum((v * 2).round() / 2);

/// Arvio liikkeen vaihdosta: mitä se muuttaa viikon kuormassa ja ohjelman tarkistuksessa.
/// Palauttaa (hyvä vaihto?, perustelut).
(bool, List<String>) assessSwap(Program p, PlanDay day, PlanItem it, String to, {List<String> injuries = const []}) {
  final msgs = <String>[];
  var ok = true;
  final newSlot = family(slotOf(to)) == family(it.slot) ? it.slot : slotOf(to);
  if (family(newSlot) == family(it.slot)) {
    msgs.add(l10n.t('✓ Sama liikemalli ({0}): korvaa hyvin, viikon kuorma pysyy samana.', [slotName(it.slot)]));
  } else {
    ok = false;
    final before = statsOf(p).weekly;
    final copy = _clone(p);
    final ci = copy.plan[p.plan.indexOf(day)].items[day.items.indexOf(it)];
    ci
      ..exercise = to
      ..slot = newSlot;
    final after = statsOf(copy).weekly;
    msgs.add(l10n.t('⚠ Eri liikemalli: {0} → {1}.', [slotName(it.slot), slotName(newSlot)]));
    for (final m in {...before.keys, ...after.keys}) {
      final b = before[m] ?? 0, a = after[m] ?? 0;
      if ((a - b).abs() >= .5) msgs.add('${a > b ? '↑' : '↓'} $m ${_fmt(b)} → ${_fmt(a)} sarjaa viikossa');
    }
  }
  if (it.kind == 'H' || it.kind == 'V') {
    final comp = slots[it.slot]?.defaults.first;
    if (comp != null && to != comp) {
      msgs.add(
        l10n.t('⚠ Voimanoston taulukko on tehty kilpaliikkeelle ({0}). Muu liike ei harjoita kilpasuoritusta.', [comp]),
      );
      ok = false;
    }
  }
  if (day.items.any((x) => x != it && x.exercise == to)) {
    msgs.add(l10n.t('⚠ {0} on jo tässä treenissä.', [to]));
    ok = false;
  }
  final inj = injuryStatus(to, injuries);
  if (inj.avoid.isNotEmpty) {
    msgs.add(l10n.t('⚠ Vammatila ({0}): tätä liikettä kannattaa välttää.', [inj.avoid.join(', ')]));
    ok = false;
  } else if (inj.modify.isNotEmpty) {
    msgs.add('🩹 ${inj.modify.join(' · ')}');
  }
  if (measureOf(to) != measureOf(it.exercise)) {
    msgs.add(l10n.t('Mitataan: {0} (toistoalue vaihdetaan sen mukaan).', [l10n.t(measureOf(to).label)]));
  }
  return (ok, msgs);
}

/// Vaihtaa liikkeen ja tarvittaessa liikemallin ja mittaustavan mukaisen toistoalueen.
void applySwap(PlanItem it, String to) {
  final newSlot = family(slotOf(to)) == family(it.slot) ? it.slot : slotOf(to);
  final mOld = measureOf(it.exercise), mNew = measureOf(to);
  it
    ..exercise = to
    ..slot = newSlot
    ..note = null;
  final ov = repRangeOverride[to];
  if (ov != null) {
    it
      ..lo = ov.$1
      ..hi = ov.$2;
  } else if (mOld != mNew) {
    final (lo, hi) = switch (mNew) {
      Measure.seconds => (20, 40),
      Measure.steps => (10, 20),
      Measure.trips => (1, 2),
      Measure.meters => (20, 40),
      Measure.reps => (8, 12),
    };
    it
      ..lo = lo
      ..hi = hi;
  }
}

/// Arvio sarjoista ja toistoalueesta tavoitteen mukaan.
List<String> assessItem(Program p, PlanItem it) {
  final msgs = <String>[];
  if (measureOf(it.exercise) != Measure.reps || it.kind == 'H' || it.kind == 'V') return msgs;
  final g = p.goal;
  final ov = repRangeOverride[it.exercise];
  if (ov != null && it.lo >= ov.$1 && it.hi <= ov.$2) {
    return [
      l10n.t('✓ Tyypillinen alue tälle liikkeelle ({0}–{1}).', [ov.$1, ov.$2]),
    ];
  }
  if (it.hi > 30) msgs.add(l10n.t('⚠ Yli 30 toistoa: kehittää lähinnä kestävyyttä, lihaskasvu ja voima heikkenevät.'));
  if (g == 'voimanosto' &&
      it.compound &&
      it.lo > 6 &&
      slots[it.slot]?.compound == true &&
      {'KK', 'KP', 'KM'}.contains(it.slot)) {
    msgs.add(l10n.t('⚠ Voimaa kehittää parhaiten raskas 1–6 toiston alue.'));
  }
  if (g != 'voimanosto' && it.hi <= 4) {
    msgs.add(l10n.t('Hyvin raskas alue: lihaskasvuun tarvitaan enemmän sarjoja kuin 6–15 toistolla.'));
  }
  if (!it.compound && it.lo < 6) {
    msgs.add(l10n.t('⚠ Eristävissä liikkeissä alle 6 toistoa rasittaa niveliä ilman lisähyötyä.'));
  }
  if (it.sets > 6) msgs.add(l10n.t('⚠ Yli 6 sarjaa yhdessä liikkeessä: hyöty tasaantuu, jaa sarjat eri päiville.'));
  if (msgs.isEmpty) {
    msgs.add(l10n.t('✓ Sopiva: {0}–{1} toistoa toimii, kun viet sarjat lähelle uupumusta.', [it.lo, it.hi]));
  }
  return msgs;
}

Program _clone(Program p) => Program(
  goal: p.goal,
  experience: p.experience,
  days: p.days,
  minutes: p.minutes,
  start: p.start,
  deloadEvery: p.deloadEvery,
  maxes: {...p.maxes},
  notes: [...p.notes],
  plan: [
    for (final d in p.plan)
      PlanDay(d.name, [
        for (final i in d.items)
          PlanItem(i.exercise, i.slot, i.sets, i.lo, i.hi, i.rir, i.restSec, kind: i.kind, note: i.note),
      ]),
  ],
);

Program cloneProgram(Program p) => _clone(p);

// --- Viikkokuorma -----------------------------------------------------------

const loadMuscles = ['rinta', 'selkä', 'olkapää', 'etureisi', 'takareisi', 'pakara', 'hauis', 'ojentaja'];

/// Suositeltu sarjamäärä viikossa lihasryhmää kohden tavoitteen ja kokemuksen mukaan.
(int, int) weeklyRange(Program p, String muscle) {
  final small = muscle == 'hauis' || muscle == 'ojentaja';
  final (lo, hi) = switch ((p.goal, p.experience)) {
    ('lihaskasvu', 'aloittelija') => (6, 12),
    ('lihaskasvu', 'kokenut') => (12, 22),
    ('lihaskasvu', _) => (10, 20),
    ('rasvanpoltto', _) => (6, 15),
    ('voimanosto', _) => (4, 20),
    _ => (4, 12),
  };
  // Hauis ja ojentaja saavat paljon epäsuoraa kuormaa monivelliikkeistä.
  return small ? ((lo * .6).round(), hi) : (lo, hi);
}

enum LoadLevel { low, ok, high }

class MuscleLoad {
  final String muscle;
  final double sets;
  final int lo, hi;
  MuscleLoad(this.muscle, this.sets, this.lo, this.hi);
  LoadLevel get level => sets < lo - .01
      ? LoadLevel.low
      : sets > hi + .01
      ? LoadLevel.high
      : LoadLevel.ok;
}

List<MuscleLoad> weeklyLoad(Program p) {
  final w = statsOf(p).weekly;
  return [
    for (final m in loadMuscles)
      () {
        final (lo, hi) = weeklyRange(p, m);
        return MuscleLoad(m, w[m] ?? 0, lo, hi);
      }(),
  ];
}

/// Tällä viikolla tehdyt sarjat lihasryhmää kohden (kirjatuista treeneistä, lämmittelyt pois: sarjat,
/// joiden paino on alle 60 % liikkeen päivän raskaimmasta).
Map<String, double> loggedWeekSets(List<Workout> history, DateTime today) =>
    loggedSets(history, weekStart(today), addDays(dateOnly(today), 1));

/// Tehdyt työsarjat lihasryhmää kohden väliltä [from, to).
Map<String, double> loggedSets(List<Workout> history, DateTime from, DateTime to) {
  final out = <String, double>{};
  for (final w in history) {
    if (w.date.isBefore(from) || !w.date.isBefore(to)) continue;
    for (final e in w.exercises) {
      final slot = slotOf(e.name);
      final top = e.sets.fold<double>(0, (a, s) => s.kg > a ? s.kg : a);
      final n = e.sets.where((s) => top == 0 || s.kg >= top * .6).length;
      for (final m in _musclesOf(slot).entries) {
        out[m.key] = (out[m.key] ?? 0) + n * m.value;
      }
    }
  }
  return out;
}

// --- Palautumista huomioiva päivän valinta --------------------------------------

/// Monivelliikkeiden suoraan kuormittamat lihasryhmät.
Set<String> _heavyMuscles(Iterable<String> slotsUsed) => {
  for (final s in slotsUsed)
    if (slots[s]?.compound ?? false)
      for (final m in _musclesOf(s).entries)
        if (m.value >= 1) m.key,
};

/// Seuraava ohjelmapäivä viikon kuorma ja palautuminen huomioiden:
///  1. kierron mukaan seuraava, jota ei ole vielä tehty tällä viikolla
///  2. jos eilen kuormitettiin samoja lihaksia raskaasti, valitaan päivä, joka antaa niille 48 h
/// Palauttaa päivän ja perustelun (null = tavallinen kierto).
(PlanDay, String?) suggestDay(Program p, List<Workout> history, DateTime today) {
  final t = dateOnly(today);
  // Tänään jo tehty salitreeni (sarjoja kirjattu) lasketaan tehdyksi: toinen treeni samalle päivälle
  // ehdottaa ohjelman seuraavaa päivää, ei samaa uudelleen.
  final doneToday = history
      .where((w) => w.date == t && w.activity == null && w.exercises.any((e) => e.sets.isNotEmpty))
      .map((w) => p.plan.indexWhere((d) => d.matches(w.dayKey)))
      .where((i) => i >= 0)
      .toList();
  final base = doneToday.isEmpty ? p.nextDay(history, t) : p.plan[(doneToday.last + 1) % p.plan.length];
  final start = p.plan.indexOf(base);
  final order = [for (var k = 0; k < p.plan.length; k++) p.plan[(start + k) % p.plan.length]];
  final doneThisWeek = {
    for (final w in history)
      if (!w.date.isBefore(weekStart(t)) && w.date.isBefore(t)) w.dayKey,
    for (final i in doneToday) p.plan[i].name,
  };
  bool done(PlanDay d) => doneThisWeek.any(d.matches);
  final open = order.where((d) => !done(d)).toList();
  final cands = open.isEmpty ? order : open;

  // Kuormitus: tänään jo tehty salitreeni (tuorein) tai muuten eilinen treeni.
  final todays = history
      .where((w) => w.date == t && w.activity == null && w.exercises.any((e) => e.sets.isNotEmpty))
      .toList();
  final yesterday = history.where((w) => w.date == addDays(t, -1)).firstOrNull;
  final recent = todays.isNotEmpty ? todays : [?yesterday];
  if (recent.isEmpty) {
    return (cands.first, cands.first == base ? null : l10n.t('{0} on jo tehty tällä viikolla.', [base.uiName]));
  }
  final isToday = todays.isNotEmpty;
  final tired = _heavyMuscles(recent.expand((w) => w.exercises).map((e) => slotOf(e.name)));
  Set<String> hits(PlanDay d) => _heavyMuscles(d.items.map((i) => i.slot)).intersection(tired);
  final first = cands.first;
  if (hits(first).isEmpty) {
    return (first, first == base ? null : l10n.t('{0} on jo tehty tällä viikolla.', [base.uiName]));
  }
  final fresh = cands.where((d) => hits(d).isEmpty).firstOrNull;
  if (fresh != null) {
    return (
      fresh,
      isToday
          ? l10n.t('Tänään kuormittui jo {0}: {1} antaa niille palautumisaikaa.', [
              hits(first).map(l10n.t).join(', '),
              l10n.trName(fresh.display),
            ])
          : l10n.t('Eilen kuormittui {0}: {1} antaa niille palautumisaikaa.', [
              hits(first).map(l10n.t).join(', '),
              l10n.trName(fresh.display),
            ]),
    );
  }
  return (
    first,
    isToday
        ? l10n.t('Tänään kuormittui jo {0}. Jos treenaat vielä, jätä enemmän varaa.', [
            hits(first).map(l10n.t).join(', '),
          ])
        : l10n.t('Eilen kuormittui {0}. Jos tuntuu raskaalta, jätä tänään enemmän varaa.', [
            hits(first).map(l10n.t).join(', '),
          ]),
  );
}
