import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'maps_screen.dart';
import '../maps/map_store.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'activity.dart';
import 'running_screen.dart';
import '../running.dart';
import '../app_info.dart';
import '../gps_recorder.dart';
import '../app_state.dart';
import '../auto_backup.dart';
import '../custom_merge.dart';
import '../drafts.dart';
import '../exercises.dart';
import '../insights.dart';
import '../models.dart';
import '../session_compare.dart';
import '../program.dart';
import '../theme.dart';
import 'drawer.dart';
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
          : w != null
          ? WorkoutScreen(workout: w.copy(), planDay: day)
          : NewWorkoutScreen(date: d, newSession: newSession),
    ),
  );
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
                  if (w.minutes != null) '${w.minutes} min',
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

class _HomeScreenState extends State<HomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// Kalenteri: oletuksena vain tämä viikko (vähemmän tilaa), kuukausi avautuu napista.
  bool _monthView = false;

  @override
  void initState() {
    super.initState();
    _resume();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkMoves().then((_) => _checkElevFormat()));
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
        final hasToday = open.isNotEmpty;
        final both = settings.trainMode == 'both';
        return Scaffold(
          appBar: AppBar(
            title: Text(
              (settings.name ?? '').isEmpty ? AppInfo.fullName : '${seGreeting(now)}, ${settings.name}',
              overflow: TextOverflow.ellipsis,
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
                  // Molemmat: + Sali ja + Lenkki vierekkäin, muut lajit pikavalintoina; ei näkymän vaihtoa.
                  const SizedBox(height: 18),
                  Builder(
                    builder: (context) {
                      final acts = store.onDay(today).where((w) => w.activity != null).toList();
                      final runs = runsOf(store.workouts);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _Cta(
                                  compact: true,
                                  label: hasToday ? t('Jatka treeniä') : t('Sali'),
                                  icon: hasToday ? Icons.play_arrow_rounded : Icons.add_rounded,
                                  onTap: () => hasToday
                                      ? (open.length == 1
                                            ? _open(context, today, open.single)
                                            : _chooseSession(context, today, open))
                                      : _startNew(context, today, gymOnly: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _Cta(
                                  compact: true,
                                  colors: const [Color(0xFF00843D), Sami.green],
                                  // Kaikki liikunta (ei vain lenkki): oma sivu, jossa lajivalinta (käytetyimmät ensin).
                                  label: t('Liikunta'),
                                  icon: Icons.add_rounded,
                                  onTap: () => _CardioHome._add(context, null),
                                ),
                              ),
                            ],
                          ),
                          if (HealthImportButton.visible) HealthImportButton(),

                          // Tämän päivän valmiit treenit (sali ja liikunta) riveinä.
                          for (final w in todays.where((w) => !open.contains(w))) _TodayRow(w),
                          for (final w in acts) _TodayRow(w),
                          if (hasToday)
                            Center(
                              child: TextButton.icon(
                                onPressed: () => _startNew(context, today, gymOnly: true),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text(t('Toinen salitreeni tälle päivälle')),
                              ),
                            ),
                          if (runs.isNotEmpty)
                            Center(
                              child: TextButton.icon(
                                onPressed: () =>
                                    Navigator.of(context)
                                        .push(MaterialPageRoute(builder: (_) => const RunningScreen())),
                                icon: const Icon(Icons.show_chart, size: 18),
                                label: Text(t('Juoksun kehitys')),
                              ),
                            ),
                          const SizedBox(height: 6),
                          const WeightTodayCard(),
                          if (settings.tips && settings.activePause == null) _InsightsCard(),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  // Iso painike: jatka keskeneräistä tai aloita uusi. Ohjelman ehdotus näkyy alarivillä;
                  // seuraavassa näkymässä päivän voi vielä vaihtaa.
                  _Cta(
                    label: hasToday
                        ? (open.length == 1
                              ? t('Jatka: {0}', [trName(open.single.title)])
                              : t('Jatka tämän päivän treeniä'))
                        : t('Aloita salitreeni'),
                    icon: hasToday ? Icons.play_arrow_rounded : Icons.add_rounded,
                    onTap: () => hasToday
                        ? (open.length == 1 ? _open(context, today, open.single) : _chooseSession(context, today, open))
                        : _startNew(context, today, gymOnly: true),
                  ),
                  // Tämän päivän valmiit treenit tiiviinä riveinä (avautuvat lukutilaan); keskeneräisen rinnalle
                  // voi aloittaa toisen treenin.
                  for (final w in todays.where((w) => !open.contains(w))) _TodayRow(w),
                  if (hasToday)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _startNew(context, today, gymOnly: true),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(both ? t('Toinen salitreeni tälle päivälle') : t('Uusi treeni tälle päivälle')),
                      ),
                    ),
                  if (store.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(store.error!, style: TextStyle(color: cs.error)),
                    ),
                  const SizedBox(height: 14),
                  const WeightTodayCard(),
                  if (settings.tips && settings.activePause == null) _InsightsCard(),
                ],
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _Calendar(
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
class _TodayRow extends StatelessWidget {
  final Workout w;
  const _TodayRow(this.w);

  @override
  Widget build(BuildContext context) {
    final name = w.activity != null ? sportName(w.activity!) : trName(w.title);
    final info = [
      if (w.distanceKm != null) '${fmtNum((w.distanceKm! * 100).round() / 100)} km',
      if (w.seconds != null) fmtDurationSec(w.seconds!) else if (w.minutes != null) fmtDuration(w.minutes!),
      if (w.activity == null && w.exercises.isNotEmpty)
        setsLabel(w.exercises.fold<int>(0, (a, e) => a + e.sets.where((s) => !s.warmup).length)),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Sami.green.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(context, w.date, w),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Sami.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${t('Tänään')}: $name',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (info.isNotEmpty) TextSpan(text: '  $info'),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.lock_outline, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Pienempi (kaksi vierekkäin) ja väri: punainen sali, vihreä kestävyys.
  final bool compact;
  final List<Color> colors;
  const _Cta({
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
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
          padding: EdgeInsets.symmetric(vertical: compact ? 16 : 20, horizontal: compact ? 8 : 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: compact ? 24 : 28),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: compact ? 16 : 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
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
                  onTap: d.isAfter(today) ? null : () => openDate(context, d),
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
                            Text(
                              w.activity != null ? sportName(w.activity!) : trName(w.title),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              w.exercises.where((e) => e.sets.isNotEmpty).map((e) => exerciseLabel(e.name)).join(' · '),
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

/// Ohut tilarivi etusivun yläreunassa (vammatila, tauko): napautus avaa tiedot.
class _ModeBanner extends StatelessWidget {
  final Color color;
  final String emoji, title, detail;
  final VoidCallback onTap;
  const _ModeBanner({
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
                        maxLines: 2,
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
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                settings.endPause();
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
    final runs = runsOf(store.workouts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        // Kuten salissa: painike avaa oman sivun, jossa valitaan laji (käytetyimmät ensin).
        _Cta(
          label: t('Aloita liikunta'),
          icon: Icons.add_rounded,
          colors: const [Color(0xFF00843D), Sami.green],
          onTap: () => _add(context, null),
        ),
        if (HealthImportButton.visible) HealthImportButton(),
        // Tämän päivän liikunnat tiiviinä riveinä (avautuvat lukutilaan).
        for (final w in acts.where((w) => w.date == today)) _TodayRow(w),
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
