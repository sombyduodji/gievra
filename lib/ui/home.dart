import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'maps_screen.dart';
import '../maps/map_store.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'activity.dart';
import '../running.dart';
import '../sports.dart';
import '../gps_recorder.dart';
import '../app_state.dart';
import '../auto_backup.dart';
import '../custom_merge.dart';
import '../drafts.dart';
import '../exercises.dart';
import '../insights.dart';
import '../models.dart';
import '../ongoing.dart';
import '../time_zone.dart';
import '../session_compare.dart';
import '../program.dart';
import '../theme.dart';
import 'drawer.dart';
import 'dumbbell_review.dart';
import 'steps_ui.dart';
import '../daily_steps.dart';
import 'whats_new_dialog.dart';
import 'battery_ui.dart';
import 'injury_screen.dart';
import '../injuries.dart' show injuryById, injuryShortName, knownInjuries, injuryAdjusted;
import 'health_import.dart';
import '../health.dart' show HealthConnect, newHealthSessions;
import 'intro.dart';
import 'program_screen.dart';
import 'run_bands.dart';
import 'running_bar.dart';
import 'start_panels.dart';
import 'home_extras_ui.dart';
import 'shell.dart' show MainShell;
import 'body_screen.dart';
import 'bug_report.dart';
import 'new_workout.dart';
import 'widgets.dart';
import 'workout.dart';
import '../l10n.dart';
import '../share_text.dart' show thousands;
import '../weekly_activity.dart';

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
  final key = (store.rev, store.workouts.length, settings.deloadEvery, dateOnly(DateTime.now()), uiLang, nameMode);
  if (key != _insKey || _ins == null) {
    _ins = analyze(store.workouts, deloadEvery: settings.deloadEvery);
    _insKey = key;
  }
  return _ins!;
}

/// Avaa kesken olevan liikunnan: GPS-tallennus (taustalla tai Androidin sulkema) tai liikuntaluonnos (ajanotto,
/// lomake). Käynnistyksessä ja alapalkin "käynnissä" -palkista. False = ei mitään avattavaa.
Future<bool> openPendingActivity(BuildContext context) async {
  final sport = await GpsRecorder.pendingSport();
  final d = await ActivityDraft.load();
  if (!context.mounted) return false;
  if (sport != null) {
    final today = dateOnly(DateTime.now());
    final same = d != null && d.$1.activity == sport;
    final w = same
        ? d.$1
        : Workout(
            date: today,
            title: sport,
            activity: sport,
            session: store.onDay(today).isEmpty ? 1 : store.nextSession(today),
          );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivityScreen(workout: w, recoverGps: true, draft: same ? d.$2 : null),
      ),
    );
    return true;
  }
  if (d == null) return false;
  final (w, extra) = d;
  // Samalle päivälle tallennettu treeni samalla numerolla: luonnos on jo tallennettu.
  if (store.onDay(w.date).any((x) => x.session == w.session && x.activity == w.activity)) {
    await ActivityDraft.clear();
    return false;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ActivityScreen(workout: w, draft: extra),
    ),
  );
  return true;
}

/// Avaa päivän treenin: yksi treeni muokattavaksi, useampi valittavaksi, muuten uusi.
void openDate(BuildContext context, DateTime d) {
  // Tauko ei pääty treeniin (käyttäjä 16.11.): treeni ja liikunta ovat sallittuja, vain muistutus näkyy.
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
          // Valmis salitreeni: yhteenveto ensin kuten liikunnassa, Muokkaa avaa liikelistan (käyttäjä 15.11.).
          : w != null && (w.minutes != null || w.feeling != null)
          ? SavedScreen(workout: w, history: true)
          : w != null
          ? WorkoutScreen(workout: w.copy(), planDay: day == null ? null : injuryAdjusted(day, settings.injuries))
          : NewWorkoutScreen(date: d, newSession: newSession),
    ),
  );
}

/// Päivän yhteenveto kalenterista: askeleet ja päivän treenit (myös yksi), josta treeni avataan tai uusi lisätään.
void showDay(BuildContext context, DateTime d) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DayPager(day: dateOnly(d))));

/// Päivän näkymä, jossa pyyhkäisy vasemmalle / oikealle vaihtaa seuraavaan / edelliseen päivään.
class _DayPager extends StatefulWidget {
  final DateTime day;
  const _DayPager({required this.day});

  @override
  State<_DayPager> createState() => _DayPagerState();
}

class _DayPagerState extends State<_DayPager> {
  /// Sivu [_origin] on tämä päivä; taaksepäin noin 55 vuotta, eteenpäin vuosi (suunnitellut treenit).
  static const _origin = 20000;
  static const _ahead = 366;
  late final DateTime _today = dateOnly(DateTime.now());
  late final PageController _pages = PageController(initialPage: _origin + _offset(widget.day));
  late DateTime _day = widget.day;

  int _offset(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(_today.year, _today.month, _today.day)).inDays;

  DateTime _at(int page) => addDays(_today, page - _origin);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: BarTitle(Text(_day == _today ? t('Tänään') : longDateYear(_day))), bottom: samiBarBand),
    body: PageView.builder(
      controller: _pages,
      itemCount: _origin + _ahead + 1,
      onPageChanged: (i) => setState(() => _day = _at(i)),
      itemBuilder: (_, i) => _DayScreen(day: _at(i)),
    ),
  );
}

class _DayScreen extends StatelessWidget {
  final DateTime day;
  const _DayScreen({required this.day});

  /// Treenin mittarit kuvakkeineen: liikunnasta aika, matka, vauhti, askeleet ja syke; salista sarjat ja kesto.
  static List<(IconData, String)> _metrics(Workout w) => w.activity != null
      ? [
          if (w.durationSec != null) (Icons.timer_outlined, fmtDurationSec(w.durationSec!)),
          if (w.distanceKm != null) (Icons.straighten, '${fmtNum(w.distanceKm!)} km'),
          if (w.paceSecPerKm != null) (Icons.speed, paceText(w.paceSecPerKm!, w.activity, short: true)),
          if (w.steps != null) (Icons.directions_walk, thousands(w.steps!)),
          if (w.hrAvg != null) (Icons.favorite_border, '${w.hrAvg}'),
        ]
      : [
          (Icons.fitness_center, setsLabel(w.exercises.fold<int>(0, (a, e) => a + e.workSets.length))),
          if (w.minutes != null) (Icons.timer_outlined, '${w.minutes} min'),
          if (w.hrAvg != null) (Icons.favorite_border, '${w.hrAvg}'),
        ];

