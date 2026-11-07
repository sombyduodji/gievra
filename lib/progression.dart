import 'app_state.dart';
import 'l10n.dart' as l10n;
import 'exercises.dart';
import 'models.dart';
import 'program.dart';

// Seuraavan kerran paino/toisto-ehdotus. Kaikki lasketaan laitteella omista .md-tiedoista.
//
// Perusajatus: tuplaprogressio + RIR-autoregulaatio (toistoja varastossa, Zourdos ym. 2016 RIR-RPE-asteikko).
//  - RIR 3+ edellisen kerran työsarjoissa: paino ylös yhdellä lisäyksellä.
//  - RIR 1–2: sama paino, yksi toisto lisää.
//  - RIR 0: sama paino ja toistot (toistetaan, kunnes tuntuu kevyemmältä).
//  - RIR merkitsemättä: toistetaan edellinen.
// Alavartalon liikkeissä lisäys on kaksinkertainen (tavallinen käytäntö: 5 kg alakroppa / 2,5 kg yläkroppa).
//
// Paluu tauolta: voima säilyy yleensä hyvin 2–4 viikon tauon yli (Mujika & Padilla 2000, Sports Med 30:79–87),
// mutta paluu tehdään silti kevyemmin, sairauden jälkeen varovaisemmin. Kerroin palautuu täyteen
// noin kahdessa viikossa. Nämä kertoimet ovat varovainen valmennuskäytäntö, eivät tutkimuksen tarkka tulos.

class Suggestion {
  final double kg;
  final int reps;
  final String reason;

  /// Sarjamäärän kerroin (paluu tauolta), 1 = tavallinen.
  final double setsFactor;
  Suggestion(this.kg, this.reps, this.reason, {this.setsFactor = 1});
}

/// Kuormakerroin tauon jälkeen: [days] tauon pituus, [sick] sairaus.
double returnLoadFactor(int days, {required bool sick}) {
  if (sick) {
    if (days <= 3) return .95;
    if (days <= 7) return .9;
    if (days <= 14) return .85;
    if (days <= 28) return .8;
    return .75;
  }
  if (days <= 7) return 1;
  if (days <= 14) return .95;
  if (days <= 28) return .9;
  return .8;
}

/// Viimeisin päättynyt tauko, jonka paluujakso (14 pv) kattaa päivän [date], ja sen kerroin tälle päivälle.
(Pause, double, double)? returnFor(DateTime date) {
  final day = dateOnly(date);
  for (final p in settings.pauses.reversed) {
    if (p.end == null || !day.isAfter(p.end!)) continue;
    final since = day.difference(p.end!).inDays; // 1 = ensimmäinen päivä tauon jälkeen
    if (since > 14) continue;
    final f = returnLoadFactor(p.days, sick: p.sick);
    if (f >= 1 && !p.sick) return null;
    // Lineaarinen palautuminen täyteen 14 päivässä.
    final t = (since - 1) / 13;
    final load = f + (1 - f) * t;
    final sets = p.sick ? (since <= 7 ? 2 / 3 : .85) : (since <= 7 ? .8 : 1.0);
    return (p, load, sets);
  }
  return null;
}

double _round(double kg, double step) => (kg / step).round() * step;

/// Toistoja varastossa luvuksi: ei yhtään 0, muutama 1,5, reilusti 3, merkitsemätön 2.
double _rirNum(int? r) => switch (r) {
  0 => 0,
  1 => 1.5,
  3 => 3,
  _ => 2,
};

/// Työmaksimi: kolmen parhaan e1RM:n mediaani viimeiseltä 28 päivältä (Epley + varaa),
/// muuten ohjelmaan syötetty maksimi.
double? workingE1rm(String exercise, DateTime date) {
  final from = addDays(date, -28);
  final vals = <double>[];
  for (final w in store.workouts) {
    if (w.date.isBefore(from) || !w.date.isBefore(dateOnly(date))) continue;
    for (final e in w.exercises.where((e) => e.name == exercise)) {
      for (final s in e.sets) {
        if (s.reps > 10 || s.kg <= 0) continue;
        vals.add(s.kg * (1 + (s.reps + _rirNum(s.rir)) / 30));
      }
    }
  }
  if (vals.isEmpty) return settings.program?.maxes[exercise];
  vals.sort((a, b) => b.compareTo(a));
  final top = vals.take(3).toList()..sort();
  return top[top.length ~/ 2];
}

