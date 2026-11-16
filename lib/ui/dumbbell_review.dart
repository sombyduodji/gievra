import 'package:flutter/material.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Kerran tehtävä tarkistus (käyttäjä 15.11.): kahden käsipainon liikkeet kirjataan nyt yhteispainona, mutta vanhoissa
/// treeneissä (vanha versio, FitNotes) paino voi olla joko yhteensä tai käsipainoa kohden, liikkeittäin vaihdellen.
/// Arvaus valmiina; käsipainoa kohden merkityt kerrotaan kahdella, ja tiedostot merkitään tarkistetuiksi.
class DumbbellReviewScreen extends StatefulWidget {
  const DumbbellReviewScreen({super.key});
  @override
  State<DumbbellReviewScreen> createState() => _DumbbellReviewScreenState();
}

/// Tarkistettava rivi: treeni ja sen kahden käsipainon liike.
typedef DumbbellRow = ({Workout w, ExerciseEntry e});

/// Tarkistettavat rivit liikkeittäin, uusin ensin.
Map<String, List<DumbbellRow>> dumbbellRows(List<Workout> workouts) {
  final out = <String, List<DumbbellRow>>{};
  for (final w in workouts.where((w) => w.dumbbellReview)) {
    for (final e in w.exercises.where((e) => totalDumbbells(e.name) && e.sets.isNotEmpty)) {
      out.putIfAbsent(e.name, () => []).add((w: w, e: e));
    }
  }
  for (final l in out.values) {
    l.sort((a, b) => b.w.date.compareTo(a.w.date));
  }
  return out;
}

/// Arvaus: oliko paino käsipainoa kohden? Vertailu saman liikkeen tavalliseen painoon: varmasti yhteispainoina
/// kirjattujen (tarkistetut ja uudet) mediaani, muuten kaikkien. Selvästi alle (≤ 65 %) = käsipainoa kohden.
/// Ilman vertailukohtaa: 9.11.2026 alkaen sovellus pyysi käsipainoa kohden, sitä ennen yhteispainoa.
bool guessPerDumbbell(DumbbellRow r, List<Workout> all) {
  double top(ExerciseEntry e) => e.sets.where((s) => !s.warmup).fold(0.0, (a, s) => s.kg > a ? s.kg : a);
  final sure = [
    for (final w in all.where((w) => !w.dumbbellReview))
      for (final e in w.exercises.where((e) => e.name == r.e.name)) top(e),
  ].where((v) => v > 0).toList();
  final others = [
    for (final w in all.where((w) => w != r.w))
      for (final e in w.exercises.where((e) => e.name == r.e.name)) top(e),
  ].where((v) => v > 0).toList();
  final ref = sure.isNotEmpty ? sure : others;
  if (ref.isEmpty) return !r.w.date.isBefore(perWeightSince);
  ref.sort();
  final median = ref[ref.length ~/ 2];
  return top(r.e) <= median * .65;
}

/// Farmer walk kuusikulmatangolla: oma liikkeensä (yksi väline, paino yhteensä).
const hexBarFarmerWalk = 'Farmer walk hex barilla';

/// Tallentaa valinnat: käsipainoa kohden kirjatut kahdella, [hexBar] siirretään hex bar -liikkeeksi (paino ennallaan),
/// kaikki tarkistetut merkitään yhteispainoiksi.
Future<int> applyDumbbellReview(
  Map<String, List<DumbbellRow>> rows,
  Set<DumbbellRow> perDumbbell, {
  Set<DumbbellRow> hexBar = const {},
  Set<DumbbellRow>? applied,
}) async {
  final touched = <Workout>{};
  for (final l in rows.values) {
    for (final r in l) {
      // Uusi yritys tallennusvirheen jälkeen: jo muutettuja rivejä ei kerrota uudelleen (yötesti 16.11.: ×4).
      if (applied != null && !applied.add(r)) {
        touched.add(r.w);
        continue;
      }
      if (hexBar.contains(r)) {
        renameExercise(r.w, r.e, hexBarFarmerWalk);
      } else if (perDumbbell.contains(r)) {
        for (final s in r.e.sets) {
          s.kg = s.kg * 2;
        }
      }
      touched.add(r.w);
    }
  }
  for (final w in touched) {
    w.dumbbellReview = false;
    await store.save(w);
  }
  return touched.length;
}

