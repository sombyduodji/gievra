import 'package:flutter/material.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../history_profile.dart';
import '../insights.dart';
import '../models.dart';
import '../program.dart';
import '../theme.dart';
import 'import_export.dart';
import 'injury_screen.dart';
import 'move_select.dart';
import 'program_view.dart';
import 'program_template.dart';
import 'picker.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Aloituskysely: tavoite, kokemus, päivät, kesto, vammat -> ohjelma. Ohitettavissa,
/// ja sen voi tehdä uudelleen ☰-valikosta.
class IntroScreen extends StatefulWidget {
  final bool firstRun;
  const IntroScreen({super.key, this.firstRun = false});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _page = PageController();
  int _i = 0;
  late String _goal = settings.style?.goal ?? settings.program?.goal ?? 'lihaskasvu';
  late String _exp = settings.style?.experience ?? settings.program?.experience ?? 'keski';
  late int _days = settings.style?.days ?? settings.program?.days ?? 3;
  late int _minutes = settings.style?.minutes ?? settings.program?.minutes ?? 60;
  late List<String> _injuries = [...settings.injuries];
  final Map<String, double> _maxes = {};
  late String _repStyle = settings.style?.repStyle ?? settings.program?.repStyle ?? 'suositus';
  late Set<String> _equipment = {
    ...?((settings.style?.equipment.isNotEmpty ?? false) ? settings.style!.equipment : settings.program?.equipment),
  };
  late List<String> _chosen = [...?settings.style?.moves];
  late String? _kbFocus = settings.style?.kbFocus ?? settings.program?.kbFocus;
  bool get _kbOnly => _equipment.length == 1 && _equipment.contains('kahvakuula');
  HistoryProfile? _profile; // treenihistoriasta päätellyt ehdotukset
  Map<String, String> _favorites = {};
  Program? _draft; // yhteenvedossa muokattu ohjelma
  String _draftKey = '';

  static const _lifts = ['Takakyykky', 'Penkkipunnerrus', 'Maastaveto'];

  bool get _pl => _goal == 'voimanosto';

  /// Voimanoston kilpaliikkeiden maksimit esitäytetään historiasta vain tankovoimanostossa.
  bool get _askMaxes => _pl && !_kbOnly;

  /// Kahvakuulaohjelman painotus; voimanostossa pelkillä kahvakuulilla oletuksena voima.
  String? get _kbFocusEff => _kbOnly ? (_kbFocus ?? (_pl ? 'voima' : null)) : null;
  int get _pages => 9; // viimeinen kysymys: ennätykset (valinnainen, kaikissa ohjelmissa)

  @override
  void initState() {
    super.initState();
    _fillMaxes(keepOld: true);
  }

  /// Ennätykset esitäytetään vain, jos ne löytyvät treenihistoriasta (paras arvioitu maksimi 6 kk:lta) tai
  /// nykyisestä ohjelmasta. Muut lisätään itse (Lisää ennätys); ilman niitä painoehdotus tulee ensimmäisen
  /// kirjatun treenin jälkeen.
  void _fillMaxes({bool keepOld = false}) {
    for (final l in _lifts) {
      final v = suggestedMax(store.workouts, l, DateTime.now()).$1?.e1rm;
      if (v != null) _maxes[l] = v.roundToDouble();
    }
    if (keepOld) {
      for (final e in (settings.program?.maxes ?? const <String, double>{}).entries) {
        _maxes.putIfAbsent(e.key, () => e.value);
      }
    }
  }

  /// Lisää ennätys: ensin liike, sitten arvio. Kahvakuulaliikkeessä kysytään raskain kuula viidelle toistolle.
  Future<void> _addMax([String? exercise]) async {
    final ex =
        exercise ??
        await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (ex == null || !mounted) return;
    final kb = kettlebellOnly(ex);
    final v = await askNumber(
      context,
      kb ? t('{0}: raskain kuula, jolla teet 5 hyvää toistoa (kg)', [ex]) : t('{0}: 1 toiston maksimi (kg)', [ex]),
      kb ? 16 : (_maxes[ex] ?? 60),
    );
    if (v == null || v <= 0) return;
    // Kahvakuula: 5 toistoa -> arvioitu maksimi (Epley).
    setState(() => _maxes[ex] = kb ? (v * (1 + 5 / 30) * 10).round() / 10 : v);
  }

