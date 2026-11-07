import 'exercises.dart';
import 'models.dart';
import 'session_compare.dart';
import 'l10n.dart' as l10n;

/// Jaettava yhteenveto treenistä (WhatsApp, viestit, sähköposti …).
String shareText(Workout w) {
  final b = StringBuffer();
  final d = w.date;
  final when = l10n.isEnglish ? '${d.month}/${d.day}/${d.year}' : '${d.day}.${d.month}.${d.year}';
  final feel = feelingOf(w.feeling);
  if (w.activity != null) {
    b.writeln('🏃 ${l10n.sportName(w.activity!)} $when');
    final parts = [
      if (w.minutes != null) fmtDuration(w.minutes!),
      if (w.distanceKm != null) '${fmtNum(w.distanceKm!)} km',
      ?w.pace,
      if (w.steps != null) l10n.t('{0} askelta', [thousands(w.steps!)]),
      if (w.intensity != null) l10n.t(w.intensity!),
    ];
    if (parts.isNotEmpty) b.writeln(parts.join(' · '));
  } else {
    b.writeln('💪 ${l10n.trName(w.title)} $when');
    final sets = w.exercises.fold(0, (a, e) => a + e.workSets.length);
    final vol = workVolume(w);
    b.writeln(
      [
        if (w.minutes != null) fmtDuration(w.minutes!),
        l10n.t('{0} sarjaa', [sets]),
        if (vol > 0) '${thousands(vol.round())} kg',
      ].join(' · '),
    );
    for (final e in w.exercises.where((e) => e.sets.isNotEmpty)) {
      final best = e.sets.reduce((a, c) => c.kg * (1 + c.reps / 30) > a.kg * (1 + a.reps / 30) ? c : a);
      final pr = e.sets.any((s) => s.pr) ? ' 🏆' : '';
      b.writeln(
        l10n.t('• {0}: {1} sarjaa, paras {2}{3}', [exerciseLabel(e.name), e.workSets.length, fmtSet(e.name, best), pr]),
      );
    }
  }
  final hr = [
    if (w.hrAvg != null || w.hrMax != null) l10n.t('syke {0}/{1}', [w.hrAvg ?? '–', w.hrMax ?? '–']),
    if (w.kcal != null) '${w.kcal} kcal',
  ];
  if (hr.isNotEmpty) b.writeln('❤️ ${hr.join(' · ')}');
  if (feel != null) b.writeln(l10n.t('Fiilis: {0} {1}', [feel.$2, l10n.t(feel.$3)]));
  if (w.notes.trim().isNotEmpty) b.writeln(w.notes.trim());
  b.write(l10n.t('— Gievra'));
  return b.toString();
}

/// Kielitoimiston suositus: nelinumeroiset ilman väliä (3820), viisinumeroisista alkaen ryhmittely
/// sitovalla välilyönnillä (12 500, 1 234 567).
String thousands(int n) {
  final s = n.abs().toString();
  if (s.length <= 4) return n.toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(l10n.isEnglish ? ',' : '\u00a0');
    b.write(s[i]);
  }
  return b.toString();
}
