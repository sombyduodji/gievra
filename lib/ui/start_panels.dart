import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../daily_steps.dart';
import '../health.dart';
import '../home_layout.dart';
import '../effort.dart' show estimateEffort;
import '../heart_rate.dart' show activeKcal, hr, hrProfile;
import '../injuries.dart' show injuryAdjusted;
import '../insights.dart' show weekStart;
import '../l10n.dart';
import '../models.dart';
import '../ongoing.dart';
import '../program.dart';
import '../program_edit.dart' show suggestDay;
import '../running.dart' show paceProgress, hrPaceProgress;
import '../sports.dart';
import '../theme.dart';
import '../weekly_activity.dart';
import 'activity.dart';
import 'health_import.dart';
import 'home.dart' show explainActivityMinutes, openPendingActivity;
import 'new_workout.dart';
import 'sport_picker.dart' show tileLabel;
import 'steps_ui.dart' show stepsTabAvailable;
import 'widgets.dart';
import 'workout.dart';

// Etusivun aloitus (käyttäjä 17.11., luonnokset ui-test): jaettu painike Sali | Liikunta, joka avaa paneelin
// etusivun päälle. Salipaneelissa ohjelman päivät (ehdotus ylimpänä), liikuntapaneelissa viimeksi käytetyt lajit
// ja sitten kirjaustapa (GPS, ajanotto, jo tehty). Kummassakin ylimpänä tämän päivän Health Connect -harjoitukset,
// joita ei vielä ole Gievrassa. Paneeli sulkeutuu pyyhkäisyllä alas, Takaisin-painikkeella tai napautuksella sen
// yläpuolelle.

const _gymRed = Sami.red;
const _actGreen = Color(0xFF00843D);

String _hm(DateTime d) => fmtClock(TimeOfDay.fromDateTime(d));

/// Uusi liikunta lajilla [sport] (null = lajivalinta näkymässä) ja kirjaustavalla [mode] ('gps', 'watch', 'manual').
/// Taustalla jo käynnissä oleva liikunta avataan sen sijaan (kaksi ajanottoa sekoittaisi luonnoksen ja sykkeet).
void startActivity(BuildContext context, String? sport, {String? mode}) {
  if (AwayActivity.away) {
    openPendingActivity(context);
    return;
  }
  final today = dateOnly(DateTime.now());
  final w = Workout(
    date: today,
    title: sport ?? 'Liikunta',
    activity: sport,
    session: store.onDay(today).isEmpty ? 1 : store.nextSession(today),
  );
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ActivityScreen(workout: w, startMode: mode),
    ),
  );
}

/// Viimeksi käytetyt lajit uusimmasta alkaen (laji kerran), enintään [n].
List<(String, DateTime)> recentSports(List<Workout> ws, int n) {
  final out = <(String, DateTime)>[];
  final seen = <String>{};
  final acts = ws.where((w) => w.activity != null).toList()..sort((a, b) => b.date.compareTo(a.date));
  for (final w in acts) {
    final s = w.activity!;
    if (sportOf(s)?.retired ?? false) continue;
    if (seen.add(s)) out.add((s, w.date));
    if (out.length >= n) break;
  }
  return out;
}

/// Lajin viimeksi käytetty kirjaustapa: GPS (reitti), jo tehty (aika käsin) tai ajanotto.
String? lastMode(List<Workout> ws, String sport) {
  final last = ws
      .where((w) => w.activity == sport)
      .fold<Workout?>(null, (a, w) => a == null || w.date.isAfter(a.date) ? w : a);
  if (last == null) return null;
  if (last.routeGpx != null || last.route != null) return 'gps';
  return last.manualTime ? 'manual' : 'watch';
}

String _when(DateTime d) {
  final today = dateOnly(DateTime.now());
  if (d == today) return t('tänään');
  if (d == addDays(today, -1)) return t('eilen');
  return shortDate(d);
}

/// Jaettu aloituspainike: punainen Sali vasemmalla, vihreä Liikunta oikealla (vain toinen, jos treenitapa on
/// pelkkä sali tai pelkkä kestävyys). Alla pieni vihje: päivän ehdotus ja viimeksi käytetty laji.
class StartSplitButton extends StatelessWidget {
  const StartSplitButton({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = settings.trainMode;
    final gym = mode != 'cardio', act = mode != 'gym';
    // Vihjeteksti (seuraava päivä / viimeksi tehty laji) pois (käyttäjä 18.11.): paneeli näyttää ne jo valmiiksi
    // valittuina, ja saameksi isolla fontilla vihje katkesi kesken sanan.
    final last = recentSports(store.workouts, 1).firstOrNull;
    Widget half(String key, Color color, String icon, String title, VoidCallback onTap, BorderRadius r) => Expanded(
      child: Semantics(
        button: true,
        label: title,
        // excludeSemantics pudottaa lapsen napautustoiminnon: ilman omaa onTapia TalkBack ei voinut painaa.
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          key: ValueKey(key),
          color: color,
          borderRadius: r,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    const r = Radius.circular(18);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (gym)
              half(
                'homeStartGym',
                _gymRed,
                '🏋️',
                t('Sali'),
                () => showGymPanel(context),
                act ? const BorderRadius.horizontal(left: r) : const BorderRadius.all(r),
              ),
            if (gym && act) const SizedBox(width: 3),
            if (act)
              half(
                'homeStartActivity',
                _actGreen,
                sportOf(last?.$1)?.icon ?? '🚶',
                t('Liikunta'),
                () => showActivityPanel(context),
                gym ? const BorderRadius.horizontal(right: r) : const BorderRadius.all(r),
              ),
          ],
        ),
      ),
    );
  }
}

