import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../session_compare.dart' show fmtDuration;
import '../sleep.dart';
import '../theme.dart';
import 'home_extras_ui.dart' show NightHrData, SleepCard;
import 'recovery_stats.dart';
import 'sleep_stages_ui.dart' show showSleepStagesSheet;
import 'widgets.dart';

// Tilastot → Uni ja palautuminen (käyttäjä 23.11.): sama jakson valinta kuin Kehityksessä ja Askeleissa. Näkyy vain,
// kun Uni-, Palautuminen- tai yöarvokortti on käytössä (pelkkä treenaaja ei näe välilehteä). Unen kesto uni.md:stä,
// univaiheet luetaan Health Connectista näytettäessä (ei tallenneta).

/// Jakson arvojen keskiarvo [from, to), null = ei arvoja.
double? periodAvg(DaySeries d, DateTime from, DateTime to) {
  final v = [
    for (final e in d.entries)
      if (!e.key.isBefore(from) && e.key.isBefore(to)) e.value,
  ];
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}

class SleepRecoveryStatsView extends StatefulWidget {
  final DateTime from, to, prevFrom, prevTo;
  final List<Widget> header;

  /// Testeille: univaiheiden lähde (oletus Health Connect).
  final Future<List<SleepSession>> Function(DateTime, DateTime)? source;
  const SleepRecoveryStatsView({
    super.key,
    required this.from,
    required this.to,
    required this.prevFrom,
    required this.prevTo,
    this.header = const [],
    this.source,
  });

  @override
  State<SleepRecoveryStatsView> createState() => _SleepRecoveryStatsViewState();
}

class _SleepRecoveryStatsViewState extends State<SleepRecoveryStatsView> {
  Future<(SleepStages, int)>? _stages;
  String _stagesFor = '';

