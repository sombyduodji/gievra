import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../insights.dart' show weekStart;
import '../l10n.dart';
import '../models.dart';
import '../session_compare.dart' show fmtDuration;
import '../sleep.dart';
import '../theme.dart';
import 'home_extras_ui.dart' show NightHrData, NightMetricsCard, nightHrNights;
import 'widgets.dart';

// Tilastot → Palautuminen ja uni (käyttäjä 18.11.): kehitys ajan mittaan (HRV nousee, yösyke laskee, uni pitenee).
// Näkyy vain, kun Palautuminen, Uni tai yöarvot on otettu käyttöön. Viikkokeskiarvot 12 viikolta ja viimeiset
// 4 viikkoa verrattuna 4 viikkoon ennen niitä.

/// Sarja: päivä → arvo.
typedef DaySeries = Map<DateTime, double>;

/// Suunta: +1 = suurempi on parempi (HRV, uni), -1 = pienempi on parempi (yösyke, hengitys), 0 = ei suuntaa.
class TrendSeries {
  final String key, label;
  final IconData icon;
  final DaySeries data;
  final int better;
  final String Function(double) fmt;
  const TrendSeries(this.key, this.label, this.icon, this.data, this.better, this.fmt);
}

/// Viikkokeskiarvot [weeks] viikolta (vanhin ensin, null = ei arvoja).
List<double?> weeklyAverages(DaySeries d, DateTime today, {int weeks = 12}) {
  final first = addDays(weekStart(dateOnly(today)), -7 * (weeks - 1));
  final sums = List<double>.filled(weeks, 0), counts = List<int>.filled(weeks, 0);
  for (final e in d.entries) {
    if (e.key.isBefore(first) || e.key.isAfter(today)) continue;
    final i = daysBetween(first, e.key) ~/ 7;
    if (i < 0 || i >= weeks) continue;
    sums[i] += e.value;
    counts[i]++;
  }
  return [for (var i = 0; i < weeks; i++) counts[i] == 0 ? null : sums[i] / counts[i]];
}

/// Viimeiset 28 päivää vs. 28 päivää ennen niitä (kumpaankin vähintään 7 arvoa).
(double, double)? fourWeekChange(DaySeries d, DateTime today) {
  final t = dateOnly(today);
  final a = [
    for (final e in d.entries)
      if (!e.key.isBefore(addDays(t, -27)) && !e.key.isAfter(t)) e.value,
  ];
  final b = [
    for (final e in d.entries)
      if (!e.key.isBefore(addDays(t, -55)) && e.key.isBefore(addDays(t, -27))) e.value,
  ];
  if (a.length < 7 || b.length < 7) return null;
  double avg(List<double> x) => x.reduce((p, q) => p + q) / x.length;
  return (avg(a), avg(b));
}

bool recoveryStatsVisible() =>
    settings.homeCardOn('recovery') || settings.homeCardOn('sleep') || settings.homeCardOn('night');

List<TrendSeries> recoverySeries() {
  final out = <TrendSeries>[
    TrendSeries(
      'nighthr',
      t('Yösyke'),
      Icons.favorite_border,
      {for (final e in nightHrNights().entries) e.key: e.value.toDouble()},
      -1,
      (v) => '${v.round()}',
    ),
  ];
  if (settings.homeCardOn('night')) {
    for (final (k, better) in [('hrv', 1), ('rr', -1), ('spo2', 0), ('temp', 0)]) {
      out.add(
        TrendSeries(
          k,
          NightMetricsCard.label(k),
          NightMetricsCard.icon(k),
          {for (final e in sleepData.metrics.entries) e.key: ?e.value.of(k)},
          better,
          (v) => NightMetricsCard.value(k, v),
        ),
      );
    }
  }
  if (sleepData.enabled) {
    out.add(
      TrendSeries(
        'sleep',
        t('Uni'),
        Icons.bedtime_outlined,
        {for (final n in sleepData.nights.values) n.day: n.asleep.inMinutes.toDouble()},
        1,
        (v) => fmtDuration(v.round()),
      ),
    );
  }
  return [
    for (final s in out)
      if (s.data.length >= 7) s,
  ];
}

