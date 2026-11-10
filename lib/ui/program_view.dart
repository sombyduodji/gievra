import 'package:flutter/material.dart';

import '../exercises.dart';
import '../program.dart';
import '../models.dart' show fmtDec;
import '../program_check.dart';
import '../program_edit.dart';
import '../theme.dart';
import 'picker.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Ohjelman näkymä (yhteenveto ja ohjelmanäkymä). Jos [onChanged] on annettu, liikkeitä voi vaihtaa,
/// lisätä ja poistaa sekä muuttaa sarjoja ja toistoalueita. Jokainen muutos arvioidaan.
class ProgramView extends StatelessWidget {
  final Program program;
  final String header;
  final List<Widget> footer;
  final List<String> injuries;
  final VoidCallback? onChanged;
  final Map<String, double>? done; // tällä viikolla tehdyt sarjat (nykyinen ohjelma): viikon kuormaan Tämä viikko
  const ProgramView({
    super.key,
    required this.program,
    required this.header,
    this.footer = const [],
    this.injuries = const [],
    this.onChanged,
    this.done,
  });

  bool get _editable => onChanged != null;

  Future<void> _editItem(BuildContext context, PlanDay d, PlanItem it) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemSheet(program: program, day: d, item: it, injuries: injuries),
    );
    if (changed == true) onChanged!();
  }

  Future<void> _addItem(BuildContext context, PlanDay d) async {
    final name = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (name == null) return;
    final slot = slotOf(name);
    final compound = slots[slot]?.compound ?? false;
    final m = measureOf(name);
    final (lo, hi) = switch (m) {
      Measure.seconds => (20, 40),
      Measure.steps => (10, 20),
      Measure.trips => (1, 2),
      Measure.meters => (20, 40),
      Measure.reps => repRangeOverride[name] ?? (compound ? (6, 10) : (10, 15)),
    };
    final it = PlanItem(name, slot, 3, lo, hi, compound ? '1–3' : '0–2', compound ? 150 : 90);
    // Monivelliikkeet ennen eristäviä (ACSM 2009).
    final at = compound ? d.items.indexWhere((i) => !i.compound && i.kind == null) : -1;
    at < 0 ? d.items.add(it) : d.items.insert(at, it);
    onChanged!();
    if (context.mounted) await _editItem(context, d, it);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final issues = validateProgram(program, injuries: injuries);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(header, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Text(program.displayTitle, style: sub),
        const SizedBox(height: 10),
        for (final n in program.notes.map(tr))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(n, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        const SizedBox(height: 6),
        _CheckCard(issues: issues),
        const SizedBox(height: 10),
        WeeklyLoadCard(program: program, done: done),
        if (_editable)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(t('Napauta liikettä vaihtaaksesi sen tai muuttaaksesi sarjoja ja toistoja.'), style: sub),
          ),
        for (final d in program.plan)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.uiName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              if (d.label != null) Text(d.name, style: sub),
                            ],
                          ),
                        ),
                        if (_editable)
                          IconButton(
                            tooltip: t('Nimeä päivä'),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.drive_file_rename_outline, size: 18, color: cs.onSurfaceVariant),
                            onPressed: () async {
                              final v = await askDayLabel(context, d);
                              if (v == null) return;
                              d.label = v.isEmpty ? null : v;
                              onChanged!();
                            },
                          ),
                        Text(t('~{0} min', [estimateMinutes(d.items).round()]), style: sub),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final i in d.items)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _editable ? () => _editItem(context, d, i) : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: ExName(i.exercise)),
                                  Text(switch (i.kind) {
                                    'H' => t('raskas, viikon mukaan'),
                                    'V' => t('volyymi, viikon mukaan'),
                                    _ =>
                                      '${i.sets} × ${i.lo == i.hi ? i.lo : '${i.lo}–${i.hi}'}'
                                          '${measureOf(i.exercise) == Measure.reps ? '' : ' ${t(measureOf(i.exercise).unit)}'}',
                                  }, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (_editable) ...[
                                    const SizedBox(width: 6),
                                    Icon(Icons.edit, size: 15, color: cs.onSurfaceVariant),
                                  ],
                                ],
                              ),
                              if (i.note != null) Text('🩹 ${trNote(i.note!)}', style: sub),
                            ],
                          ),
                        ),
                      ),
                    if (_editable)
                      TextButton.icon(
                        onPressed: () => _addItem(context, d),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(t('Lisää liike')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          t(
            '"Varaa" = montako toistoa jäi vielä varastoon. Raskaat pääliikkeet: tauko 2–4 min, '
            'lisäliikkeet 1–2 min.',
          ),
          style: sub,
        ),
        ...footer,
      ],
    );
  }
}

