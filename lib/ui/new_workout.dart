import 'package:flutter/material.dart';

import '../program_edit.dart';
import '../app_state.dart';
import '../exercises.dart' show exerciseLabel;
import '../injuries.dart' show injuryAdjusted;
import '../models.dart';
import '../program.dart';
import '../theme.dart';
import 'activity.dart';
import 'program_screen.dart';
import 'program_view.dart';
import 'tap_guard.dart' show NavTapGuard;
import 'widgets.dart';
import 'workout.dart';
import '../l10n.dart';

/// Uusi treeni: päivämäärä ja lämmittely (tai ohitus).
class NewWorkoutScreen extends StatefulWidget {
  final DateTime date;
  final bool newSession; // true = uusi treeni samalle päivälle (esim. illan juoksu)
  final bool gymOnly; // etusivun salinäkymästä: ei sali / liikunta -valintaa
  const NewWorkoutScreen({super.key, required this.date, this.newSession = false, this.gymOnly = false});
  @override
  State<NewWorkoutScreen> createState() => _NewWorkoutScreenState();
}

class _NewWorkoutScreenState extends State<NewWorkoutScreen> {
  late DateTime _date = dateOnly(widget.date);
  bool _warmup = false;
  bool _editing = false;
  int _selected = 0;
  int _minutes = 10;
  late final (PlanDay, String?)? _sugg = settings.program == null
      ? null
      : suggestDay(settings.program!, store.workouts, widget.date);
  late PlanDay? _day = _sugg?.$1;
  Set<String> get _todayMuscles => musclesTrainedToday(store.workouts, _date);
  final _newEq = TextEditingController();

  @override
  void dispose() {
    _newEq.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await pickDate(context, initial: _date, first: DateTime(2000), last: DateTime.now());
    // mounted: näkymä voi sulkeutua valitsimen ollessa auki (monkey-testi 15.11.: setState suljetussa näkymässä).
    if (d != null && mounted) setState(() => _date = dateOnly(d));
  }

  void _start(bool withWarmup) => startGymWorkout(
    context,
    date: _date,
    day: _day,
    newSession: widget.newSession,
    warmup: withWarmup ? _selected : null,
    minutes: _minutes,
    replace: true,
  );

  /// Aloita päivän kortista: lämmittely alapaneelina (laite siruina, kesto, Ohita), sitten treeni.
  Future<void> _askWarmup(PlanDay? day) async {
    setState(() => _day = day);
    await askWarmupAndStart(context, date: _date, day: day, newSession: widget.newSession, replace: true);
  }

