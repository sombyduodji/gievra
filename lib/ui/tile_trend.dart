import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../heart_rate.dart' show hrProfile;
import '../home_extras.dart' show nightHr;
import '../insights.dart' show weekStart;
import '../l10n.dart';
import '../models.dart';
import '../recovery.dart';
import '../session_compare.dart' show fmtDuration;
import '../sleep.dart';
import '../theme.dart';
import 'home_extras_ui.dart' show NightMetricsCard, nightHrNights;
import 'recovery_card.dart' show tileColor;
import 'widgets.dart' show shortDate;

// Palautuminen-ruudun käyrä (käyttäjä 19.11., vaihtoehto C): ruudun napautus avaa paneelin, jossa arvo 30 päivältä
// (oma tavallinen vaihtelu vihreänä vyönä) tai 12 viikon keskiarvoina; poikkeavassa ruudussa neuvo käyrän alla.

/// Ruudun päiväsarja näyttöyksikössä: syke lyöntiä, HRV ms, uni minuutteja, kuormitus minuutteja × rasitus.
Map<DateTime, double> tileSeries(String key, DateTime now) {
  final today = dateOnly(now);
  switch (key) {
    case 'nighthr':
      return {for (final e in nightHrNights().entries) e.key: e.value.toDouble()};
    case 'sleep':
      return {for (final n in sleepData.nights.values) n.day: n.asleep.inMinutes.toDouble()};
    case 'load':
      final maxHr = hrProfile()?.maxHr(now);
      final out = <DateTime, double>{};
      for (final w in store.workouts) {
        if (w.date.isAfter(today) || w.date.isBefore(addDays(today, -7 * 12 - 6))) continue;
        final l = workoutLoad(w, maxHr: maxHr);
        if (l > 0) out[dateOnly(w.date)] = (out[dateOnly(w.date)] ?? 0) + l;
      }
      return out;
    default:
      return {for (final e in sleepData.metrics.entries) e.key: ?e.value.of(key)};
  }
}

/// Oma tavallinen taso ja vaihtelu, jonka sisällä ruutu on vihreä (samat rajat kuin ruudun keltaisella).
/// Kuormituksella vain taso (4 viikon päiväkeskiarvo), ei vyötä.
({double mid, double? lo, double? hi})? tileUsual(String key, DateTime now) {
  final today = dateOnly(now);
  switch (key) {
    case 'nighthr':
      final b = nightHr(nightHrNights(), now)?.base;
      return b == null ? null : (mid: b, lo: b - 3, hi: b + 3);
    case 'sleep':
      final u = sleepStats(sleepData.nights, today, goal: Duration(minutes: settings.sleepGoal)).usual;
      if (u == null) return null;
      final m = u.inMinutes.toDouble();
      return (mid: m, lo: m - 45, hi: m + 45);
    case 'load':
      final s = tileSeries('load', now);
      var sum = 0.0;
      for (final e in s.entries) {
        if (!e.key.isBefore(addDays(today, -27))) sum += e.value;
      }
      return sum <= 0 ? null : (mid: sum / 28, lo: null, hi: null);
    default:
      final s = metricStat(sleepData.metrics, key, now);
      if (s == null || s.usual == null) return null;
      final u = s.usual!;
      return switch (key) {
        'hrv' when s.sd != null => (mid: math.exp(u), lo: math.exp(u - .5 * s.sd!), hi: math.exp(u + .5 * s.sd!)),
        'hrv' => (mid: math.exp(u), lo: null, hi: null),
        'rr' => (mid: u, lo: u - 1.5, hi: u + 1.5),
        'temp' => (mid: u, lo: u - .3, hi: u + .3),
        'spo2' => (mid: u, lo: u - 1, hi: math.min(100.0, u + 1)),
        _ => (mid: u, lo: null, hi: null),
      };
  }
}

String tileFmt(String key, double v) => switch (key) {
  'nighthr' => '${v.round()}',
  'sleep' => fmtDuration(v.round()),
  'load' => '${v.round()}',
  _ => NightMetricsCard.value(key, v),
};