  void _newActivity(BuildContext context) {
    final w = Workout(date: day, title: 'Liikunta', session: store.onDay(day).isEmpty ? 1 : store.nextSession(day));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: w)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final today = dateOnly(DateTime.now());
    return ListenableBuilder(
      listenable: Listenable.merge([store, dailySteps, settings]),
      builder: (context, _) {
        // Aikajärjestyksessä (aloitusaika); ilman aikaa olevat tallennusjärjestyksessä loppuun.
        final ws = [...store.onDay(day)]
          ..sort((a, b) {
            final x = a.started, y = b.started;
            if (x != null && y != null) return x.compareTo(y);
            if (x != null) return -1;
            if (y != null) return 1;
            return a.session.compareTo(b.session);
          });
        final steps = stepsTabAvailable ? dailySteps.at(day) : null;
        final minutes = ws.fold<int>(0, (a, w) => a + ((w.durationSec ?? (w.minutes ?? 0) * 60) ~/ 60));
        final km = ws.fold<double>(0, (a, w) => a + (w.distanceKm ?? 0));
        // Päivän yhteenvetoruudut kuvakkeineen.
        Widget tile(IconData icon, Color color, String value, String label, {VoidCallback? onTap}) => Expanded(
          child: Material(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                child: Column(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, style: sub, maxLines: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
          children: [
            // Päivä tauon aikana: tauon tiedot ja muokkaus (päivät, syy) suoraan kalenterista (käyttäjä 16.11.).
            if (settings.pauseOn(day) case final pz?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Material(
                  color: Sami.blue.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    key: const ValueKey('dayPause'),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: Text(pz.injury ? '🩹' : (pz.sick ? '🤒' : '🏖'), style: const TextStyle(fontSize: 22)),
                    title: Text(
                      pz.injury ? t('Vammatauko') : (pz.sick ? t('Sairastauko') : t('Loma')),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      pz.end == null
                          ? t('alkoi {0}, jatkuu', [shortDate(pz.start)])
                          : '${shortDate(pz.start)}–${shortDate(pz.end!)}',
                    ),
                    trailing: Text(
                      t('Muokkaa'),
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                    ),
                    onTap: () => showPauseDialog(context, edit: pz),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                tile(Icons.event_available, Sami.red, '${ws.length}', t('treeniä')),
                const SizedBox(width: 8),
                tile(Icons.timer_outlined, Sami.blue, minutes == 0 ? '–' : fmtDuration(minutes), t('aika')),
                if (km > 0) ...[
                  const SizedBox(width: 8),
                  tile(Icons.straighten, Sami.green, fmtNum((km * 10).round() / 10), 'km'),
                ],
                if (stepsTabAvailable) ...[
                  const SizedBox(width: 8),
                  tile(
                    Icons.directions_walk,
                    cs.primary,
                    steps == null ? '–' : thousands(steps),
                    t('askelta'),
                    onTap: steps == null ? null : () => showStepsDay(context, day),
                  ),
                ],
              ],
            ),
            if (steps != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (day == today)
                      t('Askeleet tähän mennessä')
                    else if (stepsMayChange(day))
                      t('Askeleet voivat vielä päivittyä'),
                    ...?dailySteps.apps[day],
                    ...stepsAddedNotes(day),
                  ].join(' · '),
                  style: sub,
                ),
              ),
            SectionLabel(ws.isEmpty ? t('Treenit') : t('Treenit ({0})', [ws.length])),
            if (ws.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.self_improvement, color: cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t('Ei treenejä tälle päivälle.'), style: sub)),
                  ],
                ),
              ),
            for (final w in ws)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                // Vasen reuna lajin värillä (sali punainen, liikunta vihreä; luonnos paiva).
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: (w.activity != null ? greenText(context) : redText(context)).withValues(alpha: .5),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _open(context, day, w),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: (w.activity != null ? Sami.green : Sami.red).withValues(alpha: .14),
                          child: Text(
                            w.activity != null ? (sportOf(w.activity)?.icon ?? '🏃') : '💪',
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      w.activity != null ? sportName(w.activity!) : trName(w.title),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (w.started != null)
                                    Text(
                                      '${w.started!.hour}:${w.started!.minute.toString().padLeft(2, '0')}',
                                      style: sub,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  for (final (icon, text) in _metrics(w))
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(icon, size: 15, color: cs.onSurfaceVariant),
                                        const SizedBox(width: 3),
                                        Text(text, style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                ],
                              ),
                              if (w.activity == null && w.exercises.any((e) => e.sets.isNotEmpty))
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    [for (final e in w.exercises.where((e) => e.sets.isNotEmpty)) exerciseLabel(e.name)]
                                        .join(', '),
                                    style: sub,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        w.minutes != null || w.feeling != null
                            ? Text(feelingOf(w.feeling)?.$2 ?? '✓', style: const TextStyle(fontSize: 20))
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(t('kesken'), style: TextStyle(fontSize: 12, color: cs.primary)),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            // Health Connectin harjoitukset, joita ei vielä ole Gievrassa (tämän päivän osalta).
            if (!day.isAfter(today) && HealthImportButton.visible) _DayHealthRow(day: day),
            if (!day.isAfter(today)) ...[
              const SizedBox(height: 8),
              // Molemmat: sama nuolipari kuin etusivulla, tasan 50/50 (lisätään tälle päivälle, ei suositusta).
              // Keskeneräinen salitreeni tälle päivälle: Jatka kuten etusivulla (ennen "Sali" aloitti uuden, yötesti 15.11.).
              if (settings.trainMode == 'both')
                Builder(
                  builder: (context) {
                    final open = ws.where((x) => x.activity == null && x.minutes == null && x.feeling == null).toList();
                    return _SplitCta(
                      even: true,
                      gymWide: true,
                      gymOpen: open.isNotEmpty,
                      activityIcon: _lastSportIcon(),
                      gymSemantics: open.isEmpty ? t('Aloita salitreeni') : t('Jatka treeniä'),
                      onGym: () => open.isEmpty
                          ? _startNew(context, day, gymOnly: true)
                          : open.length == 1
                          ? _open(context, day, open.single)
                          : _chooseSession(context, day, open),
                      onActivity: () => _newActivity(context),
                    );
                  },
                )
              else
                Row(
                  children: [
                    if (settings.trainMode == 'gym')
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Sami.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => _startNew(context, day, gymOnly: true),
                          icon: const Icon(Icons.add),
                          label: Text(t('Sali')),
                        ),
                      ),
                    if (settings.trainMode == 'cardio')
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Sami.green,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => _newActivity(context),
                          icon: const Icon(Icons.add),
                          label: Text(t('Liikunta')),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Uusi treeni päivälle: ensimmäinen tai saman päivän seuraava (vvvv-kk-pp-2.md …).
/// [gymOnly]: salinäkymästä aloitettu, joten tyyppivalintaa (sali / liikunta) ei näytetä.
void _startNew(BuildContext context, DateTime d, {bool gymOnly = false}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => NewWorkoutScreen(date: d, newSession: store.onDay(d).isNotEmpty, gymOnly: gymOnly),
    ),
  );
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
              title: Text(w.activity != null ? sportName(w.activity!) : trName(w.title)),
              subtitle: Text(
                [
                  ?durationRounded(w),
                  if (w.distanceKm != null) '${fmtNum(w.distanceKm!)} km',
                  if (w.activity == null) setsLabel(w.exercises.fold<int>(0, (a, e) => a + e.workSets.length)),
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

/// Kesken jääneen tallennuksen tai luonnoksen palautus on tehty tässä prosessissa.
bool _resumeDone = false;

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// Kalenteri: oletuksena vain tämä viikko (vähemmän tilaa), kuukausi avautuu napista.
  bool _monthView = false;

  /// Etusivun viikkonäkymä: viikkoja tästä viikosta (0 = tämä viikko; yön yli auki pysyy ajan tasalla).
  int _weekShift = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSteps();
    _resume();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkMoves()
          .then((_) => _checkElevFormat())
          .then((_) => _checkWhatsNew())
          .then((_) => mounted ? askDailyWeight(context) : null),
    );
  }

  /// Päivän askeleet: haku käynnistyessä, sovellukseen palatessa ja noin 15 minuutin välein etusivun ollessa auki.
  /// Viimeiset 7 päivää luetaan joka kerta uudelleen (Oura voi synkronoida myöhemmin).
  void _refreshSteps() {
    if (!stepsTabAvailable) return;
    // Piirron jälkeen (haku ilmoittaa muutoksista heti; rakennusvaiheessa ei saa).
    WidgetsBinding.instance.addPostFrameCallback((_) => dailySteps.refresh());
    dailySteps.startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      tzWatch.check();
      dayWatch.check();
      _refreshSteps();
      // Päivän ensimmäinen avaus: paino (vain kun etusivu on päällimmäisenä, ei kesken treenin).
      if (ModalRoute.of(context)?.isCurrent ?? false) askDailyWeight(context);
    } else if (state == AppLifecycleState.paused) {
      dailySteps.stopTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    dailySteps.stopTimer();
    super.dispose();
  }

  /// Päivityksen jälkeen kerran: uudet ominaisuudet (ei verkkodemossa).
  Future<void> _checkWhatsNew() async {
    if (isDemo || !mounted) return;
    try {
      await maybeShowWhatsNew(context);
      // Päivityksen jälkeen kerran: salli toiminta taustalla (uusi asennus näki sen aloituksessa).
      if (mounted) await maybeShowBatteryHint(context);
    } catch (_) {}
  }

  /// Päivityksen jälkeen: ladatut korkeustiedostot vanhassa muodossa (0.5) → kerro ja tarjoa päivitystä. Vanhat
  /// toimivat yhä, mutta uusi lohkomuoto käyttää isoilla alueilla (esim. Inari) paljon vähemmän muistia. Kysytään
  /// uudelleen aikaisintaan viikon päästä, jos käyttäjä valitsee Myöhemmin.
  Future<void> _checkElevFormat() async {
    if (isDemo || kIsWeb) return;
    try {
      final ms = MapStore.instance;
      await ms.load(network: false);
      final old = await ms.oldFormatElevation();
      if (old.isEmpty || !mounted) return;
      final sp = await SharedPreferences.getInstance();
      final last = sp.getInt('elevFormatAsked') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last < const Duration(days: 7).inMilliseconds) return;
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Korkeustiedot on päivitetty')),
          content: Text(
            t(
              'Ladatut korkeustiedot ({0} aluetta) ovat vanhassa muodossa. Uusi muoto vie isoilla alueilla paljon '
              'vähemmän muistia. Vanhat toimivat yhä, mutta päivitä ne, kun olet verkossa: uudet tiedostot '
              'tarkistetaan latauksessa (SHA-256).',
              [old.length],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Myöhemmin'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Päivitä nyt'))),
          ],
        ),
      );
      await sp.setInt('elevFormatAsked', DateTime.now().millisecondsSinceEpoch);
      if (go == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MapsScreen(initialTab: 2)));
      }
    } catch (_) {}
  }

  /// Omat liikkeet, jotka vastaavat valmista liikettä: sama nimi yhdistetään, samankaltaisesta kysytään.
  Future<void> _checkMoves() async {
    if (isDemo || settings.customExercises.isEmpty) return;
    final matches = findMoveMatches(settings.customExercises, builtinExercises(), declined: await declinedMatches());
    for (final m in matches) {
      if (!mounted) return;
      if (m.identical) {
        final n = await mergeMove(m);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('Oma liike {0} yhdistettiin Gievran liikkeeseen {1} ({2} treeniä).', [
                m.custom,
                exerciseLabel(m.builtin),
                n,
              ]),
            ),
          ),
        );
        continue;
      }
      final same = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(t('Ovatko nämä sama liike?')),
          content: Text(
            t(
              'Oma liikkeesi: {0}\nGievran liike: {1}\n\nJos ovat, treenisi, ohjelmasi ja ennätyksesi siirtyvät '
              'Gievran liikkeelle, ja saat sen liikeohjeen ja animaation.',
              [m.custom, exerciseLabel(m.builtin)],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Eri liikkeet'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Sama liike, yhdistä'))),
          ],
        ),
      );
      if (same == true) {
        final n = await mergeMove(m);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Yhdistetty: {0} treeniä siirtyi liikkeelle {1}.', [n, exerciseLabel(m.builtin)]))),
        );
      } else if (same == false) {
        await declineMatch(m);
      }
    }
  }

  /// Android sulki sovelluksen kesken: ensin kesken jäänyt GPS-tallennus (jatkuu siitä), muuten keskeneräinen
  /// liikuntakirjaus (lomake ennen Tallenna-painiketta).
  Future<void> _resume() async {
    // Kerran käynnistystä kohden: etusivu voi rakentua uudelleen (esim. tekstin koko asetuksista), jolloin
    // palautus avautui kahdesti ja sijaintilupaa kysyttiin kahdesti (päivätesti 14.11.).
    if (_resumeDone) return;
    _resumeDone = true;
    await openPendingActivity(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, store, autoBackup, AwayActivity.changes]),
      builder: (context, _) {
        final now = DateTime.now();
        final today = dateOnly(now);
        return Scaffold(
          appBar: AppBar(
            title: BarTitle(
              Text(
                (settings.name ?? '').isEmpty ? '${seGreeting(now)}!' : '${seGreeting(now)}, ${settings.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Matalampi palkki: viiva lähemmäs tervehdystä; suurella tekstillä korkeampi, ettei teksti leikkaudu.
            toolbarHeight: (MediaQuery.textScalerOf(context).scale(22) + 22).clamp(44.0, 80.0),
            // Ohut saamen viiva heti tervehdyksen alla (käyttäjä 16.11.: tiiviimpi, tekstit ja viiva ennallaan).
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(8),
              child: Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 4), child: SamiBand(height: 4, pattern: false)),
            ),
            actions: [
              // Päivämäärä ohjeen vieressä (luonnos etusivu4).
              Center(
                // Päiväys enintään 1,3-kertaisena: 2-kertaisella järjestelmäfontilla se vei tilan tervehdykseltä.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(shortDate(now), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ),
              ),
              IconButton(
                key: const ValueKey('homeHelpButton'),
                tooltip: t('Ohje'),
                icon: const Icon(Icons.help_outline),
                onPressed: () => showHomeHelp(context),
              ),
            ],
          ),
          body: RefreshIndicator(
            // Alas vetäminen: treenit, askeleet ja Health Connect (ennen vain treenit).
            onRefresh: () async {
              await store.reload();
              if (stepsTabAvailable) await dailySteps.refresh();
              await HealthImportButton.refresh();
              await NightHrData.refresh(force: true);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 32),
              children: [
                // Vammatila ja tauko näkyvät heti ylhäällä, kun ne ovat päällä.
                if (knownInjuries(settings.injuries).isNotEmpty) _InjuryBanner(),
                if (settings.activePause != null) _PauseBanner(),
                if (settings.activePause == null && settings.upcomingPause != null) _UpcomingPauseBanner(),
                // Treenitiedostot, joita ei voitu lukea: ennen ne puuttuivat historiasta ilman selitystä.
                if (store.unreadable.isNotEmpty) _UnreadableBanner(),
                // Päivityksen jälkeinen automaattinen varmuuskopio: edistyminen ja mahdollinen virhe.
                if (autoBackup.running)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t('Varmuuskopioidaan treenit päivityksen jälkeen…'),
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        const LinearProgressIndicator(),
                      ],
                    ),
                  )
                else if (autoBackup.error != null)
                  _ModeBanner(
                    color: Sami.red,
                    emoji: '⚠️',
                    title: autoBackup.error!,
                    detail: t(
                      'Yritetään uudelleen seuraavalla käynnistyksellä. Tee varmuuskopio itse: Lisää → Tuonti, vienti ja varmuuskopio.',
                    ),
                    onTap: () => autoBackup.dismissError(),
                  ),
                // Kahden käsipainon vanhat painot: tarkistus kerran (yhteensä vai käsipainoa kohden).
                if (store.workouts.any((w) => w.dumbbellReview))
                  _ModeBanner(
                    key: const ValueKey('dumbbellReviewBanner'),
                    color: Sami.yellow,
                    emoji: '🏋️',
                    title: t('Tarkista käsipainojen painot'),
                    detail: t(
                      'Kahden käsipainon liikkeet kirjataan nyt yhteispainona. Tarkista kerran, olivatko vanhat painot '
                      'yhteensä vai käsipainoa kohden.',
                    ),
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => const DumbbellReviewScreen())),
                  ),
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
                            'tilastoja ja ohjelman tekoa (Ohjelma → Tee uusi ohjelma → Tallenna pohja). '
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
                // Treeni käynnissä (liikunta taustalla tai keskeneräinen salitreeni): yksi Jatka-kortti aloitusten tilalla
                // (käyttäjä 17.11.); aloitukset palaavat, kun treeni on valmis.
                if (RunningBar.active(now)) ...[
                  const SizedBox(height: 14),
                  const RunningBar(big: true),
                  if (HealthImportButton.visible) HealthImportButton(),
                ] else ...[
                  // Aloitus (käyttäjä 17.11., ui-test): jaettu Sali | Liikunta -painike avaa paneelin etusivun päälle.
                  const SizedBox(height: 14),
                  StartSplitButton(), // ei const: päivittyy treenien ja asetusten mukana
                  if (HealthImportButton.visible) HealthImportButton(),
                  if (store.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(store.error!, style: TextStyle(color: cs.error)),
                    ),
                ],
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    // Päivän askeleet päivittyvät kalenteriin ilman koko etusivun uudelleenrakennusta.
                    child: ListenableBuilder(
                      listenable: dailySteps,
                      // Jaksokortti (käyttäjä 17.11.): Viikko | Kuukausi, ‹ jakso ›, renkaat ja kalenteri.
                      builder: (context, _) => PeriodCard(
                        monthView: _monthView,
                        month: _month,
                        weekOf: addDays(today, 7 * _weekShift),
                        onMode: (m) => setState(() {
                          _monthView = m;
                          _month = DateTime(now.year, now.month);
                          _weekShift = 0;
                        }),
                        onShift: (n) => setState(() {
                          if (_monthView) {
                            _month = DateTime(_month.year, _month.month + n);
                          } else {
                            _weekShift += n;
                          }
                        }),
                        calendar: MonthCalendar(
                          month: _month,
                          week: !_monthView,
                          home: true,
                          weekOf: addDays(today, 7 * _weekShift),
                          onShift: (n) => setState(() => _month = DateTime(_month.year, _month.month + n)),
                        ),
                      ),
                    ),
                  ),
                ),
                // Valittavat kortit asetusten järjestyksessä (Asetukset → Etusivu; käyttäjä 17.11.).
                for (final id in settings.homeOrder)
                  if (settings.homeCardOn(id))
                    switch (id) {
                      'goals' => GoalsCard(
                        monthView: _monthView,
                        month: _month,
                        weekOf: addDays(today, 7 * _weekShift),
                      ),
                      'recent' => store.workouts.isNotEmpty ? _Recent() : const SizedBox.shrink(),
                      'strength' => _InsightsCard(strength: true), // ei const: lukee treenit ja asetukset
                      'running' => _InsightsCard(strength: false),
                      'weight' => const WeightTodayCard(),
                      'next' => NextDayCard(), // ei const: lukee ohjelman ja treenit
                      'streak' => StreakCard(), // ei const: lukee treenit ja tauot
                      'recovery' => const NightHrCard(),
                      _ => const SizedBox.shrink(),
                    },
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Molemmat-tilan painikkeet rinnakkain, jaettuna keskeltä nuolina (mockup 7 B, käyttäjän valinta 14.11.): vasemmalla
/// punainen Sali kärjellä, oikealla vihreä Liikunta lovella. Käytetympi puoli on leveämpi (60/40, [_gymFirst]).
/// Tekstiä ei katkaista millään kielellä tai tekstikoolla: jos pienemmän puolen sana ei mahdu, jako siirtyy kohti
/// 50/50; vasta sitten otsikko pienenee (FittedBox). Alarivi (ohjelman päivä, viimeisin liikunta) jää pois, jos se
/// ei mahdu. Ruudunlukija lukee koko toiminnon ("Aloita salitreeni").
class _SplitCta extends StatelessWidget {
  final bool gymWide, gymOpen;

