import 'package:flutter/material.dart';

import 'activity.dart';
import 'running_screen.dart';
import '../sports.dart';
import '../running.dart';
import '../program_edit.dart';
import '../app_info.dart';
import '../app_state.dart';
import '../exercises.dart';
import '../insights.dart';
import '../models.dart';
import '../program.dart';
import '../theme.dart';
import 'drawer.dart';
import 'intro.dart';
import 'program_screen.dart';
import 'new_workout.dart';
import 'widgets.dart';
import 'workout.dart';
import '../l10n.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// Asetusten muutos (teema, painon lisäys …) rakentaa etusivun uudelleen: raskaat laskelmat lasketaan vain,
// kun treenit, ohjelma tai päivä muuttuvat.
Object? _insKey;
Insights? _ins;
Insights _insights() {
  final key = (store.rev, store.workouts.length, settings.deloadEvery, dateOnly(DateTime.now()));
  if (key != _insKey || _ins == null) {
    _ins = analyze(store.workouts, deloadEvery: settings.deloadEvery);
    _insKey = key;
  }
  return _ins!;
}

Object? _dayKey;
Program? _dayProgram;
(PlanDay, String?)? _day;
(PlanDay, String?) _suggestDay(Program p, DateTime today) {
  final key = (store.rev, store.workouts.length, today);
  if (key != _dayKey || !identical(p, _dayProgram) || _day == null) {
    _day = suggestDay(p, store.workouts, today);
    _dayKey = key;
    _dayProgram = p;
  }
  return _day!;
}

/// Avaa päivän treenin: yksi treeni muokattavaksi, useampi valittavaksi, muuten uusi.
void openDate(BuildContext context, DateTime d) {
  // Treenin aloitus päättää tauon (sairaus/loma): paluuehdotukset alkavat tästä.
  if (settings.activePause != null && !dateOnly(d).isBefore(settings.activePause!.start)) {
    settings.endPause(addDays(d, -1));
  }
  final ws = store.onDay(d);
  if (ws.length > 1) {
    _chooseSession(context, d, ws);
    return;
  }
  _open(context, d, ws.firstOrNull);
}

void _open(BuildContext context, DateTime d, Workout? w, {bool newSession = false}) {
  final p = settings.program;
  PlanDay? day;
  if (p != null && w != null) day = p.plan.where((x) => x.matches(w.dayKey)).firstOrNull;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => w != null && w.activity != null
          ? ActivityScreen(workout: w.copy())
          : w != null
          ? WorkoutScreen(workout: w.copy(), planDay: day)
          : NewWorkoutScreen(date: d, newSession: newSession),
    ),
  );
}

/// Uusi treeni päivälle: ensimmäinen tai saman päivän seuraava (vvvv-kk-pp-2.md …).
void _startNew(BuildContext context, DateTime d) {
  if (settings.activePause != null && !dateOnly(d).isBefore(settings.activePause!.start)) {
    settings.endPause(addDays(d, -1));
  }
  _open(context, d, null, newSession: store.onDay(d).isNotEmpty);
}