/// Ohjelman tavoitteen mukainen ehdotus.
Suggestion? suggestForTarget(String exercise, DateTime date, Target t) =>
    _afterFeedback(exercise, date, _suggestForTarget(exercise, date, t));

Suggestion? _suggestForTarget(String exercise, DateTime date, Target t) {
  final mu = measureOf(exercise);
  if (mu != Measure.reps) return _suggestOther(exercise, date, mu);
  final step = settings.weightStep * (bodyGroupOf(exercise) == BodyGroup.legs ? 2 : 1);
  Suggestion? s;
  if (t.pct != null) {
    final e1 = workingE1rm(exercise, date);
    if (e1 != null) {
      s = Suggestion(
        _round(e1 * t.pct!, settings.weightStep),
        t.lo,
        l10n.t('{0} arvioidusta maksimista ({1} kg).', [t.label, fmtNum(e1.roundToDouble())]),
      );
    }
  } else {
    final last = store.lastBefore(exercise, date);
    if (last != null) {
      final e = last.$2;
      final top = e.sets.map((x) => x.kg).reduce((a, b) => a > b ? a : b);
      final work = e.sets.where((x) => x.kg >= top * .9).toList();
      final minReps = work.map((x) => x.reps).reduce((a, b) => a < b ? a : b);
      final noReserve = work.any((x) => x.rir == 0);
      if (minReps >= t.hi && !noReserve) {
        final up = kettlebellOnly(exercise) ? nextKettlebell(top) : top + step;
        s = Suggestion(
          up,
          t.lo,
          l10n.t('Kaikki sarjat ylärajalla ({0}): +{1} kg, toistot alas {2}:een.', [t.hi, fmtNum(up - top), t.lo]),
        );
      } else if (noReserve) {
        s = Suggestion(
          top,
          minReps.clamp(t.lo, t.hi),
          l10n.t('Edellisellä kerralla ei jäänyt varaa: sama paino, tavoite {0} toistoa.', [t.reps]),
        );
      } else {
        s = Suggestion(
          top,
          (minReps + 1).clamp(t.lo, t.hi),
          l10n.t('Sama paino, yksi toisto lisää (tavoite {0}).', [t.reps]),
        );
      }
    } else {
      final e1 = workingE1rm(exercise, date);
      if (e1 != null) {
        // %1RM = 1 / (1 + (toistot + varaa) / 30); kahvakuulassa lähin kevyempi kuulakoko.
        final raw = e1 / (1 + (t.lo + 2) / 30);
        final kg = kettlebellOnly(exercise)
            ? kettlebellSizes.lastWhere((k) => k <= raw, orElse: () => kettlebellSizes.first)
            : _round(raw, settings.weightStep);
        s = Suggestion(
          kg,
          t.lo,
          l10n.t('Arvioitu maksimi {0} kg → {1} toistoa, varaa noin 2.', [fmtNum(e1.roundToDouble()), t.lo]),
        );
      }
    }
  }
  if (s == null) return null;
  if (t.loadFactor < 1) {
    s = Suggestion(_round(s.kg * t.loadFactor, settings.weightStep), s.reps, '${t.label}.');
  }
  final ret = returnFor(date);
  if (ret != null) {
    final (p, load, sets) = ret;
    return Suggestion(
      _round(s.kg * load, settings.weightStep),
      s.reps,
      p.sick
          ? l10n.t('Paluu sairauden jälkeen ({0} pv): kuormat −{1} %, noin {2} % sarjoista.', [
              p.days,
              ((1 - load) * 100).round(),
              (sets * 100).round(),
            ])
          : l10n.t('Paluu lomalta ({0} pv): kuormat −{1} %, noin {2} % sarjoista.', [
              p.days,
              ((1 - load) * 100).round(),
              (sets * 100).round(),
            ]),
      setsFactor: sets,
    );
  }
  return s;
}