/// 12 viikkoa (vanhin ensin): keskiarvot, kuormituksella viikon summa.
List<double?> tileWeeks(String key, Map<DateTime, double> d, DateTime now) {
  final today = dateOnly(now);
  final first = addDays(weekStart(today), -7 * 11);
  final sums = List<double>.filled(12, 0), counts = List<int>.filled(12, 0);
  for (final e in d.entries) {
    if (e.key.isBefore(first) || e.key.isAfter(today)) continue;
    final i = daysBetween(first, e.key) ~/ 7;
    sums[i] += e.value;
    counts[i]++;
  }
  if (key == 'load') {
    // Viikot ennen ensimmäistä treeniä tyhjinä, sen jälkeen treenitön viikko nollana.
    final firstData = counts.indexWhere((c) => c > 0);
    return [for (var i = 0; i < 12; i++) firstData < 0 || i < firstData ? null : sums[i]];
  }
  return [for (var i = 0; i < 12; i++) counts[i] == 0 ? null : sums[i] / counts[i]];
}

/// Käyrä ja 30 päivää | 12 vk -valitsin paneelin sisään.
class TileTrend extends StatefulWidget {
  final String tileKey;
  final TileState state;
  final DateTime now;
  const TileTrend({super.key, required this.tileKey, required this.state, required this.now});

  @override
  State<TileTrend> createState() => _TileTrendState();
}

class _TileTrendState extends State<TileTrend> {
  bool _weeks = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final key = widget.tileKey, now = widget.now, today = dateOnly(now);
    final series = tileSeries(key, now);
    final usual = tileUsual(key, now);
    final load = key == 'load';
    final sub = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    final days = [for (var i = 0; i < 30; i++) series[addDays(today, i - 29)]];
    final weeks = tileWeeks(key, series, now);
    final shown = _weeks ? weeks : days;
    final enough = shown.where((v) => v != null).length >= 2;
    double? avg(int n) {
      final v = [for (var i = 0; i < n; i++) ?series[addDays(today, -i)]];
      if (v.isEmpty) return null;
      return load ? v.reduce((a, b) => a + b) / n : v.reduce((a, b) => a + b) / v.length;
    }

    final a7 = avg(7), a30 = avg(30);
    final caption = _weeks
        ? (load ? t('Viikon kuormitus: minuutit × rasitus.') : t('Viikkokeskiarvot 12 viikolta.'))
        : load
        ? t('Päivän kuormitus: minuutit × rasitus. Katkoviiva: 4 viikon päiväkeskiarvo.')
        : usual?.lo != null
        ? t('Vihreä vyö: tavallinen vaihtelusi.')
        : '';
    return Column(
      key: const ValueKey('tileTrend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('trend30'),
                label: Text(t('30 päivää')),
                selected: !_weeks,
                onSelected: (_) => setState(() => _weeks = false),
              ),
              ChoiceChip(
                key: const ValueKey('trend12'),
                label: Text(t('12 vk')),
                selected: _weeks,
                onSelected: (_) => setState(() => _weeks = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (!enough)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(t('Liian vähän tietoa käyrään.'), style: sub, textAlign: TextAlign.center),
          )
        else ...[
          SizedBox(
            height: 130,
            child: Semantics(
              label: t('{0}: käyrä', [_weeks ? t('12 vk') : t('30 päivää')]),
              child: CustomPaint(
                size: Size.infinite,
                painter: _TrendPainter(
                  values: shown,
                  bars: _weeks || load,
                  // Kuormituksen viikkopylväät ovat summia: taso viikon mittaisena.
                  usual: _weeks && load && usual != null ? (mid: usual.mid * 7, lo: null, hi: null) : usual,
                  band: !_weeks && !load,
                  line: blueText(context),
                  last: tileColor(context, widget.state),
                  bandColor: greenText(context).withValues(alpha: .16),
                  grid: cs.outlineVariant,
                  // Asteikko oikeaan reunaan (käyttäjä 19.11.): suurin, pienin ja tavallinen taso.
                  label: (v) => key == 'sleep' ? _hm(v) : tileFmt(key, v),
                  labelStyle: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 10.5, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _weeks ? t('{0} vk sitten', [11]) : shortDate(addDays(today, -29)),
                style: sub.copyWith(fontSize: 11),
              ),
              const Spacer(),
              Text(_weeks ? t('tämä viikko') : t('tänään'), style: sub.copyWith(fontSize: 11)),
            ],
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(caption, style: sub),
            ),
          if (!_weeks && a7 != null && a30 != null)
            Text(
              load
                  ? t('Päiväkeskiarvo: 7 pv {0} · 30 pv {1}', [tileFmt(key, a7), tileFmt(key, a30)])
                  : t('Keskiarvo: 7 pv {0} · 30 pv {1}', [tileFmt(key, a7), tileFmt(key, a30)]),
              style: sub,
            ),
        ],
      ],
    );
  }
}