Future<void> _chooseSession(BuildContext context, DateTime d, List<Workout> ws) async {
  final r = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              t('{0}: {1} treeniä', [longDate(d), ws.length]),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          for (final w in ws)
            ListTile(
              leading: Text(w.activity != null ? '🏃' : '💪', style: const TextStyle(fontSize: 22)),
              title: Text(w.activity ?? trName(w.title)),
              subtitle: Text(
                [
                  if (w.minutes != null) '${w.minutes} min',
                  if (w.distanceKm != null) '${fmtNum(w.distanceKm!)} km',
                  if (w.activity == null) t('{0} sarjaa', [w.exercises.fold<int>(0, (a, e) => a + e.workSets.length)]),
                  if (feelingOf(w.feeling) != null) feelingOf(w.feeling)!.$2,
                ].join(' · '),
              ),
              onTap: () => Navigator.pop(ctx, w),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(t('Lisää uusi treeni tälle päivälle')),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (r == null || !context.mounted) return;
  r is Workout ? _open(context, d, r) : _open(context, d, null, newSession: true);
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, store]),
      builder: (context, _) {
        final now = DateTime.now();
        final today = dateOnly(now);
        final todays = store.onDay(today);
        // Kesken oleva treeni (ei merkitty valmiiksi): etusivu tarjoaa sen jatkamista, muuten uutta treeniä.
        final open = todays.where((w) => w.minutes == null && w.feeling == null).toList();
        final hasToday = open.isNotEmpty;
        return Scaffold(
          appBar: AppBar(title: const Text(AppInfo.fullName)),
          drawer: const AppDrawer(),
          body: RefreshIndicator(
            onRefresh: store.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              children: [
                Row(
                  children: [
                    const AppLogo(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: t('Bures!'),
                                  style: TextStyle(
                                    color: Theme.of(context).brightness == Brightness.light
                                        ? const Color(0xFFB07D00) // keltainen ei erotu vaalealla
                                        : Sami.yellow,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(text: ' · ${longDate(now)}'),
                              ],
                            ),
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                          // Suomenkielisessä käyttöliittymässä saamenkielinen päiväys lisärivinä.
                          if (!isSami)
                            Text(
                              seDate(now),
                              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
                            ),
                          Text(
                            '${seGreeting(now)}, ${settings.name}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.15),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const SamiBand(),
                // Kuvakaappauksia varten demo ilman ilmoitusta: --dart-define=SCREENSHOT=true
                if (isDemo && !const bool.fromEnvironment('SCREENSHOT'))
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Sami.blue.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t(
                            '🧪 Demo selaimessa: esimerkkitreenit, mitään ei tallenneta. Kokeile treenin kirjausta, '
                            'tilastoja ja ohjelman tekoa (☰ → Ohjelma ja tavoitteet → Tee uusi ohjelma → Tallenna pohja). '
                            'Oikea sovellus tallentaa treenit .md-tiedostoina omaan kansioosi.',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        // Ohjelmatyökalu suoraan: kysymykset, ehdotus, muokkaus ja .gmd-pohjan lataus.
                        FilledButton.icon(
                          // Ohjelmanäkymä alle: kyselyn jälkeen näkyy ohjelma ja Tallenna pohja -painike.
                          onPressed: () {
                            final nav = Navigator.of(context);
                            nav.push(MaterialPageRoute(builder: (_) => const ProgramScreen()));
                            nav.push(MaterialPageRoute(builder: (_) => const IntroScreen()));
                          },
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: Text(t('Tee oma treeniohjelma')),
                        ),
                      ],
                    ),
                  ),
                // Molemmat-tilassa valinta Sali / Kestävyys; muuten tila valitsee näkymän (asetukset).
                if (settings.trainMode == 'both')
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Center(
                      child: _ModeToggle(value: settings.homeView, onChanged: settings.setHomeView),
                    ),
                  ),
                if (settings.homeShows == 'cardio')
                  const _CardioHome()
                else ...[
                  const SizedBox(height: 18),
                  _Cta(
                    label: hasToday
                        ? t('Jatka tämän päivän treeniä')
                        : settings.program != null
                        ? (todays.isEmpty
                              ? t('Aloita: {0}', [_suggestDay(settings.program!, today).$1.uiName])
                              : t('Uusi treeni: {0}', [_suggestDay(settings.program!, today).$1.uiName]))
                        : todays.isEmpty
                        ? t('Lisää treeni tänään')
                        : t('Lisää uusi treeni'),
                    icon: hasToday ? Icons.play_arrow_rounded : Icons.add_rounded,
                    onTap: () => hasToday
                        ? (open.length == 1 ? _open(context, today, open.single) : openDate(context, today))
                        : _startNew(context, today),
                  ),
                  if (todays.isNotEmpty)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => hasToday ? _startNew(context, today) : openDate(context, today),
                        icon: Icon(hasToday ? Icons.add_rounded : Icons.edit_note_rounded, size: 18),
                        label: Text(
                          hasToday
                              ? t('Uusi treeni tälle päivälle')
                              : todays.length == 1
                              ? t('Avaa tämän päivän treeni')
                              : t('Tämän päivän treenit ({0})', [todays.length]),
                        ),
                      ),
                    ),
                  if (settings.program != null && !hasToday)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${settings.program!.displayTitle} · ${t('viikko {0}', [settings.program!.weekOf(today) + 1])}'
                        '${settings.program!.isDeloadWeek(today) ? ' · ${t('kevennysviikko')} 🌙' : ''}'
                        '${_suggestDay(settings.program!, today).$2 == null ? '' : '\n${_suggestDay(settings.program!, today).$2}'}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  if (store.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(store.error!, style: TextStyle(color: cs.error)),
                    ),
                  const SizedBox(height: 14),
                  _Stats(),
                  if (settings.activePause != null) const _PauseCard(),
                  if (settings.tips && settings.activePause == null) const _InsightsCard(),
                ],
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _Calendar(
                      month: _month,
                      onShift: (n) => setState(() => _month = DateTime(_month.year, _month.month + n)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (store.workouts.isNotEmpty) _Recent(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Cta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _Cta({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Sami.red, Color(0xFFA3170D)])),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Stats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = dateOnly(DateTime.now());
    final weekStart = addDays(now, 1 - now.weekday);
    final ws = store.workouts;
    final week = ws.where((w) => !w.date.isBefore(weekStart)).length;
    final month = ws.where((w) => w.date.year == now.year && w.date.month == now.month).length;
    // Viikkoputki: peräkkäiset viikot, joilla vähintään yksi treeni (tämä viikko saa vielä puuttua).
    var streak = 0;
    var start = weekStart;
    bool hasWeek(DateTime s) => ws.any((w) => !w.date.isBefore(s) && w.date.isBefore(addDays(s, 7)));
    if (!hasWeek(start)) start = addDays(start, -7);
    while (hasWeek(start)) {
      streak++;
      start = addDays(start, -7);
    }
    Widget tile(String v, String l) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(l, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        tile('$week', t('tällä viikolla')),
        const SizedBox(width: 8),
        tile('$month', t('tässä kuussa')),
        const SizedBox(width: 8),
        tile(streak > 0 ? '🔥 $streak' : '0', t('viikon putki')),
      ],
    );
  }
}