/// Aika-, askel- ja matkaliikkeet: reilusti varaa -> enemmän (tai lisäpaino), muuten sama.
Suggestion? _suggestOther(String exercise, DateTime date, Measure m) {
  final last = store.lastBefore(exercise, date);
  if (last == null) return null;
  final s = last.$2.sets.last;
  final rir = last.$2.sets.map((x) => x.rir).whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a);
  final sec = m == Measure.seconds;
  if (rir != null && rir >= 3) {
    if (s.kg > 0 || m == Measure.trips) {
      return Suggestion(
        s.kg + settings.weightStep,
        s.reps,
        (sec
            ? l10n.t('Olisit jaksanut reilusti pidempään: +{0} kg.', [fmtNum(settings.weightStep)])
            : l10n.t('Olisit jaksanut reilusti pidemmälle: +{0} kg.', [fmtNum(settings.weightStep)])),
      );
    }
    return Suggestion(
      0,
      s.reps + 2 * m.step,
      (sec
          ? l10n.t('Olisit jaksanut reilusti pidempään: +{0} {1}.', [2 * m.step, l10n.t(m.unit)])
          : l10n.t('Olisit jaksanut reilusti pidemmälle: +{0} {1}.', [2 * m.step, l10n.t(m.unit)])),
    );
  }
  if (rir != null && rir >= 1 && m != Measure.trips) {
    return Suggestion(
      s.kg,
      s.reps + m.step,
      (sec
          ? l10n.t('Olisit jaksanut vähän pidempään: +{0} {1}.', [m.step, l10n.t(m.unit)])
          : l10n.t('Olisit jaksanut vähän pidemmälle: +{0} {1}.', [m.step, l10n.t(m.unit)])),
    );
  }
  if (rir == 0) return Suggestion(s.kg, s.reps, l10n.t('Edellisellä kerralla meni loppuun asti: toista sama.'));
  return Suggestion(s.kg, s.reps, l10n.t('Toista edellinen.'));
}

Suggestion? suggestNext(String exercise, DateTime date) => _afterFeedback(exercise, date, _suggestNext(exercise, date));

Suggestion? _suggestNext(String exercise, DateTime date) {
  final m = measureOf(exercise);
  if (m != Measure.reps) return _suggestOther(exercise, date, m);
  final last = store.lastBefore(exercise, date);
  if (last == null) return null;
  final (lastDate, e) = last;
  final top = e.sets.map((s) => s.kg).reduce((a, b) => a > b ? a : b);
  // Työsarjat = vähintään 90 % päivän raskaimmasta (karsii lämmittelysarjat).
  final work = e.sets.where((s) => s.kg >= top * .9).toList();
  final reps = work.first.reps;
  final rirs = work.map((s) => s.rir).whereType<int>().toList();
  final step = settings.weightStep * (bodyGroupOf(exercise) == BodyGroup.legs ? 2 : 1);

  double kg = top;
  var r = reps;
  String why;
  if (rirs.isEmpty) {
    why = l10n.t('Toista edellinen ({0} kg × {1}). Vastaa sarjan jälkeen "jäikö varaa", niin ehdotus tarkentuu.', [
      fmtNum(top),
      reps,
    ]);
  } else {
    final minRir = rirs.reduce((a, b) => a < b ? a : b);
    if (minRir >= 3) {
      kg = top + step;
      why = l10n.t('Edellisellä kerralla jäi reilusti varaa: +{0} kg.', [fmtNum(step)]);
    } else if (minRir >= 1) {
      r = reps + 1;
      why = l10n.t('Edellisellä kerralla jäi muutama: sama paino, yksi toisto lisää.');
    } else {
      why = l10n.t('Edellisellä kerralla ei jäänyt varaa: toista sama.');
    }
  }

  final ret = returnFor(date);
  if (ret != null) {
    final (p, load, sets) = ret;
    kg = _round(top * load, settings.weightStep);
    r = reps;
    final pct = ((1 - load) * 100).round();
    why = [
      l10n.t('{0} ({1} pv): {2}', [
        p.sick ? l10n.t('Paluu sairauden jälkeen') : l10n.t('Paluu lomalta'),
        p.days,
        pct > 0 ? l10n.t('kuormat −{0} %', [pct]) : l10n.t('normaalit kuormat'),
      ]),
      if (sets < 1) l10n.t(', noin {0} % tavallisista sarjoista', [(sets * 100).round()]),
      '.',
      if (p.sick) ' ${l10n.t('Jos oireita vielä on, kevennä lisää.')}',
    ].join();
    return Suggestion(kg, r, why, setsFactor: sets);
  }
  if (lastDate.isBefore(addDays(date, -21)) && rirs.isNotEmpty) {
    // Pitkä väli ilman merkittyä taukoa: ei nosteta.
    kg = top;
    r = reps;
    why = l10n.t('Edellisestä kerrasta yli 3 viikkoa: aloita samalla painolla.');
  }
  return Suggestion(kg, r, why);
}

