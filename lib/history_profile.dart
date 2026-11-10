import 'dart:math' as math;

import 'exercises.dart';
import 'insights.dart';
import 'models.dart';
import 'program.dart';
import 'l10n.dart' as l10n;

// Treenihistoriasta päätellyt lähtöarvot aloituskyselyyn. Kaikki ovat ehdotuksia: käyttäjä voi muuttaa
// jokaisen, ja jokaiselle näytetään peruste ("historiastasi: ...").
//  - päivät viikossa: viimeisten 12 aktiivisen viikon keskiarvo
//  - kokemus: ensimmäisestä treenistä kulunut aika (alle 1 v / 1–3 v / yli 3 v)
//  - tyyli: kilpanostojen osuus ja niiden toistot (voimanosto) vai eristävien osuus (lihaskasvu)
//  - toistoalue: työsarjojen toistojen mediaani moninivelliikkeissä
//  - kesto: kirjattu kesto tai sarjamäärästä arvioitu
//  - välineet: liikkeiden välineet (yli 80 % yhtä ryhmää -> toive)
//  - suosikit: jokaiselle liikemallille eniten tehty liike viimeisen puolen vuoden ajalta

class HistoryProfile {
  final int workouts;
  final int days;
  final String experience;
  final String goal;
  final String repStyle;
  final int minutes;
  final Set<String> equipment;
  final Map<String, String> favorites; // liikemalli -> liike
  final Map<String, String> why; // kenttä -> peruste
  final int typicalSets;
  HistoryProfile({
    required this.workouts,
    required this.days,
    required this.experience,
    required this.goal,
    required this.repStyle,
    required this.minutes,
    required this.equipment,
    required this.favorites,
    required this.why,
    required this.typicalSets,
  });
}

const _competition = {
  'Takakyykky',
  'Penkkipunnerrus',
  'Maastaveto',
  'Sumomaastaveto',
  'Low bar -kyykky',
  'Taukopenkki',
};