/// Ohjelman tarkistuksen tulos: tasapaino, liikemallit, volyymi, järjestys.
class _CheckCard extends StatelessWidget {
  final List<String> issues;
  const _CheckCard({required this.issues});
  @override
  Widget build(BuildContext context) {
    final ok = issues.isEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? Sami.green : Sami.yellow).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: ok ? Sami.green : Sami.yellow, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ok ? t('✓ Ohjelma on tasapainoinen') : t('⚠ Huomioita ohjelmasta'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          if (ok)
            Text(
              t(
                'Työntö ja veto tasapainossa, kaikki päämallit mukana ja järjestys kunnossa. Määrä: ks. viikon kuorma.',
              ),
              style: TextStyle(fontSize: 12),
            )
          else
            for (final i in issues) Text('• $i', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Viikon sarjat lihasryhmää kohden ja suositus. [done] = tällä viikolla jo tehdyt: silloin jokaisella lihasryhmällä
/// kaksi palkkia allekkain, suunniteltu (ohjelma, väri suosituksen mukaan) ja toteutunut (tällä viikolla).
class WeeklyLoadCard extends StatelessWidget {
  final Program program;
  final Map<String, double>? done;
  final String? doneLabel; // toteutuneen selite (oletus: tällä viikolla)
  const WeeklyLoadCard({super.key, required this.program, this.done, this.doneLabel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final load = weeklyLoad(program);
    final small = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
    Widget bar(double value, Color color, double height) => ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        color: color,
        backgroundColor: cs.onSurfaceVariant.withValues(alpha: .12),
      ),
    );
    Color levelColor(MuscleLoad m) => switch (m.level) {
      LoadLevel.ok => Sami.green,
      LoadLevel.low => Sami.yellow,
      LoadLevel.high => Sami.red,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Viikon kuorma (sarjaa viikossa)'), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (done != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 14,
                children: [
                  for (final (c, l) in [
                    (Sami.green, t('suunniteltu')),
                    (Sami.blue, doneLabel ?? t('toteutunut tällä viikolla')),
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 6,
                          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 5),
                        Text(l, style: small),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          for (final m in load)
            Padding(
              padding: EdgeInsets.symmetric(vertical: done == null ? 4 : 5),
              child: Row(
                children: [
                  SizedBox(width: 78, child: Text(t(m.muscle), style: const TextStyle(fontSize: 13))),
                  Expanded(
                    child: Column(
                      children: [
                        // Täysi palkki = suosituksen yläraja (molemmissa sama mittakaava).
                        bar(m.hi <= 0 ? 0 : m.sets / m.hi, levelColor(m), done == null ? 10 : 8),
                        if (done != null) ...[
                          const SizedBox(height: 3),
                          bar(m.hi <= 0 ? 0 : (done![m.muscle] ?? 0) / m.hi, Sami.blue, 8),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${fmtLoad(m.sets)} / ${m.lo}–${m.hi}',
                          style: TextStyle(fontSize: done == null ? 13 : 12, fontWeight: FontWeight.w600),
                        ),
                        if (done != null)
                          Text(
                            _doneLabel(done![m.muscle] ?? 0, m.sets),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Sami.blue),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (load.any((m) => m.level == LoadLevel.low && majorMuscles.contains(m.muscle)))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '💡 ${t('{0} jää alle suosituksen. Lisää sarja liikkeisiin (napauta liikettä), pidennä treeniä tai '
                'lisää päivä. Vähemmälläkin kehittyy, kunhan treenaat säännöllisesti.', [load.where((m) => m.level == LoadLevel.low && majorMuscles.contains(m.muscle)).map((m) => t(m.muscle)).join(', ')])}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            t(
              'Luvut: sarjaa viikossa / tavoitteesi suositus. Täysi palkki = suosituksen yläraja. Vihreä: '
              'suosituksessa, keltainen: alle, punainen: yli. Epäsuora kuorma lasketaan puolikkaana (esim. '
              'penkki: ojentajille ½). Vähintään 4 sarjaa ylläpitää, lihaskasvussa 10–20 tuottaa yleensä eniten.',
            ),
            style: small,
          ),
          if (done != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t(
                  'Toteutunut: tehdyt työsarjat kirjatuista treeneistä, myös ohjelman ulkopuoliset liikkeet; '
                  'pidemmällä jaksolla keskimäärin viikossa. ✓ = suunnitelma täynnä, ↑ = enemmän kuin suunniteltu.',
                ),
                style: small,
              ),
            ),
        ],
      ),
    );
  }
}

String fmtLoad(double v) => v == v.roundToDouble() ? '${v.round()}' : fmtDec(v, 1);

/// "5 / 7", "8 / 8 ✓", "10 / 8 ↑".
String _doneLabel(double done, double planned) {
  final base = '${fmtLoad(done)} / ${fmtLoad(planned)}';
  if (planned <= 0) return base;
  if (done > planned + .01) return '$base ↑';
  if (done >= planned - .01) return '$base ✓';
  return base;
}

class _ItemSheet extends StatefulWidget {
  final Program program;
  final PlanDay day;
  final PlanItem item;
  final List<String> injuries;
  const _ItemSheet({required this.program, required this.day, required this.item, required this.injuries});
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  PlanItem get it => widget.item;
  String? _preview; // valittu uusi liike ennen vahvistusta
  bool _changed = false;

  void _set(VoidCallback f) => setState(() {
    f();
    _changed = true;
  });

  Future<void> _pickOther() async {
    final name = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (name != null) setState(() => _preview = name);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (same, _) = swapCandidates(it);
    final m = measureOf(it.exercise);
    final main = it.kind == 'H' || it.kind == 'V';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          Text(exerciseLabel(it.exercise), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text(
            '${trName(widget.day.name)} · ${slotName(it.slot)}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (_preview != null) ...[const SizedBox(height: 12), _swapPreview(cs)],
          SectionLabel(t('Vaihda liike – sama liikemalli')),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final x in same.take(12))
                ChoiceChip(
                  label: Text(exerciseLabel(x)),
                  selected: _preview == x,
                  onSelected: (_) => setState(() => _preview = x),
                ),
              ActionChip(
                avatar: const Icon(Icons.search, size: 16),
                label: Text(t('Muu liike…')),
                onPressed: _pickOther,
              ),
            ],
          ),
          if (!main) ...[
            SectionLabel(t('Sarjat')),
            ValueStepper(
              value: '${it.sets}',
              unit: 'sarjaa',
              onMinus: () => _set(() => it.sets = (it.sets - 1).clamp(1, 10)),
              onPlus: () => _set(() => it.sets = (it.sets + 1).clamp(1, 10)),
            ),
            SectionLabel(t('{0}{1}: alaraja', [m.label[0].toUpperCase(), m.label.substring(1)])),
            ValueStepper(
              value: '${it.lo}',
              unit: m.unit,
              onMinus: () => _set(() => it.lo = (it.lo - m.step).clamp(1, it.hi)),
              onPlus: () => _set(() {
                it.lo += m.step;
                if (it.hi < it.lo) it.hi = it.lo;
              }),
            ),
            SectionLabel(t('{0}{1}: yläraja', [m.label[0].toUpperCase(), m.label.substring(1)])),
            ValueStepper(
              value: '${it.hi}',
              unit: m.unit,
              onMinus: () => _set(() {
                it.hi = (it.hi - m.step).clamp(1, 9999);
                if (it.lo > it.hi) it.lo = it.hi;
              }),
              onPlus: () => _set(() => it.hi += m.step),
            ),
            const SizedBox(height: 10),
            for (final msg in assessItem(widget.program, it)) Text(msg, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final (label, lo, hi)
                    in m == Measure.reps
                        ? [(t('Voima 3–6'), 3, 6), (t('Perus 6–12'), 6, 12), (t('Kevyt 12–20'), 12, 20)]
                        : const <(String, int, int)>[])
                  ActionChip(
                    label: Text(label),
                    onPressed: () => _set(() {
                      it.lo = lo;
                      it.hi = hi;
                    }),
                  ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                t('Pääliikkeen sarjat ja toistot tulevat voimanoston 10 viikon taulukosta.'),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  widget.day.items.remove(it);
                  Navigator.pop(context, true);
                },
                icon: Icon(Icons.delete_outline, color: cs.error),
                label: Text(t('Poista'), style: TextStyle(color: cs.error)),
              ),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context, _changed), child: Text(t('Valmis'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swapPreview(ColorScheme cs) {
    final to = _preview!;
    final (ok, msgs) = assessSwap(widget.program, widget.day, it, to, injuries: widget.injuries);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? Sami.green : Sami.yellow).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: ok ? Sami.green : Sami.yellow, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${exerciseLabel(it.exercise)} → ${exerciseLabel(to)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (final msg in msgs) Text(msg, style: const TextStyle(fontSize: 13)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => setState(() => _preview = null), child: Text(t('Peruuta'))),
              FilledButton(
                onPressed: () => _set(() {
                  applySwap(it, to);
                  _preview = null;
                }),
                child: Text(ok ? t('Vaihda') : t('Vaihda silti')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ohjelmapäivän oma nimi. Pikavalinnat: viikonpäivät ja jaon nimet. Palauttaa null, jos peruttiin,
/// tyhjän merkkijonon, jos palataan oletusnimeen.
Future<String?> askDayLabel(BuildContext context, PlanDay d) {
  final c = TextEditingController(text: d.label ?? '');
  final quick = [
    t('Maanantai'),
    t('Tiistai'),
    t('Keskiviikko'),
    t('Torstai'),
    t('Perjantai'),
    t('Lauantai'),
    t('Sunnuntai'),
    t('Ylävartalo'),
    t('Alavartalo'),
    t('Työntö'),
    t('Veto'),
    'Jalat',
    'Koko keho',
  ];
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Nimeä: {0}', [d.name])),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              autofocus: false,
              decoration: InputDecoration(hintText: d.name, helperText: t('Tyhjä = {0}', [d.name])),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final q in quick) ActionChip(label: Text(q), onPressed: () => Navigator.pop(ctx, q))],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(t('Oletusnimi'))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

/// Ohjelmapäivän kortti treenin valintaan: nimi, liikkeet, kesto, suositus- ja tehty-merkit.
class DayCard extends StatelessWidget {
  final PlanDay day;
  final bool selected, suggested, doneThisWeek, doneToday;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final String? subtitle;
  const DayCard({
    super.key,
    required this.day,
    required this.selected,
    required this.onTap,
    this.suggested = false,
    this.doneThisWeek = false,
    this.doneToday = false,
    this.onRename,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final names = day.items.map((i) => exerciseLabel(i.exercise)).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? Sami.yellow.withValues(alpha: .12) : cs.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? Sami.yellow : Colors.transparent, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onRename,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? Sami.yellow : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(day.uiName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          if (day.label != null)
                            Text(trName(day.name), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          if (suggested) _badge(t('suositus'), const Color(0xFF3FBF7F)),
                          if (doneToday)
                            _badge(t('tehty tänään ✓'), Sami.green)
                          else if (doneThisWeek)
                            _badge(t('tehty tällä viikolla ✓'), cs.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ??
                            '${names.take(3).join(', ')}${names.length > 3 ? ' +${names.length - 3}' : ''} · ~${estimateMinutes(day.items).round()} min',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onRename != null)
                  IconButton(
                    tooltip: t('Nimeä'),
                    icon: Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
                    onPressed: onRename,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
    child: Text(
      t,
      style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
    ),
  );
}