class _DumbbellReviewScreenState extends State<DumbbellReviewScreen> {
  late final Map<String, List<DumbbellRow>> _rows = dumbbellRows(store.workouts);
  late final Set<DumbbellRow> _per = {
    for (final l in _rows.values)
      for (final r in l)
        if (guessPerDumbbell(r, store.workouts)) r,
  };
  final Set<DumbbellRow> _hex = {};
  final Set<DumbbellRow> _applied = {}; // muistissa jo muutetut (uusi yritys virheen jälkeen)
  bool _saving = false;

  String _sets(ExerciseEntry e) => e.sets.map((s) => '${fmtNum(s.kg)}×${s.reps}').join(', ');

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final int n;
    try {
      n = await applyDumbbellReview(_rows, _per, hexBar: _hex, applied: _applied);
    } catch (e) {
      // Virhe ei saa jättää Tallenna-painiketta pysyvästi pois käytöstä.
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Virhe: {0}', [errorText(e)]))));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Päivitetty {0} treeniä.', [n]))));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: BarTitle(Text(t('Käsipainojen painot')))),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
          child: FilledButton(
            key: const ValueKey('dumbbellReviewSave'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _saving || _rows.isEmpty ? null : _save,
            child: Text(t('Tallenna'), style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          const SamiBand(height: 4, pattern: false),
          const SizedBox(height: 12),
          Text(
            t(
              'Kahden käsipainon liikkeet kirjataan nyt yhteispainona (molemmat käsipainot yhteensä). Vanhoissa '
              'treeneissä paino voi olla yhteensä tai yhtä käsipainoa kohden. Tarkista kerran: arvaus on valmiina. '
              'Käsipainoa kohden kirjatut kerrotaan kahdella.',
            ),
            style: sub,
          ),
          if (_rows.isEmpty) Padding(padding: const EdgeInsets.only(top: 24), child: Text(t('Ei tarkistettavaa.'))),
          for (final MapEntry(key: name, value: l) in _rows.entries) ...[
            SectionLabel(exerciseLabel(name)),
            // Kapealla näytöllä ja pitkillä käännöksillä painikkeet jakavat leveyden ja teksti pienenee.
            Row(
              children: [
                Text(t('Kaikki:'), style: sub),
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _per.removeAll(l);
                      _hex.removeAll(l);
                    }),
                    child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Yhteensä'), maxLines: 1)),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _hex.removeAll(l);
                      _per.addAll(l);
                    }),
                    child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Käsipainoa kohden'), maxLines: 1)),
                  ),
                ),
                if (name == 'Farmer walk')
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('allHexBar'),
                      onPressed: () => setState(() {
                        _per.removeAll(l);
                        _hex.addAll(l);
                      }),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Hex bar'), maxLines: 1)),
                    ),
                  ),
              ],
            ),
            for (final r in l)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${shortDate(r.w.date)} ${r.w.date.year} · ${_sets(r.e)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      // 0 yhteensä, 1 käsipainoa kohden, 2 hex bar (vain Farmer walk: oma liikkeensä).
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Yhteensä'), maxLines: 1)),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Käsipainoa kohden'), maxLines: 1)),
                          ),
                          if (name == 'Farmer walk')
                            ButtonSegment(
                              value: 2,
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(t('Hex bar'), maxLines: 1)),
                            ),
                        ],
                        selected: {
                          _hex.contains(r)
                              ? 2
                              : _per.contains(r)
                              ? 1
                              : 0,
                        },
                        onSelectionChanged: (v) => setState(() {
                          _per.remove(r);
                          _hex.remove(r);
                          if (v.first == 1) _per.add(r);
                          if (v.first == 2) _hex.add(r);
                        }),
                      ),
                      if (_hex.contains(r))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(t('Siirretään: {0}', [exerciseLabel(hexBarFarmerWalk)]), style: sub),
                        ),
                      if (_per.contains(r))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            t('Tallennetaan: {0}', [r.e.sets.map((s) => '${fmtNum(s.kg * 2)}×${s.reps}').join(', ')]),
                            style: sub,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
