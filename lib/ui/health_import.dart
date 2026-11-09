import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../health.dart';
import '../l10n.dart';
import '../models.dart';
import '../sports.dart';
import 'activity.dart';
import 'widgets.dart';

// Tehdyn liikunnan lisäys Health Connectista (asetus, oletus pois): päivän harjoitukset, joita ei vielä ole
// Gievrassa. Harjoitus avautuu valmiiksi täytettynä liikuntasivuna, jonka käyttäjä tarkistaa ja tallentaa
// (Treeni valmis!). Ei massatuontia: yksi kerrallaan.

/// Etusivun painike (Android, asetus päällä).
class HealthImportButton extends StatelessWidget {
  const HealthImportButton({super.key});

  static bool get visible => settings.hcImport && !kIsWeb && !isDemo && Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    // Yhtä leveä kuin yläpuolen Sali/Liikunta-painikkeet, samat kulmat, mutta matalampi ja hillitty vihreä
    // (liikunnan väri): toissijainen toiminto.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF173A22) : const Color(0xFFDCEFD8);
    final fg = dark ? const Color(0xFFA8E0B4) : const Color(0xFF0B4F24);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthImportScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, color: fg, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t('Lisää tehty liikunta Health Connectista'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HealthImportScreen extends StatefulWidget {
  const HealthImportScreen({super.key});
  @override
  State<HealthImportScreen> createState() => _HealthImportScreenState();
}

enum _State { loading, unavailable, noPermission, ready, error }

class _HealthImportScreenState extends State<HealthImportScreen> {
  DateTime _day = dateOnly(DateTime.now());
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
      final (fresh, done) = newHealthSessions(all, store.workouts);
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

  /// Kehitysversio: keksitty kävely (79) valitulle päivälle emulaattorin testaukseen.
  Future<void> _debugInsert() async {
    if (!await HealthConnect.request(write: true, import: true).catchError((_) => false)) return;
    final s = DateTime(_day.year, _day.month, _day.day, 8, 2);
    await HealthConnect.debugInsert(s, s.add(const Duration(hours: 2, minutes: 41)), type: 79, bpm: 104);
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
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
    );
    if (d != null) _setDay(d);
  }

  String _dayLabel() {
    final today = dateOnly(DateTime.now());
    if (_day == today) return t('Tänään · {0}', [shortDate(_day)]);
    if (_day == today.subtract(const Duration(days: 1))) return t('Eilen · {0}', [shortDate(_day)]);
    return shortDate(_day);
  }

  Future<void> _add(HealthCandidate c) async {
    final sport =
        sportForHealthType(c.type) ??
        await pickSport(context, t('Health Connect: {0}. Valitse lähin laji:', [c.title ?? t('tuntematon laji')]));
    if (sport == null || !mounted) return;
    final day = DateTime(c.start.year, c.start.month, c.start.day);
    final w = workoutFromHealth(c, sport, session: store.onDay(day).isEmpty ? 1 : store.nextSession(day));
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(workout: w, manual: true)));
    if (mounted) await _load(); // tallennettu liikunta katoaa listalta
  }

  static String _hm(DateTime d) => '${d.hour}.${d.minute.toString().padLeft(2, '0')}';

  Widget _item(HealthCandidate c, TextStyle sub) {
    final sport = sportForHealthType(c.type);
    final details = [
      if ((c.meters ?? 0) > 0) '${fmtNum((c.meters! / 100).round() / 10)} km',
      if (c.hrAvg != null) '❤️ ${c.hrAvg}',
      if (c.kcal != null) '${c.kcal} kcal',
      if ((c.steps ?? 0) > 0) t('{0} askelta', [c.steps]),
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: Text(sportOf(sport)?.icon ?? '✨', style: const TextStyle(fontSize: 28)),
        title: Text(sport == null ? (c.title ?? t('tuntematon laji')) : sportName(sport)),
        subtitle: Text(
          [
            '${_hm(c.start)}–${_hm(c.end)} · ${fmtDurationSec(c.duration.inSeconds)}',
            if (details.isNotEmpty) details,
            if (c.app.isNotEmpty) c.app,
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
      appBar: AppBar(title: Text(t('Lisää tehty liikunta'))),
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