  /// Tasan 50/50 (päivänäkymä: lisätään tietylle päivälle, kumpikaan ei ole suositus).
  final bool even;

  /// Viimeksi tehdyn liikuntalajin emoji Liikunta-puolelle (käyttäjä 15.11.: ei Viimeksi-alariviä, laji näkyy
  /// heti seuraavassa vaiheessa). Ei liikuntaa vielä: yleinen juoksija.
  final String activityIcon;
  final String gymSemantics;
  final VoidCallback onGym, onActivity;
  const _SplitCta({
    required this.gymWide,
    required this.gymOpen,
    required this.activityIcon,
    required this.gymSemantics,
    required this.onGym,
    required this.onActivity,
    this.even = false,
  });

  static const gap = 6.0, arrow = 14.0, radius = 18.0, iconSize = 22.0, iconGap = 8.0;

  /// Kuvake jää pois, jos otsikko ei mahtuisi sen kanssa vähintään tähän kokoon (ennen pienennystä jako siirtyy).
  static const minScaleWithIcon = .85;

  // Kummallakin puolella kuvake ja otsikko keskellä, ei alarivejä: otsikot ovat aina samalla korkeudella
  // (käyttäjä 15.11.: Sali ja Liikunta olivat eri korkeudella, kun vain toisella oli alarivi).
  // Sali: valkoinen käsipaino (kesken: ▶). Liikunta: viimeksi tehdyn lajin emoji.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final scaler = MediaQuery.textScalerOf(context);
      const wideStyle = TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, height: 1.15);
      const narrowStyle = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.15);
      const evenStyle = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.15);
      const emojiStyle = TextStyle(fontSize: 20, height: 1);
      // Teeman fontilla (DefaultTextStyle): ilman sitä mittaus käytti oletusfonttia, joka voi olla eri kuin näytöllä.
      final base = DefaultTextStyle.of(context).style;
      Size measure(String s, TextStyle st, {TextScaler? sc}) => (TextPainter(
        text: TextSpan(text: s, style: base.merge(st)),
        textDirection: TextDirection.ltr,
        textScaler: sc ?? scaler,
      )..layout()).size;

      final w = c.maxWidth;
      final gymTitle = gymOpen ? t('Jatka') : t('Sali');
      final actTitle = t('Liikunta');
      TextStyle styleOf(bool isGym) => even ? evenStyle : (isGym == gymWide ? wideStyle : narrowStyle);
      // Kuvakkeet eivät kasva tekstikoon mukana (kuten muutkin kuvakkeet).
      final actIconW = measure(activityIcon, emojiStyle, sc: TextScaler.noScaling).width;
      double iconW(bool isGym) => (isGym ? iconSize : actIconW) + iconGap;
      double titleW(bool isGym) => measure(isGym ? gymTitle : actTitle, styleOf(isGym)).width;
      // Sisällön tila: kärki/lovi ja reunukset pois.
      double room(double width) => width - arrow - 20;

      var wide = ((w - gap) * (even ? .5 : .6)).roundToDouble();
      var narrow = w - gap - wide;
      // Pienemmän puolen sana (kuvakkeineen) ei mahdu: jako siirtyy kohti 50/50 ennen kuin mitään pienennetään.
      if (!even) {
        final need = titleW(!gymWide) + iconW(!gymWide);
        if (need > room(narrow)) {
          final shift = math.min(need - room(narrow), (w - gap) / 2 - narrow);
          narrow += shift;
          wide -= shift;
        }
      }
      final gymW = gymWide ? wide : narrow, actW = gymWide ? narrow : wide;
      bool showIcon(bool isGym) => titleW(isGym) * minScaleWithIcon + iconW(isGym) <= room(isGym ? gymW : actW);
      final titleH = measure('Åg', styleOf(true)).height;
      final h = math.max(64.0, 20 + titleH);

      Widget content({required bool isGym}) {
        final icon = !showIcon(isGym)
            ? null
            : isGym
            ? Icon(
                gymOpen ? Icons.play_arrow_rounded : Icons.fitness_center_rounded,
                color: Colors.white,
                size: iconSize,
              )
            : Text(activityIcon, style: emojiStyle, textScaler: TextScaler.noScaling);
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[icon, const SizedBox(width: iconGap)],
                Text(isGym ? gymTitle : actTitle, maxLines: 1, style: styleOf(isGym)),
              ],
            ),
          ),
        );
      }

      Widget piece({required bool isGym, required double width}) {
        final colors = isGym ? const [Sami.red, Color(0xFFA3170D)] : const [Color(0xFF00843D), Color(0xFF00692F)];
        final pad = isGym
            ? const EdgeInsets.fromLTRB(12, 10, arrow + 8, 10)
            : const EdgeInsets.fromLTRB(arrow + 8, 10, 12, 10);
        return Semantics(
          button: true,
          label: isGym ? gymSemantics : t('Aloita liikunta'),
          excludeSemantics: true,
          child: ClipPath(
            clipper: _ArrowClip(point: isGym),
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
                child: InkWell(
                  key: ValueKey(isGym ? 'splitGym' : 'splitActivity'),
                  onTap: isGym ? onGym : onActivity,
                  child: SizedBox(
                    width: width,
                    height: h,
                    child: Padding(
                      padding: pad,
                      child: content(isGym: isGym),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      // Kärki menee loven kohdalle: vasen pala on kärjen verran leveämpi, oikea alkaa [gap] kärjen jälkeen.
      return SizedBox(
        height: h,
        child: Stack(
          children: [
            Positioned(left: 0, top: 0, bottom: 0, child: piece(isGym: true, width: gymW + arrow)),
            Positioned(
              left: gymW + gap,
              top: 0,
              bottom: 0,
              child: piece(isGym: false, width: actW),
            ),
          ],
        ),
      );
    },
  );
}

/// Viimeksi tehdyn liikuntalajin emoji (Sali/Liikunta-parin Liikunta-puolelle).
String _lastSportIcon() {
  final last = latestWorkouts(store.workouts.where((w) => w.activity != null).toList(), 1).firstOrNull;
  return sportOf(last?.activity)?.icon ?? '🏃';
}

/// Vasen pala: pyöristetty vasen reuna ja kärki oikealla. Oikea pala: lovi vasemmalla, pyöristetty oikea reuna.
class _ArrowClip extends CustomClipper<Path> {
  final bool point;
  const _ArrowClip({required this.point});

  @override
  Path getClip(Size s) {
    const r = _SplitCta.radius, a = _SplitCta.arrow;
    final p = Path();
    if (point) {
      p
        ..moveTo(r, 0)
        ..lineTo(s.width - a, 0)
        ..lineTo(s.width, s.height / 2)
        ..lineTo(s.width - a, s.height)
        ..lineTo(r, s.height)
        ..quadraticBezierTo(0, s.height, 0, s.height - r)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0);
    } else {
      p
        ..moveTo(0, 0)
        ..lineTo(s.width - r, 0)
        ..quadraticBezierTo(s.width, 0, s.width, r)
        ..lineTo(s.width, s.height - r)
        ..quadraticBezierTo(s.width, s.height, s.width - r, s.height)
        ..lineTo(0, s.height)
        ..lineTo(a, s.height / 2);
    }
    return p..close();
  }

  @override
  bool shouldReclip(_ArrowClip old) => old.point != point;
}

/// Urheilun ja liikunnan väri kalenterissa.
const sportColor = Color(0xFF2BA6A6);

class MonthCalendar extends StatelessWidget {
  final DateTime month;
  final void Function(int) onShift;

  /// Vain tämä viikko (tiivis); [onToggle] vaihtaa viikon ja kuukauden välillä (null: ei vaihtoa, esim. Tilastot).
  final bool week;
  final VoidCallback? onToggle;

  /// Etusivun kortti (ui-test 17.11.): ei omaa otsikkoa eikä yhteenvetoriviä (kortissa valitsin ja renkaat),
  /// tänään keltaisella tekstillä kehän sijaan, pisteinä vain sali ja liikunta.
  final bool home;

  /// Näytettävä viikko ([week]): mikä tahansa sen päivä; oletuksena tämä viikko.
  final DateTime? weekOf;
  const MonthCalendar({
    super.key,
    required this.month,
    required this.onShift,
    this.week = false,
    this.onToggle,
    this.home = false,
    this.weekOf,
  });

  /// ISO-viikkonumero.
  static int weekNumber(DateTime d) => isoWeek(d);

  /// Päivän pisteet (ulkoasun kohennus 16.11.): punainen = salitreeni, vihreä = liikunta, keltainen = ennätys.
  List<Color> _dots(Workout w) => [
    if (w.activity == null && w.exercises.any((e) => e.sets.isNotEmpty)) Sami.redLight,
    if (w.activity != null) Sami.greenLight,
    if (!home && w.exercises.any((e) => e.sets.any((s) => s.pr))) Sami.yellow,
  ];

  /// Viikonpäivien rivi; etusivulla tämän päivän viikonpäivä keltaisella lihavoituna.
  Widget _weekdays(BuildContext context, int? todayCol) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final (i, d) in uiWeekdaysShort.indexed)
          Expanded(
            child: Center(
              child: Text(
                d,
                style: i == todayCol
                    ? TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: yellowText(context))
                    : TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
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
    if (week) {
      // Tämä viikko maanantaista sunnuntaihin (voi ulottua kahteen kuukauteen).
      final mon = weekStart(weekOf ?? today);
      final days7 = [for (var i = 0; i < 7; i++) addDays(mon, i)];
      final byDate = <DateTime, List<Workout>>{};
      for (final w in store.workouts) {
        if (!w.date.isBefore(mon) && w.date.isBefore(addDays(mon, 7))) (byDate[w.date] ??= []).add(w);
      }
      return Column(
        children: [
          if (!home)
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SeCaption('Vahkku ${weekNumber(today)}'),
                    Text(
                      t('Viikko {0}', [weekNumber(today)]),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onToggle,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(t('Kuukausi')),
                ),
              ],
            ),
          // Viikonpäivät omana matalana rivinä (ei neliön kokoisia soluja).
          _weekdays(context, home && days7.contains(today) ? today.weekday - 1 : null),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            crossAxisSpacing: 4,
            childAspectRatio: 1.1,
            children: [
              for (final d in days7)
                _DayCell(
                  day: d.day,
                  isToday: d == today,
                  yellowToday: home,
                  workout: byDate[d]?.first,
                  dots: byDate[d] == null ? const [] : {for (final w in byDate[d]!) ..._dots(w)}.toList(),
                  steps: stepsTabAvailable ? dailySteps.at(d) : null,
                  onTap: d.isAfter(today) ? null : () => showDay(context, d),
                ),
            ],
          ),
          // Viikon yhteenveto: salikerrat, liikuntaminuutit ja tämän päivän askeleet päivitysaikoineen.
          if (!home)
            Builder(
              builder: (context) {
                final a = weekActivity(store.workouts, today);
                final gym = {
                  for (final ws in byDate.values)
                    for (final w in ws)
                      if (w.activity == null && w.exercises.any((e) => e.sets.isNotEmpty)) w.date,
                }.length;
                final steps = stepsTabAvailable ? dailySteps.at(today) : null;
                final at = dailySteps.lastRefresh;
                final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '● ',
                              style: TextStyle(color: redText(context)),
                            ),
                            TextSpan(text: t('sali {0}', [gym])),
                            if (settings.sports) ...[
                              const TextSpan(text: '  '),
                              TextSpan(
                                text: '● ',
                                style: TextStyle(color: greenText(context)),
                              ),
                              TextSpan(text: t('{0}/{1} min', [a.moderateEq, whoMinutes])),
                            ],
                          ],
                        ),
                        style: sub,
                      ),
                      if (steps != null)
                        Text(
                          at == null
                              ? '👣 ${thousands(steps)}'
                              : '👣 ${thousands(steps)} · ${t('klo {0}', ['${at.hour}.${at.minute.toString().padLeft(2, '0')}'])}',
                          style: sub,
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      );
    }

    final inMonth = today.year == month.year && today.month == month.month;
    final cells = <Widget>[
      for (final (i, d) in uiWeekdaysShort.indexed)
        Center(
          child: Text(
            d,
            style: home && inMonth && i == today.weekday - 1
                ? TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: yellowText(context))
                : TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++)
        _DayCell(
          day: d,
          isToday: DateTime(month.year, month.month, d) == today,
          yellowToday: home,
          workout: byDay[d]?.first,
          dots: byDay[d] == null ? const [] : {for (final w in byDay[d]!) ..._dots(w)}.toList(),
          steps: stepsTabAvailable ? dailySteps.at(DateTime(month.year, month.month, d)) : null,
          // Taukopäivät sinisellä pohjalla (myös etukäteen merkitty loma).
          pause: settings.pauseOn(DateTime(month.year, month.month, d)) != null,
          onTap: DateTime(month.year, month.month, d).isAfter(today)
              ? null
              : () => showDay(context, DateTime(month.year, month.month, d)),
        ),
    ];

    return Column(
      children: [
        if (!home)
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
        if (home)
          const SizedBox(height: 4)
        else if (onToggle != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onToggle,
              icon: const Icon(Icons.view_week_outlined, size: 18),
              label: Text(t('Vain tämä viikko')),
            ),
          )
        else
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
              (Sami.redLight, t('Sali')),
              if (settings.sports) (Sami.greenLight, t('Liikunta')),
              if (!home) (Sami.yellow, t('Ennätys')),
              if (settings.pauses.isNotEmpty) (Sami.blue.withValues(alpha: .45), t('Tauko')),
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
            // Askelrengas päivän ympärillä: täysi = 10 000 askelta.
            if (stepsTabAvailable)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CustomPaint(painter: _StepsRing(.7, _DayCell.stepsColor, width: 2)),
                  ),
                  const SizedBox(width: 4),
                  // Kapeassa kortissa teksti rivittyy (etusivun kuukausi: ylivuoto 26 px, tarkistus 17.11.).
                  Flexible(
                    child: Text(
                      t('Askeleet (täysi rengas 10 000)'),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
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

  /// Päivän askeleet (päivän askeleet päällä): rengas päivämäärän ympärillä.
  final int? steps;

  /// Päivä on tauon aikana.
  final bool pause;

  /// Etusivu: tänään keltaisella lihavoidulla numerolla, ei keltaista kehää.
  final bool yellowToday;
  const _DayCell({
    required this.day,
    required this.isToday,
    this.yellowToday = false,
    this.workout,
    required this.dots,
    this.onTap,
    this.steps,
    this.pause = false,
  });

  /// Askelrenkaan väri (kalenteri ja selite) ja täysi rengas: sama kuin etusivun kortin tavoiteviiva.
  static const stepsColor = stepsGoalColor;
  static const stepsFull = stepsGoal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ring = SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(
        painter: _StepsRing(((steps ?? 0) / stepsFull).clamp(0.0, 1.0), stepsColor, width: 3),
        // Suuri järjestelmän fontti: kaksinumeroinen päivä pienenee renkaan sisään (ennen "10" → "1").
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$day',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? (yellowToday ? FontWeight.w900 : FontWeight.w700) : FontWeight.w400,
                  color: isToday && yellowToday
                      ? yellowText(context)
                      : (onTap == null ? cs.onSurfaceVariant : cs.onSurface),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      // Sisältö pienenee tarvittaessa (päivä ja pisteet kapeassa solussa).
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tänään: keltainen kehä askelrenkaan ympärillä (luonnos viikko-askeleet B).
            Container(
              padding: const EdgeInsets.all(2),
              decoration: (isToday && !yellowToday) || pause
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      color: pause ? Sami.blue.withValues(alpha: .38) : null,
                      border: isToday && !yellowToday ? Border.all(color: Sami.yellow, width: 2) : null,
                    )
                  : null,
              child: ring,
            ),
            SizedBox(
              height: 9,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in dots)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.fromLTRB(1, 3, 1, 0),
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

/// Viikon liikunnan selitys (WHO, rasitus, lähteet): etusivun liikuntarenkaan napautus.
void explainActivityMinutes(BuildContext context, WeekActivity a) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Viikon liikunta'), style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            t(
              'Maailman terveysjärjestö WHO suosittelee aikuisille viikossa vähintään 150 minuuttia reipasta '
              'liikuntaa ja lihaskuntoharjoittelua vähintään kahtena päivänä. Kova minuutti vastaa kahta reipasta.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t('Tällä viikolla (ma–su): kova {0} min, reipas {1} min, kevyt {2} min. Lihaskuntopäiviä {3}.', [
              a.vigorous,
              a.moderate,
              a.light,
              a.strengthDays,
            ]),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            t(
              'Näin lasketaan: liikunnan rasitus (Kevyt, Reipas, Kova) ratkaisee. Jos rasitusta ei ole valittu, '
              'kävely on reipasta vähintään 4 km/h:n vauhdissa tai 100 askeleella minuutissa, venyttely, jooga ja '
              'pilates ovat kevyitä ja muut lajit reippaita. Lihaskuntopäivä on päivä, jona on tehty salitreeni.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t('Lähde: WHO:n liikuntasuositukset 2020; askeltiheys: Tudor-Locke ym. 2018.'),
            style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  ),
);

