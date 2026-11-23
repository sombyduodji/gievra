import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../program_edit.dart';
import '../progression.dart';
import '../injuries.dart';
import '../program.dart';
import '../exercises.dart';
import '../anim/cue_lang.dart';
import '../anim/figure.dart';
import '../anim/motions.dart';
import '../theme.dart';
import 'widgets.dart';
import '../l10n.dart';
import '../rest.dart';
import 'rest_banner.dart';
import 'plate_sheet.dart';
import 'hr_ui.dart' show HrLiveStrip;
import 'percent_sheet.dart';
import '../plates.dart';

/// Sarjojen kirjaus yhdelle liikkeelle.
class SetLoggerScreen extends StatefulWidget {
  final DateTime date;

  /// Saman päivän treenin numero: päivän aiemmat treenit ovat "edellinen kerta" (testikierros 16.11.).
  final int session;
  final ExerciseEntry entry;
  final Future<void> Function() onChanged;
  final Target? target;
  final String? note;

  /// Supersarja: ryhmän liikkeet järjestyksessä (otsikkoon) ja seuraava liike juuri kirjatun sarjan jälkeen
  /// (seuraava, kierros valmis). Kesken kierroksen ei palautusajastinta.
  final List<String>? superset;
  final (String?, bool) Function()? supersetNext;
  const SetLoggerScreen({
    super.key,
    required this.date,
    this.session = 1,
    required this.entry,
    required this.onChanged,
    this.target,
    this.note,
    this.superset,
    this.supersetNext,
  });

  /// Näin pian edellisen jälkeen tullut tallennusnapautus on vahinkotoisto (testit voivat lyhentää).
  @visibleForTesting
  static Duration repeatGuard = const Duration(milliseconds: 600);

  @override
  State<SetLoggerScreen> createState() => _SetLoggerScreenState();
}

class _SetLoggerScreenState extends State<SetLoggerScreen> {
  ExerciseEntry get e => widget.entry;
  late final _last = store.lastBefore(e.name, widget.date, widget.session);
  late final double _bestBefore = store.maxKgBefore(e.name, widget.date, session: widget.session);
  late final Suggestion? _sugg = widget.target != null
      ? suggestForTarget(e.name, widget.date, widget.target!, session: widget.session)
      : suggestNext(e.name, widget.date, session: widget.session);
  late final InjuryStatus _inj = injuryStatus(e.name, settings.injuries);

  /// Tämän liikkeen lihakset, jotka kuormittuivat jo tänään toisessa salitreenissä (käyttäjä 16.11.).
  late final Set<String> _sameDay = heavyMusclesOf(e.name)
      .intersection(musclesTrainedToday(store.workouts, widget.date, exceptSession: widget.session));
  late final double _bestE1rm = bestE1rmBefore(e.name, widget.date, widget.session);

  /// Painoa tai toistoja muutettu viimeisen tallennuksen jälkeen (sarja on vielä tallentamatta).
  bool _edited = false;

  /// Painoa muutettu itse viimeisen tallennuksen jälkeen: sarjatyypin vaihto ei silloin korvaa sitä esitäytöllä
  /// (yötesti 16.11.: 1 kg ja sitten Pudotus → 15 kg).
  bool _kgEdited = false;

  void _setKg(num v) => setState(() {
    _kg = v.toDouble();
    _edited = true;
    _kgEdited = true;
  });

  void _setReps(num v) => setState(() {
    _reps = v.toInt();
    _edited = true;
  });

