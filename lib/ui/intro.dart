import 'package:flutter/material.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../history_profile.dart';
import '../insights.dart';
import '../program.dart';
import '../theme.dart';
import 'import_export.dart';
import 'injury_screen.dart';
import 'maxes_editor.dart';
import 'move_select.dart';
import 'program_view.dart';
import 'program_template.dart';
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

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  bool get _pl => _goal == 'voimanosto';

  /// Voimanoston kilpaliikkeiden maksimit esitäytetään historiasta vain tankovoimanostossa.
  bool get _askMaxes => _pl && !_kbOnly;

  /// Kahvakuulaohjelman painotus; voimanostossa pelkillä kahvakuulilla oletuksena voima.
  String? get _kbFocusEff => _kbOnly ? (_kbFocus ?? (_pl ? 'voima' : null)) : null;

  /// Sivujen määrä (päivitetään build-metodissa): täysi kysely 8–9 sivua, pikaohjelma 3.
  int _pages = 9;

  /// Pikaohjelma: suositellut oletukset, kysytään vain vammat ja näytetään yhteenveto.
  bool _quick = false;

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
      _quick = false;
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

  void _startFull() {
    setState(() => _quick = false);
    _next();
  }

  /// Pikaohjelma: seuraava sivu on vammakysymys, sitten yhteenveto.
  ///
  /// Pikaohjelma ei saa huomauttaa omasta viikon sarjamäärästään (yötesti 18.–19.11.: oletus keskitaso 3 × 60 min
  /// jäi alle 10 viikkosarjan kuudelle lihasryhmälle). Uudelle käyttäjälle aloittelijan taso (6 viikkosarjaa
  /// lihasryhmää kohden, mahtuu 3 × 60 minuuttiin); jos tallennetuilla valinnoilla sarjat eivät silti mahdu,
  /// treeni pitenee 15 min kerrallaan (enintään 90 min) lyhimpään kestoon, jolla suositus täyttyy.
  void _startQuick() {
    setState(() {
      _quick = true;
      if ((settings.style?.experience ?? settings.program?.experience) == null && _profile == null) {
        _exp = 'aloittelija';
      }
      for (var m = _minutes; m <= 90; m += 15) {
        if (meetsWeeklyTargets(_build(minutes: m))) {
          _minutes = m;
          break;
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _page.animateToPage(1, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  /// Sivu, jolle Takaisin on menossa (null = ei siirtymää). Nopeat painallukset siirtymän aikana jatkavat tästä:
  /// previousPage laskisi kohteen näkyvästä sivusta, jolloin painallukset katosivat (3 × Takaisin = 1 sivu).
  int? _backTo;

  void _back() {
    final from = _backTo ?? _i;
    if (from <= 0) return;
    final to = from - 1;
    _backTo = to;
    _page.animateToPage(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOut).whenComplete(() {
      if (mounted && _backTo == to) setState(() => _backTo = null);
    });
  }

  void _next() {
    if (_i < _pages - 1) {
      _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Program _build({int? minutes}) => generateProgram(
    goal: _goal,
    experience: _exp,
    days: _days,
    minutes: minutes ?? _minutes,
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

  /// Pikaohjelma isona korttina (ensimmäisen sivun pääpolku).
  Widget _quickHero() => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Material(
      color: Sami.red,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('quickHero'),
        onTap: _startQuick,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Sami.yellow, size: 28),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      t('Pikaohjelma'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppText.headline - 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                t(
                  'Suositellut oletukset: kysytään vain vammat, sitten valmis ohjelma. Voit muokata sitä yhteenvedossa.',
                ),
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 14),
              Container(
                alignment: Alignment.center,
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Text(
                  t('Aloita pikaohjelma'),
                  style: TextStyle(color: Sami.redDark, fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

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
    final first = _q(
      t('Onko sinulla aiempia treenejä?'),
      [
        // Pikaohjelma pääpolkuna isona korttina; muut vaihtoehdot pienempinä sen alla.
        _quickHero(),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8, left: 4),
          child: Text(
            t('TAI TARKEMMIN'),
            style: TextStyle(fontSize: 12, letterSpacing: .5, color: cs.onSurfaceVariant),
          ),
        ),
        _choice(
          t('Aloitan alusta'),
          t('Vastaan kysymyksiin itse'),
          _profile == null && !_quick && _i > 0,
          _startFull,
          icon: '🌱',
        ),
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
    );
    final injuries = _q(t('Onko sinulla vammoja tai kipuja?'), [
      _choice(t('Ei vammoja'), null, _injuries.isEmpty, () => _injuries = [], icon: '✅'),
      _choice(
        _injuries.isEmpty ? t('Valitse alueet') : t('Valittu: {0}', [_injuries.length]),
        t('Esim. olkapää, alaselkä, polvi, ranne'),
        _injuries.isNotEmpty,
        () async {
          final r = await Navigator.of(context)
              .push<List<String>>(MaterialPageRoute(builder: (_) => InjuryScreen(initial: _injuries, picker: true)));
          if (r != null && mounted) setState(() => _injuries = r);
        },
        icon: '🩹',
      ),
    ], hint: t('Ohjelma välttää ja muokkaa liikkeitä, jotka yleensä pahentavat vaivaa. Ei korvaa fysioterapeuttia.'));
    final pages = <Widget>[
      first,
      if (!_quick) ...[
        _q(
          t('Mikä on tavoitteesi?'),
          [
            _from('goal'),
            _choice(
              t('Voimanosto'),
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
          ],
          hint: t('Ohjelma lasketaan tutkimusten ja valmentajien suositusten pohjalta. Voit vaihtaa sen milloin vain.'),
        ),
        // Turvallisuuskysymys heti tavoitteen jälkeen (käyttäjän päätös 14.11).
        injuries,
        _q(t('Kauanko olet treenannut salilla?'), [
          _from('experience'),
          for (final e in experiences.entries)
            _choice(
              t(e.value),
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
            _choice(
              t('Kaikki käy'),
              t('Sali, jossa on kaikkea'),
              fitsAll(_equipment),
              () => _equipment = {},
              icon: '✅',
            ),
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
              t(
                'Valitse yksi tai useampi. Ohjelma suosii niitä ja käyttää muita vain, jos sopivaa liikettä ei löydy.',
              ) +
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
        // Ennätykset vain voimanostotavoitteelle (kilpaliikkeiden maksimit).
        if (_askMaxes)
          _q(
            t('Ennätykset (valinnainen)'),
            [MaxesEditor(maxes: _maxes, onChanged: () => setState(() {}))],
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
      ] else
        injuries,
      _summary(),
    ];
    _pages = pages.length;
    // Takaisin (järjestelmän painike ja yläpalkin nuoli) palaa edelliselle sivulle: ennen se poistui koko kyselystä
    // ja vastaukset katosivat hiljaa. Ensimmäiseltä sivulta poistutaan kuten ennen.
    return PopScope(
      canPop: _i == 0 && _backTo == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: _scaffold(pages),
    );
  }

  Widget _scaffold(List<Widget> pages) {
    return Scaffold(
      appBar: AppBar(
        title: BarTitle(Text(t('Ohjelma {0}/{1}', [_i + 1, _pages]))),
        automaticallyImplyLeading: !widget.firstRun,
        actions: [
          // Suurella tekstillä lyhyt "Ohita": pitkä teksti kutisti otsikon "Ohjelma 1/8" lähes näkymättömäksi.
          TextButton(
            key: const ValueKey('introSkip'),
            onPressed: _skip,
            child: Text(
              !widget.firstRun
                  ? t('Peruuta')
                  : MediaQuery.textScalerOf(context).scale(14) > 16
                  ? t('Ohita')
                  : t('Ohita – treenaan vapaasti'),
            ),
          ),
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
              // Suurella tekstillä ja pitkillä käännöksillä painikkeet kapenevat ja rivittyvät (ei ylivuotoa).
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_i > 0)
                    Flexible(
                      // Yksisanainen nimi pienenee eikä katkea kesken sanan (yötesti 19.11., Nothing saame + Stuoris: "Ruovttolu / otta").
                      child: OutlinedButton(
                        onPressed: _back,
                        child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Takaisin'))),
                      ),
                    ),
                  const SizedBox(width: 12),
                  // Ensimmäisellä sivulla ei Seuraava-painiketta: jokainen valinta vie eteenpäin (ennen se teki saman
                  // kuin "Aloitan alusta").
                  if (_i == _pages - 1)
                    Flexible(
                      flex: 2,
                      child: FilledButton(onPressed: _accept, child: Text(t('Aloita ohjelma'))),
                    )
                  else if (_i > 0)
                    Flexible(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _next,
                        child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Seuraava'))),
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

  Widget _summary() {
    final p = _current();
    return ProgramView(program: p, header: t('Ohjelmasi'), injuries: _injuries, onChanged: () => setState(() {}));
  }
}