/// Askelrengas: vaalea kehä ja sen päällä täytetty osuus ylhäältä myötäpäivään.
class _StepsRing extends CustomPainter {
  final double fraction;
  final Color color;
  final double width;
  const _StepsRing(this.fraction, this.color, {this.width = 2.5});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(r, pen..color = color.withValues(alpha: .2));
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * fraction, false, pen..color = color);
  }

  @override
  bool shouldRepaint(_StepsRing o) => o.fraction != fraction || o.color != color || o.width != width;
}

/// Uusimmat treenit: päivä, sitten aloitusaika (ilman aikaa tallennusjärjestys). Saman päivän aamukävely ei
/// ole uusin, vaikka se olisi lisätty viimeisenä.
List<Workout> latestWorkouts(List<Workout> ws, int n) {
  int own(Workout w) => w.started == null ? -1 : w.started!.hour * 60 + w.started!.minute;
  // Ilman alkuaikaa (itse syötetty liikunta): tallennusjärjestyksen mukaan heti ennen tallennettujen jälkeen, eli
  // saman päivän aiempien (pienempi session) myöhäisimmän alkuajan kohdalle; tasatilanteessa session ratkaisee.
  // Ennen se järjestyi päivän viimeiseksi, eikä juuri tallennettu kävely näkynyt kolmen viimeisimmän joukossa.
  final byDay = <DateTime, List<Workout>>{};
  for (final w in ws) {
    (byDay[w.date] ??= []).add(w);
  }
  int key(Workout w) {
    final k = own(w);
    if (k >= 0) return k;
    var best = -1;
    for (final o in byDay[w.date]!) {
      if (o.session < w.session && own(o) > best) best = own(o);
    }
    return best;
  }

  final sorted = [...ws]
    ..sort((a, b) {
      final d = b.date.compareTo(a.date);
      if (d != 0) return d;
      final k = key(b).compareTo(key(a));
      return k != 0 ? k : b.session.compareTo(a.session);
    });
  return sorted.take(n).toList();
}

