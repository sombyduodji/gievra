import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../daily_steps.dart';
import '../health.dart';
import '../insights.dart' show weekStart;
import '../l10n.dart';
import '../models.dart';
import '../share_text.dart' show thousands;
import '../theme.dart';
import 'stats_screen.dart';
import 'running_screen.dart';
import '../running.dart';
import 'widgets.dart';

// Päivän askeleet: etusivun kortin Askeleet-puoli, tilastojen Askeleet-välilehti ja päivän erittely (sovelluksittain
// ja tietueittain, esim. Ouran ja puhelimen vertailuun). Vain luku Health Connectista; treeneihin ei kosketa.

/// Laite tukee päivän askeleita (Android, ei verkkodemo). Testeissä voi pakottaa.
bool get stepsSupported => debugStepsSupported ?? (!kIsWeb && !isDemo && Platform.isAndroid);
@visibleForTesting
bool? debugStepsSupported;

/// Askeleet-välilehti ja etusivun Askeleet-puoli näkyvät.
bool get stepsTabAvailable => settings.dailySteps && stepsSupported;

/// Etusivun tilastokortti: Edistyminen, Juoksu ja Askeleet samassa kortissa puolina (vaihto otsikon valitsimesta tai
/// pyyhkäisemällä, valinta muistetaan). [progress]: Edistyminen-puolen sisältö (null = ei näytettävää),
/// [running]: juoksut olemassa, [steps]: päivän askeleet päällä. Yksi puoli = pelkkä otsikko ilman valitsinta.
class HomeStatsCard extends StatefulWidget {
  final Widget? progress;
  final Widget? progressTrailing;
  final bool running;
  final bool steps;
  const HomeStatsCard({super.key, this.progress, this.progressTrailing, this.running = false, this.steps = false});

  @override
  State<HomeStatsCard> createState() => _HomeStatsCardState();
}

