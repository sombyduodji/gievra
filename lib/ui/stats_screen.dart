import 'package:flutter/material.dart';

import '../app_state.dart';
import '../body.dart';
import '../exercises.dart';
import '../insights.dart';
import '../models.dart';
import '../program_edit.dart' show loggedSets;
import '../share_text.dart' show thousands;
import '../running.dart';
import '../stats.dart';
import '../theme.dart';
import 'program_view.dart' show WeeklyLoadCard;
import 'running_screen.dart';
import 'widgets.dart';
import 'steps_ui.dart';
import '../l10n.dart';

/// ☰ → Edistyminen ja tilastot.
/// Edistyminen ja tilastot. [kind]: aloitusnäkymä 'all' (kaikki), 'gym' tai 'cardio'.
class StatsScreen extends StatefulWidget {
  final String? kind;

  /// Avautuva välilehti: 'steps' = Askeleet (kun päivän askeleet ovat päällä), muuten Treenit.
  final String? tab;
  const StatsScreen({super.key, this.kind, this.tab});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _span = 'month'; // month (1 kk), quarter (3 kk), half (6 kk), custom (oma aikaväli)
  int _offset = 0; // 0 = tämä jakso, 1 = edellinen … (ei omalla aikavälillä)
  DateTime? _from, _to; // oma aikaväli, molemmat päivät mukaan
  late String _kind = widget.kind ?? (settings.trainMode == 'cardio' ? 'cardio' : 'all');

  /// Kuukausien määrä jaksossa; omalla aikavälillä 0.
  int get _months => switch (_span) {
    'quarter' => 3,
    'half' => 6,
    'month' => 1,
    _ => 0,
  };

  bool get _custom => _span == 'custom' && _from != null && _to != null;