int _median(List<int> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

/// Työsarjat: vähintään 75 % liikkeen päivän raskaimmasta (lämmittelyt pois).
Iterable<SetEntry> _workSets(ExerciseEntry e) {
  final top = e.sets.fold<double>(0, (a, s) => math.max(a, s.kg));
  return e.sets.where((s) => top == 0 || s.kg >= top * .75);
}

HistoryProfile? analyzeHistory(List<Workout> all, {DateTime? now}) {
  final ws = all.where((w) => w.exercises.any((e) => e.sets.isNotEmpty)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  if (ws.length < 4) return null;
  final why = <String, String>{};
  final last = ws.last.date;
  final today = dateOnly(now ?? DateTime.now());

  // Päivät viikossa: viimeiset 12 viikkoa, joina treenattiin (tauot eivät laske keskiarvoa).
  final perWeek = <DateTime, int>{};
  for (final w in ws) {
    final k = weekStart(w.date);
    perWeek[k] = (perWeek[k] ?? 0) + 1;
  }
  final weeks = perWeek.keys.toList()..sort();
  final recent = weeks.skip(math.max(0, weeks.length - 12)).map((k) => perWeek[k]!).toList();
  final avg = recent.fold(0, (a, b) => a + b) / recent.length;
  final days = avg.round().clamp(2, 6);
  why['days'] = l10n.t('keskimäärin {0} treeniä viikossa', [fmtDec(avg, 1)]);

  // Kokemus
  final months = (last.difference(ws.first.date).inDays / 30.4).floor();
  final experience = months < 12 ? 'aloittelija' : (months < 36 ? 'keski' : 'kokenut');
  why['experience'] = months < 1
      ? l10n.t('treenihistoriaa alle kuukausi')
      : months < 12
      ? l10n.t('treenihistoriaa {0} kk', [months])
      : l10n.t('treenihistoriaa {0} vuotta', [fmtDec(months / 12, 1)]);

  // Tyyli ja toistot (viimeinen puoli vuotta)
  final since = addDays(last, -183);
  final recentWs = ws.where((w) => !w.date.isBefore(since)).toList();
  var compSets = 0, isoSets = 0, total = 0;
  final compReps = <int>[], compoundReps = <int>[], setsPerExercise = <int>[];
  final count = <String, int>{};
  final equip = <String, int>{};
  for (final w in recentWs) {
    for (final e in w.exercises.where((e) => e.sets.isNotEmpty)) {
      count[e.name] = (count[e.name] ?? 0) + 1;
      final m = measureOf(e.name);
      final work = _workSets(e).toList();
      setsPerExercise.add(work.length);
      final slot = slotOf(e.name);
      final compound = slots[slot]?.compound ?? false;
      for (final s in work) {
        total++;
        if (_competition.contains(e.name)) {
          compSets++;
          compReps.add(s.reps);
        } else if (!compound) {
          isoSets++;
        }
        if (compound && m == Measure.reps) compoundReps.add(s.reps);
      }
      for (final g in equipmentChoices.entries) {
        if (exerciseEquipment[e.name]?.any(g.value.$3.contains) ?? false) {
          equip[g.key] = (equip[g.key] ?? 0) + e.sets.length;
        }
      }
    }
  }
  final compShare = total == 0 ? 0.0 : compSets / total;
  final isoShare = total == 0 ? 0.0 : isoSets / total;
  final compMedian = _median(compReps);
  String goal;
  if (compShare >= .35 && compMedian <= 6) {
    goal = 'voimanosto';
    why['goal'] = l10n.t('kyykky, penkki ja maastaveto {0} % sarjoista, tyypillisesti {1} toistoa', [
      (compShare * 100).round(),
      compMedian,
    ]);
  } else if (isoShare >= .3) {
    goal = 'lihaskasvu';
    why['goal'] = l10n.t('eristäviä liikkeitä {0} % sarjoista', [(isoShare * 100).round()]);
  } else {
    goal = 'lihaskasvu';
    why['goal'] = l10n.t('monipuolinen saliharjoittelu');
  }

  final repMedian = _median(compoundReps);
  final repStyle = repMedian == 0 ? 'suositus' : (repMedian <= 5 ? 'raskas' : (repMedian >= 12 ? 'kevyt' : 'suositus'));
  if (repMedian > 0) why['reps'] = l10n.t('moninivelliikkeissä tyypillisesti {0} toistoa', [repMedian]);
  final typicalSets = math.max(1, _median(setsPerExercise));
  why['sets'] = l10n.t('yleensä {0} työsarjaa liikettä kohden', [typicalSets]);

  // Kesto: kirjattu tai arvioitu sarjamäärästä (~2,5 min sarja + 8 min lämmittely).
  final durations = recentWs.map((w) => w.minutes).whereType<int>().toList();
  final setsPerSession = recentWs.map((w) => w.exercises.fold(0, (a, e) => a + e.sets.length)).toList();
  final est = durations.isNotEmpty ? _median(durations) : 8 + (_median(setsPerSession) * 2.5).round();
  final minutes = [45, 60, 75, 90].reduce((a, b) => (a - est).abs() <= (b - est).abs() ? a : b);
  why['minutes'] = durations.isNotEmpty
      ? l10n.t('treenit kestävät yleensä {0} min', [est])
      : l10n.t('noin {0} sarjaa treenissä (~{1} min)', [_median(setsPerSession), est]);

  // Välineet: jos yli 80 % sarjoista yhdellä välineryhmällä.
  final eqTotal = recentWs.fold(0, (a, w) => a + w.exercises.fold(0, (b, e) => b + e.sets.length));
  final equipment = <String>{};
  for (final e in equip.entries) {
    if (eqTotal > 0 && e.value / eqTotal >= .8) equipment.add(e.key);
  }
  if (equipment.isNotEmpty) {
    why['equipment'] = l10n.t('lähes kaikki liikkeet: {0}', [
      equipment.map((e) => l10n.t(equipmentChoices[e]!.$2).toLowerCase()).join(', '),
    ]);
  }

  // Suosikit liikemalleittain (vähintään 3 kertaa).
  final favorites = <String, String>{};
  final ranked = count.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in ranked) {
    if (e.value < 3) break;
    final slot = family(slotOf(e.key));
    if (slot.isEmpty) continue;
    favorites.putIfAbsent(slot, () => e.key);
  }
  if (favorites.isNotEmpty) why['favorites'] = favorites.values.take(6).map(exerciseLabel).join(', ');

  final idle = today.difference(last).inDays;
  if (idle > 28) why['idle'] = l10n.t('edellinen treeni {0} päivää sitten: aloita kevyemmin', [idle]);

  return HistoryProfile(
    workouts: ws.length,
    days: days,
    experience: experience,
    goal: goal,
    repStyle: repStyle,
    minutes: minutes,
    equipment: equipment,
    favorites: favorites,
    why: why,
    typicalSets: typicalSets,
  );
}
