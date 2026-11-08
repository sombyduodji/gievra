import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../running.dart';
import '../sports.dart';
import '../theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Juoksun kehitys: oma näkymä, erillään salin ja kahvakuulan edistymisestä.
class RunningScreen extends StatelessWidget {
  const RunningScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Juoksun kehitys'))),
    body: ListenableBuilder(listenable: store, builder: (context, _) => _body(context)),
  );

  Widget _body(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final today = dateOnly(DateTime.now());
    final runs = runsOf(store.workouts);
    if (runs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          const SizedBox(height: 24),
          Text(
            t(
              'Ei vielä juoksuja. Lisää juoksu tai hölkkä matkan ja ajan kanssa, niin näet täällä kilometrit, vauhdin '
              'kehityksen ja ennätykset.',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    final weeks = runWeeks(runs, today);
    final thisWeek = weeks.last;
    final month = runs.where((r) => r.date.year == today.year && r.date.month == today.month);
    final monthKm = month.fold<double>(0, (a, r) => a + r.distanceKm!);
    final trend = easyRunTrend(runs, today);
    final bests = runBests(runs);
    final types = runTypeStats(runs);
    String km(double v) => fmtNum((v * 10).round() / 10);

    Widget tile(String v, String l) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(l, style: sub, textAlign: TextAlign.center),
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
      children: [
        const SamiBand(height: 4, pattern: false),
        const SizedBox(height: 12),
        Row(
          children: [
            tile('${km(thisWeek.km)} km', t('tällä viikolla')),
            const SizedBox(width: 8),
            tile('${km(monthKm)} km', t('tässä kuussa')),
            const SizedBox(width: 8),
            tile('${runs.length}', t('juoksua yhteensä')),
          ],
        ),
        SectionLabel(t('Kilometrit viikoittain')),
        _WeekBars(weeks: weeks),
        SectionLabel(t('Keskivauhti viikoittain')),
        _PaceLine(weeks: weeks),
        Text(t('Ylempänä = nopeampi. Kaikki juoksut, matkalla painotettu.'), style: sub),
        SectionLabel(t('Kehitys')),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('Kevyet lenkit, 4 viikkoa vs. edelliset 4'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (trend.paceNow == null || trend.pacePrev == null)
                Text(t('Vertailuun tarvitaan kevyitä lenkkejä molemmilta jaksoilta.'), style: sub)
              else ...[
                Text(
                  '${fmtPace(trend.pacePrev!)} → ${fmtPace(trend.paceNow!)} min/km  '
                  '${_diff(trend.paceNow! - trend.pacePrev!)}',
                  style: const TextStyle(fontSize: 16),
                ),
                if (trend.hrNow != null && trend.hrPrev != null)
                  Text(t('keskisyke {0} → {1}', [trend.hrPrev, trend.hrNow]), style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  t(
                    'Nopeampi vauhti samalla sykkeellä tai sama vauhti matalammalla sykkeellä tarkoittaa, että '
                    'peruskunto paranee.',
                  ),
                  style: sub,
                ),
              ],
            ],
          ),
        ),
        if (bests.isNotEmpty) ...[
          SectionLabel(t('Ennätykset')),
          for (final b in bests)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Text('🏆', style: TextStyle(fontSize: 20)),
              title: Text('${_distName(b.km)}  ${fmtDurationSec(b.sec)}'),
              subtitle: Text(
                '${fmtPace(b.run.paceSecPerKm!)} min/km · ${shortDate(b.run.date)} · ${km(b.run.distanceKm!)} km',
                style: sub,
              ),
            ),
          Text(t('Nopein keskivauhti vähintään yhtä pitkältä juoksulta, aika laskettuna matkalle.'), style: sub),
        ],
        SectionLabel(t('Lenkkityypit')),
        for (final s in types)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Text(runTypeOf(s.type)?.$3 ?? '🏃', style: const TextStyle(fontSize: 20)),
            title: Text(runTypeOf(s.type) == null ? t('Ei tyyppiä') : t(runTypeOf(s.type)!.$2)),
            subtitle: Text(
              [
                t('{0} kertaa', [s.runs]),
                '${km(s.km)} km',
                if (s.pace != null) '${fmtPace(s.pace!)} min/km',
                if (s.hrAvg != null) '❤️ ${s.hrAvg}',
              ].join(' · '),
              style: sub,
            ),
          ),
        SectionLabel(t('Viimeisimmät')),
        for (final r in runs.take(8))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Text(runTypeOf(r.runType)?.$3 ?? '🏃', style: const TextStyle(fontSize: 20)),
            title: Text('${km(r.distanceKm!)} km · ${fmtDurationSec(r.durationSec!)} · ${r.pace}'),
            subtitle: Text(
              [
                shortDate(r.date),
                if (runTypeOf(r.runType) != null) t(runTypeOf(r.runType)!.$2),
                if (r.hrAvg != null) '❤️ ${r.hrAvg}',
              ].join(' · '),
              style: sub,
            ),
          ),
      ],
    );
  }

  static String _distName(double km) => switch (km) {
    5.0 => '5 km',
    10.0 => '10 km',
    21.0975 => t('Puolimaraton'),
    _ => t('Maraton'),
  };

  /// Vauhdin muutos: negatiivinen = nopeampi.
  static String _diff(double sec) {
    final s = sec.round();
    if (s == 0) return '=';
    return s < 0 ? t('{0} s/km nopeampi', [-s]) : t('{0} s/km hitaampi', [s]);
  }
}