  static int _days(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  /// Jakso [back] jakson päähän: kalenterikuukausi tai tämän kuun kanssa päättyvät 3 / 6 kuukautta. Oma aikaväli:
  /// [back] 1 = yhtä pitkä jakso juuri ennen (vertailu). Loppu on aina seuraava päivä (puoliavoin väli).
  (DateTime, DateTime) _period(int back) {
    final today = dateOnly(DateTime.now());
    if (_custom) {
      final len = _days(_from!, _to!) + 1;
      return (addDays(_from!, -len * back), addDays(_to!, 1 - len * back));
    }
    final end = DateTime(today.year, today.month + 1 - _months * back);
    return (DateTime(end.year, end.month - _months), end);
  }

  DateTime get _firstWorkout => store.workouts.isEmpty
      ? dateOnly(DateTime.now())
      : store.workouts.map((w) => w.date).reduce((a, b) => a.isBefore(b) ? a : b);

  static DateTime _clamp(DateTime d, DateTime lo, DateTime hi) => d.isBefore(lo) ? lo : (d.isAfter(hi) ? hi : d);

  /// Oman aikavälin valinta: alku ja loppu kalenterista tai pikapainikkeilla. null = peruttiin.
  Future<(DateTime, DateTime)?> _pickRange() {
    final today = dateOnly(DateTime.now());
    // Tulevaisuuteen päivätty treeni ei siirrä alkua tämän päivän jälkeen (kalenteri ei salli sitä).
    final first = _clamp(dateOnly(_firstWorkout), DateTime(1900), today);
    // Kalenterin rajat: ensimmäisestä treenistä (tai vuosi sitten) tähän päivään.
    final min = first.isBefore(DateTime(today.year - 1, today.month, today.day)) ? first : DateTime(today.year - 1);
    // Aiempi valinta rajojen sisään: vanhimmat treenit on voitu poistaa tai päivä vaihtunut.
    var from = _clamp(_from ?? first, min, today);
    var to = _clamp(_to ?? today, from, today);
    return showModalBottomSheet<(DateTime, DateTime)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final sub = TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant);
          Widget field(DateTime d, ValueChanged<DateTime> onPick) => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(numDate(d, year: true), style: const TextStyle(fontSize: 15)),
            onPressed: () async {
              final v = await pickDate(ctx, initial: d, first: min, last: today);
              if (v != null) set(() => onPick(dateOnly(v)));
            },
          );
          Widget quick(String label, bool on, VoidCallback tap) =>
              ChoiceChip(label: Text(label), selected: on, showCheckmark: false, onSelected: (_) => set(tap));
          final lastSunday = addDays(weekStart(today), -1);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('Oma aikaväli'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Text(t('Alkaen'), style: sub),
                  const SizedBox(height: 4),
                  // Alku loppua myöhemmin: loppu siirtyy mukana (ja päinvastoin), joten väli on aina kelvollinen.
                  field(from, (v) {
                    from = v;
                    if (to.isBefore(from)) to = from;
                  }),
                  const SizedBox(height: 6),
                  quick(t('Ensimmäisestä treenistä'), from == first, () {
                    from = first;
                    if (to.isBefore(from)) to = from;
                  }),
                  const SizedBox(height: 12),
                  Text(t('Päättyen'), style: sub),
                  const SizedBox(height: 4),
                  field(to, (v) {
                    to = v;
                    if (to.isBefore(from)) from = to;
                  }),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      quick(t('Tänään'), to == today, () {
                        to = today;
                      }),
                      quick(t('Viime viikon loppu'), to == lastSunday, () {
                        to = lastSunday;
                        if (to.isBefore(from)) from = to;
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: () => Navigator.pop(ctx, (from, to)), child: Text(t('Näytä'))),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _chooseCustom() async {
    final r = await _pickRange();
    if (r == null || !mounted) return;
    setState(() {
      _from = r.$1;
      _to = r.$2;
      _span = 'custom';
      _offset = 0;
    });
  }

  String _monthName(DateTime d) {
    final m = uiMonth(d.month);
    return '${isEnglish ? m : m.toLowerCase()} ${d.year}';
  }

  String _label(DateTime a, DateTime b) {
    if (_custom) return '${numDate(a, year: true)} – ${numDate(addDays(b, -1), year: true)}';
    if (_months == 1) return _monthName(a);
    if (_months > 1) return '${_monthName(a)} – ${_monthName(DateTime(b.year, b.month - 1))}';
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
    final hasGym = ws.any((w) => workoutKind(w) == 'gym');
    final hasCardio = ws.any((w) => workoutKind(w) == 'cardio');
    final showKind = settings.trainMode == 'both' || (hasGym && hasCardio);
    final kind = showKind ? _kind : (hasCardio && !hasGym ? 'cardio' : 'gym');
    final r = recap(ws, a, b, kind: kind), p = recap(ws, pa, pb, kind: kind);
    // Pylväät päättyvät valitun jakson loppuun: viikot (viikko, kuukausi) tai kuukaudet (6 kk, vuosi).
    final lastDay = addDays(b, -1);
    // 1 kk: 12 viikkoa, 3 kk: 13 viikkoa, 6 kk kuukausittain. Oma aikaväli: enintään noin 4 kk viikoittain,
    // enintään 2 vuotta kuukausittain, pidempi vuosittain (ei satoja ohuita pylväitä).
    final span = _days(a, b);
    // Yksi päivä yksikössä (englanniksi muuten "1 days").
    final days = span == 1 ? t('1 päivä') : t('{0} pv', [span]);
    // Omalla aikavälillä kaikki viikot, joihin väli osuu (myös maanantain yli menevä lyhyt väli).
    final weeksN = _custom ? _days(weekStart(a), weekStart(lastDay)) ~/ 7 + 1 : (_months == 3 ? 13 : 12);
    final monthsN = _custom ? (lastDay.year - a.year) * 12 + lastDay.month - a.month + 1 : _months;
    final bucket = _custom
        ? (span <= 126 ? 'week' : (monthsN <= 24 ? 'month' : 'year'))
        : (_months > 3 ? 'month' : 'week');
    final monthly = bucket == 'month';
    final bars = switch (bucket) {
      'year' => yearlyCounts(ws, a, lastDay),
      'month' => monthlyCounts(ws, lastDay, months: monthsN),
      _ => weeklyCounts(ws, lastDay, weeks: weeksN),
    };
    final hasEarlier = ws.any((w) => w.date.isBefore(a));
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
            // Muutosrivi aina paikallaan ja yhtä korkea (myös korostettu lasku), jotta rivin ruudut ovat yhtä korkeita.
            SizedBox(
              height: 19,
              child: Center(
                child: d.startsWith('↓')
                    ? RedNote(d, pill: true)
                    : Text(d.isEmpty ? ' ' : d, style: TextStyle(fontSize: 11, color: greenText(context))),
              ),
            ),
          ],
        ),
      ),
    );

    // Jakson valinta ja nimi: yhteiset Treenit- ja Askeleet-välilehdille (sama jakso molemmissa).
    final periodControls = <Widget>[
      const SizedBox(height: 12),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final (v, l) in [('month', t('1 kk')), ('quarter', t('3 kk')), ('half', t('6 kk'))])
            ButtonSegment(
              value: v,
              label: FittedBox(fit: BoxFit.scaleDown, child: Text(l, maxLines: 1)),
            ),
          ButtonSegment(
            value: 'custom',
            icon: const Icon(Icons.calendar_month_outlined, size: 16),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Oma'), maxLines: 1)),
          ),
        ],
        selected: {_custom ? 'custom' : _span},
        // Oma: valitaan aikaväli; peruttaessa edellinen jakso jää voimaan. Uudelleen napautus avaa valinnan.
        onSelectionChanged: (v) => v.first == 'custom'
            ? _chooseCustom()
            : setState(() {
                _span = v.first;
                _offset = 0;
              }),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: Text(_label(a, b), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          if (_custom)
            IconButton(
              tooltip: t('Muuta aikaväliä'),
              onPressed: _chooseCustom,
              icon: const Icon(Icons.edit_calendar_outlined),
            )
          else ...[
            IconButton(onPressed: () => setState(() => _offset++), icon: const Icon(Icons.chevron_left)),
            IconButton(
              onPressed: _offset == 0 ? null : () => setState(() => _offset--),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ],
      ),
      if (_custom)
        Text(
          _from == dateOnly(_firstWorkout) && _to == today
              ? t('Ensimmäisestä treenistä tähän päivään · {0}', [days])
              : days,
          style: sub,
        ),
      Text(switch (_span) {
        _ when _custom =>
          hasEarlier ? t('Vertailu yhtä pitkään jaksoon ennen') : t('Ei vertailua: ennen jaksoa ei ole treenejä'),
        'quarter' => t('Vertailu edelliseen 3 kuukauteen'),
        'half' => t('Vertailu edelliseen 6 kuukauteen'),
        _ => t('Vertailu edelliseen kuukauteen'),
      }, style: sub),
    ];

    final workoutsBody = ListView(
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
        ...periodControls,
        const SizedBox(height: 10),
        if (kind != 'cardio') ...[
          Row(
            children: [
              tile('${r.sessions}', kind == 'all' ? t('treeniä') : t('salitreeniä'), delta(r.sessions, p.sessions)),
              const SizedBox(width: 6),
              tile(
                r.minutes == 0 ? '–' : _hours(r.minutes),
                _timeLabel(r),
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
          // Erikoissarjat erikseen, vain kun niitä on.
          if (r.dropSets + r.amrapSets > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  if (r.dropSets > 0) t('pudotussarjoja {0}', [r.dropSets]),
                  if (r.amrapSets > 0) t('AMRAP-sarjoja {0}', [r.amrapSets]),
                ].join(' · '),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
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
                  _timeLabel(r),
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
                      if (e.value.steps > 0) t('{0} askelta', [thousands(e.value.steps)]),
                    ].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
        SectionLabel(switch (bucket) {
          'year' => t('Treenit vuosittain ({0} v)', [bars.length]),
          'month' => t('Treenit kuukausittain ({0} kk)', [monthsN]),
          _ when _custom && weeksN == 1 => t('Treenit viikoittain (1 viikko)'),
          _ when _custom => t('Treenit viikoittain ({0} viikkoa)', [weeksN]),
          _ => _months == 3 ? t('Treenit viikoittain (13 viikkoa)') : t('Treenit viikoittain (12 viikkoa)'),
        }),
        _StackBars(weeks: bars, kind: kind, monthly: monthly, yearly: bucket == 'year'),
        // Ohjelman viikon kuorma: suunniteltu ja toteutunut lihasryhmittäin. Viikolla valitun viikon sarjat,
        // pidemmällä jaksolla keskimäärin viikossa (kuluvasta jaksosta vain tähän päivään asti).
        if (kind != 'cardio' && settings.program != null) ...[
          const SizedBox(height: 14),
          WeeklyLoadCard(
            program: settings.program!,
            done: () {
              final end = b.isAfter(today) ? addDays(today, 1) : b;
              final sets = loggedSets(ws, a, end);
              final weeks = (end.difference(a).inDays / 7).clamp(1.0, 100000.0);
              return {for (final e in sets.entries) e.key: (e.value / weeks * 10).round() / 10};
            }(),
            doneLabel: t('toteutunut, keskimäärin viikossa'),
          ),
        ],
        if (settings.bodyTracker) _BodySection(from: _span == 'month' && !_custom ? addDays(b, -84) : a, to: b),
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
                            ? redText(context)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
    // Päivän askeleet päällä: Treenit- ja Askeleet-välilehdet, sama jakso molemmissa.
    if (!stepsTabAvailable) {
      return Scaffold(
        appBar: AppBar(title: Text(t('Edistyminen ja tilastot'))),
        body: workoutsBody,
      );
    }
    return DefaultTabController(
      length: 2,
      initialIndex: widget.tab == 'steps' ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Edistyminen ja tilastot')),
          bottom: TabBar(
            tabs: [
              Tab(text: t('Treenit')),
              Tab(text: t('Askeleet')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            workoutsBody,
            StepsStatsView(from: a, to: b, prevFrom: pa, prevTo: pb, header: periodControls),
          ],
        ),
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
              side('🏋', t('Sali'), gym, gymMinutes, redText(context), CrossAxisAlignment.start),
              side('🏃', t('Kestävyys'), cardio, cardioMinutes, greenText(context), CrossAxisAlignment.end),
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
  final bool monthly; // pylväs = kuukausi (6 kk tai oma aikaväli), muuten viikko
  final bool yearly; // pylväs = vuosi (pitkä oma aikaväli)
  const _StackBars({required this.weeks, required this.kind, this.monthly = false, this.yearly = false});

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
                        Text(
                          yearly
                              ? '${weeks[i].$1.year}'
                              : monthly
                              ? _monthShort(weeks[i].$1.month)
                              : numDate(weeks[i].$1),
                          style: label,
                          maxLines: 1,
                        ),
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

/// Kuukauden lyhenne pylvään alle: "mar" / "Nov" / "skáb".
String _monthShort(int m) {
  if (isEnglish) return uiMonth(m).substring(0, 3);
  if (isSami) return uiMonth(m).substring(0, 4);
  const fi = ['tam', 'hel', 'maa', 'huh', 'tou', 'kes', 'hei', 'elo', 'syy', 'lok', 'mar', 'jou'];
  return fi[m - 1];
}

/// Kehonpaino jaksolta (vähintään 12 viikkoa): nykyinen paino, muutos, painoindeksi ja käyrä.
/// Punnitusten korjaus: ☰ → Asetukset → Paino ja pituus.
class _BodySection extends StatelessWidget {
  final DateTime from, to;
  const _BodySection({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final all = weightSeries(settings.body, store.workouts);
    final h = settings.body.heightCm;
    if (all.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(t('Kehonpaino')),
          Text(t('Ei vielä punnituksia. Lisää paino etusivulta tai ☰ → Asetukset → Paino ja pituus.'), style: sub),
        ],
      );
    }
    final pts = all.where((e) => !e.$1.isBefore(from) && e.$1.isBefore(to)).toList();
    final last = all.where((e) => e.$1.isBefore(to)).lastOrNull ?? all.last;
    // Muutos jakson aikana: jakson ensimmäisestä punnituksesta viimeiseen. Jos jaksolla on vain yksi punnitus,
    // verrataan sitä edeltävään (jakson ulkopuoliseen) punnitukseen.
    final change = weightChange(all, from, to);
    Widget tile(String v, String l, {Color? color}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(
              v,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(l, style: sub, maxLines: 1),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(t('Kehonpaino')),
        Row(
          children: [
            tile('${fmtNum(last.$2)} kg', shortDate(last.$1)),
            const SizedBox(width: 6),
            tile(
              change == null
                  ? '–'
                  : '${change > 0
                        ? '+'
                        : change < 0
                        ? '−'
                        : ''}${fmtDec(change.abs(), 1)} kg',
              t('muutos jaksolla'),
            ),
            const SizedBox(width: 6),
            tile(h == null ? '–' : fmtNum(bmi(last.$2, h)), t('painoindeksi')),
          ],
        ),
        if (pts.length >= 2) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
              painter: _WeightPainter(pts, from, to, h, cs.onSurfaceVariant, Theme.of(context).textTheme.bodySmall!),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            h == null
                ? t('Pituus puuttuu: lisää se asetuksista, niin näet painoindeksin.')
                : t('Vihreä alue: painoindeksi 18,5–25 ({0}–{1} kg).', [
                    fmtDec(18.5 * h * h / 10000, 1),
                    fmtDec(25 * h * h / 10000, 1),
                  ]),
            style: sub,
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(t('Punnitusten korjaus ja pituus: ☰ → Asetukset → Paino ja pituus.'), style: sub),
        ),
      ],
    );
  }
}

class _WeightPainter extends CustomPainter {
  final List<(DateTime, double)> pts;
  final DateTime from, to;
  final int? height;
  final Color muted;
  final TextStyle text;
  _WeightPainter(this.pts, this.from, this.to, this.height, this.muted, this.text);

  @override
  void paint(Canvas c, Size s) {
    final ws = pts.map((e) => e.$2);
    var lo = ws.reduce((a, b) => a < b ? a : b) - 1, hi = ws.reduce((a, b) => a > b ? a : b) + 1;
    final span = to.difference(from).inHours.toDouble();
    const left = 34.0; // akselin luvuille oma sarake, ettei teksti mene käyrän päälle
    double x(DateTime d) => left + (s.width - left - 4) * (d.difference(from).inHours / span).clamp(0.0, 1.0);
    double y(double kg) => s.height - 4 - (kg - lo) / (hi - lo) * (s.height - 8);
    // Normaalin painoindeksin alue (18,5–25), jos se osuu näkyvälle välille.
    if (height != null) {
      final m2 = height! * height! / 10000;
      final a = (18.5 * m2).clamp(lo, hi), b = (25 * m2).clamp(lo, hi);
      if (b > a) {
        c.drawRect(Rect.fromLTRB(left, y(b), s.width, y(a)), Paint()..color = Sami.green.withValues(alpha: .12));
      }
    }
    final path = Path();
    for (final (i, (d, kg)) in pts.indexed) {
      i == 0 ? path.moveTo(x(d), y(kg)) : path.lineTo(x(d), y(kg));
    }
    c.drawPath(
      path,
      Paint()
        ..color = Sami.blue
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (final (d, kg) in pts) {
      c.drawCircle(Offset(x(d), y(kg)), 3, Paint()..color = Sami.blue);
    }
    void label(String t, double yy) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: text.copyWith(color: muted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(0, (yy - tp.height / 2).clamp(0, s.height - tp.height)));
    }

    label(fmtNum(hi - 1), y(hi - 1));
    label(fmtNum(lo + 1), y(lo + 1));
  }

  @override
  bool shouldRepaint(covariant _WeightPainter o) => o.pts != pts || o.height != height;
}

/// Ajan selite: jos kaikilla treeneillä ei ole kestoa (esim. FitNotes-tuonti), kerrotaan, monenko treenin aika on.
String _timeLabel(Recap r) =>
    r.timed > 0 && r.timed < r.parts ? t('aikaa, {0}/{1} treenistä', [r.timed, r.parts]) : t('aikaa');