class _HomeStatsCardState extends State<HomeStatsCard> {
  static const _key = 'homeCardSide';
  String _side = 'progress';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      final v = sp.getString(_key);
      if (v == null || !mounted) return;
      setState(() => _side = v);
      // Muistettu puoli suoraan näkyviin (ei liukumaa käynnistyessä).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final i = _sides.indexOf(v);
        if (i >= 0 && _pages.hasClients) _pages.jumpToPage(i);
      });
    });
  }

  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Valitsimesta: sivu liukuu valitulle puolelle.
  void _set(String v) {
    _save(v);
    final i = _sides.indexOf(v);
    if (i >= 0 && _pages.hasClients) {
      _pages.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  void _save(String v) {
    if (v != _side) setState(() => _side = v);
    SharedPreferences.getInstance().then((sp) => sp.setString(_key, v));
  }

  List<String> get _sides => [
    if (widget.progress != null) 'progress',
    if (widget.running) 'running',
    if (widget.steps) 'steps',
  ];

  static String _label(String side) => switch (side) {
    'running' => t('Juoksu'),
    'steps' => t('Askeleet'),
    _ => t('Edistyminen'),
  };

  void _openFull(BuildContext context, String side) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => switch (side) {
        'running' => const RunningScreen(),
        'steps' => StatsScreen(tab: 'steps'),
        _ => StatsScreen(),
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sides = _sides;
    if (sides.isEmpty) return const SizedBox.shrink();
    final side = sides.contains(_side) ? _side : sides.first;
    final many = sides.length > 1;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Card(
        // Pyyhkäisy hoidetaan sivuina (PageView alla), joten tämä vain kääreenä.
        child: GestureDetector(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _openFull(context, side),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        if (many)
                          Flexible(
                            child: _SideSwitch(
                              values: sides,
                              labels: [for (final x in sides) _label(x)],
                              value: side,
                              onChanged: _set,
                            ),
                          )
                        else
                          Expanded(
                            child: Text(
                              _label(side),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        if (many) const Spacer(),
                        if (side == 'progress' && widget.progressTrailing != null)
                          widget.progressTrailing!
                        else if (side != 'progress') ...[
                          // Askeleet: päivitys heti Health Connectista (esim. kun Oura tai kävelymatto on
                          // synkronoinut).
                          if (side == 'steps')
                            ListenableBuilder(
                              listenable: dailySteps,
                              builder: (context, _) => IconButton(
                                tooltip: t('Päivitä askeleet'),
                                visualDensity: VisualDensity.compact,
                                onPressed: dailySteps.loading ? null : () => dailySteps.refresh(),
                                icon: dailySteps.loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh),
                              ),
                            ),
                          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Korkeus: korkein puoli (kaikki puolet näkymättöminä mitoituksena), joten etusivu ei hypi.
                  // Puolet sivuina: pyyhkäisy seuraa sormea ja valitsin liu'uttaa.
                  Stack(
                    children: [
                      for (final x in sides)
                        Visibility(
                          visible: false,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: _body(x),
                        ),
                      Positioned.fill(
                        child: PageView(
                          controller: _pages,
                          onPageChanged: (i) => _save(sides[i]),
                          children: [for (final x in sides) _body(x)],
                        ),
                      ),
                    ],
                  ),
                  if (many)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final v in sides)
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: v == side ? cs.primary : cs.outlineVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(String x) => switch (x) {
    'steps' => const StepsCardBody(),
    'running' => RunningCardBody(),
    _ => widget.progress!,
  };
}

class _SideSwitch extends StatelessWidget {
  final List<String> values, labels;
  final String value;
  final ValueChanged<String> onChanged;
  const _SideSwitch({required this.values, required this.labels, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String v, String label) => GestureDetector(
      onTap: () => onChanged(v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: v == value ? Sami.yellow.withValues(alpha: .35) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(fontSize: 13, fontWeight: v == value ? FontWeight.w700 : null),
        ),
      ),
    );
    // Kapealla näytöllä tai pitkillä sanoilla (saame) pienennetään yhdelle riville.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (var i = 0; i < values.length; i++) seg(values[i], labels[i])],
        ),
      ),
    );
  }
}

/// Kortin Juoksu-puoli: tämän viikon kilometrit, viimeiset 4 viikkoa, viimeisin lenkki ja 8 viikon pylväät.
class RunningCardBody extends StatelessWidget {
  const RunningCardBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final runs = runsOf(store.workouts);
    final weeks = runWeeks(runs, DateTime.now(), n: 8);
    final now = weeks.last;
    final km4 = weeks.skip(4).fold<double>(0, (a, w) => a + w.km);
    final last = runs.firstOrNull;
    final top = weeks.map((w) => w.km).fold<double>(1, (a, b) => b > a ? b : a);
    String km(double v) => fmtNum((v * 10).round() / 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${km(now.km)} km',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              TextSpan(text: '  ${t('tällä viikolla')}', style: sub),
            ],
          ),
        ),
        Text(
          [
            t('4 viikkoa {0} km', [km(km4)]),
            if (last != null)
              t('viimeisin {0} {1} km, {2} min/km', [
                shortDate(last.date),
                km(last.distanceKm!),
                fmtPace(last.paceSecPerKm!),
              ]),
          ].join(' · '),
          style: sub,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < weeks.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FractionallySizedBox(
                      heightFactor: (weeks[i].km / top).clamp(.04, 1),
                      child: Container(
                        decoration: BoxDecoration(
                          color: i == weeks.length - 1 ? cs.primary.withValues(alpha: .6) : cs.outlineVariant,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(t('Kilometrit viikoittain, 8 viikkoa'), style: sub.copyWith(fontSize: 11)),
      ],
    );
  }
}