/// Etusivun jaksokortti (käyttäjä 17.11.): Viikko | Kuukausi -valitsin, ‹ jakso ›, renkaat jaksolta ja kalenteri.
/// Renkaat: salipäivät (ohjelman päivät viikossa, ilman ohjelmaa WHO:n 2; kuukaudessa viikkotavoite × viikot),
/// reipas liikunta (WHO 150 min viikossa) ja askeleet (viikossa tältä päivältä, muuten keskiarvo päivää kohden).
class PeriodCard extends StatelessWidget {
  final bool monthView;
  final DateTime month; // kuukauden ensimmäinen päivä
  final DateTime weekOf; // viikon jokin päivä
  final ValueChanged<bool> onMode;
  final ValueChanged<int> onShift;

  /// Kalenteri (MonthCalendar etusivun tyylillä); annetaan etusivulta, jossa päivän näkymä on.
  final Widget calendar;
  const PeriodCard({
    super.key,
    required this.monthView,
    required this.month,
    required this.weekOf,
    required this.onMode,
    required this.onShift,
    required this.calendar,
  });

  static int weekNumber(DateTime d) => isoWeek(d);

  /// Jakso [from, next) ja sen päivien määrä (kalenteripäivinä, kesäaika huomioiden).
  static (DateTime, DateTime, int) range(bool monthView, DateTime month, DateTime weekOf) {
    final from = monthView ? DateTime(month.year, month.month, 1) : weekStart(weekOf);
    final next = monthView ? DateTime(month.year, month.month + 1, 1) : addDays(from, 7);
    final days = next.difference(from).inHours ~/ 24 + (next.difference(from).inHours % 24 > 12 ? 1 : 0);
    return (from, next, days);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = dateOnly(DateTime.now());
    final (from, next, days) = range(monthView, month, weekOf);
    final a = periodActivity(store.workouts, from, next);
    // Lihaskuntopäivät (käyttäjä 17.11.: lihaskunto ja sali yhtenä renkaana): tavoitteena ohjelman päivät viikossa,
    // vähintään WHO:n 2; ilman ohjelmaa 2.
    final plan = settings.program?.plan.length ?? 0;
    final perWeek = plan > whoStrengthDays ? plan : whoStrengthDays;
    final gymTarget = monthView ? (perWeek * days / 7).round() : perWeek;
    final actTarget = monthView ? (whoMinutes * days / 7).round() : whoMinutes;
    final current = !today.isBefore(from) && today.isBefore(next);
    // Askeleet: viikossa tämän päivän (kuluva viikko), muuten keskiarvo päivistä, joilta on askeleita.
    int? steps;
    var stepsAvg = false;
    if (stepsTabAvailable) {
      if (!monthView && current) {
        steps = dailySteps.at(today);
      } else {
        // Kuluvan päivän keskeneräinen luku laskisi keskiarvoa (koodikatselmus 17.11.): mukaan vain, jos muita ei ole.
        var vals = [
          for (var d = from; d.isBefore(next) && d.isBefore(today); d = addDays(d, 1))
            if ((dailySteps.at(d) ?? 0) > 0) dailySteps.at(d)!,
        ];
        if (vals.isEmpty && current && (dailySteps.at(today) ?? 0) > 0) vals = [dailySteps.at(today)!];
        if (vals.isNotEmpty) steps = (vals.reduce((x, y) => x + y) / vals.length).round();
        stepsAvg = true;
      }
      // Askeleet juuri kytketty, eikä tietoa vielä ole (testi 18.11.: uusi käyttäjä ei nähnyt mitään ja luuli,
      // ettei kytkentä toiminut): kuluvalla jaksolla rengas nollasta.
      if (steps == null && current) steps = 0;
    }
    final mode = settings.trainMode;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rings = <(double, Color, String, String)>[
      if (mode != 'cardio')
        (a.strengthDays / gymTarget, redText(context), '${a.strengthDays}/$gymTarget', t('lihaskuntopäivää')),
      if (mode != 'gym')
        (
          a.moderateEq / actTarget,
          dark ? Sami.greenLight : Sami.green,
          '${a.moderateEq}',
          t('/{0} reipasta', [actTarget]),
        ),
      if (steps != null)
        (
          steps / settings.stepsGoal,
          blueText(context),
          steps >= 10000 ? '${(steps / 1000).toStringAsFixed(1).replaceAll('.', decimalSep)}k' : thousandsSep(steps),
          stepsAvg ? t('askelta / pv') : t('askelta tänään'),
        ),
    ];
    // Pelkkä treenipäiväkirja (käyttäjä 19.11.): salin viikon sarjat ja treeniaika ohjelman tavoitetta (ilman ohjelmaa
    // 4 edellisen viikon keskiarvoa) vasten askelten ja WHO-lukujen tilalle.
    final goals1 = settings.goals.length == 1;
    if (!settings.wellness && mode != 'cardio') {
      bool gymIn(Workout w, DateTime f, DateTime n) => w.activity == null && !w.date.isBefore(f) && w.date.isBefore(n);
      int setsIn(DateTime f, DateTime n) => store.workouts
          .where((w) => gymIn(w, f, n))
          .fold(0, (x, w) => x + w.exercises.fold(0, (y, e) => y + e.workSets.length));
      // Sekunnit yhteen ja minuuteiksi vasta lopuksi (yötesti 20.11.: jokainen treeni katkaistiin erikseen, joten
      // alle minuutin treeni jäi 0 minuutiksi ja summa jäi vajaaksi).
      int minIn(DateTime f, DateTime n) =>
          (store.workouts
                      .where((w) => !w.date.isBefore(f) && w.date.isBefore(n) && (mode == 'both' || w.activity == null))
                      .fold(0, (x, w) => x + (w.durationSec ?? 0)) /
                  60)
              .round();
      final p = settings.program;
      double perWeek(int Function(DateTime, DateTime) f) {
        var sum = 0;
        for (var i = 1; i <= 4; i++) {
          sum += f(addDays(weekStart(today), -7 * i), addDays(weekStart(today), -7 * i + 7));
        }
        return sum / 4;
      }

      final setsWeek = p != null && p.plan.isNotEmpty
          ? p.plan
                .expand((d) => d.items)
                .fold(0, (x, i) => x + (i.kind == 'H' || i.kind == 'V' ? 5 : i.sets))
                .toDouble()
          : perWeek(setsIn);
      final minWeek = p != null && p.plan.isNotEmpty
          ? (p.minutes * settings.weeklyTrainingTarget).toDouble()
          : perWeek(minIn);
      final scale = monthView ? days / 7 : 1.0;
      final sets = setsIn(from, next), mins = minIn(from, next);
      final st = (setsWeek * scale).round(), mt = (minWeek * scale).round();
      // Rivissä enintään 4 rengasta; yksi oma tavoite mahtuu silti (sarjat ennen treeniaikaa).
      final room = (goals1 ? 3 : 4) - rings.length;
      rings.addAll(
        [
          (st > 0 ? sets / st : 0.0, yellowText(context), st > 0 ? '$sets/$st' : '$sets', t('sarjaa')),
          (
            mt > 0 ? mins / mt : 0.0,
            blueText(context),
            '${mins ~/ 60}:${(mins % 60).toString().padLeft(2, '0')}',
            t('treeniaikaa, h'),
          ),
        ].take(room < 0 ? 0 : room),
      );
    }
    // Yksi oma tavoite mahtuu WHO-renkaiden riviin; useampi omana korttinaan (GoalsCard).
    final goals = settings.goals;
    if (goals.length == 1 && rings.length < 4) rings.add(goalRing(context, goals.single, from, next, days));
    final total = a.light + a.moderate + a.vigorous;
    final label = monthView
        ? '${uiMonth(month.month)} ${month.year}'
        : t('Viikko {0} · {1}', [weekNumber(from), '${numDate(from)}–${numDate(addDays(from, 6))}']);
    final canNext = !current && next.isBefore(addDays(today, 1));
    // TalkBack (20.11.): valittu jakso kerrotaan ("valittu, Viikko").
    Widget seg(String text, bool on, VoidCallback tap, Key key) => Expanded(
      child: Semantics(
        selected: on,
        button: true,
        child: Material(
          key: key,
          color: on ? cs.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Center(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(21)),
              child: Row(
                children: [
                  seg(t('Viikko'), !monthView, () => onMode(false), const ValueKey('periodWeek')),
                  seg(t('Kuukausi'), monthView, () => onMode(true), const ValueKey('periodMonth')),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('periodPrev'),
              tooltip: t('Edellinen'),
              onPressed: () => onShift(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: const ValueKey('periodNext'),
              tooltip: t('Seuraava'),
              onPressed: canNext ? () => onShift(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, (v, c, big, small)) in rings.indexed)
                Expanded(
                  child: RingTile(
                    v: v,
                    color: c,
                    big: big,
                    small: small,
                    // Liikuntarengas: selitys (WHO, rasitus) ja jakson minuutit.
                    onTap: mode != 'gym' && i == (mode == 'cardio' ? 0 : 1)
                        ? () => explainActivityMinutes(context, a)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (mode != 'gym' && total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              t('kaikkiaan {0} min liikuntaa', [total]),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 8),
        calendar,
      ],
    );
  }
}

/// Rengas ja sen alle selite (etusivun jaksokortti ja omat tavoitteet).
class RingTile extends StatelessWidget {
  final double v;
  final Color color;
  final String big, small;
  final VoidCallback? onTap;
  const RingTile({super.key, required this.v, required this.color, required this.big, required this.small, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        children: [
          SizedBox(
            width: 66,
            height: 66,
            child: CustomPaint(
              painter: _Ring(v, color, color.withValues(alpha: .18)),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: FittedBox(
                    child: Text(big, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Yksi rivi, tarvittaessa pienempänä: neljän renkaan rivissä "lihaskuntopäivää" katkesi keskeltä sanaa.
          // Väli reunoihin (yötesti 20.11.: pienennetty selite osui naapurin selitteeseen, "lihaskuntopäivää/150").
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                small,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Oman tavoitteen otsikko (asetukset ja renkaan selite).
String goalLabel(Goal g) {
  final s = g.sport == null ? null : sportName(g.sport!).toLowerCase();
  return switch (g.kind) {
    'gym' => t('salipäivää'),
    'pace' => t('juoksuvauhti vs. 4 vk'),
    'hrpace' => t('vauhti samalla sykkeellä'),
    'km' => s == null ? t('km liikuntaa') : t('km · {0}', [s]),
    'min' => s == null ? t('min liikuntaa') : t('min · {0}', [s]),
    _ => s == null ? t('kertaa liikuntaa') : t('kertaa · {0}', [s]),
  };
}

String goalNum(Goal g, double v) => g.kind == 'km' && v < 10 && v != v.roundToDouble() ? fmtDec(v, 1) : '${v.round()}';

/// Oman tavoitteen rengas jaksolle [from, next).
(double, Color, String, String) goalRing(BuildContext context, Goal g, DateTime from, DateTime next, int days) {
  // Kehitystavoite: täysi vihreä rengas, kun jakson juoksut ovat edes vähän parempia kuin 4 edellistä viikkoa.
  if (g.progress) {
    final cs = Theme.of(context).colorScheme;
    final pace = g.kind == 'pace';
    final d = pace
        ? paceProgress(store.workouts, from, next, settings.runBands)
        : hrPaceProgress(store.workouts, from, next);
    if (d == null) return (0, cs.onSurfaceVariant, '–', goalLabel(g));
    final better = pace ? d.round() < 0 : d >= 0.05;
    final sign = (pace ? d.round() : d) > 0
        ? '+'
        : (pace ? d.round() < 0 : d < 0)
        ? '−'
        : '±';
    final big = pace ? '$sign${d.round().abs()} s' : '$sign${fmtDec(d.abs(), 1)} %';
    return (better ? 1 : 0.15, better ? greenText(context) : cs.onSurfaceVariant, big, goalLabel(g));
  }
  final v = g.value(store.workouts, from, next);
  final target = g.target(days);
  // Rengas samaa pyöristettyä tavoitetta vasten kuin teksti (kuukausi 3 × 31 / 7 = 13,3: "13/13" ja täysi rengas).
  final shown = g.kind == 'km' && target < 10 ? (target * 10).round() / 10 : target.roundToDouble();
  return (
    v / (shown > 0 ? shown : target),
    yellowText(context),
    '${goalNum(g, v)}/${goalNum(g, target)}',
    goalLabel(g),
  );
}

/// Omat tavoitteet omana korttinaan, kun niitä on kaksi tai kolme (yksi näkyy WHO-renkaiden rivissä). Jakso seuraa
/// jaksokortin Viikko | Kuukausi -valintaa.
class GoalsCard extends StatelessWidget {
  final bool monthView;
  final DateTime month, weekOf;
  const GoalsCard({super.key, required this.monthView, required this.month, required this.weekOf});

  @override
  Widget build(BuildContext context) {
    final goals = settings.goals;
    if (goals.length < 2) return const SizedBox.shrink();
    final (from, next, days) = PeriodCard.range(monthView, month, weekOf);
    return Card(
      key: const ValueKey('goalsCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('Omat tavoitteet'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final g in goals)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final (v, c, big, small) = goalRing(context, g, from, next, days);
                          return RingTile(v: v, color: c, big: big, small: small);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String get decimalSep => isEnglish ? '.' : ',';
String thousandsSep(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(isEnglish ? ',' : ' ');
    b.write(s[i]);
  }
  return b.toString();
}

class _Ring extends CustomPainter {
  final double v;
  final Color fg, bg;
  _Ring(this.v, this.fg, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    const w = 8.0;
    final rect = (Offset.zero & size).deflate(w / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    canvas.drawArc(rect, 0, 2 * math.pi, false, p..color = bg);
    final s = v.clamp(0.0, 1.0);
    if (s > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * s,
        false,
        p
          ..color = fg
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_Ring o) => o.v != v || o.fg != fg;
}

// ---------------------------------------------------------------------------------------------------------------
// Paneelit

Future<R?> _panel<R>(BuildContext context, Widget Function(BuildContext ctx, StateSetter set) body) =>
    showModalBottomSheet<R>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      // Health Connectin tarkistus voi valmistua paneelin ollessa auki: uudet harjoitukset näkyvät heti.
      builder: (ctx) => ValueListenableBuilder(
        valueListenable: HealthImportButton.todayFresh,
        builder: (ctx, _, _) => StatefulBuilder(
          builder: (ctx, set) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .8),
            child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), child: body(ctx, set)),
          ),
        ),
      ),
    );

/// Paneelin toissijainen toiminto: ontto painike paneelin värillä koko leveydeltä.
class _OutlineAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _OutlineAction({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label, textAlign: TextAlign.center),
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color, width: 1.5),
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );
}

/// Liikuntapaneelin laji laattana: iso kuvake ja nimi (kuten salipaneelin rivit).
class _SportTile extends StatelessWidget {
  final String icon, name;
  final VoidCallback onTap;
  const _SportTile({super.key, required this.icon, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              // Yksi pitkä sana (Sauvakävely suurella tekstillä, saamen yhdyssanat) ei katkea kesken sanan: nimi
              // pienenee mahtuakseen, ja pitkät saamen nimet jaetaan yhdysosien rajalta kuten Kaikki lajit -ruuduissa
              // (yötesti 19.11., OnePlus: "Sauvakävel / y").
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    tileLabel(name),
                    maxLines: 2,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? lead;
  final VoidCallback onTap;
  final Color? border;
  final Key? rowKey;
  const _Row({required this.title, this.trailing, this.lead, required this.onTap, this.border, this.rowKey});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        key: rowKey,
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: border == null ? BorderSide.none : BorderSide(color: border!, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                if (lead != null) ...[lead!, const SizedBox(width: 10)],
                Expanded(
                  // Yksi pitkä sana (Kamppailulajit, Soabbevázzin fontilla 2,0) pienenee eikä katkea kesken sanan;
                  // monisanainen nimi rivittyy sanojen välistä kuten ennen (yötesti 19.11.).
                  child: title.trim().contains(' ')
                      ? Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                ),
                if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _label(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 2),
  child: Text(
    text,
    style: TextStyle(
      fontSize: 11,
      letterSpacing: .6,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  ),
);

/// Health Connect -laatikko paneelin ylälaidassa: tämän päivän uudet harjoitukset.
Widget _hcBox(BuildContext context, Color tone, List<Widget> items) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: dark ? .22 : .12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: tone.withValues(alpha: .5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          items.length == 1
              ? t('❤ HEALTH CONNECTISTA · 1 UUSI')
              : t('❤ HEALTH CONNECTISTA · {0} UUTTA', [items.length]),
          style: const TextStyle(fontSize: 11, letterSpacing: .5, fontWeight: FontWeight.w700),
        ),
        ...items,
      ],
    ),
  );
}

String _hcDetails(HealthCandidate c, {bool gym = false}) => [
  if (c.app.isNotEmpty) c.app,
  '${c.end.difference(c.start).inMinutes} min',
  if (!gym && (c.meters ?? 0) > 0) '${fmtNum((c.meters! / 100).round() / 10)} km',
  if (!gym && (c.steps ?? 0) > 0) t('{0} askelta', [c.steps]),
  if (c.hrAvg != null) '♥ ${c.hrAvg}${c.hrMax != null ? ' / ${c.hrMax}' : ''}',
  if (c.kcal != null) '${c.kcal} kcal',
].join(' · ');

bool get _hcOn => settings.hcImport && !kIsWeb && !isDemo && Platform.isAndroid;

// ---- Sali ------------------------------------------------------------------------------------------------------

/// Salipaneeli: Health Connectin voimaharjoittelut, kesken oleva treeni, ohjelman päivät (ehdotus ylimpänä),
/// vapaa treeni ja linkki päivän valintaan (toinen päivä, lisäasetukset).
Future<void> showGymPanel(BuildContext context) async {
  if (_hcOn) HealthImportButton.refresh();
  final today = dateOnly(DateTime.now());
  HealthCandidate? logFor; // Kirjaa sarjat: kellon harjoitukselle valitaan päivä
  await _panel<void>(context, (ctx, set) {
    final cs = Theme.of(ctx).colorScheme;
    final sub = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    final p = settings.program;
    final days = p?.plan ?? const <PlanDay>[];
    final (sugg, why) = p != null && days.isNotEmpty && settings.activePause == null
        ? suggestDay(p, store.workouts, today)
        : (null, null);
    final mon = weekStart(today);
    String? doneOn(PlanDay d) {
      final w = store.workouts
          .where((w) => w.activity == null && !w.date.isBefore(mon) && w.date.isBefore(today) && d.matches(w.dayKey))
          .fold<Workout?>(null, (a, w) => a == null || w.date.isAfter(a.date) ? w : a);
      return w == null ? null : t('✓ tehty {0}', [shortDate(w.date)]);
    }

    final ordered = [?sugg, ...days.where((d) => d != sugg)];

    void pickDay(PlanDay? d) {
      final c = logFor;
      Navigator.pop(ctx);
      if (c != null) {
        _logHealthGym(context, c, d);
      } else {
        askWarmupAndStart(context, date: today, day: d);
      }
    }

    final dayRows = <Widget>[
      for (final d in ordered)
        if (d == sugg && logFor == null)
          _SuggestCard(day: d, why: why, onStart: () => pickDay(d))
        else
          _Row(
            title: d.uiName,
            trailing:
                doneOn(d) ?? (d == sugg ? t('★ ehdotus') : t('~{0} min', [(estimateMinutes(d.items) / 5).round() * 5])),
            border: d == sugg ? _gymRed : null,
            onTap: () => pickDay(d),
          ),
      _Row(
        rowKey: const ValueKey('panelFreeWorkout'),
        title: t('Vapaa treeni'),
        trailing: '›',
        onTap: () => pickDay(null),
      ),
    ];

    if (logFor != null) {
      final c = logFor!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(ctx).backButtonTooltip,
                onPressed: () => set(() => logFor = null),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  t('Mitä teit {0}–{1}?', [_hm(c.start), _hm(c.end)]),
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          Text(_hcDetails(c, gym: true), style: sub),
          Text(t('Kellon tiedot tulevat treeniin; kirjaat vain sarjat.'), style: sub),
          ...dayRows,
        ],
      );
    }

    final hc = [
      for (final c in HealthImportButton.todayFresh.value)
        if (isStrengthType(c.type)) c,
    ];
    final gymToday = store.onDay(today).where((w) => w.activity == null && w.hcId == null).toList();
    final open = gymToday.where((w) => w.minutes == null && w.feeling == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Mitä treenataan?'), style: Theme.of(ctx).textTheme.titleLarge),
        Text(longDateYear(today), style: sub),
        if (_hcOn && hc.isNotEmpty)
          _hcBox(ctx, _gymRed, [
            for (final c in hc)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '💪 ${c.title ?? t('Voimaharjoittelu')} ${_hm(c.start)}–${_hm(c.end)}',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    Text(_hcDetails(c, gym: true), style: sub),
                    const SizedBox(height: 8),
                    if (gymToday.isNotEmpty)
                      OutlinedButton(
                        key: const ValueKey('hcGymAttach'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _logHealthGym(context, c, null, attach: true);
                        },
                        child: Text(
                          t('Liitä tämän päivän treeniin: {0}', [
                            // Sama treeni, johon liitos menee (lähimpänä samaa aikaa, ks. gymFromHealth).
                            trName(gymFromHealth(c, store.onDay(today), nextSession: 0).$1.title),
                          ]),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              key: const ValueKey('hcGymLog'),
                              style: FilledButton.styleFrom(backgroundColor: _gymRed, foregroundColor: Colors.white),
                              onPressed: () => set(() => logFor = c),
                              child: FittedBox(child: Text(t('Kirjaa sarjat'))),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              key: const ValueKey('hcGymNoSets'),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _saveHealthGym(context, c);
                              },
                              child: FittedBox(child: Text(t('Ilman sarjoja'))),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ]),
        for (final w in open)
          _Row(
            title: t('Jatka: {0}', [trName(w.title)]),
            trailing: setsLabel(w.exercises.fold<int>(0, (a, e) => a + e.workSets.length)),
            border: _gymRed,
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutScreen(workout: w.copy())));
            },
          ),
        if (settings.activePause != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t('Tauolla ei ehdotuksia; voit silti treenata.'), style: sub),
          ),
        if (logFor == null) _label(ctx, open.isEmpty ? t('ALOITA') : t('ALOITA UUSI')),
        ...dayRows,
        // Oma ontto punainen painike (käyttäjä 17.11.: ennen pelkkä tekstilinkki, joka hukkui listan alle).
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _OutlineAction(
            key: const ValueKey('panelOtherDay'),
            color: redText(ctx),
            icon: Icons.edit_calendar_outlined,
            label: t('Toinen päivä tai ohjelman muokkaus'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => NewWorkoutScreen(date: today, gymOnly: true)));
            },
          ),
        ),
      ],
    );
  });
}

class _SuggestCard extends StatelessWidget {
  final PlanDay day;
  final String? why;
  final VoidCallback onStart;
  const _SuggestCard({required this.day, required this.why, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    final mins = (estimateMinutes(day.items) / 5).round() * 5;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gymRed, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(day.uiName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              Text(t('★ ehdotus'), style: TextStyle(fontSize: 12, color: yellowText(context))),
            ],
          ),
          Text(
            [
              t('~{0} min', [mins]),
              t('{0} liikettä', [day.items.length]),
            ].join(' · '),
            style: sub,
          ),
          if (why != null) Text('💡 $why', style: sub),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('panelStartSuggested'),
            style: FilledButton.styleFrom(
              backgroundColor: _gymRed,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(t('Aloita')),
          ),
        ],
      ),
    );
  }
}

