import 'app_state.dart';
import 'exercises.dart';
import 'insights.dart';
import 'models.dart';
import 'program.dart';
import 'progression.dart';
import 'l10n.dart' as l10n;

// "Treeni valmis!" -vertailu: sama ohjelmapäivä (sama treenin nimi) aiemmilta viikoilta.
// Kevennysviikkoja ja sairaus- tai lomatauon jälkeisiä paluuviikkoja ei verrata: niissä kuorma on
// tarkoituksella pienempi.

class ExerciseCompare {
  final String name;
  final String now;
  final String? before;
  final int trend; // 1 parempi, 0 sama, -1 heikompi, 2 uusi liike
  ExerciseCompare(this.name, this.now, this.before, this.trend);
}

class SessionCompare {
  final String? skipReason; // miksi tätä kertaa ei verrata
  final Workout? previous;
  final List<ExerciseCompare> exercises;
  final double volume;
  final double? previousVolume;
  final List<(DateTime, double)> history; // vanhimmasta uusimpaan, mukana tämä kerta
  final int prs;
  SessionCompare({
    this.skipReason,
    this.previous,
    this.exercises = const [],
    this.volume = 0,
    this.previousVolume,
    this.history = const [],
    this.prs = 0,
  });
}

/// Syy, miksi päivän kuorma on tarkoituksella pienempi (null = normaali viikko).
String? reducedReason(DateTime date, Program? p) {
  final d = dateOnly(date);
  for (final pause in settings.pauses) {
    final end = pause.end ?? dateOnly(DateTime.now());
    if (!d.isBefore(pause.start) && !d.isAfter(end)) return pause.sick ? 'sairausjakso' : 'loma';
  }
  final ret = returnFor(d);
  if (ret != null) return ret.$1.sick ? l10n.t('paluu sairauden jälkeen') : l10n.t('paluu lomalta');
  if (p != null && !d.isBefore(p.start) && p.isDeloadWeek(d)) return 'kevennysviikko';
  return null;
}

/// Työsarjojen volyymi (kg × toistot). Aika- ja matkaliikkeet eivät mukana.
double workVolume(Workout w) {
  var v = 0.0;
  for (final e in w.exercises) {
    if (measureOf(e.name) != Measure.reps) continue;
    for (final s in e.workSets) {
      v += s.kg * s.reps * loadMultiplier(e.name); // tuplakahvakuula: molemmat kuulat
    }
  }
  return v;
}

/// Liikkeen paras sarja: toistoliikkeissä suurin arvioitu maksimi, muissa suurin arvo (aika, matka) tai paino.
(SetEntry, double)? _best(ExerciseEntry e) {
  final m = measureOf(e.name);
  (SetEntry, double)? best;
  for (final s in e.sets) {
    final score = m == Measure.reps ? (e1rm(s.kg, s.reps) ?? s.kg) : s.kg * 1000 + s.reps;
    if (best == null || score > best.$2) best = (s, score);
  }
  return best;
}

SessionCompare compareSession(Workout w, List<Workout> all, Program? p) {
  final reason = reducedReason(w.date, p);
  final prs = w.exercises.expand((e) => e.sets).where((s) => s.pr).length;
  if (reason != null) return SessionCompare(skipReason: reason, volume: workVolume(w), prs: prs);
  final same =
      all.where((x) => x.dayKey == w.dayKey && x.date.isBefore(w.date) && reducedReason(x.date, p) == null).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  final prev = same.isEmpty ? null : same.last;
  final ex = <ExerciseCompare>[];
  for (final e in w.exercises.where((e) => e.sets.isNotEmpty)) {
    final now = _best(e)!;
    final before = prev?.exercises.where((x) => x.name == e.name && x.sets.isNotEmpty).firstOrNull;
    if (before == null) {
      ex.add(ExerciseCompare(e.name, fmtSet(e.name, now.$1), null, 2));
      continue;
    }
    final b = _best(before)!;
    final diff = (now.$2 - b.$2) / (b.$2 == 0 ? 1 : b.$2);
    ex.add(
      ExerciseCompare(e.name, fmtSet(e.name, now.$1), fmtSet(e.name, b.$1), diff > .005 ? 1 : (diff < -.02 ? -1 : 0)),
    );
  }
  final hist = [
    for (final x in same.skip(same.length > 4 ? same.length - 4 : 0)) (x.date, workVolume(x)),
    (w.date, workVolume(w)),
  ];
  return SessionCompare(
    previous: prev,
    exercises: ex,
    volume: workVolume(w),
    previousVolume: prev == null ? null : workVolume(prev),
    history: hist,
    prs: prs,
  );
}

/// Ajastimen teksti: "12 min", "1 h 05 min".
String fmtDuration(int minutes) =>
    minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
