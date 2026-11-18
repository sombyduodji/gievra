import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../health.dart' show HealthConnect;
import '../home_layout.dart';
import '../l10n.dart';
import '../models.dart';
import '../running.dart' show runBandLabel;
import '../share_text.dart' show thousands;
import '../sleep.dart' show sleepData, sleepFirstDays;
import '../sports.dart';
import 'recovery_card.dart' show RecoveryTilesSettings, recoveryTileName;
import 'run_bands.dart';
import 'start_panels.dart' show goalLabel;
import 'tap_guard.dart' show NavTapGuard;
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
    'sleep' => t('Uni'),
    'night' => t('Yöarvot'),
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
        '(sykkeen luku) ja kellon, joka mittaa sykettä yöllä. Halutessasi myös yöarvot (HRV ym.) alta.',
      ),
      'sleep' => t(
        'Yöunet Health Connectista (esim. Oura): kesto, 7 yön pylväät, säännöllisyys ja vihje. Oletus pois; '
        'päälle kytkeminen kysyy unitietojen lukuluvan. Tallentuu uni.md-tiedostoon.',
      ),
      'night' => t(
        'HRV, hengitystiheys, happisaturaatio ja ihon lämpötila yöltä omaan tasoosi verrattuna, Palautuminen-kortissa. '
        'Oletus pois; päälle kytkeminen kysyy luvat (voit sallia vain osan). Näkyvät arvot valitset alta.',
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
        // Askeltavoite (käyttäjä 17.11.): WHO-rivin askelrengas, kalenterin päivärenkaat ja askelkuvaaja.
        ListTile(
          key: const ValueKey('stepsGoalTile'),
          leading: const Icon(Icons.directions_walk),
          title: Text(t('Askeltavoite')),
          subtitle: Text(t('{0} askelta päivässä', [thousands(settings.stepsGoal)]), style: sub),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final v = await editStepsGoal(context, settings.stepsGoal);
            if (v != null) settings.setStepsGoal(v);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Semantics(header: true, child: Text(t('Omat tavoitteet'))),
        ),
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
                title: Text(
                  g.kind == 'pace'
                      ? t('Juoksuvauhdin kehitys')
                      : g.kind == 'hrpace'
                      ? t('Juoksuvauhti samalla sykkeellä')
                      : '${fmtNum(g.perWeek)} ${goalLabel(g)} ${t('/ viikko')}',
                ),
                onTap: () async {
                  final v = await editGoal(context, g);
                  if (v != null) settings.setGoals([...goals]..[i] = v);
                },
                trailing: IconButton(
                  key: ValueKey('goalRemove_$i'),
                  tooltip: t('Poista'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    settings.setGoals([...goals]..removeAt(i));
                    NavTapGuard.markListChange();
                  },
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Semantics(header: true, child: Text(t('Kortit'))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Text(t('Valitse näytettävät ja vedä ne haluamaasi järjestykseen.'), style: sub),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          // Yöarvot ei ole oma kortti (näkyy Palautumisessa, käyttäjä 18.11.): pois listasta, kytkin alla.
          onReorderItem: (a, b) {
            final o = [...settings.homeOrder.where((id) => id != 'night')];
            o.insert(b, o.removeAt(a));
            settings.setHomeOrder([...o, 'night']);
          },
          children: [
            for (final (i, id) in settings.homeOrder.where((id) => id != 'night').indexed)
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
                // Kytkimelle kortin nimi: TalkBack luki pelkän "Kytkin, päällä" (uiautomator: nimetön Switch, 18.11.).
                trailing: Semantics(
                  label: cardTitle(id),
                  child: Switch(
                    key: ValueKey('homeCardSwitch_$id'),
                    value: settings.homeCardOn(id),
                    onChanged: id == 'weight' && !settings.bodyTracker
                        ? null
                        : id == 'sleep'
                        ? (v) => _setSleep(context, v)
                        : id == 'recovery'
                        ? (v) {
                            settings.setHomeCard('recovery', v);
                            if (!v) settings.setHomeCard('night', false);
                          }
                        : (v) => settings.setHomeCard(id, v),
                  ),
                ),
              ),
          ],
        ),
        // Yöarvot Palautuminen-kortissa (käyttäjä 18.11.: HRV osaksi Palautumista, ei omaa korttia).
        SwitchListTile(
          key: const ValueKey('homeCardSwitch_night'),
          contentPadding: const EdgeInsets.only(left: 56, right: 16),
          title: Text(t('Yöarvot Palautuminen-kortissa')),
          subtitle: Text(cardSub('night'), style: sub),
          value: settings.homeCardOn('night'),
          onChanged: (v) => _setNight(context, v),
        ),
        // Yöarvot päällä: mitkä arvot näytetään (käyttäjä 17.11.: kortit pitkälle muokattaviksi).
        // Palautumisen ruudut: päälle/pois ja järjestys omalla sivullaan (käyttäjä 18.11.).
        if (settings.homeCardOn('recovery'))
          ListTile(
            key: const ValueKey('recoveryTilesRow'),
            contentPadding: const EdgeInsets.only(left: 56, right: 16),
            title: Text(t('Palautumisen ruudut')),
            subtitle: Text(
              [
                for (final k in settings.recoveryOrder)
                  if (settings.nightTiles.contains(k)) recoveryTileName(k).$1,
              ].join(' · '),
              style: sub,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => RecoveryTilesSettings.open(context),
          ),
        // Kehitysversio (emulaattori): 20 keksittyä yötä Health Connectiin Uni-kortin testaukseen.
        if (kDebugMode && settings.homeCardOn('sleep'))
          TextButton(
            key: const ValueKey('sleepDebugInsert'),
            onPressed: () async {
              if (!await HealthConnect.request(write: true, sleep: true).catchError((_) => false)) return;
              final t0 = dateOnly(DateTime.now());
              for (var i = 0; i < 20; i++) {
                final d = addDays(t0, -i);
                final bed = DateTime(d.year, d.month, d.day - 1, 23, 10 + i * 7 % 40);
                final min = i == 0 ? 345 : 420 + (i * 13 % 50) - 20;
                await HealthConnect.debugInsert(
                  bed,
                  bed.add(Duration(minutes: min + 20)),
                  type: -2,
                  bpm: i < 2 ? 58 : 51,
                );
              }
              await sleepData.refresh(force: true, from: addDays(t0, -22));
            },
            child: const Text('Kehitysversio: lisää testiyöt'),
          ),
        // Unitavoitetta ei enää kysytä (käyttäjä 18.11.): Uni-kortti vertaa omaan tavalliseen uneen.
        // Uni päällä: vanhempi historia Health Connectista (historialupa, kuten askeleissa).
        if (settings.homeCardOn('sleep'))
          ListenableBuilder(
            listenable: sleepData,
            builder: (context, _) => ListTile(
              key: const ValueKey('sleepHistory'),
              leading: const Icon(Icons.history),
              title: Text(t('Hae vanhempi unihistoria')),
              subtitle: Text(
                t(
                  '{0} yötä tallennettu. Tavallinen taso lasketaan 4 viimeisestä viikosta; vanhemmat yöt tilastoihin ja vientiin.',
                  [sleepData.nights.length],
                ),
                style: sub,
              ),
              trailing: sleepData.loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: sleepData.loading
                  ? null
                  : () async {
                      final n = await sleepData.readHistory();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            n == null
                                ? t('Unihistoriaa ei saatu (lupa puuttuu tai Health Connect ei vastannut).')
                                : t('Unihistoria haettu: {0} uutta yötä.', [n]),
                          ),
                        ),
                      );
                    },
            ),
          ),
      ],
    );
  }
}