/// Kellon voimaharjoittelu Gievraan: päivän valinnalla (Kirjaa sarjat), ilman päivää (vapaa) tai liitettynä
/// tämän päivän salitreeniin ([attach]). Avaa treenin sarjojen kirjaamiseen.
Future<void> _logHealthGym(BuildContext context, HealthCandidate c, PlanDay? day, {bool attach = false}) async {
  final d = dateOnly(c.start);
  final sameDay = store.onDay(d);
  final (w, isNew) = gymFromHealth(c, sameDay, nextSession: sameDay.isEmpty ? 1 : store.nextSession(d));
  if (isNew && day != null) {
    w.title = day.display;
    w.programDay = day.name;
  }
  await store.save(w);
  HealthImportButton.refresh();
  if (!context.mounted) return;
  if (!isNew || attach) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Kellon tiedot lisätty salitreeniin.'))));
    if (attach) return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WorkoutScreen(workout: w, planDay: day == null ? null : injuryAdjusted(day, settings.injuries)),
    ),
  );
}

/// Kellon voimaharjoittelu salitreeninä ilman sarjoja (kesto, syke ja kalorit).
Future<void> _saveHealthGym(BuildContext context, HealthCandidate c) async {
  final d = dateOnly(c.start);
  final sameDay = store.onDay(d);
  final (w, _) = gymFromHealth(c, sameDay, nextSession: sameDay.isEmpty ? 1 : store.nextSession(d));
  await store.save(w);
  HealthImportButton.refresh();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Salitreeni tallennettu kellon tiedoin.'))));
  }
}

