import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import '../theme.dart' show samiBarBand;

import '../app_state.dart';
import '../health.dart';
import '../l10n.dart';
import '../models.dart';
import '../sports.dart';
import 'activity.dart';
import 'workout.dart';
import 'widgets.dart';

// Tehdyn liikunnan lisäys Health Connectista (asetus, oletus pois): päivän harjoitukset, joita ei vielä ole
// Gievrassa. Harjoitus avautuu valmiiksi täytettynä liikuntasivuna, jonka käyttäjä tarkistaa ja tallentaa
// (Treeni valmis!). Ei massatuontia: yksi kerrallaan.

/// Etusivun Health Connect -rivi (Android, asetus päällä; ulkoasun kohennus 16.11.): kaksi riviä ("HEALTH CONNECT"
/// ja "n uutta harjoitusta") ja näkyy vain, kun viimeisen 7 päivän aikana on harjoituksia, joita ei ole vielä
/// Gievrassa. Napautus avaa tuonnin uusimman tällaisen päivän kohdalta. Jos tarkistus ei onnistu (esim. lupa
/// puuttuu), rivi näyttää vanhan kehotuksen.
class HealthImportButton extends StatefulWidget {
  const HealthImportButton({super.key});

  static bool get visible => settings.hcImport && !kIsWeb && !isDemo && Platform.isAndroid;

  /// Health Connect on käytettävissä tällä laitteella (Android, ei demo); ei vaadi tuontiasetusta.
  static bool get available => !kIsWeb && !isDemo && Platform.isAndroid;

  /// Uudet harjoitukset: (määrä, uusin päivä); null = ei vielä tarkistettu tai tarkistus epäonnistui.
  static final found = ValueNotifier<(int, DateTime?)?>(null);
  static bool _checking = false;
  static bool failed = false;

  /// Tarkistus: avatessa, etusivun alas vetäessä ja treenien muuttuessa.
  static Future<void> refresh() async {
    if (!visible || _checking) return;
    _checking = true;
    try {
      final today = dateOnly(DateTime.now());
      var n = 0;
      DateTime? latest;
      for (var i = 0; i < 7; i++) {
        final d = addDays(today, -i);
        final (fresh, _) = newHealthSessions(await HealthConnect.sessions(d), store.workouts);
        if (fresh.isNotEmpty) {
          n += fresh.length;
          latest ??= d;
        }
      }
      failed = false;
      found.value = (n, latest);
    } catch (_) {
      failed = true;
      found.value = null;
    } finally {
      _checking = false;
    }
  }

  @override
  State<HealthImportButton> createState() => _HealthImportButtonState();
}

class _HealthImportButtonState extends State<HealthImportButton> {
  int _rev = -1;

