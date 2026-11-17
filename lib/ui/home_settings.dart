import 'package:flutter/material.dart';

import '../app_state.dart';
import '../home_layout.dart';
import '../l10n.dart';
import '../models.dart';
import '../running.dart' show runBandLabel;
import '../sports.dart';
import 'run_bands.dart';
import 'start_panels.dart' show goalLabel, goalNum;
import 'widgets.dart' show selectedText;

/// Asetukset → Etusivu (käyttäjä 17.11.): omat tavoitteet (0–3) ja valittavat kortit järjestyksessä. Aloitus,
/// WHO-renkaat ja kalenteri ovat aina näkyvissä.
class HomeLayoutSettings extends StatelessWidget {
  const HomeLayoutSettings({super.key});

  static String cardTitle(String id) => switch (id) {
    'next' => t('Seuraava treeni'),
    'goals' => t('Omat tavoitteet'),
    'streak' => t('Viikkoputki'),
    'recovery' => t('Palautuminen'),
    'recent' => t('Viimeksi'),
    'strength' => t('Voiman kehitys'),
    'running' => t('Juoksun kehitys'),
    'weight' => t('Kehonpaino'),
    _ => id,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final goals = settings.goals;
    String cardSub(String id) => switch (id) {
      'goals' =>
        goals.length >= 2
            ? t('Tavoitteet omana korttinaan.')
            : t('Kun tavoitteita on 2–3. Yksi tavoite näkyy WHO-renkaiden rivissä.'),
      'next' =>
        settings.program == null
            ? t('Näkyy, kun sinulla on ohjelma.')
            : t('Ohjelman seuraava päivä liikkeineen ja Aloita.'),
      'streak' => t('Montako viikkoa peräkkäin WHO:n suositukset täyttyivät; viimeiset 8 viikkoa.'),
      'recovery' => t(
        'Yön alin syke kellosta Health Connectin kautta verrattuna tavalliseen tasoosi. Vaatii Health Connect -tuonnin '
        '(sykkeen luku) ja kellon, joka mittaa sykettä yöllä. Unitietoja ei lueta.',
      ),
      'recent' => t('Viimeisimmät treenit, saman päivän sama laji yhdellä rivillä.'),
      'strength' => t('Arvioitu 1RM: viimeiset 4 viikkoa vs. 2 kuukautta ennen; ennätykset.'),
      'running' => '${t('Vauhti ja syke matkaryhmittäin:')} ${settings.runBands.map(runBandLabel).join(' · ')}',
      'weight' =>
        settings.bodyTracker
            ? t('Viimeisin paino, muutos 30 päivässä ja käyrä.')
            : t('Ota ensin kehonpainon seuranta käyttöön (Keho ja laitteet).'),
      _ => '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            t(
              'Aina näkyvissä: Sali | Liikunta -aloitus, WHO:n suositukset renkaina (lihaskuntopäivät ohjelmasi mukaan, '
              'vähintään 2, reipas liikunta 150 min viikossa ja askeleet) ja kalenteri. Niiden alle valitset omat '
              'tavoitteesi ja kortit.',
            ),
            style: sub,
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Text(t('Omat tavoitteet'))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Text(t('Enintään 3. Yksi tavoite näkyy WHO-renkaiden rivissä, useampi omana korttinaan.'), style: sub),
        ),
        // Tavoitteiden järjestys vetämällä (renkaat näkyvät tässä järjestyksessä; käyttäjä 17.11.).
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            final l = [...goals];
            l.insert(b, l.removeAt(a));
            settings.setGoals(l);
          },
          children: [
            for (final (i, g) in goals.indexed)
              ListTile(
                key: ValueKey('goal_$i'),
                contentPadding: const EdgeInsets.only(left: 4, right: 16),
                leading: goals.length > 1
                    ? ReorderableDragStartListener(
                        index: i,
                        child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_indicator)),
                      )
                    : Padding(padding: const EdgeInsets.all(12), child: Icon(_goalIcon(g.kind))),
                title: Text('${goalNum(g, g.perWeek)} ${goalLabel(g)} ${t('/ viikko')}'),
                onTap: () async {
                  final v = await editGoal(context, g);
                  if (v != null) settings.setGoals([...goals]..[i] = v);
                },
                trailing: IconButton(
                  key: ValueKey('goalRemove_$i'),
                  tooltip: t('Poista'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => settings.setGoals([...goals]..removeAt(i)),
                ),
              ),
          ],
        ),
        if (goals.length < 3)
          ListTile(
            key: const ValueKey('goalAdd'),
            leading: const Icon(Icons.add),
            title: Text(t('Lisää tavoite')),
            onTap: () async {
              final v = await editGoal(context, null);
              if (v != null) settings.setGoals([...goals, v]);
            },
          ),
        const Divider(height: 24),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), child: Text(t('Kortit'))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Text(t('Valitse näytettävät ja vedä ne haluamaasi järjestykseen.'), style: sub),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            final o = [...settings.homeOrder];
            o.insert(b, o.removeAt(a));
            settings.setHomeOrder(o);
          },
          children: [
            for (final (i, id) in settings.homeOrder.indexed)
              ListTile(
                key: ValueKey('homeCard_$id'),
                contentPadding: const EdgeInsets.only(left: 4, right: 16),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_indicator)),
                ),
                title: Text(cardTitle(id)),
                subtitle: Text(cardSub(id), style: sub),
                onTap: id == 'running' ? () => editRunBands(context) : null,
                trailing: Switch(
                  key: ValueKey('homeCardSwitch_$id'),
                  value: settings.homeCardOn(id),
                  onChanged: id == 'weight' && !settings.bodyTracker ? null : (v) => settings.setHomeCard(id, v),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

IconData _goalIcon(String kind) => switch (kind) {
  'gym' => Icons.fitness_center,
  'km' => Icons.straighten,
  'min' => Icons.timer_outlined,
  _ => Icons.repeat,
};

/// Tavoitteen muokkaus: laji (salipäivät, matka, aika tai kerrat), liikunnan laji ja määrä viikossa.
Future<Goal?> editGoal(BuildContext context, Goal? old) {
  var kind = old?.kind ?? 'gym';
  String? sport = old?.sport;
  final amount = selectedText(old == null ? '' : goalNum(old, old.perWeek));
  String? error;
  final used = sportsByUse([for (final w in store.workouts) w.activity], among: sports.where((s) => !s.retired));
  return showDialog<Goal>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final choices = [
          for (final s in used)
            if (kind != 'km' || s.distance) s.name,
        ];
        if (sport != null && !choices.contains(sport)) sport = null;
        final unit = switch (kind) {
          'gym' => t('päivää'),
          'km' => 'km',
          'min' => 'min',
          _ => t('kertaa'),
        };
        return AlertDialog(
          title: Text(old == null ? t('Uusi tavoite') : t('Muokkaa tavoitetta')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioGroup<String>(
                  groupValue: kind,
                  onChanged: (v) => set(() => kind = v!),
                  child: Column(
                    children: [
                      for (final (k, label) in [
                        ('gym', t('Salipäivät')),
                        ('km', t('Matka')),
                        ('min', t('Liikunta-aika')),
                        ('times', t('Liikuntakerrat')),
                      ])
                        RadioListTile<String>(
                          key: ValueKey('goalKind_$k'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: k,
                          title: Text(label),
                        ),
                    ],
                  ),
                ),
                if (kind != 'gym')
                  DropdownButtonFormField<String?>(
                    key: const ValueKey('goalSport'),
                    initialValue: sport,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t('Laji')),
                    items: [
                      DropdownMenuItem(value: null, child: Text(t('Kaikki liikunta'))),
                      for (final s in choices) DropdownMenuItem(value: s, child: Text(sportName(s))),
                    ],
                    onChanged: (v) => set(() => sport = v),
                  ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('goalAmount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: t('Tavoite viikossa'),
                    suffixText: unit,
                    helperText: t('Kuukausinäkymässä tavoite × päivät / 7.'),
                    errorText: error,
                  ),
                  onChanged: (_) => set(() => error = null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
            FilledButton(
              key: const ValueKey('goalSave'),
              onPressed: () {
                final n = parseNum(amount.text);
                final max = kind == 'gym' ? 7 : (kind == 'times' ? 50 : 10000);
                if (n == null || n <= 0 || n > max) {
                  set(() => error = t('Anna luku 1–{0}.', [max]));
                  return;
                }
                Navigator.pop(ctx, Goal(kind, kind == 'gym' ? null : sport, n));
              },
              child: Text(t('Tallenna')),
            ),
          ],
        );
      },
    ),
  );
}