// ---- Liikunta --------------------------------------------------------------------------------------------------

/// Liikuntapaneeli: Health Connectin uudet harjoitukset, viimeksi käytetyt lajit ja muut, sitten kirjaustapa.
Future<void> showActivityPanel(BuildContext context) async {
  if (AwayActivity.away) {
    openPendingActivity(context);
    return;
  }
  if (_hcOn) HealthImportButton.refresh();
  final today = dateOnly(DateTime.now());
  String? sport; // valittu laji: paneeli kysyy kirjaustavan
  Workout? hcW; // Health Connectin harjoitus tarkistettavana paneelissa
  String? hcEffort;
  await _panel<void>(context, (ctx, set) {
    final cs = Theme.of(ctx).colorScheme;
    final sub = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    if (hcW != null) {
      final w = hcW!;
      final act = activeKcal(w, hrProfile());
      Widget tile(String v, String l) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              FittedBox(
                child: Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
            ],
          ),
        ),
      );
      final tiles = [
        tile(fmtDurationSec(w.durationSec ?? 0), t('aika')),
        if ((w.distanceKm ?? 0) > 0) tile(fmtNum(w.distanceKm!), 'km'),
        if ((w.steps ?? 0) > 0) tile('${w.steps}', t('askelta')),
        if (w.hrAvg != null) tile('${w.hrAvg}', t('keskisyke')),
        if (w.kcal != null) tile('${w.kcal}', 'kcal'),
        if (act != null) tile('$act', t('aktiivisia')),
      ];
      final efforts = [('kevyt', '😌', t('Kevyt')), ('reipas', '😤', t('Reipas')), ('kova', '🥵', t('Kova'))];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(ctx).backButtonTooltip,
                onPressed: () => set(() => hcW = null),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  '${sportOf(w.activity)?.icon ?? ''} ${sportName(w.activity!)} · Health Connect',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Text(
            [
              shortDate(w.date),
              if (w.started != null) '${_hm(w.started!)}–${_hm(w.started!.add(Duration(seconds: w.durationSec ?? 0)))}',
              if ((w.healthSource ?? '').isNotEmpty) w.healthSource!,
            ].join(' · '),
            style: sub,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < tiles.length; i += 3)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (var j = i; j < i + 3; j++) ...[
                    if (j > i) const SizedBox(width: 6),
                    j < tiles.length ? tiles[j] : const Expanded(child: SizedBox()),
                  ],
                ],
              ),
            ),
          _label(ctx, t('RASITUS')),
          Row(
            children: [
              for (final (i, (k, e, l)) in efforts.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    key: ValueKey('hcEffort_$k'),
                    label: SizedBox(
                      width: double.infinity,
                      child: Text('$e $l', textAlign: TextAlign.center),
                    ),
                    selected: hcEffort == k,
                    onSelected: (_) => set(() => hcEffort = k),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('hcEdit'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    w.intensity = hcEffort;
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: w, manual: true)));
                  },
                  child: Text(t('Muokkaa')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const ValueKey('hcSave'),
                  style: FilledButton.styleFrom(backgroundColor: _actGreen, foregroundColor: Colors.white),
                  onPressed: () async {
                    w.intensity = hcEffort;
                    Navigator.pop(ctx);
                    await store.save(w);
                    HealthImportButton.refresh();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(persist: false, content: Text(t('Tallennettu: {0}', [sportName(w.activity!)]))),
                      );
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: Text(t('Tallenna')),
                ),
              ),
            ],
          ),
        ],
      );
    }
    if (sport != null) {
      final s = sport!;
      final sp = sportOf(s);
      final gpsOk = (sp?.distance ?? false) && !kIsWeb && !isDemo && Platform.isAndroid;
      final last = lastMode(store.workouts, s) ?? (gpsOk ? 'gps' : 'watch');
      void go(String mode) {
        Navigator.pop(ctx);
        startActivity(context, s, mode: mode);
      }

      Widget way(String mode, IconData icon, String title, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          key: ValueKey('panelMode_$mode'),
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: mode == last ? BorderSide(color: greenText(ctx), width: 1.5) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => go(mode),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icon, size: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(text, style: sub),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(ctx).backButtonTooltip,
                onPressed: () => set(() => sport = null),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(child: Text('${sp?.icon ?? ''} ${sportName(s)}', style: Theme.of(ctx).textTheme.titleLarge)),
            ],
          ),
          Text(t('Miten kirjataan?'), style: sub),
          if (gpsOk) way('gps', Icons.place_outlined, t('GPS'), t('Aika, matka, reitti ja nousut')),
          way('watch', Icons.timer_outlined, t('Ajanotto'), t('Ilman GPS:ää, esim. kävelymatto')),
          way('manual', Icons.edit_outlined, t('Jo tehty'), t('Syötä aika ja matka itse')),
          if (hr.address != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '♥ ${t('{0} yhdistyy, kun aloitat', [hr.name ?? t('Sykevyö')])}',
                textAlign: TextAlign.center,
                style: sub,
              ),
            ),
        ],
      );
    }

    final week = weekActivity(store.workouts, today);
    final recent = recentSports(store.workouts, 3);
    final more = sportsByUse(
      [for (final w in store.workouts) w.activity],
      among: sports.where((s) => !s.retired),
    ).where((s) => !recent.any((r) => r.$1 == s.name)).take(recent.isEmpty ? 6 : 3).toList();
    final hc = [
      for (final c in HealthImportButton.todayFresh.value)
        if (!isStrengthType(c.type)) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Mitä liikuntaa?'), style: Theme.of(ctx).textTheme.titleLarge),
        Text(
          settings.activePause != null
              ? t('Tauolla, ei viikkotavoitetta')
              : t('Tällä viikolla {0} / {1} min reipasta', [week.moderateEq, whoMinutes]),
          style: sub,
        ),
        if (_hcOn && hc.isNotEmpty)
          _hcBox(ctx, _actGreen, [
            for (final c in hc)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${sportOf(sportForHealthType(c.type))?.icon ?? '🏃'} '
                            '${sportForHealthType(c.type) != null ? sportName(sportForHealthType(c.type)!) : (c.title ?? t('Liikunta'))} '
                            '${_hm(c.start)}–${_hm(c.end)}',
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                          ),
                          Text(_hcDetails(c), style: sub),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('hcActAdd'),
                      style: FilledButton.styleFrom(backgroundColor: _actGreen, foregroundColor: Colors.white),
                      onPressed: () {
                        // Laji tunnetaan: tarkistus ja tallennus paneelissa; muuten lajin valinta kuten ennen.
                        final sp = sportForHealthType(c.type);
                        if (sp == null) {
                          Navigator.pop(ctx);
                          addHealthActivity(context, c);
                          return;
                        }
                        final d = dateOnly(c.start);
                        final w = workoutFromHealth(c, sp, session: store.onDay(d).isEmpty ? 1 : store.nextSession(d));
                        set(() {
                          hcW = w;
                          hcEffort = estimateEffort(w)?.$1;
                        });
                      },
                      child: Text(t('Lisää')),
                    ),
                  ],
                ),
              ),
          ]),
        if (recent.isNotEmpty) ...[
          _label(ctx, hc.isNotEmpty ? t('ALOITA UUSI · VIIMEKSI') : t('VIIMEKSI')),
          for (final (s, d) in recent)
            _Row(
              rowKey: ValueKey('panelSport_$s'),
              lead: Text(sportOf(s)?.icon ?? '🏃', style: const TextStyle(fontSize: 20)),
              title: sportName(s),
              trailing: _when(d),
              onTap: () => set(() => sport = s),
            ),
        ],
        _label(ctx, recent.isEmpty ? t('LAJIT') : t('MUUT')),
        // Lajit laattoina kahdessa sarakkeessa (käyttäjä 17.11.: sirut näyttivät vanhalta ulkoasulta).
        for (var i = 0; i < more.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in more.skip(i).take(2)) ...[
                    if (s != more[i]) const SizedBox(width: 6),
                    Expanded(
                      child: _SportTile(
                        key: ValueKey('panelSport_${s.name}'),
                        icon: s.icon,
                        name: sportName(s.name),
                        onTap: () => set(() => sport = s.name),
                      ),
                    ),
                  ],
                  if (i + 1 >= more.length) ...[const SizedBox(width: 6), const Expanded(child: SizedBox())],
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _OutlineAction(
            key: const ValueKey('panelAllSports'),
            color: greenText(ctx),
            icon: Icons.search,
            label: t('Kaikki lajit…'),
            onPressed: () {
              Navigator.pop(ctx);
              startActivity(context, null);
            },
          ),
        ),
      ],
    );
  });
}