class RecoveryTrendsSection extends StatelessWidget {
  const RecoveryTrendsSection({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([sleepData, NightHrData.nights, settings]),
    builder: (context, _) {
      if (!recoveryStatsVisible()) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final series = recoverySeries();
      final today = dateOnly(DateTime.now());
      return Column(
        key: const ValueKey('recoveryTrends'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(t('Palautuminen ja uni')),
          if (series.isEmpty)
            Text(
              t('Kehitys näkyy, kun öitä on tallessa vähintään viikon verran.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            )
          else ...[
            Text(
              t('Viikkokeskiarvot 12 viikolta; muutos: viimeiset 4 viikkoa verrattuna 4 viikkoon ennen niitä.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final s in series) _TrendRow(series: s, today: today),
          ],
        ],
      );
    },
  );
}

class _TrendRow extends StatelessWidget {
  final TrendSeries series;
  final DateTime today;
  const _TrendRow({required this.series, required this.today});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final weeks = weeklyAverages(series.data, today);
    final ch = fourWeekChange(series.data, today);
    String? change;
    Color? color;
    IconData? arrow;
    if (ch != null) {
      final (now, before) = ch;
      final diff = now - before;
      final rel = before == 0 ? 0.0 : diff / before;
      // Alle 2 %:n muutos (tai alle lukeman tarkkuuden) on ennallaan.
      final same = rel.abs() < .02;
      arrow = same
          ? Icons.trending_flat
          : diff > 0
          ? Icons.trending_up
          : Icons.trending_down;
      final good = series.better == 0 || same ? null : (diff > 0) == (series.better > 0);
      color = good == null
          ? cs.onSurfaceVariant
          : good
          ? greenText(context)
          : yellowText(context);
      change = '${nb(series.fmt(now))} ← ${nb(series.fmt(before))}';
    }
    return Container(
      key: ValueKey('trend_${series.key}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(series.icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              // Nimi vie vain tarvitsemansa tilan, muutos saa loput (käyttäjä 18.11.: "7 h 22 min ← 7 h 31 min"
              // rivittyi, koska nimi ja muutos jakoivat rivin puoliksi).
              Flexible(
                child: Text(series.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              if (arrow != null)
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(arrow, size: 18, color: color),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          change!,
                          style: TextStyle(fontSize: 13, color: color),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  flex: 3,
                  child: Text(
                    t('vertailu 8 viikon jälkeen'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    textAlign: TextAlign.end,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: CustomPaint(painter: _WeekLine(weeks, blueText(context), cs.outlineVariant), size: Size.infinite),
          ),
          // Ensimmäinen ja viimeisin viikkokeskiarvo luvuin, jotta käyrän voi lukea (testi 18.11.).
          Builder(
            builder: (context) {
              final firstI = weeks.indexWhere((x) => x != null), lastI = weeks.lastIndexWhere((x) => x != null);
              if (firstI < 0) return const SizedBox.shrink();
              final sub = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('{0} vk sitten: {1}', [weeks.length - 1 - firstI, nb(series.fmt(weeks[firstI]!))]),
                        style: sub,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Suurella tekstillä kumpikin rivittyy omalle puolelleen (ei ylivuotoa).
                    Expanded(
                      child: Text(
                        t('viimeisin viikko: {0}', [nb(series.fmt(weeks[lastI]!))]),
                        style: sub,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WeekLine extends CustomPainter {
  final List<double?> v;
  final Color line, grid;
  _WeekLine(this.v, this.line, this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (var i = 0; i < v.length; i++)
        if (v[i] != null) (i, v[i]!),
    ];
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    if (pts.isEmpty) return;
    var lo = pts.map((p) => p.$2).reduce(math.min), hi = pts.map((p) => p.$2).reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    Offset at(int i, double y) => Offset(
      v.length == 1 ? size.width / 2 : size.width * i / (v.length - 1),
      size.height - 4 - (size.height - 8) * (y - lo) / (hi - lo),
    );
    final p = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (final (j, (i, y)) in pts.indexed) {
      final o = at(i, y);
      j == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, p);
    for (final (i, y) in pts) {
      canvas.drawCircle(at(i, y), 2.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_WeekLine old) => old.v != v || old.line != line;
}

/// Arvo ("7 h 31 min", "38 ms") ei katkea rivinvaihdossa keskeltä (käyttäjä 18.11.).
String nb(String v) => v.replaceAll(' ', '\u00A0');