  /// Täyttää vastaukset treenihistoriasta. Käyttäjä voi muuttaa jokaista.
  void _useHistory() {
    final p = analyzeHistory(store.workouts);
    setState(() {
      _profile = p;
      if (p == null) return;
      _goal = p.goal;
      _exp = p.experience;
      _days = p.days;
      _minutes = p.minutes;
      _repStyle = p.repStyle;
      _equipment = {...p.equipment};
      _favorites = {...p.favorites};
      // Tallennettu treenityyli (esim. varmuuskopiosta) on käyttäjän oma valinta: se voittaa päättelyn.
      final st = settings.style;
      if (st != null && !st.isEmpty) {
        _goal = st.goal ?? _goal;
        _exp = st.experience ?? _exp;
        _days = st.days ?? _days;
        _minutes = st.minutes ?? _minutes;
        _repStyle = st.repStyle ?? _repStyle;
        if (st.equipment.isNotEmpty) _equipment = {...st.equipment};
        if (st.moves.isNotEmpty) _chosen = [...st.moves];
        _kbFocus = st.kbFocus ?? _kbFocus;
      }
      _fillMaxes();
    });
    if (p == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('Treenejä on vielä liian vähän ehdotuksiin (vähintään 4).'))));
    } else {
      _next();
    }
  }

  Future<void> _importAndUse() async {
    final before = store.workouts.length;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportExportScreen()));
    if (!mounted) return;
    if (store.workouts.length > before || store.workouts.isNotEmpty) _useHistory();
  }

  /// "Historiastasi: ..." -peruste kysymyksen alle.
  Widget _from(String key) {
    final w = _profile?.why[key];
    if (w == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📊 ', style: TextStyle(fontSize: 14)),
          Expanded(
            child: Text(
              t('Historiastasi: {0}', [w]),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _skip() {
    settings.setIntroDone();
    if (!widget.firstRun) Navigator.pop(context);
  }

  void _next() {
    if (_i < _pages - 1) {
      _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Program _build() => generateProgram(
    goal: _goal,
    experience: _exp,
    days: _days,
    minutes: _minutes,
    injuries: _injuries,
    maxes: _maxes,
    repStyle: _repStyle,
    equipment: _equipment,
    favorites: _favorites,
    chosen: _chosen,
    kbFocus: _kbFocusEff,
  );

  /// Luonnos pysyy muokkauksineen, kunnes jokin vastaus muuttuu.
  Program _current() {
    final key =
        '$_goal|$_exp|$_days|$_minutes|$_injuries|$_repStyle|$_maxes|$_equipment|$_favorites|$_chosen|$_kbFocusEff';
    if (_draft == null || key != _draftKey) {
      _draft = _build();
      _draftKey = key;
    }
    return _draft!;
  }

  Future<void> _accept() async {
    // Vaihdettaessa ohjelmaa kysytään, tallennetaanko nykyinen (vaihdettavissa takaisin).
    if (!await askSaveCurrent(context)) return;
    settings.setInjuries(_injuries);
    settings.setStyle(
      TrainingStyle(
        goal: _goal,
        experience: _exp,
        days: _days,
        minutes: _minutes,
        repStyle: _repStyle,
        equipment: _equipment,
        moves: _chosen,
        kbFocus: _kbFocusEff,
      ),
    );
    await settings.setProgram(_current());
    if (mounted && !widget.firstRun) Navigator.pop(context);
  }

  Widget _choice(String label, String? sub, bool sel, VoidCallback onTap, {String? icon}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: sel ? Sami.yellow.withValues(alpha: .12) : cs.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: sel ? Sami.yellow : Colors.transparent, width: 2),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: icon == null ? null : Text(icon, style: const TextStyle(fontSize: 26)),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          onTap: () {
            onTap();
            setState(() {});
          },
        ),
      ),
    );
  }

  Widget _q(String title, List<Widget> children, {String? hint}) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      if (hint != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(hint, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      const SizedBox(height: 18),
      ...children,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = store.workouts.where((w) => w.exercises.any((e) => e.sets.isNotEmpty)).length;
    final pages = <Widget>[
      _q(
        t('Onko sinulla aiempia treenejä?'),
        [
          if (n > 0)
            _choice(
              t('Käytä treenihistoriaani'),
              t('{0} treeniä päiväkirjassa: tyyli, päivät, toistot ja suosikkiliikkeet niistä', [n]),
              _profile != null,
              _useHistory,
              icon: '📊',
            ),
          _choice(
            t('Tuo treenit FitNotesista tai varmuuskopiosta'),
            t('FitNotes (.fitnotes), Gievran varmuuskopio (.zip) tai .md-tiedostot. Ehdotukset tehdään niistä.'),
            false,
            _importAndUse,
            icon: '📥',
          ),
          _choice(
            t('Tuo valmis ohjelmapohja (.gmd)'),
            t('Valmentajalta, kaverilta tai verkon ohjelmatyökalulla tehty pohja'),
            false,
            () async {
              final ok = await importTemplate(this.context);
              if (ok && mounted) {
                if (widget.firstRun) {
                  settings.setIntroDone();
                } else {
                  Navigator.pop(this.context);
                }
              }
            },
            icon: '📋',
          ),
          _choice(t('Aloitan alusta'), t('Vastaan kysymyksiin itse'), _profile == null && _i > 0, _next, icon: '🌱'),
          if (_profile != null) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('{0} treenistä päätelty', [_profile!.workouts]),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (final e in _profile!.why.entries)
                      Text('• ${e.value}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(
                      t('Vastaukset on esitäytetty. Voit muuttaa mitä tahansa seuraavilla sivuilla ja ohjelmassa.'),
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
        hint: t(
          'Jos sinulla on treenihistoriaa, ohjelma voi lähteä siitä: tyyli, treenipäivät, toistot, '
          'sarjat ja suosikkiliikkeesi.',
        ),
      ),
      _q(t('Mikä on tavoitteesi?'), [
        _from('goal'),
        _choice(
          'Voimanosto',
          t('Kyykky, penkki ja maastaveto raskaammiksi'),
          _goal == 'voimanosto',
          () => _goal = 'voimanosto',
          icon: '🏋️',
        ),
        _choice(
          t('Lihaskasvu'),
          t('Kehonrakennus: lisää lihasta'),
          _goal == 'lihaskasvu',
          () => _goal = 'lihaskasvu',
          icon: '💪',
        ),
        _choice(
          t('Rasvanpoltto'),
          t('Pudota rasvaa ja pidä lihakset'),
          _goal == 'rasvanpoltto',
          () => _goal = 'rasvanpoltto',
          icon: '🔥',
        ),
        _choice(
          t('Yleiskunto'),
          t('Terveys, voima ja jaksaminen'),
          _goal == 'kunto',
          () => _goal = 'kunto',
          icon: '🌿',
        ),
        _choice(
          t('Mennään fiiliksellä'),
          t('Kevyt runko-ohjelma, ei stressiä'),
          _goal == 'vapaa',
          () => _goal = 'vapaa',
          icon: '🎲',
        ),
      ], hint: t('Ohjelma lasketaan tutkimusten ja valmentajien suositusten pohjalta. Voit vaihtaa sen milloin vain.')),
      _q(t('Kauanko olet treenannut salilla?'), [
        _from('experience'),
        for (final e in experiences.entries)
          _choice(
            e.value,
            switch (e.key) {
              'aloittelija' => t('Isot liikkeet tutuiksi, paino nousee nopeasti'),
              'keski' => t('Nousu hidastunut, tarvitset rakennetta'),
              _ => t('Enemmän volyymia ja säännölliset kevennykset'),
            },
            _exp == e.key,
            () => _exp = e.key,
          ),
      ]),
      _q(
        t('Millä välineillä treenaat mieluiten?'),
        [
          _from('equipment'),
          _choice(t('Kaikki käy'), t('Sali, jossa on kaikkea'), fitsAll(_equipment), () => _equipment = {}, icon: '✅'),
          for (final e in equipmentChoices.entries)
            _choice(
              t(e.value.$2),
              switch (e.key) {
                'vapaat' => t('Kyykyt, penkit ja soudut tangolla ja käsipainoilla'),
                'laitteet' => t('Ohjatut liikeradat, helppo oppia ja säätää'),
                'kahvakuula' => t('Heilautukset, rinnallevedot, ylösnousut, sopii myös kotiin'),
                _ => t('Ilman salia: kotona tai ulkona. Leuanvetoihin riittää ovitanko tai puiston tanko.'),
              },
              !fitsAll(_equipment) && _equipment.contains(e.key),
              () {
                final s = fitsAll(_equipment) ? <String>{} : {..._equipment};
                s.contains(e.key) ? s.remove(e.key) : s.add(e.key);
                _equipment = s;
              },
              icon: e.value.$1,
            ),
          // Pelkät kahvakuulat: oma ohjelma painotuksen mukaan.
          if (_kbOnly) ...[
            const SizedBox(height: 8),
            SectionLabel(t('Kahvakuulatreenin pääpaino')),
            for (final f in kbFocuses.entries)
              _choice(t(f.value.$2), t(f.value.$3), _kbFocusEff == f.key, () => _kbFocus = f.key, icon: f.value.$1),
            _choice(
              t('Tavallinen ohjelma kahvakuulilla'),
              t('Liikemallit kuten salilla, kahvakuulaliikkeillä'),
              _kbFocusEff == null,
              () => _kbFocus = null,
              icon: '🔄',
            ),
          ],
        ],
        hint:
            t('Valitse yksi tai useampi. Ohjelma suosii niitä ja käyttää muita vain, jos sopivaa liikettä ei löydy.') +
            (_askMaxes ? ' ${t('Voimanoston kilpaliikkeet tehdään aina tangolla.')}' : ''),
      ),
      _q(t('Mitä liikkeitä haluat tehdä?'), [
        _choice(
          t('Ohjelma valitsee'),
          _favorites.isNotEmpty
              ? t('Tutkimuksiin perustuva liikevalinta (suosikkisi mukana)')
              : t('Tutkimuksiin perustuva liikevalinta'),
          _chosen.isEmpty,
          () => _chosen = [],
          icon: '🧭',
        ),
        _choice(
          _chosen.isEmpty ? t('Valitsen liikkeet itse') : t('Valitut liikkeet: {0}', [_chosen.length]),
          t('Ohjelma rakennetaan valitsemiesi liikkeiden ympärille'),
          _chosen.isNotEmpty,
          () async {
            final r = await Navigator.of(context).push<List<String>>(
              MaterialPageRoute(
                builder: (_) => MoveSelectScreen(initial: _chosen.isNotEmpty ? _chosen : _favorites.values.toList()),
              ),
            );
            if (r != null) setState(() => _chosen = r);
          },
          icon: '✍️',
        ),
        if (_chosen.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final x in _chosen) Chip(label: Text(x, style: const TextStyle(fontSize: 12)))],
          ),
        _from('favorites'),
      ], hint: t('Voit myös antaa ohjelman valita ja vaihtaa liikkeitä yhteenvedossa tai myöhemmin.')),
      _q(t('Kuinka monta kertaa viikossa?'), [
        _from('days'),
        _from('minutes'),
        Wrap(
          spacing: 8,
          children: [
            for (var d = 2; d <= 6; d++)
              ChoiceChip(
                label: Text('$d', style: const TextStyle(fontSize: 18)),
                selected: _days == d,
                onSelected: (_) => setState(() => _days = d),
              ),
          ],
        ),
        SectionLabel(t('Treenin kesto')),
        Wrap(
          spacing: 8,
          children: [
            for (final m in [45, 60, 75, 90])
              ChoiceChip(
                label: Text('$m min'),
                selected: _minutes == m,
                onSelected: (_) => setState(() => _minutes = m),
              ),
          ],
        ),
        SectionLabel(t('Toistoalue lisäliikkeissä')),
        _from('reps'),
        Wrap(
          spacing: 8,
          children: [
            for (final (k, l) in [('suositus', t('Suositus')), ('raskas', t('Raskaampi')), ('kevyt', t('Kevyempi'))])
              ChoiceChip(label: Text(l), selected: _repStyle == k, onSelected: (_) => setState(() => _repStyle = k)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(switch (_repStyle) {
            'raskas' => t('Vähemmän toistoja, isommat painot (esim. 4–6 ja 8–10). Voima kasvaa nopeammin.'),
            'kevyt' => t('Enemmän toistoja, pienemmät painot (esim. 10–15 ja 13–20). Nivelille kevyempi.'),
            _ => t(
              'Tavoitteesi mukainen alue. Lihaskasvu on yhtä hyvä 5–30 toistolla, kun sarjat viedään '
              'lähelle uupumusta.',
            ),
          }, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        const SizedBox(height: 4),
        Text(
          t('Liikkeitä, sarjoja ja toistoja voi muokata vielä yhteenvedossa.'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ]),
      _q(t('Onko sinulla vammoja tai kipuja?'), [
        _choice(t('Ei vammoja'), null, _injuries.isEmpty, () => _injuries = [], icon: '✅'),
        _choice(
          _injuries.isEmpty ? t('Valitse alueet') : t('Valittu: {0}', [_injuries.length]),
          t('Esim. olkapää, alaselkä, polvi, ranne'),
          _injuries.isNotEmpty,
          () async {
            final r = await Navigator.of(context)
                .push<List<String>>(MaterialPageRoute(builder: (_) => InjuryScreen(initial: _injuries, picker: true)));
            if (r != null) setState(() => _injuries = r);
          },
          icon: '🩹',
        ),
      ], hint: t('Ohjelma välttää ja muokkaa liikkeitä, jotka yleensä pahentavat vaivaa. Ei korvaa fysioterapeuttia.')),
      _q(
        t('Ennätykset (valinnainen)'),
        [
          for (final l in _maxes.keys.toList())
            Builder(
              builder: (context) {
                final now = DateTime.now();
                final pr = bestLift(store.workouts, l);
                final (sug, oldEnd) = suggestedMax(store.workouts, l, now);
                String d(DateTime t) => numDate(t, year: true);
                String set(LiftRecord r) => '${fmtNum(r.kg)} kg × ${r.reps}';
                final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    tileColor: cs.surfaceContainer,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    title: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: pr == null
                        ? Text(t('Oma arvio'), style: sub)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('🏆 Ennätys: {0} ({1}), arvio {2} kg', [
                                  set(pr),
                                  d(pr.date),
                                  fmtNum(pr.e1rm.roundToDouble()),
                                ]),
                                style: sub,
                              ),
                              if (sug != null)
                                Text(
                                  oldEnd == null
                                      ? t('Ehdotus: paras 6 kk:n ajalta {0} ({1})', [set(sug), d(sug.date)])
                                      : t(
                                          'Ehdotus: {0} ({1}). Liikettä ei ole tehty puoleen vuoteen: aloita kevyemmin',
                                          [set(sug), d(sug.date)],
                                        ),
                                  style: sub,
                                ),
                            ],
                          ),
                    isThreeLine: pr != null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${fmtNum(_maxes[l]!)} kg',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        IconButton(
                          tooltip: t('Poista'),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _maxes.remove(l)),
                        ),
                      ],
                    ),
                    onTap: () async {
                      final v = await askNumber(context, t('{0}: 1 toiston maksimi (kg)', [l]), _maxes[l] ?? 60);
                      if (v != null && v > 0) setState(() => _maxes[l] = v);
                    },
                  ),
                );
              },
            ),
          OutlinedButton.icon(onPressed: _addMax, icon: const Icon(Icons.add), label: Text(t('Lisää ennätys'))),
        ],
        hint: _maxes.isEmpty
            ? t(
                'Ennätyksiä ei löytynyt treenihistoriasta, eikä niitä tarvita. Ne vaikuttavat vain '
                'ensimmäisen kerran painoehdotuksiin: ilman niitä ehdotus tulee ensimmäisen kirjatun treenin jälkeen.',
              )
            : t(
                'Ensimmäisen kerran painoehdotukset lasketaan näistä. Historiasta löytyneet ovat parhaita arvioituja '
                'maksimeja viimeiseltä 6 kuukaudelta, koska vanha ennätys ei välttämättä kuvaa nykyistä kuntoa. '
                'Napauta muuttaaksesi.',
              ),
      ),
      _summary(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Ohjelma {0}/{1}', [_i + 1, _pages])),
        automaticallyImplyLeading: !widget.firstRun,
        actions: [
          TextButton(onPressed: _skip, child: Text(widget.firstRun ? t('Ohita – treenaan vapaasti') : t('Peruuta'))),
        ],
      ),
      body: Column(
        children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SamiBand(height: 4, pattern: false)),
          Expanded(
            child: PageView(controller: _page, onPageChanged: (i) => setState(() => _i = i), children: pages),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  if (_i > 0)
                    OutlinedButton(
                      onPressed: () =>
                          _page.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                      child: Text(t('Takaisin')),
                    ),
                  const Spacer(),
                  _i == _pages - 1
                      ? FilledButton(onPressed: _accept, child: Text(t('Aloita ohjelma')))
                      : FilledButton(onPressed: _next, child: Text(t('Seuraava'))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final p = _current();
    return ProgramView(program: p, header: t('Ohjelmasi'), injuries: _injuries, onChanged: () => setState(() {}));
  }
}