  void _addEq() {
    final v = _newEq.text.trim();
    if (v.isEmpty) return;
    settings.setEquipment([...settings.equipment, Equipment('⭐', v)]);
    _newEq.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isToday = _date == dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: BarTitle(Text(widget.gymOnly && settings.trainMode == 'both' ? t('Uusi salitreeni') : t('Uusi treeni'))),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final eq = settings.equipment;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
            children: [
              const SamiBand(height: 4, pattern: false),
              SectionLabel(t('Päivämäärä')),
              Material(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: Text('${isToday ? '${t('Tänään')}, ' : ''}${longDateYear(_date)}'),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: _pickDate,
                ),
              ),
              if (settings.sports && !widget.gymOnly) ...[
                SectionLabel(t('Treenin tyyppi')),
                Row(
                  children: [
                    Expanded(
                      // Valittuna (tämä näkymä on salitreeni); liikunta avaa oman näkymänsä.
                      child: FilledButton.tonalIcon(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          backgroundColor: Sami.yellow.withValues(alpha: .25),
                          foregroundColor: cs.onSurface,
                          side: const BorderSide(color: Sami.yellow, width: 2),
                        ),
                        icon: const Text('💪', style: TextStyle(fontSize: 18)),
                        label: Text(t('Salitreeni ✓')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ActivityScreen(
                              workout: Workout(
                                date: _date,
                                session: widget.newSession || store.onDay(_date).isNotEmpty
                                    ? store.nextSession(_date)
                                    : 1,
                              ),
                            ),
                          ),
                        ),
                        icon: const Text('🏃', style: TextStyle(fontSize: 18)),
                        label: Text(t('Liikunta tai laji')),
                      ),
                    ),
                  ],
                ),
              ],
              if (settings.program != null) ...[
                SectionLabel(t('Mitä treenataan?')),
                // Haitari (ulkoasun kohennus 16.11., luonnos valinta3): avattu päivä punaisella kehyksellä, ehdotus
                // vain pienellä ★:lla. Aloita avaa lämmittelyn valinnan.
                for (final d in settings.program!.plan)
                  _DayAccordion(
                    day: d,
                    open: _day == d,
                    suggested: _sugg?.$1 == d,
                    tip: _sugg?.$1 == d ? _sugg?.$2 : null,
                    doneThisWeek: store.workouts.any(
                      (w) =>
                          !w.date.isBefore(addDays(_date, 1 - _date.weekday)) &&
                          w.date.isBefore(_date) &&
                          d.matches(w.dayKey),
                    ),
                    // Samana päivänä jo tehty (sarjoja kirjattu) tai kesken (ei kestoa eikä fiilistä).
                    doneToday: store.workouts.any(
                      (w) =>
                          w.date == _date &&
                          d.matches(w.dayKey) &&
                          w.exercises.any((e) => e.sets.isNotEmpty) &&
                          (w.minutes != null || w.feeling != null),
                    ),
                    openToday: store.workouts.any(
                      (w) =>
                          w.date == _date &&
                          d.matches(w.dayKey) &&
                          w.activity == null &&
                          w.minutes == null &&
                          w.feeling == null,
                    ),
                    onTap: () => setState(() => _day = _day == d ? null : d),
                    onStart: () => _askWarmup(d),
                    onRename: () async {
                      final v = await askDayLabel(context, d);
                      if (v == null) return;
                      d.label = v.isEmpty ? null : v;
                      await settings.setProgram(settings.program);
                      if (mounted) setState(() {});
                    },
                  ),
                Card(
                  margin: const EdgeInsets.only(top: 2, bottom: 8),
                  child: ListTile(
                    key: const ValueKey('freeWorkout'),
                    leading: const Icon(Icons.add),
                    title: Text(t('Vapaa treeni')),
                    subtitle: Text(t('Valitse liikkeet itse, ilman ohjelmaa')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _askWarmup(null),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgramScreen()));
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(t('Muokkaa liikkeitä')),
                  ),
                ),
              ],
              // Vapaa treeni (tai ei ohjelmaa): samana päivänä jo kuormittuneet lihakset (käyttäjä 16.11.).
              if (_day == null && _todayMuscles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '💡 ${t('Tänään kuormittui jo {0}. Jos treenaat vielä, jätä enemmän varaa.', [_todayMuscles.map(t).join(', ')])}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              if (settings.program == null) ...[
                const SizedBox(height: 22),
                Text(t('Lisätäänkö lämmittely?'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                if (!_warmup)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Sami.green, foregroundColor: Colors.white),
                          onPressed: () => setState(() => _warmup = true),
                          child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Lisää lämmittely'), maxLines: 1)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _start(false),
                          child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Ohita →'), maxLines: 1)),
                        ),
                      ),
                    ],
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(child: SectionLabel(t('Laite'))),
                      TextButton.icon(
                        onPressed: () => setState(() => _editing = !_editing),
                        icon: Icon(_editing ? Icons.check : Icons.edit, size: 18),
                        label: Text(_editing ? t('Valmis') : t('Muokkaa')),
                      ),
                    ],
                  ),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.6,
                    children: [
                      for (var i = 0; i < eq.length; i++)
                        _EquipmentTile(
                          eq: eq[i],
                          selected: i == _selected,
                          editing: _editing,
                          onTap: () => setState(() => _selected = i),
                          onRemove: () {
                            settings.setEquipment([...eq]..removeAt(i));
                            NavTapGuard.markListChange();
                            if (_selected >= eq.length - 1) _selected = 0;
                          },
                        ),
                    ],
                  ),
                  if (_editing)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newEq,
                              decoration: InputDecoration(
                                hintText: t('Uusi laite, esim. Airbike'),
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _addEq(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: _addEq, child: Text(t('Lisää'))),
                        ],
                      ),
                    ),
                  SectionLabel(t('Kesto')),
                  ValueStepper(
                    value: '$_minutes',
                    unit: 'min',
                    onMinus: () => setState(() => _minutes = (_minutes - 1).clamp(1, 600)),
                    onPlus: () => setState(() => _minutes = (_minutes + 1).clamp(1, 600)),
                    onTap: () async {
                      final v = await askNumber(
                        context,
                        t('Kesto (min)'),
                        _minutes.toDouble(),
                        decimals: false,
                        min: 1,
                        max: 600,
                      );
                      if (v != null && v >= 1 && mounted) setState(() => _minutes = v.round());
                    },
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: eq.isEmpty ? null : () => _start(true),
                    child: Text(t('Aloita treeni →'), style: TextStyle(fontSize: 16)),
                  ),
                  TextButton(onPressed: () => _start(false), child: Text(t('Ohita lämmittely'))),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EquipmentTile extends StatelessWidget {
  final Equipment eq;
  final bool selected;
  final bool editing;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _EquipmentTile({
    required this.eq,
    required this.selected,
    required this.editing,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? Sami.yellow.withValues(alpha: .12) : cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? Sami.yellow : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(eq.icon, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 4),
                  Text(t(eq.name), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            if (editing)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(icon: const Icon(Icons.close, size: 18), tooltip: t('Poista'), onPressed: onRemove),
              ),
          ],
        ),
      ),
    );
  }
}