/// Kortin Askeleet-puoli: tänään, eilen, 7 päivän keskiarvo ja viikon pylväät.
class StepsCardBody extends StatelessWidget {
  const StepsCardBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return ListenableBuilder(
      listenable: dailySteps,
      builder: (context, _) {
        if (dailySteps.needsPermission) {
          return Row(
            children: [
              Expanded(child: Text(t('Salli askelten luku Health Connectista.'), style: sub)),
              TextButton(onPressed: dailySteps.requestPermission, child: Text(t('Salli'))),
            ],
          );
        }
        if (dailySteps.error == 'unavailable') {
          return Text(t('Health Connect ei ole käytettävissä tässä puhelimessa.'), style: sub);
        }
        final today = dateOnly(DateTime.now());
        final week = [for (var i = 6; i >= 0; i--) addDays(today, -i)];
        final top = week.map((d) => dailySteps.at(d) ?? 0).fold<int>(1, (a, b) => b > a ? b : a);
        final n = dailySteps.today;
        final y = dailySteps.yesterday;
        final avg = dailySteps.average(7);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: n == null ? '–' : thousands(n),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '  ${t('askelta tänään')}', style: sub),
                ],
              ),
            ),
            Text(
              [
                if (y != null) t('Eilen {0}', [thousands(y)]),
                if (avg != null) t('7 päivän keskiarvo {0}', [thousands(avg)]),
                if (n == null && y == null && dailySteps.loading) t('Haetaan…'),
              ].join(' · '),
              style: sub,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in week)
                    Expanded(
                      // Pylvään napautus: päivän erittely (esim. eilisen askeleet sovelluksittain).
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showStepsDay(context, d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FractionallySizedBox(
                            heightFactor: ((dailySteps.at(d) ?? 0) / top).clamp(.04, 1),
                            child: Container(
                              decoration: BoxDecoration(
                                color: d == today ? cs.primary.withValues(alpha: .6) : cs.outlineVariant,
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
            const SizedBox(height: 2),
            Row(
              children: [
                for (final d in week)
                  Expanded(
                    child: Text(
                      uiWeekdaysShort[d.weekday - 1],
                      textAlign: TextAlign.center,
                      style: sub.copyWith(fontSize: 11, color: d == today ? cs.onSurface : null),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Tilastojen Askeleet-välilehti valitulle jaksolle [from]..[to) (vertailu [prevFrom]..[prevTo)).
class StepsStatsView extends StatefulWidget {
  final DateTime from, to, prevFrom, prevTo;
  final List<Widget> header;
  const StepsStatsView({
    super.key,
    required this.from,
    required this.to,
    required this.prevFrom,
    required this.prevTo,
    this.header = const [],
  });

  @override
  State<StepsStatsView> createState() => _StepsStatsViewState();
}

class _StepsStatsViewState extends State<StepsStatsView> {
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(StepsStatsView old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) _read();
  }

  /// Näytetty jakso luetaan Health Connectista uudelleen (korvaa tallennetut, jos Oura on päivittänyt). Vasta
  /// kuvan piirron jälkeen: haku ilmoittaa muutoksista heti, eikä rakennusvaiheessa saa ilmoittaa.
  void _read() => WidgetsBinding.instance.addPostFrameCallback((_) => _readNow());

  void _readNow() {
    if (!mounted) return;
    final today = dateOnly(DateTime.now());
    final last = addDays(widget.to, -1);
    if (widget.from.isAfter(today)) return;
    dailySteps.refresh(from: widget.from, to: last.isAfter(today) ? today : last);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return ListenableBuilder(
      listenable: dailySteps,
      builder: (context, _) {
        final today = dateOnly(DateTime.now());
        List<(DateTime, int)> range(DateTime a, DateTime b) => [
          for (var d = a; d.isBefore(b) && !d.isAfter(today); d = addDays(d, 1))
            if (dailySteps.at(d) case final n?) (d, n),
        ];
        final cur = range(widget.from, widget.to);
        final prev = range(widget.prevFrom, widget.prevTo);
        // Keskiarvo täysistä päivistä (tänään ei vielä valmis).
        int? avg(List<(DateTime, int)> xs) {
          final full = xs.where((x) => x.$1 != today).map((x) => x.$2).toList();
          return full.isEmpty ? null : (full.reduce((a, b) => a + b) / full.length).round();
        }

        final a = avg(cur), pa = avg(prev);
        final best = cur.isEmpty ? null : cur.reduce((x, y) => y.$2 > x.$2 ? y : x);
        final change = a == null || pa == null || pa == 0 ? null : ((a - pa) / pa * 100).round();
        Widget tile(String value, String label) => Expanded(
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
              ],
            ),
          ),
        );
        final span = widget.to.difference(widget.from).inDays;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
          children: [
            ...widget.header,
            const SizedBox(height: 10),
            if (dailySteps.needsPermission)
              Card(
                child: ListTile(
                  title: Text(t('Salli askelten luku Health Connectista.')),
                  trailing: TextButton(onPressed: dailySteps.requestPermission, child: Text(t('Salli'))),
                ),
              ),
            Row(
              children: [
                tile(a == null ? '–' : thousands(a), t('keskimäärin / pv')),
                const SizedBox(width: 6),
                tile(best == null ? '–' : thousands(best.$2), t('paras päivä')),
                const SizedBox(width: 6),
                tile(
                  change == null ? '–' : '${change > 0 ? '↑' : (change < 0 ? '↓' : '')} ${change.abs()} %',
                  t('vs. ennen'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (cur.isNotEmpty) _StepsBars(days: cur, weekly: span > 45, from: widget.from, to: widget.to),
            if (span > 45)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t('Pylväät: viikon keskiarvo'), style: sub),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: SectionLabel(t('Päivittäin'))),
                TextButton.icon(
                  onPressed: dailySteps.loading ? null : _readNow,
                  icon: dailySteps.loading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(t('Lue uudelleen')),
                ),
              ],
            ),
            if (cur.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(t('Ei askeltietoja tältä jaksolta.'), style: sub, textAlign: TextAlign.center),
              ),
            for (final (d, n) in cur.reversed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(shortDate(d)),
                subtitle: Text(
                  [
                    if (d == today) t('tähän mennessä') else if (stepsMayChange(d)) t('voi vielä päivittyä'),
                    ...?dailySteps.apps[d],
                    ...stepsAddedNotes(d),
                  ].join(' · '),
                  style: sub,
                ),
                trailing: Text(thousands(n), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                onTap: () => showStepsDay(context, d),
              ),
            const SizedBox(height: 8),
            Text(
              t(
                'Health Connectista ilman päällekkäisyyksiä: Health Connectin sovellusten tärkeysjärjestys ratkaisee '
                'puhelimen ja esim. Ouran välillä. Treenien askeleet sisältyvät jo päivän lukuun. Viimeisimmät päivät '
                'päivittyvät, kun esim. Oura synkronoi myöhemmin.',
              ),
              style: sub,
            ),
          ],
        );
      },
    );
  }
}

/// Päivän lukuun lisätyt liikuntojen askeleet lyhyesti: "+8 400 Kävely (Kävelymatto)".
List<String> stepsAddedNotes(DateTime d) => [
  for (final a in dailySteps.added[d] ?? const <StepsAddition>[])
    '+${thousands(a.steps - a.had)} ${sportName(a.name)}${a.source == null ? '' : ' (${a.source})'}',
];

class _StepsBars extends StatelessWidget {
  final List<(DateTime, int)> days;
  final bool weekly;
  final DateTime from, to;
  const _StepsBars({required this.days, required this.weekly, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final byDay = {for (final (d, n) in days) d: n};
    final values = <double>[];
    if (weekly) {
      for (var w = weekStart(from); w.isBefore(to); w = addDays(w, 7)) {
        final xs = [for (var i = 0; i < 7; i++) ?byDay[addDays(w, i)]];
        values.add(xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length);
      }
    } else {
      for (var d = from; d.isBefore(to); d = addDays(d, 1)) {
        values.add((byDay[d] ?? 0).toDouble());
      }
    }
    final top = values.fold<double>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 90,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FractionallySizedBox(
                  heightFactor: (v / top).clamp(.02, 1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Yhden päivän askeleet: Health Connectin päivän luku, sovelluksittain ja tallennetut tietueet aikoineen
/// (esim. milloin Oura kirjasi askeleensa).
Future<void> showStepsDay(BuildContext context, DateTime day) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    String hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .95,
      builder: (_, scroll) => FutureBuilder(
        future: stepsSupported && debugStepsSupported == null
            ? Future.wait([HealthConnect.dayStepsByApp(day), HealthConnect.stepRecords(day)])
            : Future.value(<Object>[<String, int>{}, <StepRecord>[]]),
        builder: (context, snap) {
          final byApp = (snap.data?[0] as Map<String, int>?) ?? const {};
          final recs = [...((snap.data?[1] as List<StepRecord>?) ?? const <StepRecord>[])]
            ..sort((a, b) => a.start.compareTo(b.start));
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              Text(shortDate(day), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(
                t('{0} askelta', [thousands(dailySteps.at(day) ?? 0)]),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              Text(t('Päivän luku: Health Connectin koonti ilman päällekkäisyyksiä.'), style: sub),
              // Mistä luku koostuu: koonti ja siihen lisätyt liikuntojen askeleet (esim. kävelymatto, jonka
              // askeleet koonnista puuttuivat).
              if (dailySteps.hcTotal[day] case final hc?) ...[
                SectionLabel(t('Mistä luku koostuu')),
                Row(
                  children: [
                    Expanded(child: Text(t('Health Connectin koonti'))),
                    Text(thousands(hc), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                for (final (a, on) in [
                  for (final a in dailySteps.added[day] ?? const <StepsAddition>[]) (a, true),
                  for (final a in dailySteps.skipped[day] ?? const <StepsAddition>[]) (a, false),
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${sportName(a.name)} ${hm(a.start)}${a.source == null ? '' : ' · ${a.source}'}'),
                              Text(
                                t('{0} askelta, koonnissa samalta ajalta {1}', [thousands(a.steps), thousands(a.had)]),
                                style: sub,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          on ? '+${thousands(a.steps - a.had)}' : t('ei lisätty'),
                          style: on ? const TextStyle(fontWeight: FontWeight.w700) : sub,
                        ),
                      ],
                    ),
                  ),
                if ((dailySteps.added[day]?.isNotEmpty ?? false) || (dailySteps.skipped[day]?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      t(
                        'Laitteen sovelluksesta tuodun liikunnan askeleet lisätään, kun koonnista puuttuu yli puolet '
                        'niistä (esim. kävelymatto, jota puhelin ja sormus eivät huomaa). Gievrassa tallennettujen '
                        'kävelyjen askeleet ovat jo päivän luvussa.',
                      ),
                      style: sub,
                    ),
                  ),
              ],
              SectionLabel(t('Sovelluksittain')),
              if (snap.connectionState != ConnectionState.done) const LinearProgressIndicator(),
              if (snap.hasError) Text(t('Tietoja ei voitu lukea Health Connectista.'), style: sub),
              for (final e in byApp.entries)
                Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text(thousands(e.value), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              if (byApp.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    t('Sovellusten luvut ennen päällekkäisyyksien poistoa: yhteenlaskettuina ne olisivat liikaa.'),
                    style: sub,
                  ),
                ),
              SectionLabel(t('Tallennetut askeltiedot ({0})', [recs.length])),
              for (final r in recs.take(200))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 96, child: Text('${hm(r.start)}–${hm(r.end)}', style: sub)),
                      Expanded(
                        child: Text(r.app, style: sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(thousands(r.count), style: sub),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  },
);

/// Asetuksissa Päivän askeleet -kohdan alla: vanhempien askelten haku Health Connectin historialuvalla. Näkyy vain,
/// kun laitteen Health Connect tukee historiaa.
class StepsHistoryTile extends StatefulWidget {
  const StepsHistoryTile({super.key});

  /// Testeille: ohittaa Health Connectin tukitarkistuksen.
  static bool? debugAvailable;

  @override
  State<StepsHistoryTile> createState() => _StepsHistoryTileState();
}

class _StepsHistoryTileState extends State<StepsHistoryTile> {
  bool _available = false, _busy = false;

  @override
  void initState() {
    super.initState();
    final d = StepsHistoryTile.debugAvailable;
    if (d != null) {
      _available = d;
    } else {
      HealthConnect.historyAvailable().then((v) {
        if (mounted) setState(() => _available = v);
      });
    }
  }

  Future<void> _read() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final n = await dailySteps.readHistory();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n == null
              ? t('Vanhempia askeleita ei voitu hakea (lupa puuttuu tai Health Connect ei vastannut).')
              : t('Haettu kahden vuoden ajalta: {0} uutta askelpäivää.', [n]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: _busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.history),
      title: Text(t('Hae vanhemmat askeleet')),
      subtitle: Text(
        t(
          'Health Connect antaa ilman erillistä lupaa vain noin 30 päivää ennen luvan antamista. Tämä pyytää luvan '
          'vanhempiin tietoihin ja hakee askeleet kahden vuoden ajalta.',
        ),
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      onTap: _busy ? null : _read,
    );
  }
}
