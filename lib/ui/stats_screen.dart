import 'package:flutter/material.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../insights.dart';
import '../models.dart';
import '../running.dart';
import '../stats.dart';
import '../theme.dart';
import 'running_screen.dart';
import 'widgets.dart';
import '../l10n.dart';

/// ☰ → Edistyminen ja tilastot.
/// Edistyminen ja tilastot. [kind]: aloitusnäkymä 'all' (kaikki), 'gym' tai 'cardio'.
class StatsScreen extends StatefulWidget {
  final String? kind;
  const StatsScreen({super.key, this.kind});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _month = false;
  int _offset = 0; // 0 = tämä jakso, 1 = edellinen …
  late String _kind = widget.kind ?? (settings.trainMode == 'cardio' ? 'cardio' : 'all');

  (DateTime, DateTime) _period(int back) {
    final today = dateOnly(DateTime.now());
    if (_month) {
      final m = DateTime(today.year, today.month - back);
      return (m, nextMonth(m));
    }
    final w = addDays(weekStart(today), -7 * back);
    return (w, addDays(w, 7));
  }

  String _label(DateTime a, DateTime b) {
    if (_month) {
      final m = uiMonth(a.month);
      return '${isEnglish ? m : m.toLowerCase()} ${a.year}';
    }
    final e = addDays(b, -1);
    return t('viikko {0}.{1}.–{2}.{3}.', [a.day, a.month, e.day, e.month]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final ws = store.workouts;
    final (a, b) = _period(_offset);
    final (pa, pb) = _period(_offset + 1);
    // Suodatin näkyy, kun käytössä on sekä sali että kestävyys (asetus tai historia).
    final hasGym = ws.any((w) => w.activity == null && w.exercises.isNotEmpty);
    final hasCardio = ws.any((w) => w.activity != null);
    final showKind = settings.trainMode == 'both' || (hasGym && hasCardio);
    final kind = showKind ? _kind : (hasCardio && !hasGym ? 'cardio' : 'gym');
    final r = recap(ws, a, b, kind: kind), p = recap(ws, pa, pb, kind: kind);
    final weekly = weeklyCounts(ws, dateOnly(DateTime.now()));
    final today = dateOnly(DateTime.now());
    final fs = feelingStats(ws, today);
    final tips = feelingSuggestions(ws, today);
    final lifts = liftTrends(ws, today);

    String delta(num now, num prev, {String unit = ''}) {
      if (prev == 0) return '';
      final d = now - prev;
      if (d == 0) return '=';
      return '${d > 0 ? '↑' : '↓'} ${fmtNum(d.abs().toDouble().roundToDouble())}$unit';
    }

    Widget tile(String value, String label, String d) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: sub, maxLines: 1),
            ),
            // Muutosrivi aina paikallaan, jotta rivin ruudut ovat yhtä korkeita.
            Text(d.isEmpty ? ' ' : d, style: TextStyle(fontSize: 11, color: d.startsWith('↓') ? Sami.red : Sami.green)),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t('Edistyminen ja tilastot'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          // Juoksulla oma kehitysnäkymä (ei sekoitu salin edistymiseen).
          if (runsOf(ws).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                child: ListTile(
                  leading: const Text('🏃', style: TextStyle(fontSize: 26)),
                  title: Text(t('Juoksun kehitys')),
                  subtitle: Text(t('Kilometrit, vauhti, ennätykset ja lenkkityypit'), style: sub),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RunningScreen())),
                ),
              ),
            ),
          if (showKind) ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'all',
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Kaikki'), maxLines: 1)),
                ),
                ButtonSegment(
                  value: 'gym',
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Sali'), maxLines: 1)),
                ),
                ButtonSegment(
                  value: 'cardio',
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Kestävyys'), maxLines: 1)),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(t('Viikko'))),
                  ButtonSegment(value: true, label: Text(t('Kuukausi'))),
                ],
                selected: {_month},
                onSelectionChanged: (v) => setState(() {
                  _month = v.first;
                  _offset = 0;
                }),
              ),
              const Spacer(),
              IconButton(onPressed: () => setState(() => _offset++), icon: const Icon(Icons.chevron_left)),
              IconButton(
                onPressed: _offset == 0 ? null : () => setState(() => _offset--),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Text(_label(a, b), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(_month ? t('Vertailu edelliseen kuukauteen') : t('Vertailu edelliseen viikkoon'), style: sub),
          const SizedBox(height: 10),
          if (kind != 'cardio') ...[
            Row(
              children: [
                tile('${r.sessions}', kind == 'all' ? t('treeniä') : t('salitreeniä'), delta(r.sessions, p.sessions)),
                const SizedBox(width: 6),
                tile(
                  r.minutes == 0 ? '–' : _hours(r.minutes),
                  t('aikaa'),
                  delta(r.minutes / 60, p.minutes / 60, unit: ' h'),
                ),
                const SizedBox(width: 6),
                tile(r.feeling == null ? '–' : feelingOf(r.feeling!.round())!.$2, t('fiilis keskimäärin'), ''),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                tile('${r.sets}', t('sarjaa'), delta(r.sets, p.sets)),
                const SizedBox(width: 6),
                tile(
                  r.volume == 0 ? '–' : _vol(r.volume),
                  t('volyymi'),
                  p.volume == 0 || r.volume == p.volume
                      ? delta(r.volume, p.volume)
                      : '${r.volume > p.volume ? '↑' : '↓'} ${_vol((r.volume - p.volume).abs())}',
                ),
                const SizedBox(width: 6),
                tile('${r.prs}', t('ennätystä'), ''),
              ],
            ),
          ],
          if (kind != 'gym') ...[
            if (kind == 'all') const SizedBox(height: 6),
            Row(
              children: [
                if (kind == 'cardio') ...[
                  tile('${r.activities}', t('kertaa'), delta(r.activities, p.activities)),
                  const SizedBox(width: 6),
                  tile(
                    r.minutes == 0 ? '–' : _hours(r.minutes),
                    t('aikaa'),
                    delta(r.minutes / 60, p.minutes / 60, unit: ' h'),
                  ),
                  const SizedBox(width: 6),
                ],
                tile(
                  r.km == 0 ? '–' : '${fmtNum((r.km * 10).round() / 10)} km',
                  t('matka'),
                  delta(r.km, p.km, unit: ' km'),
                ),
                const SizedBox(width: 6),
                tile(r.hrAvg == null ? '–' : '${r.hrAvg}', t('keskisyke'), ''),
                if (kind == 'all') ...[const SizedBox(width: 6), tile(r.kcal == 0 ? '–' : '${r.kcal}', 'kcal', '')],
              ],
            ),
          ],
          if (kind == 'cardio' && r.kcal > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '🔥 ${t('Kalorit kellosta {0} kcal', [r.kcal])}${p.kcal > 0 ? ' ${t('(edellinen {0})', [p.kcal])}' : ''}',
                style: sub,
              ),
            ),
          // Kaikki: sali ja kestävyys rinnakkain (kerrat ja aika).
          if (kind == 'all' && r.sessions > 0) ...[
            const SizedBox(height: 10),
            _Split(gym: r.gym, cardio: r.activities, gymMinutes: r.gymMinutes, cardioMinutes: r.cardioMinutes),
          ],
          if (kind != 'gym' && r.sports.isNotEmpty) ...[
            SectionLabel(t('Lajeittain')),
            for (final e in (r.sports.entries.toList()..sort((x, y) => y.value.count.compareTo(x.value.count))))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(sportName(e.key))),
                    Text(
                      [
                        t('{0} krt', [e.value.count]),
                        if (e.value.minutes > 0) _hours(e.value.minutes),
                        if (e.value.km > 0) '${fmtNum((e.value.km * 10).round() / 10)} km',
                      ].join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
          SectionLabel(t('Treenit viikoittain (12 viikkoa)')),
          _StackBars(weeks: weekly, kind: kind),
          if (tips.isNotEmpty) ...[
            SectionLabel(t('Huomiot ja ehdotukset')),
            for (final tip in tips)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Sami.yellow.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: const Border(left: BorderSide(color: Sami.yellow, width: 4)),
                ),
                child: Text(tip, style: const TextStyle(fontSize: 13)),
              ),
          ],
          SectionLabel(t('Fiilis viikoittain (12 viikkoa)')),
          if (fs.count == 0)
            Text(t('Merkitse treenin lopuksi "Miltä tuntui?", niin näet täällä, miten treenit tuntuvat.'), style: sub)
          else ...[
            _Bars(
              values: [for (final (_, v, _) in fs.weekly) v],
              labels: [for (final (d, _, _) in fs.weekly) numDate(d)],
              max: 5,
            ),
            const SizedBox(height: 4),
            Text(t('Asteikko 1 = 😫 raskas … 5 = 🤩 loistava. Keskiarvo {0}.', [fmtDec(fs.overall!, 1)]), style: sub),
            SectionLabel(t('Viikonpäivittäin')),
            _Bars(
              values: [for (final d in weekdayNames) fs.byWeekday.where((g) => g.label == d).firstOrNull?.avg ?? 0],
              labels: uiWeekdaysShort,
              max: 5,
            ),
            if (fs.byDay.isNotEmpty) ...[
              SectionLabel(t('Treeneittäin')),
              for (final g in fs.byDay.reversed) _row(context, g),
            ],
            if (fs.byExercise.isNotEmpty) ...[
              SectionLabel(t('Raskaimmilta tuntuvat liikkeet')),
              for (final g in fs.byExercise.take(5)) _row(context, g),
            ],
          ],
          if (lifts.isNotEmpty) ...[
            SectionLabel(t('Voimakehitys (arvioitu maksimi, 6 kk)')),
            for (final lt in lifts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(width: 130, child: Text(exerciseLabel(lt.exercise), style: const TextStyle(fontSize: 13))),
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: CustomPaint(painter: _Spark([for (final m in lt.monthly) m.$2])),
                      ),
                    ),
                    SizedBox(
                      width: 78,
                      child: Text(
                        '${fmtNum(lt.monthly.last.$2.roundToDouble())} kg'
                        '${lt.light
                            ? '\n${t('kevyt jakso')}'
                            : lt.change == null
                            ? ''
                            : '\n${lt.change! >= 0 ? '+' : ''}${(lt.change! * 100).round()} %'}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: lt.light
                              ? cs.onSurfaceVariant
                              : (lt.change ?? 0) < 0
                              ? Sami.red
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, FeelingGroup g) {
    final f = feelingOf(g.avg.round());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(g.label)),
          Text('${f?.$2 ?? ''} ${fmtDec(g.avg, 1)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(
            width: 52,
            child: Text(
              t('{0} krt', [g.n]),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pylväät 0..max, väri fiiliksen mukaan.
class _Bars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final double max;
  const _Bars({required this.values, required this.labels, required this.max});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (values[i] > 0) Text(fmtDec(values[i], 1), style: const TextStyle(fontSize: 9)),
                    Container(
                      height: 80 * clamp01(values[i] / max),
                      decoration: BoxDecoration(
                        color: values[i] >= 3.5 ? Sami.green : (values[i] >= 2.5 ? Sami.yellow : Sami.red),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(labels[i], style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant), maxLines: 1),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Spark extends CustomPainter {
  final List<double> v;
  _Spark(this.v);
  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) {
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 3, Paint()..color = Sami.blue);
      return;
    }
    final lo = v.reduce((a, b) => a < b ? a : b), hi = v.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 1e-6 ? 1 : hi - lo;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - (v[i] - lo) / span * (size.height - 4) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Sami.blue
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _Spark old) => old.v != v;
}