class _WeekBars extends StatelessWidget {
  final List<RunWeek> weeks;
  const _WeekBars({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxKm = weeks.fold<double>(0, (a, w) => w.km > a ? w.km : a);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, w) in weeks.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (w.km > 0)
                      Text(fmtNum(w.km.roundToDouble()), style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                    Container(
                      height: maxKm <= 0 ? 2 : (w.km / maxKm * 86).clamp(2, 86),
                      decoration: BoxDecoration(
                        color: i == weeks.length - 1 ? Sami.red : Sami.blue.withValues(alpha: w.km > 0 ? .8 : .15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(numDate(w.start), style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaceLine extends StatelessWidget {
  final List<RunWeek> weeks;
  const _PaceLine({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 110,
      child: CustomPaint(painter: _PacePainter(weeks, cs), size: Size.infinite),
    );
  }
}

class _PacePainter extends CustomPainter {
  final List<RunWeek> weeks;
  final ColorScheme cs;
  _PacePainter(this.weeks, this.cs);

  @override
  void paint(Canvas c, Size s) {
    final pts = [
      for (final (i, w) in weeks.indexed)
        if (w.pace != null) (i, w.pace!),
    ];
    if (pts.isEmpty) return;
    var lo = pts.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
    var hi = pts.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
    if (hi - lo < 30) {
      lo -= 15;
      hi += 15;
    }
    const top = 14.0, bottom = 14.0;
    final dx = s.width / weeks.length;
    Offset at(int i, double pace) =>
        Offset(dx * (i + .5), top + (pace - lo) / (hi - lo) * (s.height - top - bottom)); // nopeampi = ylempänä
    final grid = Paint()
      ..color = cs.outlineVariant
      ..strokeWidth = 1;
    c.drawLine(Offset(0, top), Offset(s.width, top), grid);
    c.drawLine(Offset(0, s.height - bottom), Offset(s.width, s.height - bottom), grid);
    final path = Path();
    for (final (j, p) in pts.indexed) {
      final o = at(p.$1, p.$2);
      j == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    c.drawPath(
      path,
      Paint()
        ..color = Sami.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (final p in pts) {
      c.drawCircle(at(p.$1, p.$2), 3.5, Paint()..color = Sami.green);
    }
    void label(String text, double y) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(2, y));
    }

    label('${fmtPace(lo)} min/km', 0);
    label('${fmtPace(hi)} min/km', s.height - 12);
  }

  @override
  bool shouldRepaint(covariant _PacePainter old) => true;
}