  /// Liike valmis. Jos viimeinen sarja on vielä tallentamatta (tai sarjoja ei ole), ilmoitus ja takaisin
  /// kirjaukseen: sarja tallennetaan vastaamalla, jäikö varaa.
  Future<void> _markDone() async {
    if (rest.justClosed) return; // palkki sulkeutui juuri sormen alta
    if (_edited || e.sets.isEmpty) {
      // OK palaa kirjaukseen; "Merkitse silti" ei jätä umpikujaa (esim. vahingossa painettu + ja −).
      final anyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Viimeistä sarjaa ei ole tallennettu')),
          content: Text(t('Tallenna sarja ensin valitsemalla, jäikö varaa. Merkitse sitten liike valmiiksi.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Merkitse silti'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('OK'))),
          ],
        ),
      );
      if (anyway != true || !mounted) return;
    }
    // Liike valmis: tämän liikkeen palautusta ei enää tarvita (ei muistutusta sarjojen väliin).
    if (rest.running && rest.exercise == e.name) rest.stop();
    if (mounted) Navigator.pop(context, true);
  }

  /// Tietokortin lisätiedot (ehdotuksen peruste, koko edellinen kerta, jakso ja tauko).
  bool _infoOpen = false;

  /// Suunnitellut sarjat tehty (ulkoasun kohennus 16.11.): kirjauskortin tilalla "Kaikki sarjat tehty" ja
  /// Lisää sarja; alareunassa "✓ Liike valmis" (palaa listaan). Supersarjassa ei (vuorottelu jatkuu).
  bool get _allDone => widget.superset == null && widget.target != null && e.workSets.length >= widget.target!.sets;

  /// Lisäsarja auki (Lisää sarja painettu).
  bool _extra = false;
  double _kg = 20;
  int _reps = 8;

  /// Seuraavan sarjan tyyppi: null tavallinen, pudotus tai AMRAP.
  String? _kind;

  /// Supersarjassa seuraavaksi tehtävä liike ja tuleeko ensin palautus (kierros valmis).
  String? _next;
  bool _nextAfterRest = false;

  /// Aikasarjan ajastin (sekuntiliikkeet): jäljellä sekunteja, null = ei käynnissä.
  Timer? _cd;
  int? _cdLeft;
  int _cdTotal = 0;

  void _startCountdown() {
    _cd?.cancel();
    setState(() {
      _cdTotal = _reps;
      _cdLeft = _reps;
    });
    _cd = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = (_cdLeft ?? 1) - 1;
      if (left <= 0) {
        _cd?.cancel();
        HapticFeedback.heavyImpact();
        RestTimer.holdDone(e.name);
        setState(() {
          _cdLeft = null;
          _reps = _cdTotal;
          _edited = true; // ajastettu sarja odottaa tallennusta
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('Aika täynnä: {0} s. Tallenna sarja.', [_cdTotal]))));
        return;
      }
      if (left <= 3) {
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.selectionClick();
      }
      setState(() => _cdLeft = left);
    });
  }

  /// Lopetus kesken: tehty aika talteen.
  void _stopCountdown({bool keep = true}) {
    _cd?.cancel();
    setState(() {
      if (keep && _cdLeft != null) {
        _reps = (_cdTotal - _cdLeft!).clamp(1, 9999);
        _edited = true;
      }
      _cdLeft = null;
    });
  }

  @override
  void dispose() {
    _cd?.cancel();
    if (rest.nextFn == _restNext) {
      rest.nextText = _restNext();
      rest.nextFn = null;
    }
    super.dispose();
  }

  /// Palautuspalkin rivi: mitä tauon jälkeen tehdään (seuraava liike supersarjassa, lämmittely- tai työsarja).
  String? _restNext() {
    final line = _restNextLine();
    // Palautus on toisen liikkeen: kerrotaan, minkä liikkeen sarja on tulossa.
    return line != null && rest.exercise != e.name ? '${exerciseLabel(e.name)} · $line' : line;
  }

  String? _restNextLine() {
    if (_next != null && _nextAfterRest) return t('Seuraavaksi: {0}', [exerciseLabel(_next!)]);
    final set = fmtSet(e.name, SetEntry(_kg, _reps, kind: _kind));
    final done = e.sets.where((s) => !s.warmup).length;
    final target = widget.target;
    if (target != null && target.sets > 0) {
      if (done >= target.sets) return t('Tavoitteen sarjat tehty ✓');
      return t('Seuraava sarja {0}/{1}: {2}', [done + 1, target.sets, set]);
    }
    return t('Seuraava sarja: {0}', [set]);
  }

  /// Pudotussarja: edellisen sarjan paino −20 % valmiiksi. Pudotuksista takaisin tavalliseen tai AMRAP-sarjaan:
  /// viimeisimmän muun kuin pudotussarjan paino (ei pudotusten jälkeistä kevyttä painoa). Itse syötetty paino säilyy.
  void _setKind(String? k) => setState(() {
    final wasDrop = _kind == dropSet;
    _kind = k;
    final work = e.sets.where((s) => !s.warmup).toList();
    final prev = work.lastOrNull;
    if (_kgEdited) return;
    if (k == dropSet && prev != null && prev.kg > 0) {
      final step = stepFor(e.name);
      _kg = ((prev.kg * .8 / step).round() * step).clamp(0, prev.kg > step ? prev.kg - step : 0).toDouble();
    } else if (wasDrop && k != dropSet) {
      final main = work.lastWhere((s) => s.kind != dropSet, orElse: () => SetEntry(_kg, _reps));
      _kg = main.kg;
    }
  });

  /// Lämmittely on yksi painike (käyttäjä 17.11.: vanha esitäytetty lämmittelytila ja painovinkit pois): Tallenna lämmittelysarjana
  /// painoliikkeissä (tanko, käsipainot, kahvakuula, laitteet; ei pelkkä kehonpaino eikä aikaliike), kunnes
  /// ensimmäinen työsarja on tehty.
  bool get _manualWarmup =>
      e.workSets.isEmpty &&
      _m != Measure.seconds &&
      !(exerciseEquipment[e.name]?.every((q) => q == Equip.kehonpaino) ?? false);

  void _prefillWork() {
    if (_sugg != null) {
      _kg = _sugg.kg;
      _reps = _sugg.reps;
    }
  }

  @override
  void initState() {
    super.initState();
    final src = e.sets.isNotEmpty ? e.sets.last : _last?.$2.sets.last;
    if (src != null) {
      _kg = src.kg;
      _reps = src.reps;
    }
    if (e.sets.isEmpty && _sugg != null) {
      _kg = _sugg.kg;
      _reps = _sugg.reps;
    }
    if (src == null && _sugg == null && _m != Measure.reps) {
      _kg = 0;
      _reps = _m.initial;
    }
    // Vain kehonpainolla tehtävä liike (leuanveto, punnerrus) ensimmäistä kertaa: lisäpaino 0, ei tangon 20 kg
    // (yötesti 16.11.: leuanveto alkoi 20 kg:sta).
    if (src == null && _sugg == null && (exerciseEquipment[e.name]?.every((q) => q == Equip.kehonpaino) ?? false)) {
      _kg = 0;
    }
    // Hex bar ensimmäistä kertaa: tangon paino valmiina, jos se on asetettu (käyttäjä 18.11.: Farmer walk alkoi
    // 0 kg:sta, vaikka pelkkä tanko painaa 20–30 kg).
    if (src == null && _sugg == null && isHexBar(e.name)) _kg = barFor(e.name, hex: true) ?? 0;
    // Palattu lämmittelyn jälkeen: työpaino valmiina (ei viimeisimmän lämmittelysarjan painoa).
    if (e.workSets.isEmpty && e.sets.isNotEmpty) _prefillWork();
    // Toisen liikkeen palautus käynnissä: palkki näyttää tämän liikkeen ensimmäisen sarjan (tauon jälkeen tämä).
    if (rest.running && rest.exercise != e.name) rest.nextFn = _restNext;
  }

  Measure get _m => measureOf(e.name);

  /// Ohje (oikea yläkulma): liikkeen animaatio ja vinkit sekä mittaustapa samassa paneelissa.
  Future<void> _showHelp() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final cs = Theme.of(ctx).colorScheme;
        final sub = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
        final motion = exerciseMotions[e.name];
        final cues = cuesFor(e.name);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: motion != null || cues.isNotEmpty ? .75 : .35,
          maxChildSize: .95,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              if (motion != null || cues.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(t('Näin teet'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    // Joustava: suurella tekstillä (2,0) rivi ylitti reunan 26 px (yötesti 22.11.).
                    Flexible(
                      child: Text(t('Kokeellinen ohje'), style: sub, textAlign: TextAlign.end),
                    ),
                  ],
                ),
                if (motion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(child: FigureAnimation(motion: motion, size: 200)),
                  ),
                if (cues.isNotEmpty)
                  LangNotice(
                    healthTextLang == 'en'
                        ? t('Ei saatavilla saameksi: liikevinkit näkyvät englanniksi.')
                        : t('Ei saatavilla saameksi: liikevinkit näkyvät suomeksi.'),
                    show: isSami,
                  ),
                for (final c in cues)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: TextStyle(color: yellowText(ctx))),
                        Expanded(child: Text(c, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  t(
                    '⚠️ Kokeellinen: animaatio ja vinkit ovat suuntaa antavia eikä niitä ole vielä tarkistanut '
                    'ammattilainen. Varmista oikea tekniikka valmentajalta tai fysioterapeutilta ennen kuin '
                    'nostat raskaita painoja. Jos ohje näyttää oudolta, kerro siitä: Lisää → Ilmoita ongelmasta.',
                  ),
                  style: sub,
                ),
                const Divider(height: 28),
              ],
              Text(
                t('Miten {0} mitataan?', [exerciseLabel(e.name)]),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in Measure.values)
                    ChoiceChip(
                      label: Text(_cap(t(m.label))),
                      selected: m == _m,
                      onSelected: (_) async {
                        if (m == _m) return;
                        settings.setMeasure(e.name, m);
                        setState(() {});
                        setSheet(() {});
                        await widget.onChanged();
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  /// Yksi tietokortti: tavoite, ehdotus ja edellinen kerta. Napautus näyttää lisätiedot.
  Widget _infoCard(ColorScheme cs) {
    final target = widget.target;
    final sugg = settings.tips ? _sugg : null;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final strong = TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600);
    // Kahden käsipainon tai kuulan liikkeet: historia yhteispainona (käyttäjä 15.11.), syöttö painoa kohden.
    final mul = loadMultiplier(e.name);
    final total = mul == 2 ? ' ${t('yhteensä')}' : '';
    // Tuplakahvakuula: kuulien yhteispaino "48×8 yhteensä"; muut fmtSetsCompact-muodossa.
    final last = _last == null
        ? t('ei aiempaa')
        : mul == 1
        // Tiivis muoto kuten muualla, yksikkö kerran (käyttäjä 15.11., vaihtoehto B); kahden käsipainon liikkeissä
        // kummankin käden paino. Aika- ja matkaliikkeissä yksikkö sarjassa (ennen "0×60, 0×60" ilman yksikköä).
        ? '${shortDateY(_last.$1)} – ${fmtSetsUnit(e.name, _last.$2.sets, short: false)}'
        : '${shortDateY(_last.$1)} – ${_last.$2.sets.map((s) => '${fmtNum(s.kg * mul)}×${s.reps}').join(', ')}$total';
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _infoOpen = !_infoOpen),
        child: Container(
          decoration: sugg == null
              ? null
              : const BoxDecoration(
                  border: Border(left: BorderSide(color: Sami.green, width: 4)),
                ),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (target != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${t('Tavoite')}: ${target.text}${_m == Measure.reps ? '' : ' ${t(_m.unit)}'} · '
                        '${reserveTarget(_m, target.rir)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    // Väli laskuriin: pitkä tavoiteteksti ei osu siihen kiinni ("…varaa0/4", testikierros 16.11.).
                    const SizedBox(width: 8),
                    Text('${e.workSets.length}/${target.sets}', style: sub),
                  ],
                ),
              if (sugg != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        // Työsarjojen paino ja toistot (käyttäjä 17.11.: "Ehdotus" sekoittui lämmittelyyn ja maksimiin).
                        t('Työsarjat: {0}', [fmtSet(e.name, SetEntry(sugg.kg, sugg.reps))]) +
                            (mul == 2 && sugg.kg > 0 ? ' (${t('yhteensä {0} kg', [fmtNum(sugg.kg * mul)])})' : ''),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => setState(() {
                        _kg = sugg.kg;
                        _reps = sugg.reps;
                        _edited = true;
                      }),
                      child: Text(t('Käytä')),
                    ),
                  ],
                ),
              if (_infoOpen) ...[
                if (sugg != null) Text(sugg.reason, style: sub),
                if (target != null)
                  Text(
                    '${t('{0} · tehty {1}/{2}', [target.label, e.workSets.length, target.sets])} · '
                    '${t('tauko {0} min', [fmtNum(target.restSec / 60)])}',
                    style: sub,
                  ),
                const SizedBox(height: 4),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: t('Edellinen kerta: ')),
                          TextSpan(text: last, style: strong),
                          if (_bestBefore > 0) ...[
                            TextSpan(text: _infoOpen ? '\n${t('Paras: ')}' : ' · ${t('Paras: ')}'),
                            TextSpan(
                              text: mul == 2
                                  ? '${fmtNum(_bestBefore * mul)} kg$total'
                                  : '${fmtNum(shownKg(e.name, _bestBefore))} ${kgUnit(e.name)}',
                              style: strong,
                            ),
                          ],
                        ],
                      ),
                      maxLines: _infoOpen ? null : 1,
                      overflow: _infoOpen ? null : TextOverflow.ellipsis,
                      style: sub,
                    ),
                  ),
                  Icon(_infoOpen ? Icons.expand_less : Icons.expand_more, size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ennätys = raskaampi kuin mikään aiempi sarja tässä liikkeessä (myös tämän päivän aiemmat).
  void _recomputePr() {
    var best = _bestBefore;
    // Aika-, askel- ja matkaliikkeissä ilman lisäpainoa ennätys = pisin/eniten.
    final byValue = _m != Measure.reps && e.sets.every((s) => s.kg == 0);
    if (byValue) {
      var b = 0;
      for (final w in store.workouts.where((w) => w.date.isBefore(widget.date))) {
        for (final x in w.exercises.where((x) => x.name == e.name)) {
          for (final s in x.sets) {
            if (s.reps > b) b = s.reps;
          }
        }
      }
      var cur = b;
      for (final s in e.sets) {
        s.pr = b > 0 && s.reps > cur;
        if (s.reps > cur) cur = s.reps;
      }
      return;
    }
    for (final s in e.sets) {
      s.pr = !s.warmup && _bestBefore > 0 && s.kg > best;
      if (!s.warmup && s.kg > best) best = s.kg;
    }
  }

  DateTime? _lastSave;

  /// Yksi napautus tallentaa sarjan ja vastauksen "jäikö varaa" (null = ei merkitty).
  Future<void> _saveSet([int? rir, bool warmup = false]) async {
    _extra = false; // lisäsarjan kortti sulkeutuu tallennuksen jälkeen
    if (rest.justClosed) return; // palkki sulkeutui juuri sormen alta
    // Vahinkotuplanapautus (hikinen sormi, napautus kahteen kertaan) ei tallenna samaa sarjaa kahdesti.
    final now = DateTime.now();
    if (_lastSave != null && now.difference(_lastSave!).abs() < SetLoggerScreen.repeatGuard) return;
    _lastSave = now;
    setState(() {
      _edited = false;
      _kgEdited = false;
      if (warmup) {
        e.sets.add(SetEntry(_kg, _reps, warmup: true));
      } else {
        e.sets.add(SetEntry(_kg, _reps, rir: _kind == amrapSet ? 0 : rir, kind: _kind));
        // AMRAP on yksittäinen sarja; pudotus jatkuu, kunnes käyttäjä vaihtaa takaisin.
        if (_kind == amrapSet) _kind = null;
        if (_kind == dropSet && _kg > 0) {
          final step = stepFor(e.name);
          _kg = ((_kg * .8 / step).round() * step).clamp(0, _kg > step ? _kg - step : 0).toDouble();
        }
      }
      _recomputePr();
    });
    // TalkBack (20.11.): tallennus ei kertonut mitään; nyt "Sarja tallennettu: 5 kg × 6".
    final last = e.sets.last;
    SemanticsService.sendAnnouncement(
      View.of(context),
      t('Sarja tallennettu: {0}', ['${fmtNum(last.kg)} kg × ${last.reps}']),
      Directionality.of(context),
    );
    // Supersarja: kesken kierroksen suoraan seuraavaan liikkeeseen, palautus vasta kierroksen jälkeen.
    var restNow = true;
    if (widget.supersetNext != null && !e.sets.last.warmup) {
      final (next, roundDone) = widget.supersetNext!();
      restNow = roundDone;
      setState(() {
        _next = next == e.name ? null : next;
        _nextAfterRest = roundDone;
      });
      if (!roundDone && rest.running) rest.stop();
    }
    if (settings.restTimer && restNow) {
      final deload = widget.target == null && (settings.program?.isDeloadWeek(widget.date) ?? false);
      rest.start(
        restSeconds(
          e.name,
          e.sets.last,
          target: widget.target,
          deload: deload,
          best: _bestE1rm,
          work: _sugg?.kg ?? _last?.$2.workSets.lastOrNull?.kg,
        ),
        e.name,
      );
      rest.nextFn = _restNext;
    }
    await widget.onChanged();
    if (mounted && e.sets.last.pr) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('🏆 Uusi ennätys: {0}! Giitu, hienoa!', [fmtSet(e.name, e.sets.last)]))));
    }
  }

  /// Väärin kirjatun sarjan korjaus: napauta sarjaa listassa.
  Future<void> _editSet(int i) async {
    final r = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Sama numerointi kuin listassa: lämmittelysarjat eivät kasvata numeroa (17.11.: lista Sarja 1, ikkuna Sarja 3).
      builder: (_) => _EditSetSheet(
        name: e.name,
        index: i - e.sets.take(i).where((s) => s.warmup).length,
        set: e.sets[i],
        measure: _m,
      ),
    );
    if (r == null) return;
    if (r.delete) return _removeSet(i);
    setState(() {
      e.sets[i] = r.warmup
          ? SetEntry(r.kg, r.reps, warmup: true)
          : SetEntry(r.kg, r.reps, rir: r.rir, rpe: e.sets[i].rpe, kind: r.kind);
      _recomputePr();
    });
    await widget.onChanged();
  }

  Future<void> _removeSet(int i) async {
    setState(() {
      e.sets.removeAt(i);
      _recomputePr();
    });
    await widget.onChanged();
  }

  /// Aikasarjan ajastin: aloitus valitulla ajalla, käynnissä rengas ja lopetus.
  Widget _countdown(ColorScheme cs) {
    final left = _cdLeft;
    if (left == null) {
      return FilledButton.tonalIcon(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        onPressed: _startCountdown,
        icon: const Icon(Icons.timer_outlined),
        label: Text(t('Aloita ajastin ({0})', [fmtDurationSec(_reps)]), style: const TextStyle(fontSize: 15)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: _cdTotal == 0 ? 0 : left / _cdTotal,
                    strokeWidth: 9,
                    backgroundColor: cs.outlineVariant,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fmtDurationSec(left), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                    Text('/ ${fmtDurationSec(_cdTotal)}', style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => _stopCountdown(keep: false), child: Text(t('Peruuta'))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(onPressed: _stopCountdown, child: Text(t('Lopeta nyt ({0} s)', [_cdTotal - left]))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = stepFor(e.name); // kahden käsipainon yhteispaino: askel molempiin käsiin
    return Scaffold(
      // Palautusajastin kiinteänä alapalkkina: ei siirrä painikkeita sormen alta. Kun suunnitellut sarjat on tehty,
      // alimpana läpinäkyvä vihreä "✓ Liike valmis" (vain tämä liike; treeni jatkuu).
      bottomNavigationBar: _allDone
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RestBanner(),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('exerciseDone'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            foregroundColor: greenText(context),
                            side: BorderSide(color: greenText(context), width: 2),
                          ),
                          onPressed: _markDone,
                          icon: const Icon(Icons.check),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              t('{0} valmis', [exerciseLabel(e.name)]),
                              maxLines: 1,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t('palaa treenilistaan · treeni jatkuu'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : const RestBanner(),
      appBar: AppBar(
        title: BarTitle(ExName(e.name)),
        actions: [
          // Prosenttilaskuri painoliikkeissä (napautus valitsee painon).
          if (_m == Measure.reps)
            IconButton(
              tooltip: t('Prosenttia maksimista'),
              icon: const Icon(Icons.percent),
              onPressed: () => showPercentSheet(context, exercise: e.name, date: widget.date, onPick: (v) => _setKg(v)),
            ),
          IconButton(
            tooltip: t('Ohje ja mittaustapa'),
            icon: Icon(Icons.help_outline, color: yellowText(context)),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          // Sykevyö: syke ja alue myös sarjan aikana.
          const HrLiveStrip(),
          const SizedBox(height: 12),
          if (widget.superset case final g?)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: g.length > 2 ? t('Kiertoharjoittelu: ') : t('Supersarja: '),
                      style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                    ),
                    for (var i = 0; i < g.length; i++) ...[
                      if (i > 0) const TextSpan(text: ' → '),
                      TextSpan(
                        text: exerciseLabel(g[i]),
                        style: g[i] == e.name ? const TextStyle(fontWeight: FontWeight.w700) : null,
                      ),
                    ],
                    TextSpan(
                      text: '\n${t('Tauko vasta kierroksen jälkeen.')}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (_inj.flagged || widget.note != null || (_sameDay.isNotEmpty && e.workSets.isEmpty))
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_inj.avoid.isNotEmpty ? Sami.red : Sami.yellow).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                [
                  if (_inj.avoid.isNotEmpty)
                    '⚠️ ${t('Vammatila ({0}): tätä liikettä kannattaa välttää.', [_inj.avoid.map(t).join(', ')])}'
                        '${_inj.substitute != null ? ' ${t('Kokeile: {0}.', [exerciseLabel(_inj.substitute!)])}' : ''}',
                  if (widget.note != null) '🩹 ${trNote(widget.note!)}' else ..._inj.modify.map((m) => '🩹 ${t(m)}'),
                  if (settings.injuries.isNotEmpty)
                    t('Kipua enintään 3–5/10, ja sen pitää rauhoittua aamuun mennessä.'),
                  if (_sameDay.isNotEmpty && e.workSets.isEmpty)
                    '💡 ${t('Tänään toisessa treenissä kuormittui jo {0}. Jätä enemmän varaa.', [_sameDay.map(t).join(', ')])}',
                ].join('\n'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          // Vammatilan merkitsemä liike (esim. selkä ja maastaveto): vaihto tähän treeniin ennen ensimmäistä sarjaa (käyttäjä 16.11.).
          // Ohjelma ei muutu; valinta koskee vain tätä treeniä.
          if (_inj.flagged && e.workSets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_inj.substitute != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey('injurySwap'),
                      onPressed: () => Navigator.pop(context, ExerciseSwap(_inj.substitute)),
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(t('Vaihda: {0}', [exerciseLabel(_inj.substitute!)])),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('injuryPick'),
                    onPressed: () => Navigator.pop(context, const ExerciseSwap(null)),
                    icon: const Icon(Icons.list),
                    label: Text(t('Valitse muu liike')),
                  ),
                ],
              ),
            ),
          _infoCard(cs),
          const SizedBox(height: 12),
          // Kaikki suunnitellut sarjat tehty: yhteenveto ja Lisää sarja (avaa kirjauksen lisäsarjalle).
          if (_allDone && !_extra) ...[
            Container(
              key: const ValueKey('allSetsDone'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: greenText(context), width: 2),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_rounded, color: greenText(context), size: 32),
                  const SizedBox(height: 4),
                  Text(
                    t('Kaikki {0} sarjaa tehty', [e.workSets.length]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  if (e.sets.any((x) => x.pr))
                    Text('🏆 ${t('uusi ennätys')}', style: TextStyle(fontSize: 13, color: yellowText(context))),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              key: const ValueKey('addExtraSet'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => setState(() => _extra = true),
              icon: const Icon(Icons.add),
              label: Text(t('Lisää sarja ({0}.)', [e.workSets.length + 1]), style: const TextStyle(fontSize: 15)),
            ),
          ] else
            // Sarjan kirjaus omana korttinaan (käyttäjä 15.11., mockup A): paino, toistot, sarjatyyppi ja tallennus.
            // Merkitse liike valmiiksi on tehtyjen sarjojen jälkeen, kaukana tallennuspainikkeista (ei vahinkonapautusta).
            Container(
              key: const ValueKey('setCard'),
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: .6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      _extra
                          ? t('Sarja {0} · lisäsarja', [e.sets.where((s) => !s.warmup).length + 1])
                          : t('Sarja {0}', [e.sets.where((s) => !s.warmup).length + 1]),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _CompactStepper(
                          label:
                              weightTitle(e.name) ?? (_m == Measure.reps ? t('Paino') : t('Lisäpaino (0 = oma paino)')),
                          value: fmtNum(_kg),
                          unit: 'kg',
                          onMinus: () => _setKg((_kg - step).clamp(0, 1000)),
                          onPlus: () => _setKg((_kg + step).clamp(0, 1000)),
                          onTap: () async {
                            final v = await askNumber(context, t('Paino (kg)'), _kg, min: 0, max: 1000);
                            if (v != null && v >= 0 && v <= 1000) _setKg(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CompactStepper(
                          label: _cap(t(_m.label)) + (perSideExercises.contains(e.name) ? t(' (per puoli)') : ''),
                          value: '$_reps',
                          unit: _m == Measure.reps ? '' : _m.unit,
                          onMinus: () => _setReps((_reps - _m.step).clamp(1, 9999)),
                          onPlus: () => _setReps((_reps + _m.step).clamp(1, 9999)),
                          onTap: () async {
                            final v = await askNumber(
                              context,
                              t(_m.label),
                              _reps.toDouble(),
                              decimals: false,
                              min: 1,
                              max: 9999,
                            );
                            if (v != null && v >= 1 && v <= 9999) _setReps(v.round());
                          },
                        ),
                      ),
                    ],
                  ),
                  if (weightTotal(e.name, _kg) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        weightTotal(e.name, _kg)!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  if (isBarbell(e.name) && _kg > 0) PlateLine(kg: _kg, exercise: e.name, onPick: (v) => _setKg(v)),
                  // Hex bar: levylaskuri vain, kun tangon paino on asetettu; muuten linkki asetukseen.
                  if (isHexBar(e.name))
                    barFor(e.name, hex: true) != null
                        ? PlateLine(kg: _kg, hex: true, exercise: e.name, onPick: (v) => _setKg(v))
                        : Center(
                            child: TextButton.icon(
                              key: const ValueKey('hexBarSet'),
                              onPressed: () async {
                                await showPlateSheet(context, kg: _kg > 0 ? _kg : null, hex: true, exercise: e.name);
                                final b = barFor(e.name, hex: true);
                                if (mounted && b != null && _kg == 0) _setKg(b);
                                if (mounted) setState(() {});
                              },
                              icon: const Icon(Icons.fitness_center, size: 16),
                              label: Text(t('Aseta hex barin paino'), style: const TextStyle(fontSize: 13)),
                            ),
                          ),
                  const SizedBox(height: 14),
                  ...[
                    // Aikaliikkeet: ajastin laskee alas, lopussa ääni ja värinä.
                    if (_m == Measure.seconds) ...[_countdown(cs), const SizedBox(height: 14)],
                    if (_m == Measure.reps) ...[
                      SetKindPicker(value: _kind, onChanged: _setKind),
                      if (_kind != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _kind == dropSet
                                ? t('Pudotus: kevyempi paino heti edellisen sarjan perään, ilman taukoa.')
                                : t('AMRAP: niin monta toistoa kuin jaksat. Päivittää arvioidun maksimin.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                    if (_kind == amrapSet)
                      FilledButton(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                        onPressed: () => _saveSet(0),
                        child: Text(t('Tallenna AMRAP-sarja'), style: const TextStyle(fontSize: 15)),
                      )
                    else ...[
                      // Oma lämmittely (käyttäjä 17.11.: uudessa liikkeessä ei ole valmista lämmittelyä, ja kolme
                      // kevyttä sarjaa täytti tavoitteen): näkyy, kunnes liikkeen ensimmäinen työsarja on tehty.
                      if (_manualWarmup) ...[
                        OutlinedButton.icon(
                          key: const ValueKey('saveWarmupSet'),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: () => _saveSet(null, true),
                          icon: const Icon(Icons.local_fire_department_outlined, size: 20),
                          label: Text(t('Tallenna lämmittelysarjana')),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Tallennus = vastaus kysymykseen "jäikö varaa?". Yksi napautus, ei kirjoittamista.
                      Text(
                        t('Tallenna sarja – {0}{1}', [
                          reserveWords(_m).question[0].toLowerCase(),
                          reserveWords(_m).question.substring(1),
                        ]),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      // Samankorkuiset painikkeet myös, kun yksi teksti pienenee (IntrinsicHeight + stretch).
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (v, label) in reserveWords(_m).answers) ...[
                              if (v != 0) const SizedBox(width: 8),
                              Expanded(
                                // Suuri järjestelmän fontti: teksti pienenee yhdelle riville keskelle, painikkeet pysyvät
                                // samankorkuisina (ennen "Ii veaháge" rivittyi vasempaan reunaan ja painike kasvoi).
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                                  ),
                                  onPressed: () => _saveSet(v),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      label,
                                      // TalkBack (20.11.): "Tallenna sarja: Ei yhtään" (ennen pelkkä "Ei yhtään").
                                      semanticsLabel: t('Tallenna sarja: {0}', [label]),
                                      maxLines: 1,
                                      softWrap: false,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          if (_next != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: Sami.yellow,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(context, _next),
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                _nextAfterRest
                    ? t('Tauon jälkeen: {0}', [exerciseLabel(_next!)])
                    : t('Seuraavaksi: {0}', [exerciseLabel(_next!)]),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          if (e.sets.isNotEmpty) SectionLabel(t('Tehdyt sarjat · {0}', [e.sets.where((s) => !s.warmup).length])),
          for (var i = 0; i < e.sets.length; i++)
            Dismissible(
              key: ObjectKey(e.sets[i]),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.delete, color: cs.error),
              ),
              onDismissed: (_) => _removeSet(i),
              // Pyyhkäisy ei onnistu ruudunlukijalla: Poista-toiminto (TalkBack 20.11.).
              child: Semantics(
                customSemanticsActions: {CustomSemanticsAction(label: t('Poista')): () => _removeSet(i)},
                child: Material(
                  color: e.sets[i].pr ? Sami.yellow.withValues(alpha: .15) : cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => rest.justClosed
                        ? null
                        : _editSet(i), // palkki sulkeutui juuri sormen alta (Ohita-tuplanapautus)
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          // Kapea näyttö tai suuri fontti: otsikko vie enintään puolet, varaa-teksti ja sarja kapenevat
                          // (17.11.: Lämmittely + reilusti varaa + 42 kg × 2 edestakaisin vuoti yli).
                          Flexible(
                            child: Text(
                              e.sets[i].warmup
                                  ? t('Lämmittely')
                                  : t('Sarja {0}', [i + 1 - e.sets.take(i).where((s) => s.warmup).length]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (e.sets[i].rir != null)
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: Text(
                                        reserveWords(_m).short[e.sets[i].rir] ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                  ),
                                // Yksi rivi, tarvittaessa pienempänä (suurella fontilla ennen "20 / kg × / 8").
                                Flexible(
                                  flex: 2,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: Text(
                                      '${fmtSetHand(e.name, e.sets[i])}${e.sets[i].pr ? ' 🏆' : ''}',
                                      textAlign: TextAlign.end,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.edit, size: 16, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (e.sets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t('Napauta sarjaa korjataksesi, pyyhkäise vasemmalle poistaaksesi.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          // Ennen suunniteltujen sarjojen loppua: aina näkyvä Merkitse liike valmiiksi (lopetus 1–2 sarjan jälkeenkin).
          if (!_allDone) ...[
            const SizedBox(height: 14),
            // Ohuempi reunapainike listan lopussa: löytyy viimeisen sarjan jälkeen, mutta ei osu vahingossa.
            OutlinedButton.icon(
              key: const ValueKey('markDone'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                foregroundColor: greenText(context),
                side: BorderSide(color: greenText(context), width: 1.5),
              ),
              onPressed: _markDone,
              icon: const Icon(Icons.check),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(t('Merkitse liike valmiiksi'), maxLines: 1, style: const TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditResult {
  final double kg;
  final int reps;
  final int? rir;
  final String? kind;
  final bool delete, warmup;
  const _EditResult(this.kg, this.reps, this.rir, {this.kind, this.delete = false, this.warmup = false});
}

/// Sarjan muokkaus: paino, toistot/aika/matka ja "jäikö varaa" -vastaus, tai poisto.
class _EditSetSheet extends StatefulWidget {
  final String name;
  final int index;
  final SetEntry set;
  final Measure measure;
  const _EditSetSheet({required this.name, required this.index, required this.set, required this.measure});
  @override
  State<_EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<_EditSetSheet> {
  late double _kg = widget.set.kg;
  late int _reps = widget.set.reps;
  late int? _rir = widget.set.rir;
  late String? _kind = widget.set.kind;
  late bool _warmup = widget.set.warmup;
  Measure get _m => widget.measure;

  @override
  Widget build(BuildContext context) {
    final step = stepFor(widget.name);
    final rw = reserveWords(_m);
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.set.warmup ? t('Korjaa lämmittelysarja') : t('Korjaa sarja {0}', [widget.index + 1]),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SectionLabel(weightTitle(widget.name) ?? (_m == Measure.reps ? t('Paino') : t('Lisäpaino (0 = oma paino)'))),
          ValueStepper(
            label: weightTitle(widget.name) ?? (_m == Measure.reps ? t('Paino') : t('Lisäpaino (0 = oma paino)')),
            value: fmtNum(_kg),
            unit: 'kg',
            onMinus: () => setState(() => _kg = (_kg - step).clamp(0, 1000)),
            onPlus: () => setState(() => _kg = (_kg + step).clamp(0, 1000)),
            onTap: () async {
              final v = await askNumber(context, t('Paino (kg)'), _kg, min: 0, max: 1000);
              if (v != null && v >= 0 && v <= 1000 && mounted) setState(() => _kg = v);
            },
          ),
          if (weightTotal(widget.name, _kg) != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                weightTotal(widget.name, _kg)!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          if (isBarbell(widget.name) && _kg > 0) PlateLine(kg: _kg, onPick: (v) => setState(() => _kg = v)),
          SectionLabel(t(_m.label)[0].toUpperCase() + t(_m.label).substring(1)),
          ValueStepper(
            label: t(_m.label)[0].toUpperCase() + t(_m.label).substring(1),
            value: '$_reps',
            unit: _m.unit,
            onMinus: () => setState(() => _reps = (_reps - _m.step).clamp(1, 9999)),
            onPlus: () => setState(() => _reps = (_reps + _m.step).clamp(1, 9999)),
            onTap: () async {
              final v = await askNumber(context, t(_m.label), _reps.toDouble(), decimals: false, min: 1, max: 9999);
              if (v != null && v >= 1 && v <= 9999 && mounted) setState(() => _reps = v.round());
            },
          ),
          // Lämmittelysarja ei vaikuta ehdotuksiin eikä tavoitteeseen (käyttäjä 17.11.: jälkikäteen merkittävissä).
          SwitchListTile(
            key: const ValueKey('editWarmup'),
            contentPadding: EdgeInsets.zero,
            title: Text(t('Lämmittelysarja')),
            subtitle: Text(
              t('Ei lasketa työsarjoihin eikä ehdotuksiin.'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            value: _warmup,
            onChanged: (v) => setState(() => _warmup = v),
          ),
          if (_m == Measure.reps && !_warmup) ...[
            SectionLabel(t('Sarjan tyyppi')),
            SetKindPicker(value: _kind, onChanged: (k) => setState(() => _kind = k)),
          ],
          if (!_warmup) ...[
            SectionLabel(rw.question),
            SegmentedButton<int?>(
              showSelectedIcon: false,
              segments: [
                for (final (v, label) in rw.answers) ButtonSegment(value: v, label: _segLabel(label)),
                const ButtonSegment(value: null, label: Text('–')),
              ],
              selected: {_rir},
              onSelectionChanged: (v) => setState(() => _rir = v.first),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              // Kapea näyttö (360 dp) tai suuri teksti: Poista kapenee, ettei rivi vuoda yli (yötesti 16.11.).
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => Navigator.pop(context, const _EditResult(0, 0, null, delete: true)),
                    icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                    label: Text(
                      t('Poista'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => Navigator.pop(context),
                child: Text(t('Peruuta')),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => Navigator.pop(context, _EditResult(_kg, _reps, _rir, kind: _kind, warmup: _warmup)),
                child: Text(t('Tallenna')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Painokentän otsikko käsipaino- ja kahvakuulaliikkeissä (null = tavallinen otsikko).
String? weightTitle(String exercise) {
  if (pairedKettlebell.contains(exercise)) return t('Paino per kuula (2 kuulaa)');
  // Kahden käsipainon liikkeet yhteispainona (käyttäjä 15.11.: näin ne on aina ajateltu ja kirjattu FitNotesissa).
  // Hex bar: tangon ja levyjen paino (ei lisäpaino eikä kahden painon liike).
  if (exercise == 'Farmer walk hex barilla') return t('Paino (tanko ja levyt)');
  if (exercise == 'Farmer walk' || exercise == 'Renegade-soutu') return t('Paino yhteensä (2 painoa)');
  if (pairedDumbbell.contains(exercise)) return t('Paino yhteensä (2 käsipainoa)');
  if (kettlebellOnly(exercise)) return t('Paino per kuula');
  if (singleWeight.contains(exercise)) {
    final eq = exerciseEquipment[exercise] ?? const {};
    return eq.contains(Equip.kahvakuula) ? t('Paino (yksi käsipaino tai kuula)') : t('Paino per käsipaino');
  }
  return null;
}

/// Kahdella painolla kentän alle: kuulilla kokonaispaino, käsipainoilla (yhteispaino) yhden käden paino.
String? weightTotal(String exercise, double kg) => kg <= 0
    ? null
    : pairedKettlebell.contains(exercise)
    ? t('Molemmissa käsissä · yhteensä {0} kg', [fmtNum(kg * 2)])
    : totalDumbbells(exercise)
    ? t('{0} kg kummassakin kädessä', [fmtNum(kg / 2)])
    : null;

/// Ensimmäinen kirjain isoksi (mittaustavan nimi otsikkona).
/// Paino- tai toistosäädin puolen leveydellä: otsikko, arvo (napautus = kirjoita) ja −/+.
class _CompactStepper extends StatelessWidget {
  final String label, value, unit;
  final VoidCallback onMinus, onPlus, onTap;
  const _CompactStepper({
    required this.label,
    required this.value,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = MediaQuery.textScalerOf(context);
    // Nimi ruudunlukijalle ja pitkälle painallukselle (ennen TalkBack sanoi vain "Painike").
    Widget btn(IconData i, VoidCallback f, String tip) => SizedBox.square(
      dimension: 52, // isompi napautuskohde (ennen 48); 56 ei mahtunut 300 dp:n näytölle
      child: IconButton.filledTonal(
        onPressed: f,
        tooltip: tip,
        icon: Icon(i, size: 26),
        style: IconButton.styleFrom(
          backgroundColor: cs.surfaceContainerHigh,
          foregroundColor: yellowText(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          // Yksi rivi, tarvittaessa pienempänä: suurella fontilla "GEARDDUHEAMIT" katkesi sanan keskeltä ja
          // toistoruutu kasvoi painoruutua korkeammaksi.
          // Kiinteä rivikorkeus: pitkä otsikko pienenee, mutta ruudut pysyvät samankorkuisina ja luvut samalla
          // tasolla (suuri tekstikoko, 15.11.).
          SizedBox(
            height: ts.scale(11) * 1.45,
            // Otsikko luetaan arvon kanssa (alla), ei erikseen (TalkBack 20.11.: "Sarja 1 PAINO TOISTOT", sitten "5 kg").
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                semanticsLabel: '',
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontSize: 11, letterSpacing: .6, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          // TalkBack (20.11.): "Paino: 5 kg", "Toistot: 6" (ennen pelkkä "5 kg" ja "6").
          Semantics(
            label: '$label: $value${unit.isEmpty ? '' : ' ${t(unit)}'}',
            button: true,
            excludeSemantics: true,
            onTap: onTap,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: SizedBox(
                width: double.infinity,
                height: ts.scale(38) * 1.25 + 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: value,
                            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
                          ),
                          if (unit.isNotEmpty)
                            TextSpan(
                              text: ' ${t(unit)}',
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              btn(Icons.remove, onMinus, t('Vähennä: {0}', [label])),
              btn(Icons.add, onPlus, t('Lisää: {0}', [label])),
            ],
          ),
        ],
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Segmenttinapin teksti yhdelle riville: suuri tekstikoko tai pitkä käännös pienentää tekstiä, ei katkaise sanaa
/// kesken ("Dábála/š", "AMRA/P" järjestelmän fontilla 2,0).
Widget _segLabel(String s) => FittedBox(fit: BoxFit.scaleDown, child: Text(s, maxLines: 1, softWrap: false));

/// Sarjan tyyppi: tavallinen, pudotus tai AMRAP.
class SetKindPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const SetKindPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<String?>(
    showSelectedIcon: false,
    segments: [
      ButtonSegment(value: null, label: _segLabel(t('Tavallinen'))),
      ButtonSegment(value: dropSet, label: _segLabel(t('Pudotus'))),
      ButtonSegment(value: amrapSet, label: _segLabel('AMRAP')),
    ],
    selected: {value},
    onSelectionChanged: (v) => onChanged(v.first),
  );
}

/// Sarjanäkymän paluuarvo: liike vaihdetaan tässä treenissä [to]-liikkeeseen (null = valitse liikevalitsimesta).
class ExerciseSwap {
  final String? to;
  const ExerciseSwap(this.to);
}
