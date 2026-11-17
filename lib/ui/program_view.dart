import 'package:flutter/material.dart';

import '../exercises.dart';
import '../program.dart';
import '../models.dart' show fmtDec, fmtNum;
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

  /// Päivien lisäys ja poisto (käyttäjä 16.11.). Viikon kuorma lasketaan päivistä, joten treenipäiviä viikossa
  /// seuraa päivien määrää, kun ne olivat samat.
  void _setDays(int before) {
    if (program.days == before) program.days = program.plan.length;
  }

  void _addDay() {
    final before = program.plan.length;
    var n = before + 1;
    // Pysyvä nimi (tiedostossa, treenien vertailu) yksilöllinen, käyttäjän kielellä; nimeä voi muuttaa kynästä.
    while (program.plan.any((d) => d.matches(t('Päivä {0}', [n])) || d.name == 'Päivä $n')) {
      n++;
    }
    program.plan.add(PlanDay(t('Päivä {0}', [n]), []));
    _setDays(before);
    onChanged!();
  }

  Future<void> _removeDay(BuildContext context, PlanDay d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko {0}?', [d.uiName])),
        content: Text(t('Päivän liikkeet poistuvat ohjelmasta. Tehdyt treenit säilyvät.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista'))),
        ],
      ),
    );
    if (ok != true || program.plan.length <= 1) return;
    final before = program.plan.length;
    program.plan.remove(d);
    _setDays(before);
    onChanged!();
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

  Widget _itemRow(BuildContext context, PlanDay d, PlanItem i, TextStyle sub, ColorScheme cs) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: _editable ? () => _editItem(context, d, i) : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (i.group != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '${i.group}${d.items.where((x) => x.group == i.group).toList().indexOf(i) + 1}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                  ),
                ),
              Expanded(child: ExName(i.exercise)),
              Text(switch (i.kind) {
                'H' => t('raskas, viikon mukaan'),
                'V' => t('volyymi, viikon mukaan'),
                _ =>
                  '${i.sets} × ${i.lo == i.hi ? i.lo : '${i.lo}–${i.hi}'}'
                      '${measureOf(i.exercise) == Measure.reps ? '' : ' ${t(measureOf(i.exercise).unit)}'}'
                      '${i.pct == null ? '' : ' @ ${fmtNum(double.parse((i.pct! * 100).toStringAsFixed(1)))} %'}',
              }, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (_editable) ...[const SizedBox(width: 6), Icon(Icons.edit, size: 15, color: cs.onSurfaceVariant)],
            ],
          ),
          if (i.alts.isNotEmpty) Text(t('tai: {0}', [i.alts.map(exerciseLabel).join(', ')]), style: sub),
          if (i.note != null) Text('🩹 ${trNote(i.note!)}', style: sub),
        ],
      ),
    ),
  );

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
            child: Text(
              t(
                'Napauta liikettä vaihtaaksesi sen tai muuttaaksesi sarjoja ja toistoja. Järjestä vetämällä rivin vasemmasta reunasta.',
              ),
              style: sub,
            ),
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
                              if (d.label != null) Text(trName(d.name), style: sub),
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
                        if (_editable && program.plan.length > 1)
                          IconButton(
                            tooltip: t('Poista päivä'),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.delete_outline, size: 18, color: cs.onSurfaceVariant),
                            onPressed: () => _removeDay(context, d),
                          ),
                        Text(t('~{0} min', [estimateMinutes(d.items).round()]), style: sub),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Muokkaustilassa liikkeiden järjestys vetämällä (käyttäjä 16.11.: ilman poistoa ja uudelleen lisäystä).
                    if (_editable)
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        onReorderItem: (from, to) {
                          d.items.insert(to, d.items.removeAt(from));
                          onChanged!();
                        },
                        children: [
                          for (final (n, i) in d.items.indexed)
                            Row(
                              key: ObjectKey(i),
                              children: [
                                ReorderableDragStartListener(
                                  index: n,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                                    child: Semantics(
                                      label: t('Siirrä: {0}', [exerciseLabel(i.exercise)]),
                                      child: Icon(Icons.drag_indicator, size: 20, color: cs.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                                Expanded(child: _itemRow(context, d, i, sub, cs)),
                              ],
                            ),
                        ],
                      )
                    else
                      for (final i in d.items) _itemRow(context, d, i, sub, cs),
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
        if (_editable)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(onPressed: _addDay, icon: const Icon(Icons.add), label: Text(t('Lisää päivä'))),
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

  static const _grouped = {'hauis', 'ojentaja', 'etureisi', 'takareisi', 'pakara', 'pohje'};

  Widget _groupHeader(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  /// Alarivi (olkapään tai selän osa): ohut palkki pääpalkin mittakaavassa, luku ja tehdyt sarjat.
  Widget _subRow(BuildContext context, String label, double v, double? doneV, int hi, TextStyle small) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              // Pitkä kaksisanainen nimi kahdelle riville, ettei se kutistu lukukelvottomaksi
              // (testi 16.11.: saame "govda čielgedeahkki", suomi "leveä selkälihas").
              child: Text(
                label.length > 12 && label.contains(' ') ? label.replaceFirst(' ', '\n') : label,
                maxLines: 2,
                softWrap: false,
                style: small.copyWith(height: 1.1),
              ),
            ),
          ),
        ),
        Expanded(
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: hi <= 0 ? 0 : (v / hi).clamp(0.0, 1.0),
                minHeight: 5,
                color: Sami.green.withValues(alpha: .55),
                backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .10),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 84,
          child: Text(
            doneV == null ? fmtLoad(v) : '${fmtLoad(v)} · ${fmtLoad(doneV)}',
            textAlign: TextAlign.end,
            style: small,
          ),
        ),
      ],
    ),
  );

  /// Keskivartalo: harmaa tietorivi (ei suositusta). Palkin täysi pituus 10 sarjaa.
  Widget _coreRow(BuildContext context, double v, double? doneV, TextStyle small) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(t('keskivartalo'), maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
        Expanded(
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: (v / 10).clamp(0.0, 1.0),
                minHeight: 8,
                color: cs.onSurfaceVariant,
                backgroundColor: cs.onSurfaceVariant.withValues(alpha: .12),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 84,
          child: Text(
            doneV == null ? fmtLoad(v) : '${fmtLoad(v)} · ${fmtLoad(doneV)}',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final load = weeklyLoad(program);
    final stats = statsOf(program);
    final sub = stats.sub;
    final core = stats.weekly['vatsa'] ?? 0;
    final small = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
    // Palkit kuvina: sarjamäärät ovat tekstinä vieressä (ruudunlukija luki nimettömän arvon).
    Widget bar(double value, Color color, double height) => ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          color: color,
          backgroundColor: cs.onSurfaceVariant.withValues(alpha: .12),
        ),
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
                    (blueText(context), doneLabel ?? t('toteutunut tällä viikolla')),
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
          for (final m in load) ...[
            // Ryhmät (käyttäjä 16.11.): käsivarret ja jalat otsikon alla, kuten olkapää ja selkä osineen.
            if (m.muscle == 'hauis') _groupHeader(context, t('käsivarret')),
            if (m.muscle == 'etureisi') _groupHeader(context, t('jalat')),
            Padding(
              padding: EdgeInsets.symmetric(vertical: done == null ? 4 : 5),
              child: Row(
                children: [
                  // Lihasryhmän nimi yhdellä rivillä, tarvittaessa pienempänä (saameksi "maŋŋeruoida" katkesi
                  // sanan keskeltä; suurella fontilla vielä useampi).
                  SizedBox(
                    width: 90,
                    child: Padding(
                      // Väli palkkiin: pisin nimi (saameksi "maŋŋeruoida") ei kosketa palkkia. Ryhmän jäsenet sisennettyinä.
                      padding: EdgeInsetsDirectional.only(start: _grouped.contains(m.muscle) ? 10 : 0, end: 6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(t(m.muscle), maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        // Täysi palkki = suosituksen yläraja (molemmissa sama mittakaava).
                        bar(m.hi <= 0 ? 0 : m.sets / m.hi, levelColor(m), done == null ? 10 : 8),
                        if (done != null) ...[
                          const SizedBox(height: 3),
                          bar(m.hi <= 0 ? 0 : (done![m.muscle] ?? 0) / m.hi, blueText(context), 8),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Yhdellä rivillä, tarvittaessa pienempänä: suurella fontilla "11 / 4–20" katkesi
                        // ajatusviivan kohdalta kahdelle riville (16.11. ilta).
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            '${fmtLoad(m.sets)} / ${m.lo}–${m.hi}',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(fontSize: done == null ? 13 : 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (done != null)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              _doneLabel(done![m.muscle] ?? 0, m.sets),
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: blueText(context)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Olkapään ja selän osat pieninä alariveinä (käyttäjä 16.11.): vain sarjamäärä, sama mittakaava kuin pääpalkissa.
            for (final x in subMuscles[m.muscle] ?? const <String>[])
              _subRow(context, t(x), sub[x] ?? 0, done?[x], m.hi, small),
            // Tietorivit ryhmän lopussa: kyynärvarret käsivarsiin, lähentäjät jalkoihin (ei suositusta).
            if (m.muscle == 'ojentaja')
              _subRow(context, t('kyynärvarret'), sub['kyynärvarret'] ?? 0, done?['kyynärvarret'], m.hi, small),
            if (m.muscle == 'pohje')
              _subRow(
                context,
                t('lähentäjät'),
                sub['lähentäjät'] ?? 0,
                done?['lähentäjät'],
                load.firstWhere((x) => x.muscle == 'etureisi', orElse: () => m).hi,
                small,
              ),
          ],
          // Keskivartalo omana rivinään: tieto, ei suositusrajaa eikä varoitusta.
          Divider(height: 18, color: cs.outlineVariant),
          _coreRow(context, core, done?['vatsa'], small),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              t(
                'Keskivartalo: suorat liikkeet (esim. Pallof press, lankku, jalannosto roikkuen). Kyykky ja maastaveto '
                'kuormittavat sitä myös, mutta niitä ei lasketa. Ei suositusrajaa.',
              ),
              style: small,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t(
                'Alarivit voivat yhteensä olla enemmän kuin pääpalkki: sama liike kuormittaa useaa osaa (esim. soutu '
                'yläselkää ja leveää selkälihasta).',
              ),
              style: small,
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
          if (program.plan.any((d) => d.items.any((i) => i.alts.isNotEmpty)))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('Tämä tai tuo -liikkeet: sarjat jaetaan vaihtoehtojen kesken tasan, eli oletuksena vuorottelet.'),
                style: small,
              ),
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

  void _move(int by) => _set(() {
    final items = widget.day.items;
    final i = items.indexOf(it);
    items.insert(i + by, items.removeAt(i));
  });

  Future<void> _pickAlt() async {
    final name = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (name == null || !mounted || name == it.exercise || it.alts.contains(name)) return;
    _set(() => it.alts.add(name));
  }

  Future<void> _pickOther() async {
    final name = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
    if (name != null && mounted) setState(() => _preview = name);
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
          // Vaihtoehdot (käyttäjä 16.11.): treenissä valitaan, mikä tehdään tänään.
          SectionLabel(t('Vaihtoehdot treenissä')),
          Text(
            t('Treenissä valitset, minkä näistä teet tänään. Sama tavoite, jokaisella oma historia ja painoehdotus.'),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in it.alts)
                InputChip(
                  label: Text(exerciseLabel(a)),
                  onDeleted: () => _set(() => it.alts.remove(a)),
                  deleteButtonTooltipMessage: t('Poista vaihtoehto'),
                ),
              for (final x in same.where((x) => !it.alts.contains(x)).take(it.alts.isEmpty ? 4 : 2))
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(exerciseLabel(x)),
                  onPressed: () => _set(() => it.alts.add(x)),
                ),
              ActionChip(
                avatar: const Icon(Icons.search, size: 16),
                label: Text(t('Muu vaihtoehto…')),
                onPressed: _pickAlt,
              ),
            ],
          ),
          for (final a in it.alts.where((a) => family(slotOf(a)) != family(it.slot)))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '⚠️ ${t('{0}: eri liikemalli kuin {1}. Viikon kuormassa sarjat jaetaan vaihtoehtojen kesken tasan (vuorottelu).', [exerciseLabel(a), exerciseLabel(it.exercise)])}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (!main) ...[
            SectionLabel(t('Sarjat')),
            ValueStepper(
              value: '${it.sets}',
              unit: 'sarjaa',
              onMinus: () => _set(() => it.sets = (it.sets - 1).clamp(1, 10)),
              onPlus: () => _set(() => it.sets = (it.sets + 1).clamp(1, 10)),
            ),
            SectionLabel(t('{0}{1}: alaraja', [t(m.label)[0].toUpperCase(), t(m.label).substring(1)])),
            ValueStepper(
              value: '${it.lo}',
              unit: m.unit,
              onMinus: () => _set(() => it.lo = (it.lo - m.step).clamp(1, it.hi)),
              onPlus: () => _set(() {
                it.lo += m.step;
                if (it.hi < it.lo) it.hi = it.lo;
              }),
            ),
            SectionLabel(t('{0}{1}: yläraja', [t(m.label)[0].toUpperCase(), t(m.label).substring(1)])),
            ValueStepper(
              value: '${it.hi}',
              unit: m.unit,
              onMinus: () => _set(() {
                it.hi = (it.hi - m.step).clamp(1, 9999);
                if (it.lo > it.hi) it.lo = it.hi;
              }),
              onPlus: () => _set(() => it.hi += m.step),
            ),
            // Paino prosentteina arvioidusta maksimista (painoliikkeet).
            if (m == Measure.reps) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('Paino prosentteina maksimista')),
                subtitle: Text(
                  t('Sovellus laskee painon arvioidusta maksimista (e1RM).'),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                value: it.pct != null,
                onChanged: (v) => _set(() => it.pct = v ? .75 : null),
              ),
              if (it.pct != null)
                ValueStepper(
                  value: fmtNum(double.parse((it.pct! * 100).toStringAsFixed(1))),
                  unit: '%',
                  onMinus: () => _set(() => it.pct = ((it.pct! * 100 - 2.5).clamp(40, 100)) / 100),
                  onPlus: () => _set(() => it.pct = ((it.pct! * 100 + 2.5).clamp(40, 100)) / 100),
                ),
            ],
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
          ] else if (main)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                t('Pääliikkeen sarjat ja toistot tulevat voimanoston 10 viikon taulukosta.'),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          SectionLabel(t('Supersarja')),
          Text(
            t(
              'Saman kirjaimen liikkeet tehdään vuorotellen, tauko vasta kierroksen jälkeen. 3 tai useampi = kiertoharjoittelu.',
            ),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: Text(t('Ei')),
                selected: it.group == null,
                onSelected: (_) => _set(() => it.group = null),
              ),
              for (final g in const ['A', 'B', 'C', 'D'])
                ChoiceChip(
                  label: Text(
                    '$g${widget.day.items.where((x) => x != it && x.group == g).isEmpty ? '' : ' · ${widget.day.items.where((x) => x != it && x.group == g).map((x) => exerciseLabel(x.exercise)).join(', ')}'}',
                  ),
                  selected: it.group == g,
                  onSelected: (_) => _set(() => it.group = g),
                ),
            ],
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
              // Järjestys ilman vetämistä (ruudunlukija, tarkka siirto): ylös / alas päivän sisällä.
              IconButton(
                tooltip: t('Siirrä ylös'),
                onPressed: widget.day.items.indexOf(it) > 0 ? () => _move(-1) : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: t('Siirrä alas'),
                onPressed: widget.day.items.indexOf(it) < widget.day.items.length - 1 ? () => _move(1) : null,
                icon: const Icon(Icons.arrow_downward),
              ),
              const SizedBox(width: 4),
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
    t('Jalat'),
    t('Koko keho'),
  ];
  // Oletusnimi näytetään käännettynä ("Full body C"), kuten muuallakin ohjelmassa.
  final base = trName(d.name);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Nimeä: {0}', [base])),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              autofocus: false,
              decoration: InputDecoration(hintText: base, helperText: t('Tyhjä = {0}', [base])),
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
  final bool selected, suggested, doneThisWeek, doneToday, openToday;
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
    this.openToday = false,
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
                          if (openToday)
                            _badge(t('kesken'), cs.primary)
                          else if (doneToday)
                            _badge(t('tehty tänään ✓'), greenText(context))
                          else if (doneThisWeek)
                            _badge(t('tehty tällä viikolla ✓'), cs.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ??
                            '${names.take(3).join(', ')}${names.length > 3 ? ' +${names.length - 3}' : ''} · ~${estimateMinutes(day.items).round()} min',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        // Suurella tekstillä koko lista ja kesto näkyviin (kuusi liikettä vie neljä riviä).
                        maxLines: bigText(context) ? 5 : 2,
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