/// Päivä haitarina: kiinni nimi, ehdotus-★, kesto, liikemäärä; auki liikkeet sarjoineen, vinkki ja Aloita.
class _DayAccordion extends StatelessWidget {
  final PlanDay day;
  final bool open, suggested, doneThisWeek, doneToday, openToday;
  final String? tip;
  final VoidCallback onTap, onStart, onRename;
  const _DayAccordion({
    required this.day,
    required this.open,
    required this.suggested,
    required this.doneThisWeek,
    this.doneToday = false,
    this.openToday = false,
    required this.tip,
    required this.onTap,
    required this.onStart,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: AppText.caption, color: cs.onSurfaceVariant);
    final mins = (estimateMinutes(day.items) / 5).round() * 5;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: open ? Sami.redLight : Colors.transparent, width: 2),
      ),
      child: InkWell(
        key: ValueKey('day_${day.name}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(day.uiName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            if (suggested)
                              Text('★ ${t('ehdotus')}', style: TextStyle(fontSize: 12, color: yellowText(context))),
                            if (openToday)
                              Text(t('kesken'), style: TextStyle(fontSize: 12, color: yellowText(context)))
                            else if (doneToday)
                              Text(t('tehty tänään ✓'), style: TextStyle(fontSize: 12, color: greenText(context)))
                            else if (doneThisWeek)
                              Text('✓ ${t('tehty tällä viikolla')}', style: sub),
                          ],
                        ),
                        Text(t('~{0} min · {1} liikettä', [mins, day.items.length]), style: sub),
                      ],
                    ),
                  ),
                  IconButton(tooltip: t('Nimeä päivä'), icon: const Icon(Icons.edit, size: 18), onPressed: onRename),
                  Icon(open ? Icons.expand_less : Icons.expand_more, color: cs.onSurfaceVariant),
                ],
              ),
              if (open) ...[
                const Divider(height: 16),
                for (final i in day.items)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            [exerciseLabel(i.exercise), ...i.alts.map(exerciseLabel)].join(' ${t('tai')} '),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text('${i.sets} × ${i.lo == i.hi ? i.lo : '${i.lo}–${i.hi}'}', style: sub),
                      ],
                    ),
                  ),
                if (tip != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: Text('💡 $tip', style: sub),
                  ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    key: ValueKey('startDay_${day.name}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Sami.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Aloita: {0}', [day.uiName]), maxLines: 1)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Aloittaa salitreenin päivälle [day] (null = vapaa treeni): jos päivälle on jo treeni, sitä jatketaan (ellei
/// [newSession]). [warmup]: lämmittelylaitteen indeksi asetuksissa (null = ei lämmittelyä). [replace]: korvaa
/// nykyisen näkymän (päivän valinta), muuten avautuu päälle (etusivun paneeli).
void startGymWorkout(
  BuildContext context, {
  required DateTime date,
  PlanDay? day,
  bool newSession = false,
  int? warmup,
  int minutes = 10,
  bool replace = false,
}) {
  final eq = settings.equipment;
  final d = dateOnly(date);
  // Jatketaan vain saman päivän keskeneräistä salitreeniä. Ennen jatkettiin päivän ensimmäistä treeniä, mikä
  // tahansa se oli: etusivun paneelista Koko keho C avasi saman päivän tallennetun koripallon (testi 17.11.).
  final open = newSession
      ? null
      : store.onDay(d).where((w) => w.activity == null && w.minutes == null && w.feeling == null).firstOrNull;
  final w =
      open?.copy() ??
      Workout(
        date: d,
        title: day?.display ?? 'Treeni', // tiedostoon suomeksi
        programDay: day?.name,
        session: store.onDay(d).isEmpty ? 1 : store.nextSession(d),
      );
  if (warmup != null && eq.isNotEmpty) w.warmup = Warmup(eq[warmup.clamp(0, eq.length - 1)].name, minutes);
  final route = MaterialPageRoute<void>(
    builder: (_) => WorkoutScreen(workout: w, planDay: day == null ? null : injuryAdjusted(day, settings.injuries)),
  );
  replace ? Navigator.of(context).pushReplacement(route) : Navigator.of(context).push(route);
}

/// Lämmittely alapaneelina (laite siruina, kesto, Ohita lämmittely / Aloita lämmittely), sitten treeni. Ilman
/// lämmittelylaitteita treeni alkaa suoraan. Peruttu paneeli (Takaisin, pyyhkäisy) ei aloita mitään.
Future<void> askWarmupAndStart(
  BuildContext context, {
  required DateTime date,
  PlanDay? day,
  bool newSession = false,
  bool replace = false,
}) async {
  final eq = settings.equipment;
  if (eq.isEmpty) {
    return startGymWorkout(context, date: date, day: day, newSession: newSession, replace: replace);
  }
  var selected = 0, minutes = 10;
  final r = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(day?.uiName ?? t('Vapaa treeni'), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(t('Lämmittely'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < eq.length; i++)
                    ChoiceChip(
                      key: ValueKey('warmupEq$i'),
                      label: Text('${eq[i].icon} ${t(eq[i].name)}'),
                      selected: i == selected,
                      onSelected: (_) => set(() => selected = i),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // ValueStepperissa on Expanded: rivissä sille annetaan leveys (ennen rajaton leveys, asettelu
              // kaatui; debug-koonnissa ruutu jäi himmeäksi ilman paneelia, yötesti 18.11.).
              Row(
                children: [
                  Expanded(flex: 2, child: Text(t('Kesto'))),
                  Expanded(
                    flex: 5,
                    child: ValueStepper(
                      value: '$minutes',
                      unit: 'min',
                      onMinus: () => set(() => minutes = (minutes - 1).clamp(1, 600)),
                      onPlus: () => set(() => minutes = (minutes + 1).clamp(1, 600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('skipWarmup'),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Ohita lämmittely'), maxLines: 1)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('startWarmup'),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Aloita lämmittely'), maxLines: 1)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (r == null || !context.mounted) return;
  startGymWorkout(
    context,
    date: date,
    day: day,
    newSession: newSession,
    warmup: r ? selected : null,
    minutes: minutes,
    replace: replace,
  );
}
