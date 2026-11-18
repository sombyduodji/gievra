import 'package:flutter/material.dart';

import '../app_state.dart';
import '../daily_steps.dart';
import '../exercises.dart';
import '../insights.dart';
import '../l10n.dart';
import '../models.dart';
import '../program_edit.dart' show loggedSets;
import '../running.dart';
import '../session_compare.dart' show fmtDuration;
import '../share_text.dart' show thousands;
import '../theme.dart';
import 'home.dart' show MonthCalendar, WorkoutRow, openWorkout;
import 'program_view.dart' show WeeklyLoadCard;
import 'running_screen.dart' show RunningScreen;
import 'steps_ui.dart' show stepsTabAvailable;
import 'widgets.dart';

/// Tilastot › Viikko: valitun viikon treenit, määrät ja ohjelman kuorma kaikkine lihasosineen (←/→ vaihtaa viikkoa).
class WeekStatsTab extends StatefulWidget {
  const WeekStatsTab({super.key});
  @override
  State<WeekStatsTab> createState() => _WeekStatsTabState();
}

class _WeekStatsTabState extends State<WeekStatsTab> {
  int _back = 0; // 0 = tämä viikko

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([settings, store, dailySteps]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final today = dateOnly(DateTime.now());
    final from = addDays(weekStart(today), -7 * _back);
    final to = addDays(from, 7);
    final ws = store.workouts.where((w) => !w.date.isBefore(from) && w.date.isBefore(to)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final gym = ws.where((w) => w.activity == null && w.exercises.any((e) => e.sets.isNotEmpty)).toList();
    final act = ws.where((w) => w.activity != null).toList();
    final sets = gym.fold<int>(0, (n, w) => n + w.exercises.fold(0, (m, e) => m + e.sets.length));
    final actMin = act.fold<int>(0, (n, w) => n + (w.seconds != null ? (w.seconds! / 60).round() : (w.minutes ?? 0)));
    final km = act.fold<double>(0, (n, w) => n + (w.distanceKm ?? 0));
    var steps = 0;
    for (var d = from; d.isBefore(to) && !d.isAfter(today); d = addDays(d, 1)) {
      steps += dailySteps.at(d) ?? 0;
    }
    final weekNo = MonthCalendar.weekNumber(from);

    Widget tile(String value, String label, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border(top: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, maxLines: 1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            FitLabel(label, style: sub),
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('weekPrev'),
              tooltip: t('Edellinen viikko'),
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _back++),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _back == 0 ? t('Tämä viikko') : t('Viikko {0}', [weekNo]),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text('${numDate(from)}–${numDate(addDays(to, -1))}', style: sub),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('weekNext'),
              tooltip: t('Seuraava viikko'),
              icon: const Icon(Icons.chevron_right),
              onPressed: _back == 0 ? null : () => setState(() => _back--),
            ),
          ],
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile('${gym.length}', gym.length == 1 ? t('salitreeni') : t('salitreeniä'), Sami.red),
              const SizedBox(width: 8),
              tile('$sets', sets == 1 ? t('sarja') : t('sarjaa'), Sami.red),
              const SizedBox(width: 8),
              tile(
                act.isEmpty ? '0' : (km > 0 ? '${fmtNum((km * 10).round() / 10)} km' : fmtDuration(actMin)),
                t('liikuntaa'),
                Sami.green,
              ),
              if (stepsTabAvailable) ...[const SizedBox(width: 8), tile(thousands(steps), t('askelta'), Sami.blue)],
            ],
          ),
        ),
        SectionLabel(t('Treenit')),
        if (ws.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t('Ei treenejä tällä viikolla.'), style: sub),
          )
        else
          for (final w in ws) WorkoutRow(w),
        if (settings.program != null && settings.trainMode != 'cardio') ...[
          const SizedBox(height: 14),
          WeeklyLoadCard(
            program: settings.program!,
            done: loggedSets(store.workouts, from, to),
            doneLabel: _back == 0 ? null : t('toteutunut tällä viikolla'),
          ),
        ],
      ],
    );
  }
}

/// Tilastot › Ennätykset: salin liikkeet arvioituna maksimina (paras sarja) ja juoksun nopeimmat vakiomatkat.
/// Uusi = alle 2 viikkoa vanha. Napautus näyttää liikkeen parhaan sarjan joka kerralta.
class RecordsTab extends StatelessWidget {
  const RecordsTab({super.key});

  static bool _isNew(DateTime d) => !d.isBefore(addDays(dateOnly(DateTime.now()), -14));

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Listenable.merge([settings, store]), builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final ws = store.workouts;
    final names = <String>{
      for (final w in ws)
        if (w.activity == null)
          for (final e in w.exercises)
            if (e.sets.any((s) => s.kg > 0 && !s.warmup)) e.name,
    };
    final lifts = [
      for (final n in names)
        if (bestLift(ws, n) case final r?) (n, r, bestLift(ws, n, until: addDays(r.date, -1)) != null),
    ]..sort((a, b) => b.$2.date.compareTo(a.$2.date));
    final bests = runBests(runsOf(ws));