/// Uni-kortti päälle: ensin Health Connectin lupa (unijaksot ja syke), sitten 30 viimeistä yötä.
Future<void> _setSleep(BuildContext context, bool on) async {
  if (!on) return settings.setHomeCard('sleep', false);
  // Ei Health Connectia (esim. Android 11 ilman sovellusta, testi 17.11.): oma viesti, ei lupaviestiä.
  final hc = isDemo ? 'available' : await HealthConnect.status();
  if (hc != 'available' || !await sleepData.requestPermission()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hc == 'available'
                ? t('Uni-kortti tarvitsee Health Connectin unitietojen lukuluvan.')
                : t('Health Connect pitää asentaa tai päivittää Play Kaupasta.'),
          ),
        ),
      );
    }
    return;
  }
  settings.setHomeCard('sleep', true);
  await sleepData.refresh(force: true);
}

/// Yöarvot-kortti päälle: Health Connectin luvat (voi sallia vain osan), sitten haku.
Future<void> _setNight(BuildContext context, bool on) async {
  if (!on) return settings.setHomeCard('night', false);
  final hc = isDemo ? 'available' : await HealthConnect.status();
  if (hc != 'available' || !await sleepData.requestMetrics()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hc == 'available'
                ? t('Yöarvot tarvitsevat luvan lukea ainakin yksi yöarvo Health Connectista.')
                : t('Health Connect pitää asentaa tai päivittää Play Kaupasta.'),
          ),
        ),
      );
    }
    return;
  }
  settings.setHomeCard('night', true);
  settings.setHomeCard('recovery', true); // yöarvot näkyvät Palautuminen-kortissa
  // Ensimmäinen haku 30 yöltä myös silloin, kun Uni-kortti on jo päällä (muuten vain 3 viimeistä yötä, ja vertailu
  // omaan tasoon olisi odottanut kaksi viikkoa, vaikka Health Connectissa on 30 päivää).
  await sleepData.refresh(force: true, from: addDays(dateOnly(DateTime.now()), -(sleepFirstDays - 1)));
}