/// Volyymi: alle tonni kiloina (562 kg), muuten tonneina yhdellä desimaalilla (1,2 t / 14 t).
String _vol(num kg) {
  if (kg < 1000) return '${fmtNum(kg.roundToDouble())} kg';
  final t = kg / 1000;
  return t < 10 ? '${fmtDec(t, 1)} t' : '${fmtNum(t.roundToDouble())} t';
}

/// Tunnit: "1,5 h" / "45 min".
String _hours(int minutes) => minutes < 60 ? '$minutes min' : '${fmtDec(minutes / 60, 1)} h';

/// Sali ja kestävyys rinnakkain: kerrat ja aika, palkki osuuksista (ajan mukaan, jos aika on kirjattu).
class _Split extends StatelessWidget {
  final int gym, cardio, gymMinutes, cardioMinutes;
  const _Split({required this.gym, required this.cardio, required this.gymMinutes, required this.cardioMinutes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final byTime = gymMinutes + cardioMinutes > 0;
    final g = byTime ? gymMinutes : gym, c = byTime ? cardioMinutes : cardio;
    final total = g + c;
    Widget side(String icon, String label, int n, int mins, Color color, CrossAxisAlignment align) => Column(
      crossAxisAlignment: align,
      children: [
        Text('$icon $label', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        Text(
          '${t('{0} krt', [n])}${mins > 0 ? ' · ${_hours(mins)}' : ''}',
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              side('🏋', t('Sali'), gym, gymMinutes, Sami.red, CrossAxisAlignment.start),
              side('🏃', t('Kestävyys'), cardio, cardioMinutes, Sami.green, CrossAxisAlignment.end),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (g > 0)
                    Expanded(
                      flex: g,
                      child: Container(color: Sami.red),
                    ),
                  if (c > 0)
                    Expanded(
                      flex: c,
                      child: Container(color: Sami.green),
                    ),
                  if (total == 0) Expanded(child: Container(color: cs.outlineVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Treenit viikoittain: pinotut pylväät, sali punainen ja kestävyys vihreä. [kind] rajaa näytettävät.
class _StackBars extends StatelessWidget {
  final List<(DateTime, int, int)> weeks;
  final String kind;
  const _StackBars({required this.weeks, required this.kind});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    int g(int i) => kind == 'cardio' ? 0 : weeks[i].$2;
    int c(int i) => kind == 'gym' ? 0 : weeks[i].$3;
    final top = [for (var i = 0; i < weeks.length; i++) g(i) + c(i)].fold(0, (a, b) => a > b ? a : b);
    final max = top < 3 ? 3 : top;
    final label = TextStyle(fontSize: 9, color: cs.onSurfaceVariant);
    Widget legend(Color col, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: col, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < weeks.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (g(i) + c(i) > 0) Text('${g(i) + c(i)}', style: const TextStyle(fontSize: 9)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Column(
                            children: [
                              if (c(i) > 0) Container(height: 80 * c(i) / max, color: Sami.green),
                              if (g(i) > 0) Container(height: 80 * g(i) / max, color: Sami.red),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(numDate(weeks[i].$1), style: label, maxLines: 1),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          children: [
            if (kind != 'cardio') legend(Sami.red, t('Sali')),
            if (kind != 'gym') legend(Sami.green, t('Kestävyys')),
          ],
        ),
      ],
    );
  }
}