class _Recent extends StatelessWidget {
  /// Viimeisimmät treenit ryhminä: saman päivän sama laji yhdeksi riviksi (käyttäjä 17.11.: "Kävely ×4").
  static List<List<Workout>> groups(List<Workout> all, int n) {
    final ws = [...all]
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : (b.started ?? b.date).compareTo(a.started ?? a.date);
      });
    final out = <List<Workout>>[];
    for (final w in ws) {
      final last = out.lastOrNull;
      if (last != null && w.activity != null && last.first.activity == w.activity && last.first.date == w.date) {
        last.add(w);
        continue;
      }
      if (out.length == n) break;
      out.add([w]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t('Viimeksi'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  key: const ValueKey('recentAll'),
                  onPressed: () => MainShell.goTo(context, 2),
                  child: Text(t('Kaikki ›')),
                ),
              ],
            ),
            for (final g in groups(store.workouts, 3))
              if (g.length == 1)
                WorkoutRow(g.single)
              else
                InkWell(
                  onTap: () => showDay(context, g.first.date),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(right: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Sami.green.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(sportOf(g.first.activity)?.icon ?? '🏃', style: const TextStyle(fontSize: 18)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${sportName(g.first.activity!)} ×${g.length}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                [
                                  if (g.any((w) => (w.distanceKm ?? 0) > 0))
                                    '${fmtNum(double.parse(g.fold<double>(0, (a, w) => a + (w.distanceKm ?? 0)).toStringAsFixed(1)))} km',
                                  fmtDurationSec(g.fold<int>(0, (a, w) => a + (w.durationSec ?? 0))),
                                ].join(' · '),
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            shortDateY(g.first.date),
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ),
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

/// Treeni yhtenä rivinä (kuvake lajin värillä, nimi, liikkeet tai matka ja aika, päivä); napautus avaa treenin.
class WorkoutRow extends StatelessWidget {
  final Workout w;
  const WorkoutRow(this.w, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _open(context, w.date, w),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Kuvake: sali (käsipaino) tai lajin oma merkki; väri kertoo lajin (punainen sali, vihreä liikunta).
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (w.activity != null ? Sami.green : Sami.red).withValues(alpha: .16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: w.activity != null
                  ? Text(sportOf(w.activity)?.icon ?? '🏃', style: const TextStyle(fontSize: 18))
                  : Icon(Icons.fitness_center_rounded, size: 20, color: redText(context)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.activity != null ? sportName(w.activity!) : trName(w.title),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    w.activity != null
                        // Liikunta: matka ja aika (ennen tyhjä rivi, vaikka tiedot tunnetaan).
                        ? [
                            if ((w.distanceKm ?? 0) > 0) '${fmtNum(double.parse(w.distanceKm!.toStringAsFixed(2)))} km',
                            if (w.seconds != null)
                              fmtDurationSec(w.seconds!)
                            else if (w.minutes != null)
                              fmtDuration(w.minutes!),
                          ].join(' · ')
                        : w.exercises.where((e) => e.sets.isNotEmpty).map((e) => exerciseLabel(e.name)).join(' · '),
                    maxLines: linesFor(context, 1),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(shortDateY(w.date), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Avaa tallennetun treenin (sali: yhteenveto, liikunta: liikuntanäkymä).
void openWorkout(BuildContext context, Workout w) => _open(context, w.date, w);

/// Edistyminen ja kevennysviikkovinkki (pois päältä asetuksista).
/// Kehitys-kortti: [strength] voiman kehitys (arvioitu 1RM, ennätykset, kevennysvinkki) tai juoksun kehitys
/// matkaryhmittäin. Etusivulla kumpikin on oma korttinsa, joka valitaan asetuksista (käyttäjä 17.11.).
class _InsightsCard extends StatelessWidget {
  final bool strength;
  const _InsightsCard({required this.strength});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Vinkit pois tai tauko: vain askeleet (jos ne ovat päällä).
    final tips = settings.tips && settings.activePause == null;
    final ins = _insights();
    final week = isoDate(weekStart(DateTime.now()));
    // Ohjelma ajoittaa kevennykset itse; vinkki vain vapaassa treenissä.
    final showDeload =
        strength && tips && ins.suggestDeload && settings.deloadDismissed != week && settings.program == null;
    final hasProgress = strength && tips && (ins.improving.isNotEmpty || ins.stalled.isNotEmpty || ins.prs30d > 0);
    // Juoksu matkaryhmittäin (käyttäjä 17.11.): alle 5, 5–10 ja yli 10 km, vauhti ja syke.
    final runG = strength || !tips || settings.trainMode == 'gym'
        ? const <RunGroup>[]
        : runGroups(store.workouts, dateOnly(DateTime.now()), bands: settings.runBands);
    if (!hasProgress && !showDeload && runG.isEmpty) return const SizedBox.shrink();
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    Widget row(Progress p, bool up) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            up ? Icons.trending_up : Icons.trending_flat,
            size: 18,
            color: up ? greenText(context) : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(exerciseLabel(p.exercise), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(
            // Kahden käsipainon tai kuulan liikkeet yhteispainona (sovelluksessa painoa kohden).
            up
                ? '${fmtNum((p.before * loadMultiplier(p.exercise)).roundToDouble())} → '
                      '${fmtNum((p.now * loadMultiplier(p.exercise)).roundToDouble())} kg'
                : t('junnaa'),
            style: sub,
          ),
          if (up) ...[
            const SizedBox(width: 6),
            Text(
              '+${p.pct.toStringAsFixed(0)} %',
              style: TextStyle(color: greenText(context), fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ],
      ),
    );
    // Ennätyksiä on, mutta vertailtavia liikkeitä ei vielä: lyhyt selitys tyhjän alueen sijaan (yötesti 16.11.).
    List<Widget> progressRows() => ins.improving.isEmpty && ins.stalled.isEmpty
        ? [
            Text(
              t(
                'Odotetaan lisää treenejä. Vertailu näkyy, kun samaa liikettä on tehty viimeisten 4 viikon aikana '
                'ja 2 kuukautta ennen sitä.',
              ),
              style: sub,
            ),
          ]
        : [
            Text(t('Arvioitu 1RM: viimeiset 4 viikkoa vs. 2 kuukautta ennen'), style: sub),
            const SizedBox(height: 4),
            for (final p in ins.improving) row(p, true),
            for (final p in ins.stalled) row(p, false),
          ];
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
          // Kehitys 30 pv (käyttäjä 17.11.): ennätykset, nousevat ja junnaavat liikkeet sekä juoksu matkaryhmittäin.
          if (hasProgress || runG.isNotEmpty)
            Card(
              key: const ValueKey('homeProgress'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            strength ? t('Kehitys') : t('Juoksun kehitys'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('progressStats'),
                          onPressed: () => MainShell.goTo(context, 2),
                          child: Text(t('Tilastot ›')),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ennätykset omalla rivillään (otsikkorivillä se ei mahtunut kapeaan näyttöön).
                          if (strength && ins.prs30d > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                ins.prs30d == 1
                                    ? t('🏆 1 ennätys / 30 pv')
                                    : t('🏆 {0} ennätystä / 30 pv', [ins.prs30d]),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (hasProgress) ...progressRows(),
                          if (runG.isNotEmpty) ...[
                            if (hasProgress) const SizedBox(height: 8),
                            InkWell(
                              key: const ValueKey('runBandsEdit'),
                              onTap: () => editRunBands(context),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(t('Juoksu: viimeiset 4 viikkoa vs. 8 viikkoa ennen'), style: sub),
                                  ),
                                  Icon(Icons.tune, size: 16, color: cs.onSurfaceVariant),
                                ],
                              ),
                            ),
                            for (final g in runG)
                              Padding(
                                key: ValueKey('runGroup_${g.label}'),
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  children: [
                                    const Text('🏃', style: TextStyle(fontSize: 15)),
                                    const SizedBox(width: 8),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(minWidth: 62),
                                      child: Text(g.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${paceText(g.pace, 'Juoksu', short: true)}'
                                        '${g.paceDelta == 0 ? '' : ' (${g.paceDelta > 0 ? '+' : '−'}${g.paceDelta.abs()} s)'}',
                                        style: TextStyle(
                                          color: g.paceDelta < 0
                                              ? greenText(context)
                                              : (g.paceDelta > 0 ? cs.onSurfaceVariant : null),
                                        ),
                                      ),
                                    ),
                                    if (g.hr != null)
                                      Text(
                                        '♥ ${g.hr}${g.prevHr == null || g.hr == g.prevHr ? '' : ' (${g.hr! > g.prevHr! ? '+' : '−'}${(g.hr! - g.prevHr!).abs()})'}',
                                        style: sub,
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ohut tilarivi etusivun yläreunassa (vammatila, tauko): napautus avaa tiedot.
class _ModeBanner extends StatelessWidget {
  final Color color;
  final String emoji, title, detail;
  final VoidCallback onTap;
  const _ModeBanner({
    super.key,
    required this.color,
    required this.emoji,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: color.withValues(alpha: .14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color, width: 1.2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(
                        detail,
                        maxLines: settings.textFactor > 1 ? 3 : 2, // suurella tekstillä kolme riviä
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InjuryBanner extends StatelessWidget {
  const _InjuryBanner();

  @override
  Widget build(BuildContext context) => _ModeBanner(
    color: Sami.yellow,
    emoji: '🩹',
    title: t('Vammatila'),
    // Lyhyet nimet kerran kukin (kaksi olkapään aluetta → Olkapää); tarkemmat tiedot napautuksella.
    detail: {for (final id in knownInjuries(settings.injuries)) injuryShortName(t(injuryById(id)!.name))}.join(', '),
    onTap: () =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => InjuryScreen(initial: settings.injuries))),
  );
}

class _PauseBanner extends StatelessWidget {
  const _PauseBanner();

  @override
  Widget build(BuildContext context) {
    final p = settings.activePause!;
    final title = p.injury
        ? t('🩹  Vammatauko – parane pian!')
        : p.sick
        ? t('🤒  Sairastat – parane pian!')
        : t('🏖  Lomalla – nauti!');
    return _ModeBanner(
      color: p.sick ? Sami.red : Sami.blue,
      // Emoji rivin alkuun, otsikosta ilman sitä.
      emoji: p.injury ? '🩹' : (p.sick ? '🤒' : '🏖'),
      title: title.replaceFirst(RegExp(r'^[^\p{L}]+', unicode: true), ''),
      detail: p.end == null
          ? t('Alkoi {0}.{1}.{2}', [p.start.day, p.start.month, p.start.year])
          : t('{0}–{1} · {2}. päivä', [shortDate(p.start), shortDate(p.end!), p.days]),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(
                  'Tauko alkoi {0} ({1} pv). Kun palaat, sovellus ehdottaa kevyempiä kuormia ja vähemmän '
                  'sarjoja noin kahden viikon ajan.',
                  [shortDate(p.start), p.days],
                ),
              ),
              if (p.end != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t('Päättyy itsestään {0} jälkeen.', [shortDate(p.end!)])),
                ),
              if (p.sick)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t('Älä treenaa kuumeisena tai jos koko kroppa on kipeä.')),
                ),
            ],
          ),
          actions: [
            // Päivien tai syyn muutos (käyttäjä 16.11.: "voi muokata päiviä myöhemmin").
            TextButton(
              key: const ValueKey('pauseEdit'),
              onPressed: () {
                Navigator.pop(ctx);
                showPauseDialog(context, edit: p);
              },
              child: Text(t('Muokkaa')),
            ),
            // Vahingossa aloitettu tauko pois kokonaan.
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                removePauseUndo(context, p);
              },
              child: Text(t('Poista tauko')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                stopPause(context);
              },
              child: Text(t('Lopeta tauko')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tuleva tauko (loma ensi viikolla): näkyy etusivulla, napautus muokkaa.
class _UpcomingPauseBanner extends StatelessWidget {
  const _UpcomingPauseBanner();

  @override
  Widget build(BuildContext context) {
    final p = settings.upcomingPause!;
    return _ModeBanner(
      color: Sami.blue,
      emoji: p.injury ? '🩹' : (p.sick ? '🤒' : '🏖'),
      title: t('Tauko tulossa'),
      detail: p.end == null ? t('alkaa {0}', [shortDate(p.start)]) : '${shortDate(p.start)}–${shortDate(p.end!)}',
      onTap: () => showPauseDialog(context, edit: p),
    );
  }
}

/// Lukukelvottomat treenitiedostot: tiedot, korjausyritys (väärä merkistö) ja ongelmaraportti tiedostot liitteenä.
class _UnreadableBanner extends StatelessWidget {
  const _UnreadableBanner();

  static Future<void> _report(BuildContext context, Map<String, String> files) async {
    final root = (await store.rootDir()).path;
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BugReportScreen(
          type: 'save',
          attach: [
            for (final rel in files.keys) (p.basename(rel), p.joinAll([root, ...rel.split('/')])),
          ],
          description: t('Treenitiedostoja ei voitu lukea: {0}', [
            [for (final e in files.entries) '${e.key} (${e.value})'].join('; '),
          ]),
        ),
      ),
    );
  }

  static void _details(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Treenitiedostoja ei voitu lukea')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(
                'Näitä treenejä ei näytetä historiassa. Tiedosto voi olla vaurioitunut tai tallennettu toisella '
                'merkistöllä (esim. muokattu Windowsin Muistiossa). Tiedostoja ei poisteta.',
              ),
            ),
            const SizedBox(height: 10),
            for (final e in store.unreadable.entries) ...[
              Text('• ${e.key}', style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: Text(e.value, style: TextStyle(fontSize: 12, color: redText(context))),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Sulje'))),
        TextButton(
          onPressed: () {
            final files = {...store.unreadable};
            Navigator.pop(ctx);
            _report(context, files);
          },
          child: Text(t('Lähetä ongelmaraportti')),
        ),
        FilledButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(ctx);
            final fixed = await store.repairUnreadable();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  fixed == 0
                      ? t('Tiedostoja ei voitu korjata. Lähetä ne ongelmaraporttina.')
                      : store.unreadable.isEmpty
                      ? t('Korjattu {0}. Alkuperäiset ovat tallessa .bak-päätteellä.', [fixed])
                      : t('Korjattu {0}, jäljellä {1}. Alkuperäiset ovat tallessa .bak-päätteellä.', [
                          fixed,
                          store.unreadable.length,
                        ]),
                ),
              ),
            );
          },
          child: Text(t('Yritä korjata')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => _ModeBanner(
    color: Sami.red,
    emoji: '⚠️',
    title: t('Treenitiedostoja ei voitu lukea: {0}', [store.unreadable.length]),
    detail: store.unreadable.keys.map(p.basename).join(', '),
    onTap: () => _details(context),
  );
}

/// Aamupaino etusivulla (kehonpainon seuranta päällä, ei vielä punnittu tänään eikä ohitettu): painike avaa
/// syöttöikkunan, Ohita piilottaa rivin tältä päivältä. Korjaukset ☰ → Asetukset → Paino ja pituus.
/// Kysyy päivän painon kerran päivässä (käyttäjä 17.11.): kehonpainon seuranta päällä, tänään ei punnitusta eikä
/// ohitusta. Ikkunan sulkeminen ilman painoa ohittaa tämän päivän, joten kysymys ei toistu.
bool _askingWeight = false;

Future<void> askDailyWeight(BuildContext context) async {
  final today = dateOnly(DateTime.now());
  if (!settings.bodyTracker || !settings.introDone || _askingWeight) return;
  if (settings.body.weights.containsKey(today) || settings.bodySkipped == isoDate(today)) return;
  // Käynnistys ja sovellukseen palaaminen voivat kysyä yhtä aikaa: vain yksi ikkuna (koodikatselmus 17.11.).
  _askingWeight = true;
  final double? kg;
  try {
    kg = await askBodyValue(context, height: false, title: t('Aamupaino'), previous: settings.body.sorted.lastOrNull);
  } finally {
    _askingWeight = false;
  }
  if (kg != null) {
    await settings.setWeight(today, kg);
  } else {
    settings.skipBodyToday(isoDate(today));
  }
}

/// Kehonpaino etusivulla (vain asetuksella Painon kehitys etusivulla): viimeisin paino, muutos 30 päivässä ja käyrä.
class WeightTodayCard extends StatelessWidget {
  const WeightTodayCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      if (!settings.bodyTracker || !settings.weightOnHome) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final today = dateOnly(DateTime.now());
      final all = settings.body.sorted;
      final last = all.lastOrNull;
      final from = addDays(today, -30);
      final recent = [
        for (final e in all)
          if (!e.$1.isBefore(from)) e,
      ];
      final base =
          [
            for (final e in all)
              if (!e.$1.isAfter(from)) e,
          ].lastOrNull ??
          recent.firstOrNull;
      final change = last == null || base == null || identical(base, last) ? null : last.$2 - base.$2;
      return Card(
        key: const ValueKey('weightCard'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(t('Kehonpaino'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    key: const ValueKey('weightLog'),
                    onPressed: () async {
                      final kg = await askBodyValue(
                        context,
                        height: false,
                        title: t('Aamupaino'),
                        current: settings.body.weights[today],
                        previous: last,
                      );
                      if (kg != null) await settings.setWeight(today, kg);
                    },
                    child: Text(t('Merkitse ›')),
                  ),
                ],
              ),
              if (last == null)
                Text(t('Ei vielä punnituksia.'), style: TextStyle(color: cs.onSurfaceVariant))
              else
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${fmtNum(last.$2)} kg',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        if (change != null)
                          Text(
                            t('{0} kg / 30 pv', [
                              '${change > 0
                                  ? '+'
                                  : change < 0
                                  ? '−'
                                  : '±'}${fmtNum(double.parse(change.abs().toStringAsFixed(1)))}',
                            ]),
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    if (recent.length >= 2)
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: CustomPaint(painter: _Spark([for (final e in recent) e.$2], blueText(context))),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _Spark extends CustomPainter {
  final List<double> v;
  final Color c;
  _Spark(this.v, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final lo = v.reduce(math.min), hi = v.reduce(math.max);
    final span = (hi - lo).abs() < .5 ? .5 : hi - lo;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - 3 - (size.height - 6) * (v[i] - lo) / span;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = c,
    );
  }

  @override
  bool shouldRepaint(_Spark o) => o.v != v || o.c != c;
}

// ---------------------------------------------------------------------------------------------------------------
// Ulkoasun kohennus (16.11., luonnokset docs/facelift): Sali | Liikunta -valitsin, ehdotuskortti, liikuntakortti
// ja etusivun ?-ohje.

/// Pieni saamenkielinen otsikko keltaisena suomen/englannin otsikon yllä (aina päällä fi/en-kielissä, käyttäjä 16.11.).
class _SeCaption extends StatelessWidget {
  final String se;
  const _SeCaption(this.se);
  @override
  Widget build(BuildContext context) => isSami
      ? const SizedBox.shrink()
      : Text(
          se.toUpperCase(),
          style: TextStyle(fontSize: 10.5, letterSpacing: .6, fontWeight: FontWeight.w600, color: yellowText(context)),
        );
}

/// Etusivun ?-ohje: valitsin, kortit, viikon merkit ja askeleet (käyttäjä 16.11.: yksi ? koko etusivulle).
void showHomeHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final sub = TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant, height: 1.35);
    Widget sec(String title, String body) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(body, style: sub),
        ],
      ),
    );
    Widget dot(Color c, {bool hollow = false}) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? null : c,
        border: hollow ? Border.all(color: c, width: 2) : null,
      ),
    );
    Widget mark(Widget w, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 26, child: Center(child: w)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: sub)),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('homeHelp'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('Etusivu'), style: Theme.of(ctx).textTheme.titleLarge),
            sec(
              t('Sali ja Liikunta'),
              t(
                'Sali avaa ohjelmasi päivät (ehdotus ylimpänä) ja vapaan treenin; Liikunta avaa viimeksi käyttämäsi '
                'lajit ja sitten kirjaustavan (GPS, ajanotto tai jo tehty). Kellon harjoitukset Health Connectista '
                'näkyvät paneelin ylälaidassa. Paneeli sulkeutuu pyyhkäisyllä alas tai Takaisin-painikkeella.',
              ),
            ),
            sec(t('Viikko ja kuukausi'), t('Valitse Viikko tai Kuukausi; ‹ › vaihtaa jaksoa.')),
            mark(
              SizedBox(width: 22, height: 22, child: CustomPaint(painter: _StepsRing(.6, redText(ctx), width: 3))),
              t('Lihaskuntopäivät: tavoitteena ohjelmasi päivät viikossa, ilman ohjelmaa WHO:n vähimmäismäärä 2.'),
            ),
            mark(
              SizedBox(width: 22, height: 22, child: CustomPaint(painter: _StepsRing(.4, greenText(ctx), width: 3))),
              t(
                'Reipas liikunta: WHO suosittaa 150 min viikossa; kova minuutti lasketaan kahdesti. Hidas kävely '
                'näkyy kokonaisminuuteissa. Napauta rengasta nähdäksesi laskutavan.',
              ),
            ),
            mark(
              SizedBox(width: 22, height: 22, child: CustomPaint(painter: _StepsRing(.8, blueText(ctx), width: 3))),
              t('Askeleet: viikossa tämän päivän, kuukaudessa keskiarvo päivää kohden; tavoite {0}.', [
                thousands(stepsGoal),
              ]),
            ),
            sec(t('Päivät'), ''),
            mark(
              SizedBox(
                width: 22,
                height: 22,
                child: CustomPaint(painter: _StepsRing(.7, _DayCell.stepsColor, width: 3)),
              ),
              t('Kehä täyttyy päivän askelista; täysi = {0} askelta.', [thousands(stepsGoal)]),
            ),
            mark(dot(redText(ctx)), t('Salitreeni tehty')),
            mark(dot(greenText(ctx)), t('Liikuntaa tehty')),
            mark(
              Text(
                '17',
                style: TextStyle(fontWeight: FontWeight.w900, color: yellowText(ctx)),
              ),
              t('Tänään keltaisella · napauta päivää nähdäksesi sen treenit'),
            ),
            mark(
              SizedBox(width: 22, height: 22, child: CustomPaint(painter: _StepsRing(.5, yellowText(ctx), width: 3))),
              t('Omat tavoitteet keltaisella: yksi näkyy tässä rivissä, useampi omana korttinaan.'),
            ),
            sec(
              t('Omat tavoitteet ja kortit'),
              t(
                'Asetukset → Etusivu: lisää enintään 3 omaa tavoitetta (salipäivät, matka, liikunta-aika tai kerrat, '
                'koko liikunta tai yksi laji) ja valitse kortit järjestyksessä: Seuraava treeni, Viikkoputki, '
                'Palautuminen, Viimeksi, Voiman kehitys, Juoksun kehitys (omat matkaryhmät) ja Kehonpaino.',
              ),
            ),
            sec(
              t('Viikkoputki'),
              t(
                'Montako viikkoa peräkkäin molemmat WHO:n suositukset täyttyivät (lihaskunto 2 päivänä ja 150 min '
                'reipasta liikuntaa). Vihreä = molemmat, keltainen = toinen, tyhjä = ei kumpaakaan. Tauko (sairas, loma '
                'tai vamma vähintään 4 päivää) ei katkaise putkea. Kuluva viikko lasketaan, kun se täyttyy.',
              ),
            ),
            sec(
              t('Palautuminen'),
              t(
                'Yön alin syke (alin 15 minuutin keskiarvo klo 21–10) kellosta Health Connectin kautta. Kolmen viimeisen '
                'yön keskiarvoa verrataan tavalliseen tasoosi (mediaani 28 yöstä): 5 lyöntiä tai enemmän koholla voi '
                'kertoa sairastumisesta, rasituksesta tai huonosta unesta. Vain sykkeen lukulupa; unitietoja ei lueta.',
              ),
            ),
            sec(
              t('Askeleet ja Health Connect'),
              t(
                'Askeleet ja kellon harjoitukset tulevat Health Connectista. Ne päivittyvät, kun avaat sovelluksen, ja '
                '15 minuutin välein sen ollessa auki. Vedä etusivua alas päivittääksesi heti.',
              ),
            ),
          ],
        ),
      ),
    );
  },
);

/// Päiväsivun Health Connect -rivi: päivän harjoitukset, joita ei vielä ole Gievrassa; napautus avaa tuonnin.
class _DayHealthRow extends StatelessWidget {
  final DateTime day;
  const _DayHealthRow({required this.day});

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: HealthConnect.sessions(day).then((all) => newHealthSessions(all, store.workouts).$1.length),
    builder: (context, snap) {
      final n = snap.data ?? 0;
      if (n == 0) return const SizedBox.shrink();
      final fg = greenText(context);
      return Card(
        key: const ValueKey('dayHcRow'),
        margin: const EdgeInsets.only(bottom: 10),
        color: Sami.green.withValues(alpha: .12),
        child: ListTile(
          leading: Icon(Icons.sync, color: fg),
          title: Text(
            'HEALTH CONNECT',
            style: TextStyle(fontSize: 11, letterSpacing: .6, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          subtitle: Text(
            n == 1 ? t('1 uusi harjoitus') : t('{0} uutta harjoitusta', [n]),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg),
          ),
          trailing: Icon(Icons.chevron_right, color: fg),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HealthImportScreen(day: day))),
        ),
      );
    },
  );
}