IconData _goalIcon(String kind) => switch (kind) {
  'gym' => Icons.fitness_center,
  'km' => Icons.straighten,
  'min' => Icons.timer_outlined,
  'pace' => Icons.speed,
  'hrpace' => Icons.monitor_heart_outlined,
  _ => Icons.repeat,
};

/// Tavoitteen muokkaus: laji (salipäivät, matka, aika tai kerrat), liikunnan laji ja määrä viikossa.
Future<Goal?> editGoal(BuildContext context, Goal? old) {
  var kind = old?.kind ?? 'gym';
  String? sport = old?.sport;
  final amount = selectedText(old == null ? '' : fmtNum(old.perWeek));
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
                        ('pace', t('Juoksuvauhdin kehitys')),
                        ('hrpace', t('Juoksuvauhti samalla sykkeellä')),
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
                if (kind == 'pace' || kind == 'hrpace')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      kind == 'pace'
                          ? t(
                              'Jakson juoksujen keskivauhti verrattuna 4 edelliseen viikkoon samassa matkaryhmässä '
                              '(Asetukset → Etusivu → Juoksun kehitys). Rengas täyttyy, kun vauhti paranee, vaikka '
                              'vähänkin.',
                            )
                          : t(
                              'Kuinka pitkälle juokset yhdellä sydämenlyönnillä verrattuna 4 edelliseen viikkoon. '
                              'Reilumpi kunnon mittari kuin pelkkä vauhti; tarvitsee sykkeen (sykevyö tai kello).',
                            ),
                      style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                  )
                else ...[
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
                      helperMaxLines: 3,
                      errorText: error,
                    ),
                    onChanged: (_) => set(() => error = null),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
            FilledButton(
              key: const ValueKey('goalSave'),
              onPressed: () {
                if (kind == 'pace' || kind == 'hrpace') {
                  Navigator.pop(ctx, Goal(kind, null, 1));
                  return;
                }
                final n = parseNum(amount.text);
                final max = kind == 'gym' ? 7 : (kind == 'times' ? 50 : 10000);
                // Päivät ja kerrat kokonaislukuina; teksti lupaa 1–max (ennen 0,3 kelpasi).
                if (n == null || n < 1 || n > max || (kind == 'gym' || kind == 'times') && n != n.roundToDouble()) {
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

/// Askeltavoitteen muokkaus: 1 000–50 000 askelta päivässä (oletus 10 000).
Future<int?> editStepsGoal(BuildContext context, int current) {
  final c = selectedText('$current');
  String? error;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(t('Askeltavoite')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('stepsGoalField'),
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t('Askelta päivässä'),
                errorText: error,
                helperText: t('Terveyshyöty tasaantuu noin 6 000–10 000 askeleessa päivässä.'),
                helperMaxLines: 3,
              ),
              onChanged: (_) => set(() => error = null),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final n in [6000, 8000, 10000, 12000])
                  ActionChip(label: Text(thousands(n)), onPressed: () => Navigator.pop(ctx, n)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          FilledButton(
            key: const ValueKey('stepsGoalSave'),
            onPressed: () {
              final n = int.tryParse(c.text.replaceAll(RegExp(r'[\s.,]'), ''));
              if (n == null || n < 1000 || n > 50000) {
                set(() => error = t('Anna askelmäärä {0}–{1}.', [thousands(1000), thousands(50000)]));
                return;
              }
              Navigator.pop(ctx, n);
            },
            child: Text(t('Tallenna')),
          ),
        ],
      ),
    ),
  );
}
