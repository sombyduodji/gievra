import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../health.dart';
import '../health_bulk.dart';
import '../l10n.dart';
import '../models.dart';
import '../sports.dart';
import 'widgets.dart';

// Health Connectin joukkotuonti (Tuonti ja vienti, käyttäjä 21.11.): kaikki harjoitukset valitulta ajalta listana,
// josta käyttäjä valitsee tuotavat. Ei kaksoiskappaleita: jo Gievrassa olevat joko ohitetaan tai, jos Health
// Connectissa on niille lisätietoja, tarjotaan päivitettäväksi (vain puuttuvat tiedot). Keskeytyneen voi jatkaa.

enum _S { loading, checking, unavailable, noPermission, ready, importing, done, error }

class HealthBulkImportScreen extends StatefulWidget {
  const HealthBulkImportScreen({super.key});
  @override
  State<HealthBulkImportScreen> createState() => _HealthBulkImportScreenState();
}

class _HealthBulkImportScreenState extends State<HealthBulkImportScreen> with WidgetsBindingObserver {
  /// Yksi tuonti kerrallaan koko sovelluksessa (kaksi avattua sivua ei tuo samoja kahdesti).
  static bool _running = false;

  _S _s = _S.loading;

  /// Aikaväli päivinä; 0 = kaikki (Health Connect antaa sen, minkä luvat sallivat).
  int _days = 0;
  List<BulkItem> _items = const [];
  final Map<int, List<BulkGain>> _gains = {};
  Set<int> _chosen = {};
  bool _historyMissing = false;
  String? _error, _checkFailed;

  /// Lupaa on jo pyydetty tällä sivulla: kiellon jälkeen Android ei näytä lupakyselyä uudelleen, joten tarjotaan
  /// Health Connectin asetukset (yötesti 22.11.: Anna lupa ei muuten tehnyt mitään).
  bool _asked = false, _askedHistory = false, _asking = false;

  // Tarkistus ja tuonti: edistyminen, keskeytys ja tulos.
  int _progress = 0, _total = 0, _added = 0, _updated = 0, _skipped = 0;
  bool _cancel = false;
  String? _stopped;