  /// Jakson univaiheet haetaan kerran jaksoa ja öitä kohden (ei joka piirrolla).
  Future<(SleepStages, int)> _stagesOf(List<SleepNight> ns) {
    final k = '${widget.from}|${widget.to}|${ns.length}|${ns.lastOrNull?.app}';
    if (_stages == null || k != _stagesFor) {
      _stagesFor = k;
      _stages = periodStages(ns, source: widget.source).catchError((_) => (const SleepStages(), 0));
    }
    return _stages!;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([sleepData, NightHrData.nights, settings]),
    builder: (context, _) {
      final cs = Theme.of(context).colorScheme;
      final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
      final goal = Duration(minutes: settings.sleepGoal);
      final p = sleepPeriod(sleepData.nights, widget.from, widget.to, goal: goal);
      final prev = sleepPeriod(sleepData.nights, widget.prevFrom, widget.prevTo, goal: goal);
      return ListView(
        key: const ValueKey('sleepStatsTab'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ...widget.header,
          if (sleepData.enabled) ...[
            SectionLabel(t('Uni')),
            if (p.nights.isEmpty)
              Text(t('Ei öitä tällä jaksolla.'), style: sub)
            else ...[
              _summary(context, p, prev, goal),
              const SizedBox(height: 12),
              _NightBars(nights: p.nights, all: sleepData.nights),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t('Napauta yötä: sen univaiheet. Väri kuten Uni-kortissa, katkoviiva on unitavoitteesi.'),
                  style: sub,
                ),
              ),
              _stagesSection(context, p.nights),
              SectionLabel(t('Pisin ja lyhin yö')),
              _nightTile(context, p.longest!, Icons.arrow_upward),
              if (p.shortest != p.longest) _nightTile(context, p.shortest!, Icons.arrow_downward),
            ],
          ],
          _recoverySection(context),
          // 12 viikon kehitys (ennen Kehitys-välilehdellä).
          const RecoveryTrendsSection(),
        ],
      );
    },
  );

  Widget _summary(BuildContext context, SleepPeriod p, SleepPeriod prev, Duration goal) {
    String clock(int m) => fmtClock(TimeOfDay(hour: m ~/ 60, minute: m % 60));
    final cmp = prev.avg == null ? null : t('edellinen jakso {0}', [fmtDuration(prev.avg!.inMinutes)]);
    final blue = blueText(context);
    final spread = p.spread;
    final spreadColor = spread == null
        ? blue
        : spread <= 30
        ? greenText(context)
        : spread <= 90
        ? SleepCard.amber(context)
        : redText(context);
    final share = p.belowGoal / p.nights.length;
    List<Widget> tilesFor(double lw) => <Widget>[
      _Stat(
        fmtDuration(p.avg!.inMinutes),
        t('keskimäärin yössä'),
        labelWidth: lw,
        icon: Icons.bedtime_outlined,
        accent: SleepCard.durationColor(context, p.avg!, goal),
        note: cmp,
        key: const ValueKey('sleepAvg'),
      ),
      _Stat(
        '${p.nights.length}',
        p.nights.length == 1 ? t('yö') : t('yötä'),
        labelWidth: lw,
        icon: Icons.nights_stay_outlined,
        accent: blue,
      ),
      _Stat(clock(p.bedMin!), t('nukkumaan keskimäärin'), labelWidth: lw, icon: Icons.king_bed_outlined, accent: blue),
      _Stat(clock(p.wakeMin!), t('herätys keskimäärin'), labelWidth: lw, icon: Icons.wb_twilight, accent: blue),
      if (spread != null)
        _Stat('±$spread', t('säännöllisyys, min'), labelWidth: lw, icon: Icons.schedule, accent: spreadColor),
      _Stat(
        '${p.belowGoal} / ${p.nights.length}',
        t('alle tavoitteen ({0})', [fmtDuration(goal.inMinutes)]),
        labelWidth: lw,
        icon: Icons.flag_outlined,
        accent: share <= .25
            ? greenText(context)
            : share <= .5
            ? SleepCard.amber(context)
            : redText(context),
      ),
    ];
    // Tasainen kahden sarakkeen ruudukko, rivin ruudut yhtä korkeat (käyttäjä 23.11.).
    return LayoutBuilder(
      builder: (context, c) {
        // Nimen leveys: puolikas miinus väli, reunukset, väripalkki ja kuvake.
        final tiles = tilesFor((c.maxWidth - 8) / 2 - 20 - 14 - 20);
        return Column(
          children: [
            for (var k = 0; k < tiles.length; k += 2)
              Padding(
                padding: EdgeInsets.only(top: k == 0 ? 0 : 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: tiles[k]),
                      const SizedBox(width: 8),
                      Expanded(child: k + 1 < tiles.length ? tiles[k + 1] : const SizedBox.shrink()),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _stagesSection(BuildContext context, List<SleepNight> ns) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return FutureBuilder<(SleepStages, int)>(
      future: _stagesOf(ns),
      builder: (context, snap) {
        final children = <Widget>[SectionLabel(t('Univaiheet keskimäärin yössä'))];
        if (snap.connectionState != ConnectionState.done) {
          children.add(Text(t('Haetaan univaiheita…'), style: sub));
        } else {
          final (s, n) = snap.data ?? (const SleepStages(), 0);
          if (n == 0) {
            children.add(
              Text(
                t(
                  'Tämän jakson öille ei ole univaiheita Health Connectissa. Yli 30 päivää vanhoihin tarvitaan '
                  'historialupa.',
                ),
                style: sub,
              ),
            );
          } else {
            Duration per(Duration d) => Duration(milliseconds: d.inMilliseconds ~/ n);
            final total = s.asleep.inMinutes;
            String pct(Duration d) => total <= 0 ? '' : ' · ${(d.inMinutes * 100 / total).round()} %';
            Widget row(String label, Duration d, {bool share = true}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => WordFitText(label, style: const TextStyle(), width: c.maxWidth),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Suurella tekstillä arvo pienenee mahtuakseen (ei ylivuotoa).
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        '${fmtDuration(per(d).inMinutes)}${share ? pct(d) : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            );
            children.addAll([
              if (s.light > Duration.zero) row(t('Kevyt uni'), s.light),
              if (s.deep > Duration.zero) row(t('Syvä uni'), s.deep),
              if (s.rem > Duration.zero) row(t('REM-uni'), s.rem),
              if (s.sleeping > Duration.zero) row(t('Uni, vaihe ei tiedossa'), s.sleeping),
              row(t('Univaiheet yhteensä'), s.asleep, share: false),
              row(t('Hereillä'), s.awake, share: false),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t('{0} / {1} yöstä vaiheet Health Connectissa.', [n, ns.length]), style: sub),
              ),
            ]);
          }
        }
        return Column(
          key: const ValueKey('periodStages'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  Widget _nightTile(BuildContext context, SleepNight n, IconData icon) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
    title: Text(fmtDuration(n.asleep.inMinutes), style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(
      '${shortDate(n.day)} · ${fmtClock(TimeOfDay.fromDateTime(n.bed))}–${fmtClock(TimeOfDay.fromDateTime(n.wake))}',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showSleepStagesSheet(context, n),
  );

  /// Palautumisen arvot jakson keskiarvoina ja edelliseen jaksoon verrattuna.
  Widget _recoverySection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (final s in allRecoverySeries()) {
      if (s.key == 'sleep') continue;
      final now = periodAvg(s.data, widget.from, widget.to);
      if (now == null) continue;
      final before = periodAvg(s.data, widget.prevFrom, widget.prevTo);
      // Jakson yöt käyränä (käyttäjä 23.11.): päivä kerrallaan, puuttuvat yöt aukkoina.
      final today = dateOnly(DateTime.now());
      final end = widget.to.isAfter(addDays(today, 1)) ? addDays(today, 1) : widget.to;
      final n = math.max(1, daysBetween(widget.from, end));
      final days = [for (var i = 0; i < n; i++) s.data[addDays(widget.from, i)]];
      rows.add(
        Container(
          key: ValueKey('periodRec_${s.key}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(s.icon, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => WordFitText(
                        s.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        width: c.maxWidth,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: nb(s.fmt(now)),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (before != null)
                              TextSpan(
                                text: '  ${t('ed. {0}', [nb(s.fmt(before))])}',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ExcludeSemantics(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _DayLine(
                      days,
                      avg: now,
                      fmt: s.fmt,
                      line: blueText(context),
                      grid: cs.onSurface.withValues(alpha: .16),
                      avgColor: cs.onSurfaceVariant,
                      label: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(shortDate(widget.from), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ),
                  Text(shortDate(addDays(end, -1)), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Palautuminen jaksolla')),
        ...rows,
        Text(
          t('Yöt jakson ajalta, katkoviiva on jakson keskiarvo; ed. = edellinen yhtä pitkä jakso.'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  final String? note;
  final IconData icon;
  final Color accent;
  final double labelWidth; // nimen leveys (IntrinsicHeight ei salli LayoutBuilderia ruudun sisällä)
  const _Stat(
    this.value,
    this.label, {
    required this.icon,
    required this.accent,
    this.note,
    this.labelWidth = double.infinity,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Sama tyyli kuin Palautuminen-ruuduissa: neutraali pinta, värillinen palkki vasemmalla. Ruudunlukija lukee
    // ruudun yhtenä: nimi ja arvo (testi 23.11.).
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withValues(alpha: .07) : Colors.black.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              margin: const EdgeInsets.only(right: 10, top: 2, bottom: 2),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(icon, size: 15, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: WordFitText(
                          label,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          width: labelWidth,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(note!, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), maxLines: 2),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Jakson yöt pylväinä (vanhin vasemmalla); napautus avaa yön univaiheet.
class _NightBars extends StatelessWidget {
  final List<SleepNight> nights;
  final Map<DateTime, SleepNight> all;
  const _NightBars({required this.nights, required this.all});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Asteikko tasatunteihin: vähintään 9 h, pisin yö mahtuu (käyttäjä 23.11.: vaakaviivat).
    final top = ((math.max(9 * 60, nights.map((n) => n.asleep.inMinutes).reduce(math.max)) + 59) ~/ 60) * 60;
    const h = 130.0, axis = 30.0;
    final goal = settings.sleepGoal;
    final gap = nights.length > 60 ? 0.5 : (nights.length > 20 ? 1.5 : 3.0);
    return Column(
      key: const ValueKey('nightBars'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: h,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: axis),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final n in nights)
                      Expanded(
                        // Ruudunlukija (testi 23.11.): päivä, kesto ja tavoitteen alitus; kaksoisnapautus avaa vaiheet.
                        child: Semantics(
                          button: true,
                          label: [
                            '${shortDate(n.day)}: ${fmtDuration(n.asleep.inMinutes)}',
                            if (n.asleep.inMinutes < settings.sleepGoal)
                              t('alle tavoitteen ({0})', [fmtDuration(settings.sleepGoal)]),
                          ].join(', '),
                          onTap: () => showSleepStagesSheet(context, n),
                          excludeSemantics: true,
                          child: GestureDetector(
                            key: ValueKey('nightBar_${isoDate(n.day)}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => showSleepStagesSheet(context, n),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                margin: EdgeInsets.symmetric(horizontal: gap / 2),
                                height: math.max(3, h * n.asleep.inMinutes / top),
                                decoration: BoxDecoration(
                                  color: SleepCard.durationColor(
                                    context,
                                    n.asleep,
                                    SleepCard.usualOf(sleepStats(all, n.day)),
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: _Grid(
                        top: top,
                        goal: goal,
                        axis: axis,
                        line: cs.onSurface.withValues(alpha: .16),
                        goalColor: cs.onSurfaceVariant,
                        label: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(shortDate(nights.first.day), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),
            Text(shortDate(nights.last.day), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(width: axis),
          ],
        ),
      ],
    );
  }
}

/// Pylväiden vaakaviivat tasatunnein (kahden tunnin välein, tunnit oikeassa reunassa) ja unitavoite katkoviivana.
class _Grid extends CustomPainter {
  final int top, goal;
  final double axis;
  final Color line, goalColor;
  final TextStyle label;
  _Grid({
    required this.top,
    required this.goal,
    required this.axis,
    required this.line,
    required this.goalColor,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - axis;
    double y(int m) => size.height - size.height * m / top;
    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var hr = 2; hr * 60 <= top; hr += 2) {
      final yy = y(hr * 60);
      canvas.drawLine(Offset(0, yy), Offset(w, yy), p);
      final tp = TextPainter(
        text: TextSpan(text: '$hr h', style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w + 4, (yy - tp.height / 2).clamp(0, size.height - tp.height)));
    }
    // Tavoite katkoviivana.
    final gy = y(goal);
    final gp = Paint()
      ..color = goalColor
      ..strokeWidth = 1.2;
    for (var x = 0.0; x < w; x += 8) {
      canvas.drawLine(Offset(x, gy), Offset(math.min(x + 4, w), gy), gp);
    }
  }

  @override
  bool shouldRepaint(_Grid old) => old.top != top || old.goal != goal || old.line != line;
}

/// Jakson yöt viivana: alin ja ylin yö ohuina viivoina arvoineen oikeassa reunassa, keskiarvo katkoviivana.
class _DayLine extends CustomPainter {
  final List<double?> v;
  final double avg;
  final String Function(double) fmt;
  final Color line, grid, avgColor;
  final TextStyle label;
  _DayLine(
    this.v, {
    required this.avg,
    required this.fmt,
    required this.line,
    required this.grid,
    required this.avgColor,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (var i = 0; i < v.length; i++)
        if (v[i] != null) (i, v[i]!),
    ];
    if (pts.isEmpty) return;
    var lo = pts.map((p) => p.$2).reduce(math.min), hi = pts.map((p) => p.$2).reduce(math.max);
    final flat = hi - lo < 1e-9;
    if (flat) {
      lo -= 1;
      hi += 1;
    }
    // Arvot oikeassa reunassa: tilaa pisimmälle.
    TextPainter tp(String s) => TextPainter(
      text: TextSpan(text: s, style: label),
      textDirection: TextDirection.ltr,
    )..layout();
    final hiT = tp(fmt(hi)), loT = tp(fmt(lo));
    final axis = math.max(hiT.width, loT.width) + 6;
    final w = size.width - axis;
    const pad = 6.0;
    double y(double x) => size.height - pad - (size.height - 2 * pad) * (x - lo) / (hi - lo);
    double xAt(int i) => v.length == 1 ? w / 2 : w * i / (v.length - 1);
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    if (!flat) {
      for (final (val, t) in [(hi, hiT), (lo, loT)]) {
        canvas.drawLine(Offset(0, y(val)), Offset(w, y(val)), gp);
        t.paint(canvas, Offset(w + 6, (y(val) - t.height / 2).clamp(0, size.height - t.height)));
      }
    }
    final ap = Paint()
      ..color = avgColor
      ..strokeWidth = 1.2;
    for (var x = 0.0; x < w; x += 8) {
      canvas.drawLine(Offset(x, y(avg)), Offset(math.min(x + 4, w), y(avg)), ap);
    }
    // Viiva katkeaa puuttuvan yön kohdalla.
    final p = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    Path? path;
    for (var i = 0; i < v.length; i++) {
      final val = v[i];
      if (val == null) {
        if (path != null) canvas.drawPath(path, p);
        path = null;
        continue;
      }
      final o = Offset(xAt(i), y(val));
      path == null ? (path = Path()..moveTo(o.dx, o.dy)) : path.lineTo(o.dx, o.dy);
    }
    if (path != null) canvas.drawPath(path, p);
    if (v.length <= 45) {
      for (final (i, val) in pts) {
        canvas.drawCircle(Offset(xAt(i), y(val)), 2.2, Paint()..color = line);
      }
    }
  }

  @override
  bool shouldRepaint(_DayLine old) => old.v != v || old.avg != avg || old.line != line;
}
