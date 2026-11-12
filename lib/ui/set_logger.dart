import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
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
import 'percent_sheet.dart';
import '../plates.dart';

/// Sarjojen kirjaus yhdelle liikkeelle.
class SetLoggerScreen extends StatefulWidget {
  final DateTime date;
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
    required this.entry,
    required this.onChanged,
    this.target,
    this.note,
    this.superset,
    this.supersetNext,
  });
  @override
  State<SetLoggerScreen> createState() => _SetLoggerScreenState();
}

class _SetLoggerScreenState extends State<SetLoggerScreen> {
  ExerciseEntry get e => widget.entry;
  late final _last = store.lastBefore(e.name, widget.date);
  late final double _bestBefore = store.maxKgBefore(e.name, widget.date);
  late final Suggestion? _sugg = widget.target != null
      ? suggestForTarget(e.name, widget.date, widget.target!)
      : suggestNext(e.name, widget.date);
  late final InjuryStatus _inj = injuryStatus(e.name, settings.injuries);
  late final double _bestE1rm = bestE1rmBefore(e.name, widget.date);
  bool _showSugg = true;
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
      if (keep && _cdLeft != null) _reps = (_cdTotal - _cdLeft!).clamp(1, 9999);
      _cdLeft = null;
    });
  }

  @override
  void dispose() {
    _cd?.cancel();
    super.dispose();
  }

  /// Pudotussarja: edellisen sarjan paino −20 % valmiiksi.
  void _setKind(String? k) => setState(() {
    _kind = k;
    final prev = e.sets.where((s) => !s.warmup).lastOrNull;
    if (k == dropSet && prev != null && prev.kg > 0) {
      final step = settings.weightStep;
      _kg = ((prev.kg * .8 / step).round() * step).clamp(0, prev.kg - step).toDouble();
    }
  });

  /// Esitäytetyt lämmittelysarjat (vain kun liikkeessä ei ole vielä sarjoja tänään).
  List<SetEntry> _warm = const [];
  int _warmIdx = 0;
  bool get _warming => _warmIdx < _warm.length;

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
    // Lämmittely kohti työpainoa (ehdotus tai edellinen kerta).
    final work = _sugg?.kg ?? _last?.$2.workSets.lastOrNull?.kg;
    if (e.sets.isEmpty && work != null) {
      _warm = warmupSets(e.name, work);
      if (_warm.isNotEmpty) {
        _kg = _warm.first.kg;
        _reps = _warm.first.reps;
      }
    }
  }

  Measure get _m => measureOf(e.name);

  Future<void> _chooseMeasure() async {
    final m = await showDialog<Measure>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t('Miten {0} mitataan?', [exerciseLabel(e.name)])),
        children: [
          for (final m in Measure.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text('${m == _m ? '● ' : ''}${_cap(t(m.label))}'),
            ),
        ],
      ),
    );
    if (m != null) {
      settings.setMeasure(e.name, m);
      setState(() {});
      await widget.onChanged();
    }
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

  /// Yksi napautus tallentaa sarjan ja vastauksen "jäikö varaa" (null = ei merkitty).
  Future<void> _saveSet([int? rir]) async {
    setState(() {
      if (_warming) {
        e.sets.add(SetEntry(_kg, _reps, warmup: true));
        _warmIdx++;
        if (_warming) {
          _kg = _warm[_warmIdx].kg;
          _reps = _warm[_warmIdx].reps;
        } else {
          _prefillWork();
        }
      } else {
        e.sets.add(SetEntry(_kg, _reps, rir: _kind == amrapSet ? 0 : rir, kind: _kind));
        // AMRAP on yksittäinen sarja; pudotus jatkuu, kunnes käyttäjä vaihtaa takaisin.
        if (_kind == amrapSet) _kind = null;
        if (_kind == dropSet && _kg > 0) {
          final step = settings.weightStep;
          _kg = ((_kg * .8 / step).round() * step).clamp(0, _kg - step).toDouble();
        }
      }
      _recomputePr();
    });
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
      builder: (_) => _EditSetSheet(name: e.name, index: i, set: e.sets[i], measure: _m),
    );
    if (r == null) return;
    if (r.delete) return _removeSet(i);
    setState(() {
      e.sets[i] = SetEntry(r.kg, r.reps, rir: r.rir, rpe: e.sets[i].rpe, warmup: e.sets[i].warmup, kind: r.kind);
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
    final step = settings.weightStep;
    return Scaffold(
      // Palautusajastin kiinteänä alapalkkina: ei siirrä painikkeita sormen alta.
      bottomNavigationBar: const RestBanner(),
      appBar: AppBar(
        title: ExName(e.name),
        actions: [
          // Prosenttilaskuri painoliikkeissä (napautus valitsee painon).
          if (_m == Measure.reps)
            IconButton(
              tooltip: t('Prosenttia maksimista'),
              icon: const Icon(Icons.percent),
              onPressed: () => showPercentSheet(
                context,
                exercise: e.name,
                date: widget.date,
                onPick: (v) => setState(() => _kg = v),
              ),
            ),
          TextButton.icon(
            onPressed: _chooseMeasure,
            icon: const Icon(Icons.straighten, size: 18),
            label: Text(t(_m.label)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          const SizedBox(height: 12),
          if (exerciseMotions[e.name] != null || cuesFor(e.name).isNotEmpty)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ExpansionTile(
                shape: const Border(),
                initiallyExpanded: _last == null,
                leading: const Icon(Icons.play_circle_outline),
                title: Text(t('Näin teet')),
                subtitle: Text(
                  t('Kokeellinen ohje'),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (exerciseMotions[e.name] != null)
                    Center(child: FigureAnimation(motion: exerciseMotions[e.name]!, size: 200)),
                  if (cuesFor(e.name).isNotEmpty)
                    LangNotice(
                      healthTextLang == 'en'
                          ? t('Ei saatavilla saameksi: liikevinkit näkyvät englanniksi.')
                          : t('Ei saatavilla saameksi: liikevinkit näkyvät suomeksi.'),
                      show: isSami,
                    ),
                  for (final c in cuesFor(e.name))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ', style: TextStyle(color: yellowText(context))),
                          Expanded(child: Text(c, style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    t(
                      '⚠️ Kokeellinen: animaatio ja vinkit ovat suuntaa antavia eikä niitä ole vielä tarkistanut '
                      'ammattilainen. Varmista oikea tekniikka valmentajalta tai fysioterapeutilta ennen kuin '
                      'nostat raskaita painoja. Jos ohje näyttää oudolta, kerro siitä: ☰ → Ilmoita ongelmasta.',
                    ),
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
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
          if (widget.target != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Sami.blue.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t('Tavoite')}: ${widget.target!.sets} × ${widget.target!.reps}${_m == Measure.reps ? '' : ' ${t(_m.unit)}'} · '
                    '${reserveTarget(_m, widget.target!.rir)} · ${t('tauko {0} min', [fmtNum(widget.target!.restSec / 60)])}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    t('{0} · tehty {1}/{2}', [widget.target!.label, e.workSets.length, widget.target!.sets]),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          if (_inj.flagged || widget.note != null)
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
                ].join('\n'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: t('Edellinen kerta: ')),
                  TextSpan(
                    text: _last == null
                        ? t('ei aiempaa')
                        : '${shortDate(_last.$1)} – ${_last.$2.sets.map((s) => '${fmtNum(s.kg)}×${s.reps}').join(', ')}',
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
                  ),
                  if (_bestBefore > 0) ...[
                    TextSpan(text: '\n${t('Paras: ')}'),
                    TextSpan(
                      text: '${fmtNum(_bestBefore)} kg',
                      style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          if (_sugg != null && _showSugg && settings.tips)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
              decoration: BoxDecoration(
                color: Sami.green.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
                border: const Border(left: BorderSide(color: Sami.green, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Ehdotus: {0}', [fmtSet(e.name, SetEntry(_sugg.kg, _sugg.reps))]),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(_sugg.reason, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => setState(() => _showSugg = false), child: Text(t('Ohita'))),
                      TextButton(
                        onPressed: () => setState(() {
                          _kg = _sugg.kg;
                          _reps = _sugg.reps;
                        }),
                        child: Text(t('Käytä')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          SectionLabel(weightTitle(e.name) ?? (_m == Measure.reps ? t('Paino') : t('Lisäpaino (0 = oma paino)'))),
          ValueStepper(
            value: fmtNum(_kg),
            unit: 'kg',
            onMinus: () => setState(() => _kg = (_kg - step).clamp(0, 1000)),
            onPlus: () => setState(() => _kg = (_kg + step).clamp(0, 1000)),
            onTap: () async {
              final v = await askNumber(context, t('Paino (kg)'), _kg);
              if (v != null && v >= 0 && v <= 1000) setState(() => _kg = v);
            },
          ),
          if (weightTotal(e.name, _kg) != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                weightTotal(e.name, _kg)!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          if (isBarbell(e.name) && _kg > 0) PlateLine(kg: _kg, onPick: (v) => setState(() => _kg = v)),
          SectionLabel(
            t(_m.label)[0].toUpperCase() +
                t(_m.label).substring(1) +
                (perSideExercises.contains(e.name) ? t(' (per puoli)') : ''),
          ),
          ValueStepper(
            value: '$_reps',
            unit: _m.unit,
            onMinus: () => setState(() => _reps = (_reps - _m.step).clamp(1, 9999)),
            onPlus: () => setState(() => _reps = (_reps + _m.step).clamp(1, 9999)),
            onTap: () async {
              final v = await askNumber(context, t(_m.label), _reps.toDouble(), decimals: false);
              if (v != null && v >= 1 && v <= 9999) setState(() => _reps = v.round());
            },
          ),
          const SizedBox(height: 18),
          if (_warming) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Sami.yellow.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Lämmittely {0}/{1}', [_warmIdx + 1, _warm.length]),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      for (var i = 0; i < _warm.length; i++)
                        '${i == _warmIdx ? '▶ ' : ''}${fmtNum(_warm[i].kg)}×${_warm[i].reps}',
                      if (_sugg != null) '${t('työsarjat')} ${fmtNum(_sugg.kg)}×${_sugg.reps}',
                    ].join('  →  '),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('Esitäytetty: muuta painoa tai toistoja vapaasti. Lämmittelysarjat eivät vaikuta ehdotuksiin.'),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              onPressed: () => _saveSet(),
              child: Text(t('Tallenna lämmittelysarja'), style: const TextStyle(fontSize: 15)),
            ),
            TextButton(
              onPressed: () => setState(() {
                _warmIdx = _warm.length;
                _prefillWork();
              }),
              child: Text(t('Ohita lämmittely')),
            ),
          ] else ...[
            if (_next != null) ...[
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
              const SizedBox(height: 14),
            ],
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
              Row(
                children: [
                  for (final (v, label) in reserveWords(_m).answers) ...[
                    if (v != 0) const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                        onPressed: () => _saveSet(v),
                        child: Text(label, style: const TextStyle(fontSize: 15)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            // Yhtä leveä kuin vastausnapit: tallennus ilman vastausta on oma selkeä painike. AMRAP-sarjassa ei:
            // siinä ei kysytä varaa (tallentuu aina "ei yhtään"), joten kaksi painiketta tekisi saman.
            if (_kind != amrapSet) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: cs.primary),
                ),
                onPressed: () => _saveSet(),
                child: Text(t('Tallenna vastaamatta'), style: const TextStyle(fontSize: 15)),
              ),
            ],
            const SizedBox(height: 8),
            // Erotinviiva: sarjan tallennus yllä, liikkeen lopetus alla.
            const Divider(height: 24),
            // Yhtä iso kuin yllä oleva painike, vihreä (tehty).
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Sami.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                // Liike valmis: tämän liikkeen palautusta ei enää tarvita (ei muistutusta sarjojen väliin).
                if (rest.running && rest.exercise == e.name) rest.stop();
                Navigator.pop(context, true);
              },
              icon: const Icon(Icons.check),
              label: Text(t('Merkitse liike valmiiksi'), style: const TextStyle(fontSize: 15)),
            ),
          ],
          const SizedBox(height: 12),
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
              child: Material(
                color: e.sets[i].pr ? Sami.yellow.withValues(alpha: .15) : cs.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _editSet(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          e.sets[i].warmup
                              ? t('Lämmittely')
                              : t('Sarja {0}', [i + 1 - e.sets.take(i).where((s) => s.warmup).length]),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const Spacer(),
                        if (e.sets[i].rir != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text(
                              reserveWords(_m).short[e.sets[i].rir] ?? '',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                        // Joustava: pudotus- ja AMRAP-merkinnät ja pitkät käännökset eivät vie riviä yli.
                        Flexible(
                          child: Text(
                            '${fmtSet(e.name, e.sets[i])}${e.sets[i].pr ? ' 🏆' : ''}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
          if (e.sets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t('Napauta sarjaa korjataksesi, pyyhkäise vasemmalle poistaaksesi.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
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
  final bool delete;
  const _EditResult(this.kg, this.reps, this.rir, {this.kind, this.delete = false});
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
  Measure get _m => widget.measure;

  @override
  Widget build(BuildContext context) {
    final step = settings.weightStep;
    final rw = reserveWords(_m);
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Korjaa sarja {0}', [widget.index + 1]),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SectionLabel(weightTitle(widget.name) ?? (_m == Measure.reps ? t('Paino') : t('Lisäpaino (0 = oma paino)'))),
          ValueStepper(
            value: fmtNum(_kg),
            unit: 'kg',
            onMinus: () => setState(() => _kg = (_kg - step).clamp(0, 1000)),
            onPlus: () => setState(() => _kg = (_kg + step).clamp(0, 1000)),
            onTap: () async {
              final v = await askNumber(context, t('Paino (kg)'), _kg);
              if (v != null && v >= 0 && v <= 1000) setState(() => _kg = v);
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
            value: '$_reps',
            unit: _m.unit,
            onMinus: () => setState(() => _reps = (_reps - _m.step).clamp(1, 9999)),
            onPlus: () => setState(() => _reps = (_reps + _m.step).clamp(1, 9999)),
            onTap: () async {
              final v = await askNumber(context, t(_m.label), _reps.toDouble(), decimals: false);
              if (v != null && v >= 1 && v <= 9999) setState(() => _reps = v.round());
            },
          ),
          if (_m == Measure.reps && !widget.set.warmup) ...[
            SectionLabel(t('Sarjan tyyppi')),
            SetKindPicker(value: _kind, onChanged: (k) => setState(() => _kind = k)),
          ],
          SectionLabel(rw.question),
          SegmentedButton<int?>(
            showSelectedIcon: false,
            segments: [
              for (final (v, label) in rw.answers) ButtonSegment(value: v, label: Text(label)),
              const ButtonSegment(value: null, label: Text('–')),
            ],
            selected: {_rir},
            onSelectionChanged: (v) => setState(() => _rir = v.first),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context, const _EditResult(0, 0, null, delete: true)),
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                label: Text(t('Poista'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Peruuta'))),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _EditResult(_kg, _reps, _rir, kind: _kind)),
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
  if (exercise == 'Farmer walk' || exercise == 'Renegade-soutu') return t('Paino per käsi (2 painoa)');
  if (pairedDumbbell.contains(exercise)) return t('Paino per käsipaino (2 käsipainoa)');
  if (kettlebellOnly(exercise)) return t('Paino per kuula');
  if (singleWeight.contains(exercise)) {
    final eq = exerciseEquipment[exercise] ?? const {};
    return eq.contains(Equip.kahvakuula) ? t('Paino (yksi käsipaino tai kuula)') : t('Paino per käsipaino');
  }
  return null;
}

/// Kahdella painolla: kokonaispaino näkyviin kentän alle.
String? weightTotal(String exercise, double kg) =>
    kg > 0 && (pairedKettlebell.contains(exercise) || pairedDumbbell.contains(exercise))
    ? t('Molemmissa käsissä · yhteensä {0} kg', [fmtNum(kg * 2)])
    : null;

/// Ensimmäinen kirjain isoksi (mittaustavan nimi otsikkona).
String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Sarjan tyyppi: tavallinen, pudotus tai AMRAP.
class SetKindPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const SetKindPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<String?>(
    showSelectedIcon: false,
    segments: [
      ButtonSegment(value: null, label: Text(t('Tavallinen'))),
      ButtonSegment(value: dropSet, label: Text(t('Pudotus'))),
      const ButtonSegment(value: amrapSet, label: Text('AMRAP')),
    ],
    selected: {value},
    onSelectionChanged: (v) => onChanged(v.first),
  );
}