/// Lämmittelysarjat työpainoon (esitäytetyt, käyttäjä voi muuttaa). Yleinen käytäntö: kevyestä kohti
/// työpainoa, toistot vähenevät painon noustessa, ettei lämmittely väsytä.
/// Tanko: tyhjä tanko 20 kg × 10, ~50 % × 5, ~70 % × 3, ~85 % × 1 (raskaimmat). Muut moninivelliikkeet:
/// yksi sarja ~50 % × 8. Eristävät ja kehonpainoliikkeet: ei lämmittelysarjoja.
List<SetEntry> warmupSets(String exercise, double work) {
  if (measureOf(exercise) != Measure.reps || work < 30) return const [];
  final eq = exerciseEquipment[exercise] ?? const {};
  final slot = slotOf(exercise);
  final compound = slot.isNotEmpty && (slots[slot]?.compound ?? false);
  if (!compound) return const [];
  final out = <SetEntry>[];
  if (eq.contains(Equip.tanko) && !eq.contains(Equip.kasipaino)) {
    double r(double kg) => ((kg / 2.5).round() * 2.5).clamp(20, work).toDouble();
    if (work >= 40) out.add(SetEntry(20, 10, warmup: true));
    for (final (pct, reps) in [(.5, 5), (.7, 3), (.85, 1)]) {
      final kg = r(work * pct);
      if (pct == .85 && work < 80) continue;
      if (kg <= (out.isEmpty ? 0 : out.last.kg) + 2.5 || kg > work - 5) continue;
      out.add(SetEntry(kg, reps, warmup: true));
    }
  } else {
    final kg = kettlebellOnly(exercise)
        ? kettlebellSizes.lastWhere((s) => s <= work * .55, orElse: () => kettlebellSizes.first)
        : ((work * .5) / settings.weightStep).round() * settings.weightStep;
    if (kg > 0 && kg < work - 2) out.add(SetEntry(kg.toDouble(), 8, warmup: true));
  }
  return out;
}

/// Edellisen kerran palaute (raskaan treenin jälkeen kysytty): liian raskas -> kevyempi, rankka päivä -> ei nostoa.
Suggestion? _afterFeedback(String exercise, DateTime date, Suggestion? s) {
  if (s == null || measureOf(exercise) != Measure.reps) return s;
  final w = store.workouts
      .where((w) => w.date.isBefore(date) && w.exercises.any((e) => e.name == exercise && e.workSets.isNotEmpty))
      .firstOrNull;
  if (w == null) return s;
  final top = w.exercises
      .firstWhere((e) => e.name == exercise)
      .workSets
      .map((x) => x.kg)
      .fold<double>(0, (a, b) => b > a ? b : a);
  if (top <= 0) return s;
  if (w.tooHeavy.contains(exercise)) {
    final lighter = kettlebellOnly(exercise)
        ? kettlebellSizes.lastWhere((k) => k < top, orElse: () => top)
        : _round(top * .92, settings.weightStep);
    if (lighter < s.kg) {
      return Suggestion(
        lighter,
        s.reps,
        l10n.t('Viime kerralla paino tuntui liian raskaalta: kevyempi ({0} kg), rakenna siitä uudelleen.', [
          fmtNum(lighter),
        ]),
        setsFactor: s.setsFactor,
      );
    }
  }
  if (w.dayReasons.isNotEmpty && (w.feeling ?? 3) <= 2 && s.kg > top) {
    return Suggestion(
      top,
      s.reps,
      l10n.t('Viime kerta oli raskas ({0}): sama paino kuin viimeksi.', [w.dayReasons.map(l10n.t).join(', ')]),
      setsFactor: s.setsFactor,
    );
  }
  return s;
}
