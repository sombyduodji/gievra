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
import '../injuries.dart' show injuryById, injuryShortName, knownInjuries;
import 'health_import.dart';
import 'intro.dart';
import 'program_screen.dart';
import 'body_screen.dart';
import 'bug_report.dart';
import 'new_workout.dart';
import 'stats_screen.dart';
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
          // Valmis salitreeni: yhteenveto ensin kuten liikunnassa, Muokkaa avaa liikelistan (käyttäjä 15.11.).
          : w != null && (w.minutes != null || w.feeling != null)
          ? SavedScreen(workout: w, history: true)
          : w != null
          ? WorkoutScreen(workout: w.copy(), planDay: day)
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
    appBar: AppBar(title: BarTitle(Text(_day == _today ? t('Tänään') : longDateYear(_day)))),
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
          if (w.paceSecPerKm != null) (Icons.speed, '${fmtPace(w.paceSecPerKm!)} /km'),
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
      listenable: Listenable.merge([store, dailySteps]),
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
            const SamiBand(height: 4, pattern: false),
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
  if (settings.activePause != null && !dateOnly(d).isBefore(settings.activePause!.start)) {
    settings.endPause(addDays(d, -1));
  }
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
                  ?durationText(w),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSteps();
    _resume();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkMoves().then((_) => _checkElevFormat()).then((_) => _checkWhatsNew()),
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
      _refreshSteps();
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

  /// Molemmat-tilassa iso painike: sali, jos tänään on keskeneräinen salitreeni tai salitreenejä on tehty vähintään
  /// yhtä usein kuin liikuntaa viimeisen 14 päivän aikana; muuten liikunta.
  bool _gymFirst(DateTime today, bool hasOpenGym) {
    if (hasOpenGym) return true;
    final from = addDays(today, -14);
    var gym = 0, act = 0;
    for (final w in store.workouts) {
      if (w.date.isBefore(from)) continue;
      w.activity == null ? gym++ : act++;
    }
    return gym >= act;
  }

  /// Android sulki sovelluksen kesken: ensin kesken jäänyt GPS-tallennus (jatkuu siitä), muuten keskeneräinen
  /// liikuntakirjaus (lomake ennen Tallenna-painiketta).
  Future<void> _resume() async {
    // Kerran käynnistystä kohden: etusivu voi rakentua uudelleen (esim. tekstin koko asetuksista), jolloin
    // palautus avautui kahdesti ja sijaintilupaa kysyttiin kahdesti (päivätesti 14.11.).
    if (_resumeDone) return;
    _resumeDone = true;
    final sport = await GpsRecorder.pendingSport();
    final d = await ActivityDraft.load();
    if (!mounted) return;
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
      return;
    }
    if (d == null) return;
    final (w, extra) = d;
    // Samalle päivälle tallennettu treeni samalla numerolla: luonnos on jo tallennettu.
    if (store.onDay(w.date).any((x) => x.session == w.session && x.activity == w.activity)) {
      await ActivityDraft.clear();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivityScreen(workout: w, draft: extra),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, store, autoBackup]),
      builder: (context, _) {
        final now = DateTime.now();
        final today = dateOnly(now);
        // Salinäkymä käsittelee vain salitreenejä; liikunta ja lenkit ovat kestävyysnäkymässä.
        final todays = store.onDay(today).where((w) => w.activity == null).toList();
        // Kesken oleva treeni (ei merkitty valmiiksi): etusivu tarjoaa sen jatkamista, muuten uutta treeniä.
        final open = todays.where((w) => w.minutes == null && w.feeling == null).toList();
        // Eilen aloitettu, yhä käynnissä oleva treeni (yli puolenyön): jatkettavissa etusivulta.
        final running = Ongoing.gymInProgress(store.workouts, now);
        if (running != null && running.date != today) open.add(running);
        final hasToday = open.isNotEmpty;
        final both = settings.trainMode == 'both';
        return Scaffold(
          appBar: AppBar(
            title: BarTitle(
              Text(
                (settings.name ?? '').isEmpty ? '${seGreeting(now)}!' : '${seGreeting(now)}, ${settings.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          drawer: const AppDrawer(),
          body: RefreshIndicator(
            onRefresh: store.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              children: [
                const SizedBox(height: 4),
                const SamiBand(),
                // Vammatila ja tauko näkyvät heti ylhäällä, kun ne ovat päällä.
                if (knownInjuries(settings.injuries).isNotEmpty) _InjuryBanner(),
                if (settings.activePause != null) _PauseBanner(),
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
                      'Yritetään uudelleen seuraavalla käynnistyksellä. Tee varmuuskopio itse: ☰ → Tuonti, vienti ja varmuuskopio.',
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
                if (settings.trainMode == 'cardio')
                  _CardioHome()
                else if (both) ...[
                  // Molemmat: yksi Tänään-kortti. Iso painike on sali, jos tänään on keskeneräinen salitreeni tai
                  // salitreenejä on tehty vähintään yhtä usein kuin liikuntaa viimeisen 14 päivän aikana; muuten
                  // liikunta. Ohjelman päivää ei oteta huomioon. Toinen on pienempi painike (ei näkymän vaihtoa).
                  const SizedBox(height: 18),
                  Builder(
                    builder: (context) {
                      final acts = store.onDay(today).where((w) => w.activity != null).toList();
                      final gymFirst = _gymFirst(today, hasToday);
                      void gym() => hasToday
                          ? (open.length == 1
                                ? _open(context, open.single.date, open.single)
                                : _chooseSession(context, today, open))
                          : _startNew(context, today, gymOnly: true);
                      void activity() => _CardioHome._add(context, null);
                      final gymLabel = hasToday ? t('Jatka treeniä') : t('Aloita salitreeni');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TodayCard(
                            today: today,
                            actions: [
                              _SplitCta(
                                gymWide: gymFirst,
                                gymOpen: hasToday,
                                activityIcon: _lastSportIcon(),
                                gymSemantics: gymLabel,
                                onGym: gym,
                                onActivity: activity,
                              ),
                            ],
                            done: [...todays.where((w) => !open.contains(w)), ...acts],
                          ),
                          if (HealthImportButton.visible) HealthImportButton(),
                          const SizedBox(height: 6),
                          const WeightTodayCard(),
                          _InsightsCard(),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  // Iso painike: jatka keskeneräistä tai aloita uusi. Ohjelman ehdotus näkyy alarivillä;
                  // seuraavassa näkymässä päivän voi vielä vaihtaa.
                  _TodayCard(
                    today: today,
                    actions: [
                      _Cta(
                        label: hasToday
                            ? (open.length == 1
                                  ? t('Jatka: {0}', [trName(open.single.title)])
                                  : t('Jatka tämän päivän treeniä'))
                            : t('Aloita salitreeni'),
                        icon: hasToday ? Icons.play_arrow_rounded : Icons.add_rounded,
                        onTap: () => hasToday
                            ? (open.length == 1
                                  ? _open(context, open.single.date, open.single)
                                  : _chooseSession(context, today, open))
                            : _startNew(context, today, gymOnly: true),
                      ),
                    ],
                    // Tämän päivän valmiit treenit tiiviinä riveinä (avautuvat lukutilaan).
                    done: todays.where((w) => !open.contains(w)).toList(),
                  ),
                  if (store.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(store.error!, style: TextStyle(color: cs.error)),
                    ),
                  const SizedBox(height: 14),
                  const WeightTodayCard(),
                  _InsightsCard(),
                ],
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    // Päivän askeleet päivittyvät kalenteriin ilman koko etusivun uudelleenrakennusta.
                    child: ListenableBuilder(
                      listenable: dailySteps,
                      builder: (context, _) => _Calendar(
                        month: _month,
                        week: !_monthView,
                        onToggle: () => setState(() {
                          _monthView = !_monthView;
                          _month = DateTime(now.year, now.month);
                        }),
                        onShift: (n) => setState(() => _month = DateTime(_month.year, _month.month + n)),
                      ),
                    ),
                  ),
                ),
                _OverviewLink(),
                const SizedBox(height: 6),
                if (store.workouts.isNotEmpty) _Recent(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tämän päivän valmis treeni tiiviinä rivinä: avautuu lukutilaan (muokkaus kysyy ensin).
/// Etusivun Tänään-kortti: toimintopainikkeet ja päivän valmiit treenit yhdessä kortissa (ennen yksi vihreä rivi
/// jokaisesta treenistä painikkeen alla).
class _TodayCard extends StatelessWidget {
  final DateTime today;
  final List<Widget> actions;
  final List<Workout> done;
  const _TodayCard({required this.today, required this.actions, required this.done});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minutes = done.fold<int>(0, (a, w) => a + (w.minutes ?? 0));
    final summary = done.isEmpty
        ? null
        : [
            done.length == 1 ? t('1 treeni') : t('{0} treeniä', [done.length]),
            if (minutes > 0) fmtDuration(minutes),
          ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Yhteenveto otsikon viereen, tai sen alle kun ei mahdu (fontti 2,0: ennen katkesi "…", yötesti 15.11.).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(t('Tänään'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (summary != null)
                  Text(
                    summary,
                    style: TextStyle(fontSize: AppText.caption, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ...actions,
            if (done.isNotEmpty) ...[const SizedBox(height: 6), for (final w in done) _TodayRow(w)],
          ],
        ),
      ),
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

class _TodayRow extends StatelessWidget {
  final Workout w;
  const _TodayRow(this.w);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = w.activity != null ? sportName(w.activity!) : trName(w.title);
    final info = [
      if (w.distanceKm != null) '${fmtNum((w.distanceKm! * 100).round() / 100)} km',
      ?durationText(w),
      if (w.activity == null && w.exercises.isNotEmpty)
        setsLabel(w.exercises.fold<int>(0, (a, e) => a + e.sets.where((s) => !s.warmup).length)),
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(context, w.date, w),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .5))),
        ),
        child: Row(
          children: [
            Icon(Icons.check_rounded, color: greenText(context), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w500),
              ),
            ),
            if (info.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .5),
                child: Text(
                  info,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppText.caption, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Väri: punainen sali, vihreä kestävyys.
  final List<Color> colors;
  const _Cta({
    required this.label,
    required this.icon,
    required this.onTap,
    this.colors = const [Sami.red, Color(0xFFA3170D)],
  });

  @override
  Widget build(BuildContext context) => Material(
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(width: 8),
              Flexible(child: _CtaLabel(label, compact: false)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Painikkeen teksti kahdella rivillä. Jos jokin sana ei mahdu leveyteen (saame, suuri teksti, pieni näyttö),
/// teksti jaetaan väliltä kahdelle riville ja pienennetään: sanaa ei katkaista keskeltä ("Lihkadeap / mi").
class _CtaLabel extends StatelessWidget {
  final String label;
  final bool compact;
  const _CtaLabel(this.label, {required this.compact});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final style = TextStyle(color: Colors.white, fontSize: compact ? 16 : 18, fontWeight: FontWeight.w700);
      final scaler = MediaQuery.textScalerOf(context);
      double width(String w) => (TextPainter(
        text: TextSpan(text: w, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout()).width;
      final words = label.split(' ');
      final fits = !c.maxWidth.isFinite || words.every((w) => width(w) <= c.maxWidth);
      if (fits) {
        return Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
      }
      // Jako sanavälistä mahdollisimman tasan kahdelle riville.
      var best = label;
      if (words.length > 1) {
        var bestDiff = double.infinity;
        for (var i = 1; i < words.length; i++) {
          final a = words.take(i).join(' '), b = words.skip(i).join(' ');
          final d = (width(a) - width(b)).abs();
          if (d < bestDiff) {
            bestDiff = d;
            best = '$a\n$b';
          }
        }
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(best, textAlign: TextAlign.center, style: style),
      );
    },
  );
}

/// Urheilun ja liikunnan väri kalenterissa.
const sportColor = Color(0xFF2BA6A6);

class _Calendar extends StatelessWidget {
  final DateTime month;
  final void Function(int) onShift;

  /// Vain tämä viikko (tiivis); [onToggle] vaihtaa viikon ja kuukauden välillä.
  final bool week;
  final VoidCallback onToggle;
  const _Calendar({required this.month, required this.onShift, this.week = false, required this.onToggle});

  /// ISO-viikkonumero.
  static int weekNumber(DateTime d) {
    final thursday = d.add(Duration(days: 4 - d.weekday));
    final jan1 = DateTime(thursday.year, 1, 1);
    return thursday.difference(jan1).inDays ~/ 7 + 1;
  }

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
    if (week) {
      // Tämä viikko maanantaista sunnuntaihin (voi ulottua kahteen kuukauteen).
      final mon = weekStart(today);
      final days7 = [for (var i = 0; i < 7; i++) addDays(mon, i)];
      final byDate = <DateTime, List<Workout>>{};
      for (final w in store.workouts) {
        if (!w.date.isBefore(mon) && w.date.isBefore(addDays(mon, 7))) (byDate[w.date] ??= []).add(w);
      }
      return Column(
        children: [
          Row(
            children: [
              Text(
                t('Viikko {0}', [weekNumber(today)]),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
          Row(
            children: [
              for (final d in uiWeekdaysShort)
                Expanded(
                  child: Center(
                    child: Text(d, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
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
                  workout: byDate[d]?.first,
                  dots: byDate[d] == null ? const [] : {for (final w in byDate[d]!) ..._dots(w)}.toList(),
                  steps: stepsTabAvailable ? dailySteps.at(d) : null,
                  onTap: d.isAfter(today) ? null : () => showDay(context, d),
                ),
            ],
          ),
        ],
      );
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
          steps: stepsTabAvailable ? dailySteps.at(DateTime(month.year, month.month, d)) : null,
          onTap: DateTime(month.year, month.month, d).isAfter(today)
              ? null
              : () => showDay(context, DateTime(month.year, month.month, d)),
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onToggle,
            icon: const Icon(Icons.view_week_outlined, size: 18),
            label: Text(t('Vain tämä viikko')),
          ),
        ),
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
              (Sami.red, t('Jalat')),
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
                  Text(t('Askeleet (täysi rengas 10 000)'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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
  const _DayCell({required this.day, required this.isToday, this.workout, required this.dots, this.onTap, this.steps});

  /// Askelrenkaan väri (kalenteri ja selite) ja täysi rengas: sama kuin etusivun kortin tavoiteviiva.
  static const stepsColor = stepsGoalColor;
  static const stepsFull = stepsGoal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cell = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: workout != null ? cs.surfaceContainerHigh : null,
          borderRadius: BorderRadius.circular(10),
          border: isToday ? Border.all(color: Sami.yellow, width: 2) : null,
        ),
        // Sisältö pienenee tarvittaessa (päivä ja pisteet kapeassa solussa).
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Päivämäärä; askeleet rengas sen ympärillä (kuin akkukuvake, täysi = 10 000, tarkka luku päivän näkymässä).
              SizedBox(
                width: 24,
                height: 24,
                child: CustomPaint(
                  painter: (steps ?? 0) > 0 ? _StepsRing((steps! / stepsFull).clamp(.04, 1.0), stepsColor) : null,
                  // Suuri järjestelmän fontti: kaksinumeroinen päivä pienenee renkaan sisään (ennen "10" → "1").
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$day',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(fontSize: 12, color: onTap == null ? cs.onSurfaceVariant : cs.onSurface),
                      ),
                    ),
                  ),
                ),
              ),
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
      ),
    );
    return cell;
  }
}

/// Viikon liikunta WHO:n suositusta vasten (kortin Viikko-puoli): rengas reippaille minuuteille (kova × 2) ja
/// lihaskuntopäivät. Kortin napautus avaa laskutavan ja lähteen ([explain]).
class _WeekGoalBody extends StatelessWidget {
  final WeekActivity a;
  const _WeekGoalBody(this.a);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final frac = (a.moderateEq / whoMinutes).clamp(0.0, 1.0);
    // Tummassa teemassa vaaleammat sävyt (raaka sininen katosi tummalle kortille).
    final ringColor = a.minutesMet ? greenText(context) : blueText(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CustomPaint(
              painter: _StepsRing(frac, ringColor, width: 7),
              child: Center(
                child: a.minutesMet
                    ? Icon(Icons.check_rounded, color: greenText(context), size: 30)
                    : Text(
                        '${(frac * 100).round()} %',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('{0} / {1} min reipasta', [a.moderateEq, whoMinutes]),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(t('Lihaskunto')),
                    const SizedBox(width: 6),
                    for (var i = 0; i < whoStrengthDays; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Icon(
                          i < a.strengthDays ? Icons.check_circle_rounded : Icons.circle_outlined,
                          size: 16,
                          color: i < a.strengthDays ? greenText(context) : cs.outline,
                        ),
                      ),
                    const SizedBox(width: 3),
                    Text(
                      a.strengthMet
                          ? t('{0} päivää', [a.strengthDays])
                          : t('{0}/{1} päivää', [a.strengthDays, whoStrengthDays]),
                      style: sub,
                    ),
                  ],
                ),
                if (a.light > 0) ...[
                  const SizedBox(height: 2),
                  Text(t('+ {0} min kevyttä', [a.light]), style: sub),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void explain(BuildContext context, WeekActivity a) => showModalBottomSheet<void>(
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
}

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
            for (final w in latestWorkouts(store.workouts, 3))
              InkWell(
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
                                      if ((w.distanceKm ?? 0) > 0)
                                        '${fmtNum(double.parse(w.distanceKm!.toStringAsFixed(2)))} km',
                                      if (w.seconds != null)
                                        fmtDurationSec(w.seconds!)
                                      else if (w.minutes != null)
                                        fmtDuration(w.minutes!),
                                    ].join(' · ')
                                  : w.exercises
                                        .where((e) => e.sets.isNotEmpty)
                                        .map((e) => exerciseLabel(e.name))
                                        .join(' · '),
                              maxLines: linesFor(context, 1),
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
    // Vinkit pois tai tauko: vain askeleet (jos ne ovat päällä).
    final tips = settings.tips && settings.activePause == null;
    final ins = _insights();
    final week = isoDate(weekStart(DateTime.now()));
    // Ohjelma ajoittaa kevennykset itse; vinkki vain vapaassa treenissä.
    final showDeload = tips && ins.suggestDeload && settings.deloadDismissed != week && settings.program == null;
    final hasProgress = tips && (ins.improving.isNotEmpty || ins.stalled.isNotEmpty || ins.prs30d > 0);
    final hasRuns = runsOf(store.workouts).isNotEmpty;
    // Viikon liikunta (WHO) kortin ensimmäisenä puolena, kun vinkit ovat päällä.
    final weekAct = tips ? weekActivity(store.workouts, DateTime.now()) : null;
    if (!hasProgress && !showDeload && !stepsTabAvailable && !hasRuns && weekAct == null) {
      return const SizedBox.shrink();
    }
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
          // Päivän askeleet päällä: sama kortti kahtena puolena (Edistyminen | Askeleet).
          if (stepsTabAvailable || hasRuns || weekAct != null)
            HomeStatsCard(
              running: hasRuns,
              steps: stepsTabAvailable,
              week: weekAct == null ? null : _WeekGoalBody(weekAct),
              onWeekTap: weekAct == null ? null : () => _WeekGoalBody.explain(context, weekAct),
              progress: !hasProgress
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Arvioitu 1RM: viimeiset 4 viikkoa vs. 2 kuukautta ennen'), style: sub),
                        const SizedBox(height: 4),
                        for (final p in ins.improving) row(p, true),
                        for (final p in ins.stalled) row(p, false),
                      ],
                    ),
              progressTrailing: ins.prs30d > 0
                  ? Text(
                      ins.prs30d == 1 ? t('🏆 1 ennätys / 30 pv') : t('🏆 {0} ennätystä / 30 pv', [ins.prs30d]),
                      style: sub,
                    )
                  : null,
            )
          else if (hasProgress)
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
                        if (ins.prs30d > 0)
                          Text(
                            ins.prs30d == 1 ? t('🏆 1 ennätys / 30 pv') : t('🏆 {0} ennätystä / 30 pv', [ins.prs30d]),
                            style: sub,
                          ),
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
    final title = p.sick ? t('🤒  Sairastat – parane pian!') : t('🏖  Lomalla – nauti!');
    return _ModeBanner(
      color: p.sick ? Sami.red : Sami.blue,
      // Emoji rivin alkuun, otsikosta ilman sitä.
      emoji: p.sick ? '🤒' : '🏖',
      title: title.replaceFirst(RegExp(r'^[^\p{L}]+', unicode: true), ''),
      detail: t('Alkoi {0}.{1}.{2}', [p.start.day, p.start.month, p.start.year]),
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
              if (p.sick)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t('Älä treenaa kuumeisena tai jos koko kroppa on kipeä.')),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Sulje'))),
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

/// Sali / Kestävyys -valinta etusivun yläreunassa (kielivalinnan tyylinen liuska).
/// Kestävyysnäkymä: lisää lenkki tai muu laji yhdellä napautuksella ja tämän päivän liikunnat.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        // Kuten salissa: Tänään-kortti, jonka painike avaa oman sivun, jossa valitaan laji (käytetyimmät ensin), ja
        // tämän päivän liikunnat tiiviinä riveinä (avautuvat lukutilaan).
        _TodayCard(
          today: today,
          actions: [
            _Cta(
              label: t('Aloita liikunta'),
              icon: Icons.add_rounded,
              colors: const [Color(0xFF00843D), Sami.green],
              onTap: () => _add(context, null),
            ),
          ],
          done: acts.where((w) => w.date == today).toList(),
        ),
        if (HealthImportButton.visible) HealthImportButton(),
        const SizedBox(height: 10),
        const WeightTodayCard(),
        if (acts.isEmpty)
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
        // Juoksun kehitys (ja askeleet) tilastokortissa.
        _InsightsCard(),
      ],
    );
  }
}

/// Linkki yhteenvetoon: viikko ja kuukausi, kaikki treenit sekä sali ja kestävyys erikseen.
class _OverviewLink extends StatelessWidget {
  const _OverviewLink();

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsScreen())),
      icon: const Icon(Icons.insights_rounded, size: 18),
      label: Text(settings.trainMode == 'both' ? t('Yhteenveto: kaikki treenit') : t('Yhteenveto ja tilastot')),
    ),
  );
}

/// Aamupaino etusivulla (kehonpainon seuranta päällä, ei vielä punnittu tänään eikä ohitettu): painike avaa
/// syöttöikkunan, Ohita piilottaa rivin tältä päivältä. Korjaukset ☰ → Asetukset → Paino ja pituus.
class WeightTodayCard extends StatelessWidget {
  const WeightTodayCard({super.key});

  // Kuuntelee asetuksia itse, jotta merkintä tai ohitus piilottaa rivin heti.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final today = dateOnly(DateTime.now());
      if (!settings.bodyTracker || settings.body.weights.containsKey(today) || settings.bodySkipped == isoDate(today)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: const Icon(Icons.monitor_weight_outlined),
                label: Text(t('Merkitse aamupaino')),
                onPressed: () async {
                  final kg = await askBodyValue(
                    context,
                    height: false,
                    title: t('Aamupaino'),
                    previous: settings.body.sorted.lastOrNull,
                  );
                  if (kg != null) await settings.setWeight(today, kg);
                },
              ),
            ),
            const SizedBox(width: 4),
            TextButton(onPressed: () => settings.skipBodyToday(isoDate(today)), child: Text(t('Ohita'))),
          ],
        ),
      );
    },
  );
}