    Widget badge() => Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: Sami.yellow, borderRadius: BorderRadius.circular(8)),
      child: Text(
        t('uusi'),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black),
      ),
    );

    Widget row({
      Key? key,
      required String title,
      required bool isNew,
      required String detail,
      required String value,
      VoidCallback? onTap,
    }) => InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isNew) badge(),
                    ],
                  ),
                  Text(detail, style: sub),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );

    if (lifts.isEmpty && bests.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(t('Ennätykset näkyvät täällä, kun olet kirjannut sarjoja painoilla tai juoksuja.'), style: sub),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
      children: [
        if (lifts.isNotEmpty) ...[
          SectionLabel(t('Sali · arvioitu maksimi (1 toisto)')),
          for (final (n, r, beat) in lifts)
            row(
              key: ValueKey('record_$n'),
              title: exerciseLabel(n),
              isNew: beat && _isNew(r.date),
              detail: measureOf(n) == Measure.reps
                  ? '${fmtNum(shownKg(n, r.kg))} × ${r.reps} · ${shortDateY(r.date)}'
                  // Kantaminen: paras paino matkoineen ("132 kg × 2 edestakaisin"), ei arvioitua maksimia.
                  : '${fmtSetHand(n, SetEntry(r.kg, r.reps))} · ${shortDateY(r.date)}',
              value: '${fmtNum(shownKg(n, r.e1rm).roundToDouble())} ${kgUnit(n, short: true)}',
              onTap: () => _showHistory(context, n),
            ),
          Text(t('Epleyn kaava parhaasta enintään 12 toiston sarjasta.'), style: sub),
        ],
        if (bests.isNotEmpty) ...[
          SectionLabel(t('Juoksu · nopein')),
          for (final b in bests)
            row(
              title: RunningScreen.distName(b.km),
              isNew:
                  _isNew(b.run.date) &&
                  runsOf(ws).any((x) => x.date.isBefore(b.run.date) && x.distanceKm! >= b.km - .05),
              detail: '${shortDateY(b.run.date)} · ${fmtPace(b.run.paceSecPerKm!)} /km',
              value: fmtDurationSec(b.sec),
              onTap: () => openWorkout(context, b.run),
            ),
          Text(t('Nopein keskivauhti vähintään yhtä pitkältä juoksulta, aika laskettuna matkalle.'), style: sub),
        ],
      ],
    );
  }

  /// Liikkeen paras sarja joka kerralta uusimmasta vanhimpaan; napautus avaa treenin.
  static void _showHistory(BuildContext context, String exercise) {
    final rows = <(Workout, SetEntry, double)>[];
    for (final w in store.workouts) {
      if (w.activity != null) continue;
      SetEntry? best;
      double bestV = 0;
      for (final e in w.exercises.where((e) => e.name == exercise)) {
        for (final s in e.sets.where((s) => !s.warmup)) {
          final v = recordValue(exercise, s);
          if (v != null && v > bestV) (best, bestV) = (s, v);
        }
      }
      if (best != null) rows.add((w, best, bestV));
    }
    rows.sort((a, b) => b.$1.date.compareTo(a.$1.date));
    final top = rows.fold<double>(0, (m, r) => r.$3 > m ? r.$3 : m);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final unit = kgUnit(exercise, short: true);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .6,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              Text(exerciseLabel(exercise), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              Text(t('Paras sarja joka kerralta'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              for (final (w, s, v) in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Text(v >= top ? '🏆' : '·', style: const TextStyle(fontSize: 18)),
                  title: Text(
                    measureOf(exercise) == Measure.reps
                        ? '${fmtNum(shownKg(exercise, s.kg))} $unit × ${s.reps}'
                        : fmtSetHand(exercise, s),
                  ),
                  subtitle: Text(shortDateY(w.date)),
                  // Arvioitu maksimi vain toistoliikkeissä (kantamisessa paino on jo ennätys).
                  trailing: measureOf(exercise) == Measure.reps
                      ? Text(
                          '≈ ${fmtNum(shownKg(exercise, v).roundToDouble())}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    openWorkout(context, w);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tilastot › Kalenteri: kuukausikalenteri (sama kuin etusivulla), ←/→ vaihtaa kuukautta, päivä avaa päivän.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});
  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ListenableBuilder(
            listenable: dailySteps,
            builder: (context, _) => MonthCalendar(
              month: _month,
              onShift: (n) => setState(() => _month = DateTime(_month.year, _month.month + n)),
            ),
          ),
        ),
      ),
    ],
  );
}