  List<int> _idx(BulkKind k) => [
    for (var i = _items.length - 1; i >= 0; i--)
      if (_items[i].kind == k) i,
  ]; // uusin ensin kuten kalenterissa

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Health Connectin asetuksista palattaessa luvat tarkistetaan uudelleen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_asking &&
        (_s == _S.noPermission || (_s == _S.ready && _historyMissing))) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _s = _S.loading;
      _checkFailed = null;
    });
    try {
      if (await HealthConnect.status() != 'available') {
        if (mounted) setState(() => _s = _S.unavailable);
        return;
      }
      if (!await HealthConnect.granted(import: true)) {
        if (mounted) setState(() => _s = _S.noPermission);
        return;
      }
      _historyMissing =
          await HealthConnect.historyAvailable() && !await HealthConnect.granted(import: true, history: true);
      final now = DateTime.now();
      final from = _days == 0 ? DateTime(2000) : DateTime(now.year, now.month, now.day - _days + 1);
      final items = bulkPlan(await HealthConnect.sessionList(from, now), store.workouts);
      _gains.clear();
      // Jo Gievrassa olevat, joilta puuttuu jotain: haetaan Health Connectin tiedot ja katsotaan, mitä lisättäisiin.
      final check = [
        for (var i = 0; i < items.length; i++)
          if (items[i].kind == BulkKind.update) i,
      ];
      if (check.isNotEmpty && mounted) {
        setState(() {
          _s = _S.checking;
          _progress = 0;
          _total = check.length;
        });
      }
      for (final i in check) {
        if (!mounted) return;
        final it = items[i];
        try {
          it.c = await HealthConnect.fullSession(it.c);
        } catch (e) {
          // Lukurajoitus tms.: loput jätetään tällä kertaa ohitetuiksi (ei muutoksia), voi tarkistaa myöhemmin.
          _checkFailed = errorText(e);
          for (final j in check.where((j) => j >= i)) {
            items[j].kind = BulkKind.skip;
          }
          break;
        }
        final g = bulkGains(it.match!, it.c);
        if (g.isEmpty) {
          it.kind = BulkKind.skip;
        } else {
          _gains[i] = g;
        }
        if (mounted) setState(() => _progress++);
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _chosen = {
          for (var i = 0; i < items.length; i++)
            if (items[i].kind == BulkKind.add && !items[i].dupe) i,
        };
        _s = _S.ready;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _s = _S.error;
        });
      }
    }
  }

  Future<void> _ask({bool history = false}) async {
    _asking = true;
    try {
      final h = history || await HealthConnect.historyAvailable();
      await HealthConnect.request(import: true, history: h).catchError((_) => false);
    } finally {
      _asking = false;
    }
    if (!mounted) return;
    setState(() => history ? _askedHistory = true : _asked = true);
    await _load();
  }

  /// Tuonti: uudet 20 harjoituksen erissä (tiedot haetaan, ja erä tallennetaan heti, jotta keskeytys ei hukkaa jo
  /// haettuja), sitten valitut päivitykset. Ennen tallennusta tarkistetaan vielä Gievran nykytila: harjoitus, joka on
  /// jo tuotu (esim. toisesta ikkunasta tai uudelleen valittuna), ohitetaan.
  Future<void> _import() async {
    if (_s != _S.ready || _chosen.isEmpty) return;
    if (_running) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Tuonti on jo käynnissä.'))));
      return;
    }
    _running = true;
    final sorted = _chosen.toList()..sort();
    final adds = [
      for (final i in sorted)
        if (_items[i].kind == BulkKind.add) _items[i].c,
    ];
    final updates = [
      for (final i in sorted)
        if (_items[i].kind == BulkKind.update) _items[i],
    ];
    setState(() {
      _s = _S.importing;
      _progress = 0;
      _total = adds.length + updates.length;
      _added = _updated = _skipped = 0;
      _cancel = false;
      _stopped = null;
    });
    try {
      for (var i = 0; i < adds.length && !_cancel && _stopped == null; i += 20) {
        final batch = <HealthCandidate>[];
        for (final c in adds.skip(i).take(20)) {
          if (_cancel) break;
          try {
            batch.add(await HealthConnect.fullSession(c));
          } catch (e) {
            // Lukurajoitus tms. kesken erän: jo haetut tallennetaan silti (yötesti 22.11.: erä hukkui).
            _stopped = errorText(e);
            break;
          }
          if (mounted) setState(() => _progress++);
        }
        final (created, skipped) = bulkWorkouts(batch, store.workouts);
        final n = await store.saveMany(created);
        _added += n;
        _skipped += skipped + created.length - n;
      }
      for (final it in updates) {
        if (_cancel || _stopped != null) break;
        final m = it.match!;
        final cur = store.onDay(m.date).where((w) => w.session == m.session).firstOrNull;
        final w = cur?.copy();
        if (w != null && fillMissing(w, it.c).isNotEmpty) {
          await store.save(w);
          _updated++;
        } else {
          _skipped++;
        }
        if (mounted) setState(() => _progress++);
      }
    } catch (e) {
      _stopped = errorText(e);
    } finally {
      _running = false;
    }
    if (mounted) setState(() => _s = _S.done);
  }

  /// Kehitysversio: 40 keksittyä harjoitusta viimeisille 120 päivälle (kävely, juoksu, sali, tuntematon laji ja
  /// kaksoiskappale) sekä käsin kirjattu kävely ilman sykettä ja aloitusaikaa (päivitys) joukkotuonnin testaukseen.
  Future<void> _debugFill() async {
    if (!await HealthConnect.request(write: true, import: true).catchError((_) => false)) return;
    final now = DateTime.now();
    const types = [79, 56, 70, 8, 0];
    for (var i = 0; i < 40; i++) {
      final s = DateTime(now.year, now.month, now.day - 2 - i * 3, 7 + i % 10, 5);
      final type = types[i % types.length];
      await HealthConnect.debugInsert(
        s,
        s.add(Duration(minutes: 25 + i % 40)),
        type: type,
        bpm: 95 + i % 50,
      );
      if (i % 10 == 0) {
        await HealthConnect.debugInsert(
          s.add(const Duration(minutes: 1)),
          s.add(Duration(minutes: 24 + i % 40)),
          type: type,
          bpm: 100,
        );
      }
    }
    final d = DateTime(now.year, now.month, now.day - 1);
    await store.save(Workout(date: d, title: 'Kävely', activity: 'Kävely', session: store.nextSession(d), minutes: 45));
    final s = DateTime(d.year, d.month, d.day, 6, 30);
    await HealthConnect.debugInsert(s, s.add(const Duration(minutes: 44)), type: 79, bpm: 108);
    await _load();
  }

  static String _hm(DateTime d) => '${d.hour}.${d.minute.toString().padLeft(2, '0')}';

  String _gainText(BulkGain g) => switch (g) {
    BulkGain.hr => t('syke'),
    BulkGain.curve => t('sykekäyrä'),
    BulkGain.kcal => t('kalorit'),
    BulkGain.distance => t('matka'),
    BulkGain.steps => t('askeleet'),
    BulkGain.start => t('aloitusaika'),
    BulkGain.time => t('kesto'),
  };

  Widget _row(int i, TextStyle sub) {
    final it = _items[i];
    final c = it.c;
    final gym = isStrengthType(c.type);
    final sport = sportForHealthType(c.type);
    final name = gym
        ? t('Salitreeni')
        : sport != null
        ? sportName(sport)
        : '${sportName('Muu liikunta')}${(c.title ?? '').isEmpty ? '' : ' · ${c.title}'}';
    final gains = _gains[i];
    return CheckboxListTile(
      key: ValueKey('bulk$i'),
      value: _chosen.contains(i),
      onChanged: (v) => setState(() => v == true ? _chosen.add(i) : _chosen.remove(i)),
      secondary: Text(
        gym ? '🏋️' : sportOf(sport ?? 'Muu liikunta')?.icon ?? '✨',
        style: const TextStyle(fontSize: 24),
      ),
      title: Text(name),
      subtitle: Text(
        [
          '${shortDateY(c.start)} ${_hm(c.start)} · ${fmtDurationSec(c.duration.inSeconds)}',
          if (c.app.isNotEmpty) c.app,
          if (it.dupe) t('Mahdollinen kaksoiskappale (sama aika kuin edellisellä)'),
          if (gains != null) t('Lisätään: {0}', [gains.map(_gainText).join(', ')]),
        ].join('\n'),
        style: sub,
      ),
      isThreeLine: c.app.isNotEmpty || it.dupe || gains != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _periodChoice() => Wrap(
    spacing: 8,
    children: [
      for (final (d, label) in [(30, t('30 päivää')), (365, t('12 kuukautta')), (0, t('Kaikki'))])
        ChoiceChip(
          label: Text(label),
          selected: _days == d,
          onSelected: _s != _S.ready
              ? null
              : (_) {
                  _days = d;
                  _load();
                },
        ),
    ],
  );

  /// Ryhmän valinta: kaikki tai ei mitään.
  Widget _toggle(List<int> group) {
    final all = group.every(_chosen.contains);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => setState(() => all ? _chosen.removeAll(group) : _chosen.addAll(group)),
        child: Text(all ? t('Poista valinnat') : t('Valitse kaikki')),
      ),
    );
  }

  Widget _progressView(String text, {bool cancel = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        LinearProgressIndicator(value: _total == 0 ? null : _progress / _total),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        if (cancel) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            key: const ValueKey('bulkCancel'),
            onPressed: _cancel ? null : () => setState(() => _cancel = true),
            child: Text(t('Keskeytä')),
          ),
        ],
      ],
    ),
  );

  Widget _readyView(TextStyle sub) {
    final adds = _idx(BulkKind.add), updates = _idx(BulkKind.update);
    final skips = _items.where((x) => x.kind == BulkKind.skip).length;
    final rows = <Widget Function()>[
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('Aikaväli'), style: const TextStyle(fontWeight: FontWeight.w600)),
          _periodChoice(),
          if (_historyMissing) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(
                        'Health Connect näyttää ilman historialupaa vain 30 päivää ennen ensimmäistä '
                        'lupaa. Salli vanhempi historia, niin myös vanhemmat harjoitukset löytyvät.',
                      ),
                      style: sub,
                    ),
                    TextButton(onPressed: () => _ask(history: true), child: Text(t('Salli vanhempi historia'))),
                    if (_askedHistory)
                      TextButton(onPressed: HealthConnect.openSettings, child: Text(t('Avaa Health Connect'))),
                  ],
                ),
              ),
            ),
          ],
          if (kDebugMode)
            TextButton(onPressed: _debugFill, child: const Text('Kehitysversio: lisää 40 testiharjoitusta')),
          const SizedBox(height: 8),
          Text(
            adds.length == 1 ? t('1 uusi harjoitus') : t('{0} uutta harjoitusta', [adds.length]),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (skips > 0)
            Text(
              skips == 1
                  ? t('1 on jo Gievrassa, eikä Health Connectissa ole sille uutta tietoa: ohitetaan.')
                  : t('{0} on jo Gievrassa, eikä Health Connectissa ole niille uutta tietoa: ohitetaan.', [skips]),
              style: sub,
            ),
          if (_checkFailed != null)
            Text(t('Kaikkia Gievrassa olevia ei voitu tarkistaa: {0}', [_checkFailed!]), style: sub),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t('Liikunta näkyy täällä, kun kellon tai muun sovelluksen tallentama harjoitus on Health Connectissa.'),
                style: sub,
              ),
            )
          else if (adds.isNotEmpty)
            _toggle(adds),
        ],
      ),
      for (final i in adds) () => _row(i, sub),
      if (updates.isNotEmpty) ...[
        () => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Jo Gievrassa, Health Connectissa lisätietoja ({0})', [updates.length]),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                t('Päivitetäänkö? Vain puuttuvat tiedot lisätään; mitään ei korvata eikä uutta treeniä tehdä.'),
                style: sub,
              ),
              _toggle(updates),
            ],
          ),
        ),
        for (final i in updates) () => _row(i, sub),
      ],
    ];
    final nAdd = _chosen.where((i) => _items[i].kind == BulkKind.add).length;
    final nUpd = _chosen.length - nAdd;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: rows.length,
            itemBuilder: (context, i) => rows[i](),
          ),
        ),
        if (adds.isNotEmpty || updates.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('bulkImport'),
                  onPressed: _chosen.isEmpty ? null : _import,
                  child: Text(
                    [
                      if (nAdd > 0 || nUpd == 0) nAdd == 1 ? t('Tuo 1 harjoitus') : t('Tuo {0} harjoitusta', [nAdd]),
                      if (nUpd > 0) nUpd == 1 ? t('päivitä 1') : t('päivitä {0}', [nUpd]),
                    ].join(', '),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 13, color: cs.onSurfaceVariant);
    const pad = EdgeInsets.fromLTRB(16, 8, 16, 8);
    final Widget body = switch (_s) {
      _S.loading => const Center(child: CircularProgressIndicator()),
      _S.checking => _progressView(t('Verrataan Gievrassa oleviin: {0}/{1}', [_progress, _total])),
      _S.unavailable => Padding(
        padding: pad,
        child: Text(
          t('Health Connect ei ole käytettävissä tässä puhelimessa. Asenna tai päivitä Health Connect -sovellus.'),
          style: sub,
        ),
      ),
      _S.error => Padding(
        padding: pad,
        child: Text(t('Health Connectin lukeminen ei onnistunut: {0}', [_error ?? '']), style: sub),
      ),
      _S.noPermission => ListView(
        padding: pad,
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
          if (_asked) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: HealthConnect.openSettings, child: Text(t('Avaa Health Connect'))),
          ],
        ],
      ),
      _S.importing => _progressView(t('Haetaan tietoja: {0}/{1}', [_progress, _total]), cancel: true),
      _S.done => ListView(
        padding: pad,
        children: [
          const SizedBox(height: 16),
          Text(
            _added == 1 ? t('Tuotiin 1 harjoitus.') : t('Tuotiin {0} harjoitusta.', [_added]),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          if (_updated > 0)
            Text(
              _updated == 1 ? t('Päivitettiin 1 treeni.') : t('Päivitettiin {0} treeniä.', [_updated]),
              textAlign: TextAlign.center,
            ),
          if (_skipped > 0)
            Text(
              _skipped == 1
                  ? t('Ohitettiin 1, joka oli jo Gievrassa.')
                  : t('Ohitettiin {0}, jotka olivat jo Gievrassa.', [_skipped]),
              style: sub,
              textAlign: TextAlign.center,
            ),
          if (_stopped != null || _cancel) ...[
            const SizedBox(height: 8),
            Text(
              _stopped != null ? t('Health Connect keskeytti haun: {0}', [_stopped!]) : t('Tuonti keskeytettiin.'),
              style: sub,
              textAlign: TextAlign.center,
            ),
            Text(
              t('Tuodut säilyvät. Jatka myöhemmin: jo tuodut jätetään pois.'),
              style: sub,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            t('Fiiliksen ja muistiinpanoja voi lisätä treeneihin myöhemmin kalenterista.'),
            style: sub,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('Valmis'))),
          TextButton(onPressed: _load, child: Text(t('Näytä lista uudelleen'))),
        ],
      ),
      _S.ready => _readyView(sub),
    };
    return PopScope(
      // Kesken tuonnin takaisin keskeyttää (jo tallennetut säilyvät); sivu pysyy auki tulokseen asti.
      canPop: _s != _S.importing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _s == _S.importing) setState(() => _cancel = true);
      },
      child: Scaffold(
        appBar: AppBar(title: BarTitle(Text(t('Tuo Health Connectista')))),
        body: body,
      ),
    );
  }
}
