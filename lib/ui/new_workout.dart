import 'package:flutter/material.dart';

import '../program_edit.dart';
import '../app_state.dart';
import '../models.dart';
import '../program.dart';
import '../theme.dart';
import 'activity.dart';
import 'program_screen.dart';
import 'program_view.dart';
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
  final _newEq = TextEditingController();

  @override
  void dispose() {
    _newEq.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = dateOnly(d));
  }

  void _start(bool withWarmup) {
    final eq = settings.equipment;
    // Jos päivälle on jo treeni, jatketaan sitä.
    // Jos päivälle on jo treeni, jatketaan sitä, ellei käyttäjä aloittanut uutta treeniä samalle päivälle.
    final w =
        (widget.newSession ? null : store.forDate(_date)?.copy()) ??
        Workout(
          date: _date,
          title: _day?.display ?? 'Treeni', // tiedostoon suomeksi
          programDay: _day?.name,
          session: widget.newSession ? store.nextSession(_date) : 1,
        );
    if (withWarmup && eq.isNotEmpty) {
      w.warmup = Warmup(eq[_selected.clamp(0, eq.length - 1)].name, _minutes);
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WorkoutScreen(workout: w, planDay: _day),
      ),
    );
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
        title: Text(widget.gymOnly && settings.trainMode == 'both' ? t('Uusi salitreeni') : t('Uusi treeni')),
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
                for (final d in settings.program!.plan)
                  DayCard(
                    day: d,
                    selected: _day == d,
                    suggested: _sugg?.$1 == d,
                    doneThisWeek: store.workouts.any(
                      (w) =>
                          !w.date.isBefore(addDays(_date, 1 - _date.weekday)) &&
                          w.date.isBefore(_date) &&
                          d.matches(w.dayKey),
                    ),
                    // Samana päivänä jo tehty (sarjoja kirjattu): ehdotus on silloin ohjelman seuraava päivä.
                    doneToday: store.workouts.any(
                      (w) => w.date == _date && d.matches(w.dayKey) && w.exercises.any((e) => e.sets.isNotEmpty),
                    ),
                    onTap: () => setState(() => _day = d),
                    onRename: () async {
                      final v = await askDayLabel(context, d);
                      if (v == null) return;
                      d.label = v.isEmpty ? null : v;
                      await settings.setProgram(settings.program);
                      setState(() {});
                    },
                  ),
                DayCard(
                  day: PlanDay(t('Vapaa treeni'), []),
                  subtitle: t('Valitse liikkeet itse, ilman ohjelmaa'),
                  selected: _day == null,
                  onTap: () => setState(() => _day = null),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('✎ nimeää päivän (esim. maanantai tai veto).'),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgramScreen()));
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.tune, size: 18),
                      label: Text(t('Muokkaa liikkeitä')),
                    ),
                  ],
                ),
                if (_sugg?.$2 != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('💡 ${_sugg!.$2}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
              ],
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
                        child: Text(t('Lisää lämmittely')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(onPressed: () => _start(false), child: Text(t('Ohita →'))),
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
                    final v = await askNumber(context, t('Kesto (min)'), _minutes.toDouble(), decimals: false);
                    if (v != null && v >= 1) setState(() => _minutes = v.round());
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
                child: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
              ),
          ],
        ),
      ),
    );
  }
}
