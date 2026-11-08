import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../health.dart';
import '../l10n.dart';
import '../models.dart';
import '../share_text.dart';
import '../sports.dart';
import '../theme.dart';
import 'widgets.dart';

/// Health Connect treenin jälkeen: odota, että kello on siirtänyt tiedot, tarkista, ja vahvista ehdokas
/// ("Onko tämä se?"). Palauttaa true, kun tiedot lisättiin treeniin.
Future<bool?> showHealthSheet(BuildContext context, Workout w) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _HealthSheet(w),
);

/// Treenit, joihin tällä kerralla haettiin tiedot Health Connectista (näkyy Kellon tiedot -kortissa).
final healthFilled = Expando<bool>('healthFilled');

enum _Step { start, unavailable, update, permission, wait, checking, found, none, error }

class _HealthSheet extends StatefulWidget {
  final Workout w;
  const _HealthSheet(this.w);
  @override
  State<_HealthSheet> createState() => _HealthSheetState();
}

class _HealthSheetState extends State<_HealthSheet> {
  _Step step = _Step.start;
  List<HealthCandidate> found = const [];
  int index = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    final s = await HealthConnect.status();
    if (!mounted) return;
    if (s != 'available') return setState(() => step = s == 'update' ? _Step.update : _Step.unavailable);
    final ok = await HealthConnect.granted().catchError((_) => false);
    if (mounted) setState(() => step = ok ? _Step.wait : _Step.permission);
  }

  Future<void> _ask() async {
    final ok = await HealthConnect.request().catchError((_) => false);
    if (mounted) setState(() => step = ok ? _Step.wait : _Step.permission);
  }

  Future<void> _check() async {
    setState(() => step = _Step.checking);
    try {
      final (start, end, _) = workoutWindow(widget.w);
      final all = await HealthConnect.candidates(start, end);
      found = rankCandidates(widget.w, all);
      index = 0;
      if (mounted) setState(() => step = found.isEmpty ? _Step.none : _Step.found);
    } catch (e) {
      error = '$e';
      if (mounted) setState(() => step = _Step.error);
    }
  }

  /// Kehitysversio: keksitty harjoitus treenin ajalle, jotta kulun voi testata emulaattorilla.
  Future<void> _debugInsert() async {
    final ok = await HealthConnect.request(write: true).catchError((_) => false);
    if (!ok) return;
    final (start, end, timed) = workoutWindow(widget.w);
    final s = timed ? start.subtract(const Duration(minutes: 2)) : start.add(const Duration(hours: 12));
    final e = timed ? end.add(const Duration(minutes: 1)) : s.add(const Duration(minutes: 35));
    await HealthConnect.debugInsert(s, e);
    await _check();
  }

  /// Askeleet näytetään ja lisätään vain kävely- ja juoksulajeihin.
  bool get stepsSport => sportOf(widget.w.activity)?.steps ?? false;

  String _hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 13, color: cs.onSurfaceVariant);
    Widget body;
    switch (step) {
      case _Step.start:
      case _Step.checking:
        body = const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      case _Step.unavailable:
        body = Text(t('Health Connect ei ole käytettävissä tässä puhelimessa. Kirjoita syke ja kalorit käsin.'));
      case _Step.update:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('Health Connect pitää asentaa tai päivittää Play Kaupasta.')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => launchUrl(
                Uri.parse('market://details?id=com.google.android.apps.healthdata'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(t('Avaa Play Kauppa')),
            ),
          ],
        );
      case _Step.permission:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(
                'Gievra lukee Health Connectista vain tämän treenin ajalta harjoituksen, sykkeen, kalorit ja askeleet. '
                'Tiedot pysyvät puhelimessa.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _ask, child: Text(t('Anna lupa'))),
          ],
        );
      case _Step.wait:
      case _Step.none:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              step == _Step.none
                  ? t('Tätä treeniä vastaavaa harjoitusta ei vielä löytynyt.')
                  : t('Lopeta harjoitus kellosta ja odota, että kellon sovellus siirtää tiedot Health Connectiin.'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              t('Siirto kestää yleensä muutaman minuutin. Voit jättää tämän auki ja tarkistaa välillä.'),
              style: sub,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _check,
              icon: const Icon(Icons.refresh),
              label: Text(step == _Step.none ? t('Tarkista uudelleen') : t('Tarkista')),
            ),
            if (kDebugMode)
              TextButton(onPressed: _debugInsert, child: const Text('Kehitysversio: lisää testiharjoitus')),
          ],
        );
      case _Step.found:
        final c = found[index];
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('Onko tämä se?'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.session ? (c.title ?? t('Harjoitus')) : t('Sykedata treenin ajalta'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        if (c.app.isNotEmpty) c.app,
                        '${_hm(c.start)}–${_hm(c.end)}',
                        t('{0} min', [c.duration.inMinutes]),
                      ].join(' · '),
                      style: sub,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (c.hrAvg != null || c.hrMax != null) '❤️ ${c.hrAvg ?? '–'} / ${c.hrMax ?? '–'}',
                        if (c.kcal != null) t('🔥 {0} kcal', [c.kcal]),
                        if (stepsSport && (c.steps ?? 0) > 0) t('👣 {0} askelta', [thousands(c.steps!)]),
                      ].join('   '),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => index + 1 < found.length ? setState(() => index++) : Navigator.pop(context),
                    child: Text(index + 1 < found.length ? t('Ei, seuraava') : t('Ohita')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Sami.green, foregroundColor: Colors.white),
                    onPressed: () {
                      applyCandidate(widget.w, c, steps: stepsSport);
                      healthFilled[widget.w] = true;
                      Navigator.pop(context, true);
                    },
                    child: Text(t('Lisää')),
                  ),
                ),
              ],
            ),
          ],
        );
      case _Step.error:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('Health Connectin luku ei onnistunut: {0}', [error ?? ''])),
            const SizedBox(height: 12),
            FilledButton(onPressed: _check, child: Text(t('Tarkista uudelleen'))),
          ],
        );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [SectionLabel(t('Health Connect')), body],
        ),
      ),
    );
  }
}