String _hm(double minutes) {
  final m = minutes.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

class _TrendPainter extends CustomPainter {
  final String Function(double) label;
  final TextStyle labelStyle;
  final List<double?> values;
  final bool bars, band;
  final ({double mid, double? lo, double? hi})? usual;
  final Color line, last, bandColor, grid;
  _TrendPainter({
    required this.values,
    required this.bars,
    required this.usual,
    required this.band,
    required this.line,
    required this.last,
    required this.bandColor,
    required this.grid,
    required this.label,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (var i = 0; i < values.length; i++)
        if (values[i] != null) (i, values[i]!),
    ];
    if (pts.isEmpty) return;
    final u = usual;
    var lo = pts.map((p) => p.$2).reduce(math.min), hi = pts.map((p) => p.$2).reduce(math.max);
    if (u != null) {
      lo = math.min(lo, band ? (u.lo ?? u.mid) : u.mid);
      hi = math.max(hi, band ? (u.hi ?? u.mid) : u.mid);
    }
    if (bars) lo = math.min(lo, 0);
    final dataLo = lo, dataHi = hi;
    // Asteikon tekstit oikeaan reunaan: piirtoalue kapenee niiden verran.
    TextPainter tp(double v) => TextPainter(
      text: TextSpan(text: label(v), style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final marks = <double>[dataHi, if (u != null) u.mid, dataLo];
    final tps = [for (final v in marks) tp(v)];
    final gutter = tps.map((t) => t.width).reduce(math.max) + 6;
    size = Size(math.max(40, size.width - gutter), size.height);
    final pad = (hi - lo) * .08;
    if (!bars) lo -= pad;
    hi += pad;
    if (hi - lo < 1e-9) hi = lo + 1;
    final n = values.length;
    double y(double v) => size.height - (size.height) * (v - lo) / (hi - lo);
    double x(int i) => bars ? size.width * (i + .5) / n : (n == 1 ? size.width / 2 : size.width * i / (n - 1));
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    if (u != null && band && u.lo != null && u.hi != null) {
      canvas.drawRect(Rect.fromLTRB(0, y(u.hi!), size.width, y(u.lo!)), Paint()..color = bandColor);
    }
    if (bars) {
      final w = size.width / n * .62;
      for (final (j, (i, v)) in pts.indexed) {
        final r = RRect.fromRectAndRadius(
          Rect.fromLTRB(x(i) - w / 2, y(v), x(i) + w / 2, y(math.max(lo, 0))),
          const Radius.circular(3),
        );
        canvas.drawRRect(r, Paint()..color = j == pts.length - 1 && i == n - 1 ? last : line);
      }
    } else {
      final path = Path();
      for (final (j, (i, v)) in pts.indexed) {
        j == 0 ? path.moveTo(x(i), y(v)) : path.lineTo(x(i), y(v));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      for (final (i, v) in pts) {
        canvas.drawCircle(Offset(x(i), y(v)), 2.2, Paint()..color = line);
      }
      final (li, lv) = pts.last;
      canvas.drawCircle(Offset(x(li), y(lv)), 5, Paint()..color = last);
    }
    // Asteikko: suurin, tavallinen ja pienin; päällekkäiset (alle 12 px) jätetään pois.
    final placed = <double>[];
    for (final (k, v) in marks.indexed) {
      final yy = y(v);
      if (placed.any((p) => (p - yy).abs() < 12)) continue;
      placed.add(yy);
      final t = tps[k];
      t.paint(canvas, Offset(size.width + 6, (yy - t.height / 2).clamp(0, size.height + 4 - t.height)));
      if (k != 1 || u == null) {
        // Ohut apuviiva suurimmalle ja pienimmälle.
        canvas.drawLine(
          Offset(0, yy),
          Offset(size.width, yy),
          Paint()
            ..color = grid.withValues(alpha: .35)
            ..strokeWidth = .6,
        );
      }
    }
    if (u != null) {
      // Tavallinen taso katkoviivana.
      final p = Paint()
        ..color = grid
        ..strokeWidth = 1.2;
      final yy = y(u.mid);
      for (var xx = 0.0; xx < size.width; xx += 8) {
        canvas.drawLine(Offset(xx, yy), Offset(math.min(xx + 4, size.width), yy), p);
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values || old.bars != bars || old.last != last || old.usual != usual;
}