/// Urheilun ja liikunnan väri kalenterissa.
const sportColor = Color(0xFF2BA6A6);

class _Calendar extends StatelessWidget {
  final DateTime month;
  final void Function(int) onShift;
  const _Calendar({required this.month, required this.onShift});

  List<Color> _dots(Workout w) {
    final groups = {for (final e in w.exercises.where((e) => e.sets.isNotEmpty)) bodyGroupOf(e.name)};
    return [
      if (groups.contains(BodyGroup.legs)) Sami.red,
      if (groups.contains(BodyGroup.upper)) Sami.blue,
      if (w.warmup != null || groups.contains(BodyGroup.core)) Sami.green,
      if (w.activity != null) sportColor,
      if (w.exercises.any((e) => e.sets.any((s) => s.pr))) Sami.yellow,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = dateOnly(DateTime.now());
    final first = DateTime(month.year, month.month, 1);
    final lead = first.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final byDay = <int, List<Workout>>{};
    for (final w in store.workouts) {
      if (w.date.year == month.year && w.date.month == month.month) (byDay[w.date.day] ??= []).add(w);
    }

    final cells = <Widget>[
      for (final d in uiWeekdaysShort)
        Center(
          child: Text(d, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++)
        _DayCell(
          day: d,
          isToday: DateTime(month.year, month.month, d) == today,
          workout: byDay[d]?.first,
          dots: byDay[d] == null ? const [] : {for (final w in byDay[d]!) ..._dots(w)}.toList(),
          onTap: DateTime(month.year, month.month, d).isAfter(today)
              ? null
              : () => openDate(context, DateTime(month.year, month.month, d)),
        ),
    ];

    return Column(
      children: [
        Row(
          children: [
            IconButton.filledTonal(onPressed: () => onShift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${uiMonth(month.month)} ${month.year}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (!isSami)
                    Text(
                      seMonths[month.month - 1],
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            IconButton.filledTonal(onPressed: () => onShift(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final (c, l) in [
              (Sami.red, 'Jalat'),
              (Sami.blue, t('Ylävartalo')),
              (Sami.green, t('Kardio / keskivartalo')),
              if (settings.sports) (sportColor, t('Liikunta')),
              (Sami.yellow, t('Ennätys')),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(l, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final Workout? workout;
  final List<Color> dots;
  final VoidCallback? onTap;
  const _DayCell({required this.day, required this.isToday, this.workout, required this.dots, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: workout != null ? cs.surfaceContainerHigh : null,
          borderRadius: BorderRadius.circular(10),
          border: isToday ? Border.all(color: Sami.yellow, width: 2) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day', style: TextStyle(fontSize: 13, color: onTap == null ? cs.onSurfaceVariant : cs.onSurface)),
            if (dots.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in dots)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
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

class _Recent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('Viimeksi'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            for (final w in store.workouts.take(3))
              InkWell(
                onTap: () => openDate(context, w.date),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(trName(w.title), style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              w.exercises.where((e) => e.sets.isNotEmpty).map((e) => e.name).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Text(shortDate(w.date), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Edistyminen ja kevennysviikkovinkki (pois päältä asetuksista).
class _InsightsCard extends StatelessWidget {
  const _InsightsCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ins = _insights();
    final week = isoDate(weekStart(DateTime.now()));
    // Ohjelma ajoittaa kevennykset itse; vinkki vain vapaassa treenissä.
    final showDeload = ins.suggestDeload && settings.deloadDismissed != week && settings.program == null;
    if (ins.improving.isEmpty && ins.stalled.isEmpty && !showDeload && ins.prs30d == 0) {
      return const SizedBox.shrink();
    }
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    Widget row(Progress p, bool up) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_flat, size: 18, color: up ? Sami.green : cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(exerciseLabel(p.exercise), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(
            up ? '${fmtNum(p.before.roundToDouble())} → ${fmtNum(p.now.roundToDouble())} kg' : t('junnaa'),
            style: sub,
          ),
          if (up) ...[
            const SizedBox(width: 6),
            Text(
              '+${p.pct.toStringAsFixed(0)} %',
              style: const TextStyle(color: Sami.green, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          if (showDeload)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Sami.yellow.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Sami.yellow, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🌙', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t('Kevennysviikon paikka?'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(onPressed: () => settings.dismissDeload(week), child: Text(t('Ohita'))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ins.autoregulated
                        ? t(
                            'Olet treenannut {0} viikkoa putkeen, ja {1} liikettä junnaa paikallaan. Väsymys voi '
                            'peittää kehityksen.',
                            [ins.loadingWeeks, ins.stalled.length],
                          )
                        : t('Olet treenannut {0} viikkoa putkeen ilman kevennystä.', [ins.loadingWeeks]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t(
                      'Kevennysviikko: sama treenitiheys, noin puolet sarjoista ja toistoista, painot noin 10 % '
                      'kevyemmät, ei maksimiyrityksiä. Voima- ja fysiikkaurheilijat keventävät tyypillisesti 5–6 '
                      'viikon välein noin viikon ajan.',
                    ),
                    style: sub,
                  ),
                ],
              ),
            ),
          if (ins.improving.isNotEmpty || ins.stalled.isNotEmpty || ins.prs30d > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(t('Edistyminen'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        if (ins.prs30d > 0) Text(t('🏆 {0} ennätystä / 30 pv', [ins.prs30d]), style: sub),
                      ],
                    ),
                    Text(t('Arvioitu 1RM: viimeiset 4 viikkoa vs. 2 kuukautta ennen'), style: sub),
                    const SizedBox(height: 4),
                    for (final p in ins.improving) row(p, true),
                    for (final p in ins.stalled) row(p, false),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PauseCard extends StatelessWidget {
  const _PauseCard();

  @override
  Widget build(BuildContext context) {
    final p = settings.activePause!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (p.sick ? Sami.red : Sami.blue).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.sick ? Sami.red : Sami.blue, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.sick ? t('🤒  Sairastat – parane pian!') : t('🏖  Lomalla – nauti!'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            t(
              'Tauko alkoi {0} ({1} pv). Kun palaat, sovellus ehdottaa kevyempiä kuormia ja vähemmän '
              'sarjoja noin kahden viikon ajan.',
              [shortDate(p.start), p.days],
            ),
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          if (p.sick)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('Älä treenaa kuumeisena tai jos koko kroppa on kipeä.'),
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => settings.endPause(), child: Text(t('Lopeta tauko'))),
          ),
        ],
      ),
    );
  }
}

/// Sali / Kestävyys -valinta etusivun yläreunassa (kielivalinnan tyylinen liuska).
class _ModeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ModeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String v, IconData icon, String label) {
      final on = value == v;
      return Material(
        color: on ? cs.surface : Colors.transparent,
        elevation: on ? 1 : 0,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => onChanged(v),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: on ? cs.onSurface : cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('gym', Icons.fitness_center, t('Sali')), seg('cardio', Icons.directions_run, t('Kestävyys'))],
      ),
    );
  }
}

/// Kestävyysnäkymä: lisää lenkki tai muu laji yhdellä napautuksella, viikon kilometrit, vauhti ja syke,
/// kevyiden lenkkien kehitys ja viimeisin suoritus.
class _CardioHome extends StatelessWidget {
  const _CardioHome();

  static void _add(BuildContext context, String? sport) {
    final today = dateOnly(DateTime.now());
    final w = Workout(
      date: today,
      title: sport ?? 'Liikunta',
      activity: sport,
      session: store.onDay(today).isEmpty ? 1 : store.nextSession(today),
    );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: w)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final today = dateOnly(DateTime.now());
    final acts = [
      for (final w in store.workouts)
        if (w.activity != null) w,
    ]..sort((a, b) => b.date.compareTo(a.date));
    // Käytetyimmät lajit pikavalinnoiksi (oletuksena juoksu, pyöräily, kävely).
    final counts = <String, int>{};
    for (final w in acts) {
      counts[w.activity!] = (counts[w.activity!] ?? 0) + 1;
    }
    final top = (counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!))).take(3).toList();
    for (final d in ['Juoksu', 'Pyöräily', 'Kävely']) {
      if (top.length < 3 && !top.contains(d)) top.add(d);
    }
    final main = top.first;
    final week = acts.where((w) => !w.date.isBefore(weekStart(today))).toList();
    final km = week.fold<double>(0, (a, w) => a + (w.distanceKm ?? 0));
    final runs = runsOf(store.workouts);
    final recentRuns = runs.where((r) => !r.date.isBefore(addDays(today, -27))).toList();
    final runKm = recentRuns.fold<double>(0, (a, r) => a + r.distanceKm!);
    final runSec = recentRuns.fold<int>(0, (a, r) => a + r.durationSec!);
    final hrs = [for (final w in acts.where((w) => !w.date.isBefore(addDays(today, -27)))) ?w.hrAvg];
    final trend = easyRunTrend(runs, today);
    String kmS(double v) => fmtNum((v * 10).round() / 10);

    Widget tile(String v, String l) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(l, style: sub, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _Cta(
          label: main == 'Juoksu' || main == 'Hölkkä' ? t('Lisää lenkki') : t('Lisää: {0}', [main]),
          icon: Icons.add_rounded,
          onTap: () => _add(context, main),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final sp in top.skip(1))
              ActionChip(avatar: Text(sportOf(sp)?.icon ?? '✨'), label: Text(sp), onPressed: () => _add(context, sp)),
            ActionChip(
              avatar: const Icon(Icons.more_horiz, size: 18),
              label: Text(t('Muu laji')),
              onPressed: () => _add(context, null),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            tile('${kmS(km)} km', t('tällä viikolla')),
            const SizedBox(width: 8),
            tile(runKm > 0 ? fmtPace(runSec / runKm) : '–', t('vauhti /km')),
            const SizedBox(width: 8),
            tile(hrs.isEmpty ? '–' : '${(hrs.reduce((a, b) => a + b) / hrs.length).round()}', t('keskisyke')),
          ],
        ),
        if (trend.paceNow != null && trend.pacePrev != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t('Kevyet lenkit: {0} → {1} /km (4 vk)', [fmtPace(trend.pacePrev!), fmtPace(trend.paceNow!)]),
              textAlign: TextAlign.center,
              style: sub,
            ),
          ),
        if (acts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t('Viimeksi: {0}', [
                [
                  acts.first.activity!,
                  if (runTypeOf(acts.first.runType) != null) t(runTypeOf(acts.first.runType)!.$2).toLowerCase(),
                  if (acts.first.distanceKm != null) '${kmS(acts.first.distanceKm!)} km',
                  shortDate(acts.first.date),
                ].join(' · '),
              ]),
              textAlign: TextAlign.center,
              style: sub,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t(
                'Kirjaa ensimmäinen lenkki tai muu laji: aika, matka ja kellon tiedot. Vauhti ja kehitys lasketaan itse.',
              ),
              textAlign: TextAlign.center,
              style: sub,
            ),
          ),
        if (runs.isNotEmpty)
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RunningScreen())),
              icon: const Icon(Icons.show_chart, size: 18),
              label: Text(t('Juoksun kehitys')),
            ),
          ),
      ],
    );
  }
}