  @override
  Widget build(BuildContext context) {
    // Treenit muuttuivat (tuonti tai tallennus): tarkistetaan uudelleen.
    if (_rev != store.rev) {
      _rev = store.rev;
      WidgetsBinding.instance.addPostFrameCallback((_) => HealthImportButton.refresh());
    }
    return ValueListenableBuilder(
      valueListenable: HealthImportButton.found,
      builder: (context, v, _) {
        final n = v?.$1 ?? 0;
        if (!HealthImportButton.failed && n == 0) return const SizedBox.shrink();
        final dark = Theme.of(context).brightness == Brightness.dark;
        final bg = dark ? const Color(0xFF16261C) : const Color(0xFFDCEFD8);
        final fg = dark ? const Color(0xFFA8E0B4) : const Color(0xFF0B4F24);
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: fg.withValues(alpha: .35)),
            ),
            child: InkWell(
              key: const ValueKey('hcRow'),
              borderRadius: BorderRadius.circular(16),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => HealthImportScreen(day: v?.$2))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.sync, color: fg, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HEALTH CONNECT',
                            style: TextStyle(fontSize: 10.5, letterSpacing: .6, color: cs.onSurfaceVariant),
                          ),
                          Text(
                            n == 0
                                ? t('Lisää tehty liikunta Health Connectista')
                                : n == 1
                                ? t('1 uusi harjoitus')
                                : t('{0} uutta harjoitusta', [n]),
                            style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: fg),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class HealthImportScreen extends StatefulWidget {
  /// Avautuva päivä (etusivun rivi: uusin päivä, jolla on uutta); oletuksena tänään.
  final DateTime? day;
  const HealthImportScreen({super.key, this.day});
  @override
  State<HealthImportScreen> createState() => _HealthImportScreenState();
}

enum _State { loading, unavailable, noPermission, ready, error }

class _HealthImportScreenState extends State<HealthImportScreen> {
  late DateTime _day = dateOnly(widget.day ?? DateTime.now());
  _State _state = _State.loading;
  List<HealthCandidate> _fresh = const [];
  int _done = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _State.loading);
    try {
      if (await HealthConnect.status() != 'available') {
        if (mounted) setState(() => _state = _State.unavailable);
        return;
      }
      if (!await HealthConnect.granted(import: true)) {
        if (mounted) setState(() => _state = _State.noPermission);
        return;
      }
      final all = await HealthConnect.sessions(_day);
      // Askeleet ilman harjoitusta (esim. kävelymatto, joka ei tallenna harjoitusta): yhtenäiset kävelyt listaan.
      var walks = <HealthCandidate>[];
      try {
        walks = stepStretches(await HealthConnect.stepRecords(_day), sessions: all);
        walks = [for (final c in walks) await HealthConnect.withRangeStats(c).catchError((_) => c)];
      } catch (_) {}
      final (fresh, done) = newHealthSessions([...all, ...walks], store.workouts);
      fresh.sort((a, b) => a.start.compareTo(b.start));
      if (!mounted) return;
      setState(() {
        _fresh = fresh;
        _done = done;
        _state = _State.ready;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _state = _State.error;
        });
      }
    }
  }

  /// Kehitysversio: keksitty kävely (79) tai salitreeni (70) valitulle päivälle emulaattorin testaukseen.
  Future<void> _debugInsert({bool gym = false, bool steps = false}) async {
    if (!await HealthConnect.request(write: true, import: true).catchError((_) => false)) return;
    if (steps) {
      var s = DateTime(_day.year, _day.month, _day.day, 13, 10);
      final ago = DateTime.now().subtract(const Duration(minutes: 50));
      if (s.isAfter(ago)) s = ago;
      await HealthConnect.debugInsert(s, s.add(const Duration(minutes: 42)), type: -1, bpm: 96);
      await _load();
      return;
    }
    var s = DateTime(_day.year, _day.month, _day.day, gym ? 17 : 8, gym ? 5 : 2);
    final ago = DateTime.now().subtract(const Duration(hours: 2)); // ei tulevaisuuteen
    if (gym && s.isAfter(ago)) s = ago;
    gym
        ? await HealthConnect.debugInsert(s, s.add(const Duration(minutes: 64)), type: 70, bpm: 118)
        : await HealthConnect.debugInsert(s, s.add(const Duration(hours: 2, minutes: 41)), type: 79, bpm: 104);
    await _load();
  }

  Future<void> _ask() async {
    await HealthConnect.request(import: true);
    await _load();
  }

  void _setDay(DateTime d) {
    final today = dateOnly(DateTime.now());
    _day = d.isAfter(today) ? today : dateOnly(d);
    _load();
  }

  Future<void> _pickDay() async {
    final today = dateOnly(DateTime.now());
    final d = await pickDate(context, initial: _day, first: today.subtract(const Duration(days: 365)), last: today);
    if (d != null && mounted) _setDay(d);
  }

  String _dayLabel() {
    final today = dateOnly(DateTime.now());
    if (_day == today) return t('Tänään · {0}', [shortDate(_day)]);
    if (_day == today.subtract(const Duration(days: 1))) return t('Eilen · {0}', [shortDate(_day)]);
    return shortDate(_day);
  }

  bool _adding = false;

  /// Rivin napautus. Tuplanapautus ei saa avata kahta näkymää samasta treenistä (alempi kopio tallentaisi
  /// poistuessaan vanhan tilansa ylemmän päälle).
  Future<void> _add(HealthCandidate c) async {
    if (_adding) return;
    _adding = true;
    try {
      await _addInner(c);
    } finally {
      _adding = false;
    }
  }

  Future<void> _addInner(HealthCandidate c) async {
    if (isStrengthType(c.type)) return _addGym(c);
    final sport =
        sportForHealthType(c.type) ??
        await pickSport(
          context,
          c.stepsOnly
              ? t('{0} askelta ilman harjoitusta. Valitse laji:', [c.steps])
              : t('Health Connect: {0}. Valitse lähin laji:', [c.title ?? t('tuntematon laji')]),
        );
    if (sport == null || !mounted) return;
    final day = DateTime(c.start.year, c.start.month, c.start.day);
    final w = workoutFromHealth(c, sport, session: store.onDay(day).isEmpty ? 1 : store.nextSession(day));
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: w, manual: true)));
    if (mounted) await _load(); // tallennettu liikunta katoaa listalta
  }

  /// Salitreeni: kellon tiedot päivän salitreeniin tai uusi salitreeni, johon voi lisätä liikkeet.
  Future<void> _addGym(HealthCandidate c) async {
    final day = DateTime(c.start.year, c.start.month, c.start.day);
    final sameDay = store.onDay(day);
    final (w, isNew) = gymFromHealth(c, sameDay, nextSession: sameDay.isEmpty ? 1 : store.nextSession(day));
    await store.save(w);
    if (!mounted) return;
    if (!isNew) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Kellon tiedot lisätty salitreeniin.'))));
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutScreen(workout: w)));
    if (mounted) await _load();
  }

  /// Onko päivällä salitreeni, johon kellon tiedot lisätään.
  bool _hasGym(DateTime start) =>
      store.onDay(DateTime(start.year, start.month, start.day)).any((w) => w.activity == null && w.hcId == null);

  static String _hm(DateTime d) => '${d.hour}.${d.minute.toString().padLeft(2, '0')}';

  Widget _item(HealthCandidate c, TextStyle sub) {
    final sport = sportForHealthType(c.type);
    final gym = isStrengthType(c.type);
    final details = [
      if (!gym && (c.meters ?? 0) > 0) '${fmtNum((c.meters! / 100).round() / 10)} km',
      if (c.hrAvg != null) '❤️ ${c.hrAvg}',
      if (c.kcal != null) '${c.kcal} kcal',
      if (!gym && !c.stepsOnly && (c.steps ?? 0) > 0) t('{0} askelta', [c.steps]),
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: Text(
          gym
              ? '🏋️'
              : c.stepsOnly
              ? '👣'
              : sportOf(sport)?.icon ?? '✨',
          style: const TextStyle(fontSize: 28),
        ),
        title: Text(
          gym
              ? t('Salitreeni')
              : c.stepsOnly
              ? t('{0} askelta', [c.steps])
              : sport == null
              ? (c.title ?? t('tuntematon laji'))
              : sportName(sport),
        ),
        subtitle: Text(
          [
            '${_hm(c.start)}–${_hm(c.end)} · ${fmtDurationSec(c.duration.inSeconds)}',
            if (details.isNotEmpty) details,
            if (c.app.isNotEmpty) c.app,
            if (gym) _hasGym(c.start) ? t('Lisätään päivän salitreeniin') : t('Uusi salitreeni'),
            if (c.stepsOnly) t('Askeleita ilman harjoitusta'),
          ].join('\n'),
          style: sub,
        ),
        isThreeLine: details.isNotEmpty || c.app.isNotEmpty,
        trailing: const Icon(Icons.add_circle_outline),
        onTap: () => _add(c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 13, color: cs.onSurfaceVariant);
    final today = dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: BarTitle(Text(t('Lisää tehty liikunta'))), bottom: samiBarBand),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: t('Edellinen päivä'),
                onPressed: () => _setDay(_day.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _pickDay,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_dayLabel(), style: const TextStyle(fontSize: 16)),
                ),
              ),
              IconButton(
                tooltip: t('Seuraava päivä'),
                onPressed: _day == today ? null : () => _setDay(_day.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Text('Health Connect', textAlign: TextAlign.center, style: sub),
          const SizedBox(height: 12),
          switch (_state) {
            _State.loading => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            _State.unavailable => Text(
              t('Health Connect ei ole käytettävissä tässä puhelimessa. Asenna tai päivitä Health Connect -sovellus.'),
              style: sub,
            ),
            _State.noPermission => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    'Gievra tarvitsee luvan lukea Health Connectista harjoitukset, sykkeen, kalorit, askeleet ja '
                    'matkan. Tietoja ei lähetetä minnekään.',
                  ),
                  style: sub,
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _ask, child: Text(t('Anna lupa'))),
              ],
            ),
            _State.error => Text(t('Health Connectin lukeminen ei onnistunut: {0}', [_error ?? '']), style: sub),
            _State.ready => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_fresh.isEmpty) ...[
                  Text(
                    t('Tälle päivälle ei ole uutta tehtyä liikuntaa Health Connectissa.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t(
                      'Liikunta näkyy täällä, kun kellon tai muun sovelluksen tallentama harjoitus on Health Connectissa.',
                    ),
                    textAlign: TextAlign.center,
                    style: sub,
                  ),
                ],
                for (final c in _fresh) _item(c, sub),
                if (kDebugMode)
                  TextButton(onPressed: _debugInsert, child: const Text('Kehitysversio: lisää testikävely')),
                if (kDebugMode)
                  TextButton(
                    onPressed: () => _debugInsert(gym: true),
                    child: const Text('Kehitysversio: lisää testisali'),
                  ),
                if (kDebugMode)
                  TextButton(
                    onPressed: () => _debugInsert(steps: true),
                    child: const Text('Kehitysversio: lisää testiaskeleet'),
                  ),
                if (_done > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _done == 1 ? t('1 liikunta on jo Gievrassa.') : t('{0} liikuntaa on jo Gievrassa.', [_done]),
                      textAlign: TextAlign.center,
                      style: sub,
                    ),
                  ),
              ],
            ),
          },
        ],
      ),
    );
  }
}
