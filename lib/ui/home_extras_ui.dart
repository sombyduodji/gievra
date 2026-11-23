import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../health.dart';
import '../heart_rate.dart' show hrProfile;
import '../exercises.dart' show exerciseDisplay;
import '../home_extras.dart';
import '../l10n.dart';
import '../models.dart';
import '../program_edit.dart' show suggestDay;
import '../sleep.dart';
import '../theme.dart';
import '../session_compare.dart' show fmtDuration;
import 'recovery_card.dart' show RecoveryCard;
import 'sleep_stages_ui.dart' show showSleepStagesSheet;
import 'start_panels.dart' show RingTile, showGymPanel;
import 'widgets.dart' show fmtClock, shortDate, uiWeekdaysShort;

const _title = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

/// Viikkoputki (käyttäjä 17.11.): montako viikkoa peräkkäin WHO:n molemmat suositukset täyttyivät, paras putki ja
/// viimeiset 8 viikkoa pisteinä.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Pelkkä treenipäiväkirja (ei terveyttä ja hyvinvointia): treenipäivien putki ohjelman mukaan; WHO:n putki
    // vaatisi 150 min liikuntaa, johon pelkkä salitreenaaja ei yllä (käyttäjä 19.11.).
    final training = !settings.wellness;
    final target = settings.weeklyTrainingTarget;
    final s = training
        ? trainingStreak(store.workouts, DateTime.now(), target, mode: settings.trainMode, pauses: settings.pauses)
        : whoStreak(store.workouts, DateTime.now(), pauses: settings.pauses);
    if (store.workouts.isEmpty) return const SizedBox.shrink();
    final open = s.weeks.last.$2 == WeekMark.open;
    return Card(
      key: const ValueKey('streakCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(training ? t('Treeniputki') : t('Viikkoputki'), style: _title),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${s.current}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    training
                        ? (s.current == 1
                              ? t('viikko treenitavoitteessa ({0} treeniä)', [target])
                              : t('viikkoa peräkkäin treenitavoitteessa ({0} treeniä)', [target]))
                        : s.current == 1
                        ? t('viikko WHO:n suositusten mukaan')
                        : t('viikkoa peräkkäin WHO:n suositusten mukaan'),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
                if (s.best > s.current)
                  Text(t('Paras {0}', [s.best]), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (mon, m) in s.weeks)
                  Expanded(
                    child: Tooltip(
                      message: '${t('Viikko')} ${isoWeek(mon)}',
                      child: Column(
                        children: [
                          _Dot(mark: m),
                          const SizedBox(height: 2),
                          Text('${isoWeek(mon)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              training
                  ? (open
                        ? t('Tämä viikko lasketaan, kun {0} treeniä on tehty. Tauot eivät katkaise putkea.', [target])
                        : t('{0} treeniä viikossa (ohjelmasi mukaan). Tauot eivät katkaise putkea.', [target]))
                  : open
                  ? t(
                      'Tämä viikko lasketaan, kun lihaskunto 2 päivänä ja 150 min reipasta liikuntaa täyttyvät. Tauot eivät katkaise putkea.',
                    )
                  : t('Lihaskunto 2 päivänä ja 150 min reipasta liikuntaa viikossa. Tauot eivät katkaise putkea.'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final WeekMark mark;
  const _Dot({required this.mark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = greenText(context);
    final (Color? fill, Color border, IconData? icon) = switch (mark) {
      WeekMark.both => (g, g, Icons.check),
      WeekMark.one => (yellowText(context).withValues(alpha: 0.35), yellowText(context), null),
      WeekMark.none => (null, cs.outlineVariant, null),
      WeekMark.pause => (cs.surfaceContainerHighest, cs.outlineVariant, Icons.pause),
      WeekMark.open => (null, g, null),
    };
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: mark == WeekMark.open ? 2 : 1.5),
      ),
      child: icon == null
          ? null
          : Icon(icon, size: 14, color: mark == WeekMark.both ? Colors.white : cs.onSurfaceVariant),
    );
  }
}

/// Seuraava ohjelman päivä (käyttäjä 17.11.): sama ehdotus kuin salipaneelissa (kierto, viikon tehdyt ja
/// palautuminen) ja Aloita, joka avaa salipaneelin. Ei näy ilman ohjelmaa.
class NextDayCard extends StatelessWidget {
  const NextDayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = settings.program;
    if (p == null || p.plan.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final (day, why) = suggestDay(p, store.workouts, DateTime.now());
    final names = [for (final i in day.items) exerciseDisplay(i.exercise)];
    final shown = names.take(4).join(' · ');
    return Card(
      key: const ValueKey('nextDayCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(t('Seuraava treeni'), style: _title)),
                TextButton(
                  key: const ValueKey('nextDayStart'),
                  onPressed: () => showGymPanel(context),
                  child: Text(t('Aloita ›')),
                ),
              ],
            ),
            Text(day.uiName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                names.length > 4 ? '$shown · +${names.length - 4}' : shown,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            if (why != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(why, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Yön alin syke Health Connectista (käyttäjä 17.11.). Vain sykkeen lukulupa (sama kuin harjoitusten tuonnissa);
/// unitietoja ei lueta. Haetaan enintään puolen tunnin välein ja alas vedettäessä.
class NightHrData {
  static final nights = ValueNotifier<Map<DateTime, int>>(const {});
  static DateTime? _at;
  static bool _busy = false;

  @visibleForTesting
  static set debugNights(Map<DateTime, int> v) => nights.value = v;

  /// Health Connect -tuonti tai Palautuminen-kortti päällä (kortin kytkin kysyy sykkeen lukuluvan, 19.11.).
  static bool get available =>
      !kIsWeb && !isDemo && Platform.isAndroid && (settings.hcImport || settings.homeCardOn('recovery'));

  static Future<void> refresh({bool force = false}) async {
    if (isDemo) {
      // Demo ja verkkoversio (kotisivun kuvat): keksityt yöt, tavallinen taso 52.
      if (nights.value.isEmpty) {
        final today = dateOnly(DateTime.now());
        nights.value = {for (var i = 0; i < 30; i++) addDays(today, -i): 52 + (i * 7 % 5) - 2 + (i < 3 ? 1 : 0)};
      }
      return;
    }
    if (!available || _busy) return;
    final now = DateTime.now();
    if (!force && _at != null && now.difference(_at!).inMinutes < 30) return;
    _busy = true;
    try {
      if (await HealthConnect.status() != 'available' || !await HealthConnect.granted(heartRate: true)) return;
      final today = dateOnly(now);
      // Vain unen lähteen syke, jos lähde tiedetään (käyttäjä 20.11.).
      nights.value = await HealthConnect.nightLowHr(
        addDays(today, -34),
        today,
        app: settings.sleepApp ?? sleepData.currentApp,
      );
      _at = now;
    } catch (_) {
      // Ei lupaa tai Health Connect ei vastaa: kortti pysyy piilossa.
    } finally {
      _busy = false;
    }
  }
}

/// Yön alin syke aamuittain: Uni-kortin ollessa päällä unen ajalta (uni.md), muuten klo 21–10.
Map<DateTime, int> nightHrNights() => {
  ...NightHrData.nights.value,
  if (sleepData.enabled)
    for (final n in sleepData.nights.values)
      if (n.lowHr != null) n.day: n.lowHr!,
};

class NightHrCard extends StatelessWidget {
  const NightHrCard({super.key});

  @override
  Widget build(BuildContext context) {
    // Haku taustalla etusivun piirron jälkeen (enintään puolen tunnin välein).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NightHrData.refresh();
      if (sleepData.enabled) sleepData.refresh();
    });
    // Uusi ulkoasu (käyttäjä 18.11., vaihtoehto A): ruudut värireunoin, ⚠ ja ohjeet ? -painikkeen takana.
    return const RecoveryCard();
  }
}

/// Uni (käyttäjä 17.11.; oletus pois, Asetukset → Etusivu): renkaat kuten WHO-rivissä (viime yö ja 7 päivän
/// keskiarvo 7 tunnin suositusta vasten, säännöllisyys), 7 yön pylväät ja vihje. Lähteet: lib/sleep.dart.
class SleepCard extends StatelessWidget {
  const SleepCard({super.key});

  /// Unen väri omaan tavalliseen verrattuna (käyttäjä 18.11.: ei asetettua tavoitetta, vaan oma mediaani):
  /// vihreä enintään 30 min alle tavallisen, keltainen enemmän, punainen 6 h tai alle (Craven 2022; turvaraja,
  /// jottei pitkäaikaisesti lyhyt uni näytä "tavalliselta").
  static Color durationColor(BuildContext context, Duration d, Duration usual) => d <= const Duration(hours: 6)
      ? redText(context)
      : d < usual - const Duration(minutes: 30)
      ? amber(context)
      : greenText(context);

  /// Vertailutaso: oma tavallinen uni (mediaani 8–34 päivää sitten), ennen riittäviä öitä 7 h (AASM 2015).
  static Duration usualOf(SleepStats s) => s.usual ?? const Duration(hours: 7);

  /// Renkaiden ja pylväiden keltainen: kirkkaampi kuin tekstin tumma keltainen (vaaleassa teemassa ruskea).
  static Color amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Sami.yellow : const Color(0xFFE0A100);

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => sleepData.refresh());
    return ListenableBuilder(
      listenable: Listenable.merge([sleepData, NightHrData.nights]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
        final now = DateTime.now();
        final s0 = sleepStats(sleepData.nights, now);
        final ref = usualOf(s0);
        final s = sleepStats(sleepData.nights, now, goal: ref);
        final last = s.last;
        String hm(Duration d) => '${d.inMinutes ~/ 60}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
        String clock(DateTime d) => fmtClock(TimeOfDay.fromDateTime(d));
        final children = <Widget>[
          // Kaksi sovellusta kirjasi saman yön eri arvoin: kysytään kerran, kumpi on oletus (käyttäjä 19.11.).
          if (sleepData.conflict case final c?) _SleepSourceQuestion(nights: c),
        ];
        // Vihje ⚠-kuvakkeena otsikossa (käyttäjä 18.11.: ei tekstilaatikkoa kortissa); napautus näyttää sen.
        (String, Color)? tip;
        if (sleepData.needsPermission) {
          children.addAll([
            Text(t('Salli unitietojen luku Health Connectista.'), style: TextStyle(color: cs.onSurfaceVariant)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('sleepAllow'),
                onPressed: () async {
                  if (await sleepData.requestPermission()) await sleepData.refresh(force: true);
                },
                child: Text(t('Salli')),
              ),
            ),
          ]);
        } else if (last == null) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  if (sleepData.loading)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  Expanded(
                    child: Text(
                      sleepData.loading
                          ? t('Haetaan öitä Health Connectista…')
                          : t('Ei viime öitä. Kortti näyttää unen, kun kello tai sormus kirjaa sen Health Connectiin.'),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          final hint = sleepHint(
            s,
            hrDelta: nightHr(nightHrNights(), now)?.delta,
            goal: ref - const Duration(minutes: 30),
          );
          var (String msg, Color c, IconData icon) = switch (hint) {
            SleepHint.shortAndHr => (
              t('Lyhyt yö ja tavallista korkeampi yösyke: kevyempi päivä tai enemmän varaa sarjoihin.'),
              redText(context),
              Icons.battery_alert_outlined,
            ),
            SleepHint.short => (
              t(
                'Lyhyt yö (6 h tai alle): suorituskyky voi olla heikompi, eniten illalla ja taitoa vaativissa liikkeissä. Jätä enemmän varaa. Aiempi nukkumaanmeno tai lyhyt päiväuni voi auttaa.',
              ),
              yellowText(context),
              Icons.bedtime_outlined,
            ),
            SleepHint.lowWeek => (
              t(
                'Viikon keskiarvo {0}, tavallisesti {1}: tavallista lyhyempi. Aiempi nukkumaanmeno tai lyhyt päiväuni voi auttaa.',
                [fmtDuration((s.avg7 ?? Duration.zero).inMinutes), fmtDuration(ref.inMinutes)],
              ),
              yellowText(context),
              Icons.trending_down,
            ),
            SleepHint.ok => (t('Ei huomautettavaa.'), greenText(context), Icons.check_circle_outline),
          };
          // Myöhäinen kova treeni (käyttäjä 18.11.): selittää lyhyen yön, kun treeni päättyi alle tunti ennen omaa
          // tavallista nukkumaanmenoa. Sykkeen ja lyhyen yön yhdistelmä menee edelle.
          final late = hint == SleepHint.shortAndHr
              ? null
              : lateHardWorkout(s, sleepData.nights, store.workouts, maxHr: hrProfile()?.maxHr(now));
          if (late != null) {
            final mins = late.minutesBefore;
            final args = [
              fmtClock(TimeOfDay.fromDateTime(late.end)),
              mins,
              fmtClock(TimeOfDay.fromDateTime(late.usualBed)),
              fmtDuration(late.asleep.inMinutes),
              fmtDuration(late.usual.inMinutes),
            ];
            msg = mins >= 0
                ? t(
                    'Eilinen kova treeni päättyi {0}, {1} min ennen tavallista nukkumaanmenoasi ({2}). Uni jäi {3} '
                    '(tavallisesti {4}). Kova treeni alle tunti ennen nukkumaanmenoa voi pidentää nukahtamista; '
                    'kevyt iltaliikunta ei haittaa.',
                    args,
                  )
                : t(
                    'Eilinen kova treeni päättyi {0}, tavallisen nukkumaanmenosi ({2}) jälkeen. Uni jäi {3} '
                    '(tavallisesti {4}). Kova treeni alle tunti ennen nukkumaanmenoa voi pidentää nukahtamista; '
                    'kevyt iltaliikunta ei haittaa.',
                    args,
                  );
            c = yellowText(context);
            icon = Icons.nightlight_outlined;
          }
          if (hint != SleepHint.ok || late != null) tip = (msg, c);
          final spread = s.bedSpread == null || s.wakeSpread == null ? null : (s.bedSpread! + s.wakeSpread!) ~/ 2;
          final spreadColor = spread == null
              ? cs.outlineVariant
              : spread <= 30
              ? greenText(context)
              : spread <= 90
              ? amber(context)
              : redText(context);
          children.addAll([
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: RingTile(
                      key: const ValueKey('sleepRingLast'),
                      onTap: () => showSleepStagesSheet(context, last),
                      v: last.asleep.inMinutes / ref.inMinutes,
                      color: durationColor(context, last.asleep, ref),
                      big: hm(last.asleep),
                      small: t('viime yö'),
                    ),
                  ),
                  Expanded(
                    child: RingTile(
                      v: s.avg7 == null ? 0 : s.avg7!.inMinutes / ref.inMinutes,
                      color: s.avg7 == null ? cs.outlineVariant : durationColor(context, s.avg7!, ref),
                      big: s.avg7 == null ? '–' : hm(s.avg7!),
                      small: t('7 pv keskiarvo'),
                    ),
                  ),
                  Expanded(
                    child: RingTile(
                      v: spread == null ? 0 : (1 - spread / 180).clamp(0.05, 1.0),
                      color: spreadColor,
                      big: spread == null ? '–' : '±$spread',
                      small: t('säännöllisyys, min'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${clock(last.bed)}–${clock(last.wake)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (s.usual != null) TextSpan(text: ' · ${t('tavallisesti {0}', [fmtDuration(s.usual!.inMinutes)])}'),
                ],
              ),
              style: sub,
            ),
            const SizedBox(height: 10),
            _SleepBars(nights: sleepData.nights, today: dateOnly(now), usual: ref),
          ]);
        }
        return Card(
          key: const ValueKey('sleepCard'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.bedtime_outlined, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(child: Text(t('Uni'), style: _title)),
                    if (tip != null)
                      IconButton(
                        key: const ValueKey('sleepTip'),
                        tooltip: t('Vihje'),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.warning_amber_rounded, color: tip.$2),
                        onPressed: () => showSleepTip(context, tip!.$1, tip.$2),
                      ),
                    if (last != null && last.app.isNotEmpty) Text(last.app, style: sub),
                  ],
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 7 viimeistä yötä pylväinä omaan tavalliseen verrattuna (värit kuten renkaissa); viiva tavallisen kohdalla.
class _SleepBars extends StatelessWidget {
  final Map<DateTime, SleepNight> nights;
  final DateTime today;
  final Duration usual;
  const _SleepBars({required this.nights, required this.today, required this.usual});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Asteikko 3–10 h, jotta tunnin erot erottuvat (0 h:sta alkaen kaikki pylväät näyttivät yhtä pitkiltä).
    const h = 48.0, minMin = 180, maxMin = 600;
    double hOf(int m) => h * ((m.clamp(minMin, maxMin) - minMin) / (maxMin - minMin)).clamp(0.08, 1.0);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: h - hOf(usual.inMinutes),
          child: Container(height: 1, color: cs.outlineVariant),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 6; i >= 0; i--)
              Expanded(
                child: Builder(
                  builder: (context) {
                    final d = addDays(today, -i);
                    final n = nights[d];
                    final m = n?.asleep.inMinutes ?? 0;
                    final c = SleepCard.durationColor(context, Duration(minutes: m), usual);
                    return Semantics(
                      label: n == null ? null : '${uiWeekdaysShort[d.weekday - 1]} ${fmtDuration(m)}',
                      child: Column(
                        children: [
                          SizedBox(
                            height: h,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 14,
                                height: n == null ? 2 : hOf(m),
                                decoration: BoxDecoration(
                                  color: n == null ? cs.outlineVariant : c,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            uiWeekdaysShort[d.weekday - 1],
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Yöarvot (käyttäjä 17.11.; oletus pois): HRV, leposyke, hengitystiheys, happisaturaatio ja ihon lämpötila
/// ruutuina omaan tasoon verraten, ja yhteinen vihje. Näytettävät arvot: Asetukset → Etusivu.
/// Yöarvo-ruudun pitkien otsikoiden tavutus yhdyssanan saumasta, kun otsikko ei mahdu yhdelle riville.
/// (Saamen sanat tarkistaa puhuja; tavutus vain sanaliitoksesta.)
const tileLabelBreaks = {'Vuoiŋŋastanpulsa': 'Vuoiŋŋastan-\npulsa', 'Vuoiŋŋaheapmi': 'Vuoiŋŋa-\nheapmi'};

/// HRV-vihje (käyttäjä 18.11.: käyttäjän omat tiedot + tutkimus): lyhyt yö ensin, koska se selitti matalan HRV:n
/// selvimmin (alle 6,5 h yöt −0,8 SD omasta tasosta), sitten eilinen kova treeni (1–2 yön lasku on odotettu,
/// Stanley ym. 2013), lopuksi neuvo: kevyempi tai kohtuullinen treeni, liiku silti (Javaloyes 2019, Düking 2021).
/// Ei väitettä palautumisesta, ylikunnosta tai sairaudesta.
String hrvHint(DateTime now) {
  final today = dateOnly(now);
  final last = sleepData.nights[today];
  final usual = sleepStats(sleepData.nights, today).usual;
  final shortNight =
      last != null &&
      (last.asleep < const Duration(hours: 6, minutes: 30) ||
          (usual != null && last.asleep <= usual - const Duration(minutes: 45)));
  final y = addDays(today, -1);
  final hardYesterday = store.workouts.any((w) => w.date == y && hardWorkout(w));
  return [
    t('HRV on ollut kaksi päivää omaa tavallista vaihteluväliäsi alempana.'),
    if (shortNight) t('Viime yö jäi lyhyeksi, mikä laskee HRV:tä usein.'),
    if (hardYesterday) t('Eilinen kova treeni voi laskea HRV:tä yhdeksi tai kahdeksi yöksi; se on odotettua.'),
    t(
      'Harkitse tänään kevyempää tai kohtuullista treeniä kovan sijaan, mutta liiku silti. Muita yleisiä syitä: '
      'sairastuminen, alkoholi, stressi tai matkustus. Ei lääketieteellinen mittaus.',
    ),
  ].join(' ');
}

/// Yöarvo-ruudun otsikon rivikorkeus (sama mittauksessa ja piirrossa).
const tileLabelStrut = StrutStyle(fontSize: 12, height: 1.3, forceStrutHeight: true);

class NightMetricsCard extends StatelessWidget {
  /// Palautuminen-kortin sisällä (käyttäjä 18.11.: HRV osaksi Palautumista): ei omaa korttia eikä otsikkoa, ei
  /// leposykettä (yön alin syke näkyy jo), ja yösykkeen poikkeama [extraFlag] lasketaan yhteiseen vihjeeseen.
  final bool embedded;
  final bool extraFlag;
  const NightMetricsCard({super.key, this.embedded = false, this.extraFlag = false});

  static String label(String k) => switch (k) {
    'hrv' => 'HRV',
    'rest' => t('Leposyke'),
    'rr' => t('Hengitys'),
    'spo2' => t('Happi'),
    _ => t('Lämpö'),
  };

  static IconData icon(String k) => switch (k) {
    'hrv' => Icons.monitor_heart_outlined,
    'rest' => Icons.favorite_border,
    'rr' => Icons.air,
    'spo2' => Icons.water_drop_outlined,
    _ => Icons.thermostat,
  };

  static String value(String k, double v) => switch (k) {
    'hrv' => '${v.round()} ms',
    'rest' => '${v.round()}',
    'rr' => fmtDec(v, 1),
    'spo2' => '${fmtDec(v, 0)} %',
    // Pyöristys ennen etumerkkiä: -0,04 näkyi "-0,0 °C" (testi 18.11.).
    _ => () {
      final r = (v * 10).round() / 10;
      return r == 0 ? '${fmtDec(0, 1)} °C' : '${r > 0 ? '+' : ''}${fmtDec(r, 1)} °C';
    }(),
  };

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => sleepData.refresh());
    return ListenableBuilder(
      listenable: Listenable.merge([sleepData, settings]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
        final now = DateTime.now();
        final keys = [
          for (final k in nightMetricKeys)
            if (settings.nightTiles.contains(k) && !(embedded && k == 'rest')) k,
        ];
        final stats = {for (final k in keys) k: ?metricStat(sleepData.metrics, k, now)};
        final flags = {for (final e in stats.entries) e.key: metricFlag(e.key, e.value)};
        // HRV liputetaan vasta toisena päivänä peräkkäin (yksittäinen matala jakso ei vielä näy).
        if (flags['hrv'] == 1 && !hrvLowSustained(sleepData.metrics, now)) flags['hrv'] = 0;
        final body = flags.entries.where((e) => e.key != 'spo2' && e.value == 1).length + (extraFlag ? 1 : 0);
        final children = <Widget>[];
        if (stats.isEmpty) {
          children.add(
            Text(
              sleepData.loading
                  ? t('Haetaan yöarvoja Health Connectista…')
                  : t('Ei yöarvoja. Kortti näyttää ne, kun kello tai sormus kirjaa ne Health Connectiin.'),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          );
        } else {
          Color col(String k) => switch (flags[k]) {
            1 => k == 'spo2' || body >= 2 ? redText(context) : SleepCard.amber(context),
            0 => greenText(context),
            _ => cs.onSurfaceVariant,
          };
          children.addAll([
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 16) / 3;
                // Pitkä otsikko kahdelle riville yhdyssanan saumasta (käyttäjä 18.11., vaihtoehto B: saameksi
                // "Vuoiŋŋastan-/pulsa"). Jos yksikin otsikko tarvitsee kaksi riviä, kaikkien ruutujen otsikkoalue on
                // saman korkuinen, jotta arvot ja "tav."-rivit pysyvät samalla korkeudella eivätkä hypi.
                final scaler = MediaQuery.textScalerOf(context);
                final labelW = w - 20 - 3 - 18;
                // Kiinteä rivikorkeus (strut): saamen ŋ tulee varafontista, jonka rivi on korkeampi kuin "A":n
                // (testi 18.11.: "Vuoiŋŋa-/heapmi" -otsikon toinen rivi leikkautui).
                TextPainter paint(String s, {int? maxLines}) => TextPainter(
                  text: TextSpan(text: s, style: sub),
                  textDirection: TextDirection.ltr,
                  textScaler: scaler,
                  maxLines: maxLines,
                  strutStyle: tileLabelStrut,
                )..layout(maxWidth: labelW);
                final labels = <String, String>{};
                for (final k in stats.keys) {
                  final l = label(k);
                  if (paint(l, maxLines: 1).didExceedMaxLines) {
                    labels[k] = tileLabelBreaks[l] ?? l;
                  } else {
                    labels[k] = l;
                  }
                }
                var labelH = 0.0;
                for (final l in labels.values) {
                  final h = paint(l, maxLines: 2).height;
                  if (h > labelH) labelH = h;
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in stats.entries)
                      Container(
                        key: ValueKey('nightTile_${e.key}'),
                        width: w,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(left: BorderSide(color: col(e.key), width: 3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(icon(e.key), size: 14, color: col(e.key)),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: SizedBox(
                                    height: labelH,
                                    child: Text(
                                      labels[e.key]!,
                                      key: ValueKey('nightLabel_${e.key}'),
                                      style: sub,
                                      strutStyle: tileLabelStrut,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                value(e.key, e.value.last),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              flags[e.key] == -1
                                  ? t('vertailu 2 viikon jälkeen')
                                  : t('tav. {0}', [value(e.key, metricUsual(e.key, e.value)!)]),
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            _hint(
              context,
              body >= 2
                  ? (
                      t(
                        'Useampi yöarvo poikkeaa tavallisesta: mahdollinen sairastuminen tai kova kuormitus. Kevyt päivä tai lepo.',
                      ),
                      redText(context),
                      Icons.sick_outlined,
                    )
                  : body == 1 && flags['hrv'] == 1
                  ? (hrvHint(now), SleepCard.amber(context), Icons.info_outline)
                  : body == 1
                  ? (
                      t(
                        'Yksi yöarvo poikkeaa tavallisesta. Yksittäinen yö voi johtua esim. alkoholista tai myöhäisestä treenistä; seuraa huomenna.',
                      ),
                      SleepCard.amber(context),
                      Icons.info_outline,
                    )
                  : (t('Yöarvot tavallisella tasolla.'), greenText(context), Icons.check_circle_outline),
            ),
            if (flags['spo2'] == 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _hint(context, (
                  t(
                    'Happisaturaatio tavallista matalampi. Kellon tai sormuksen lukema on suuntaa-antava; jos se toistuu ja olet väsynyt tai kuorsaat, kysy lääkäriltä.',
                  ),
                  redText(context),
                  Icons.water_drop_outlined,
                )),
              ),
          ]);
        }
        if (embedded) {
          return Column(
            key: const ValueKey('nightCard'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              ...children,
              const SizedBox(height: 6),
              Text(
                t(
                  'Omaan tasoosi verrattuna, kun öitä on vähintään 2 viikkoa. Vain vihjeitä, ei diagnoosia. Lähteet: Lisää → Tietoa.',
                ),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          );
        }
        return Card(
          key: const ValueKey('nightCard'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.nights_stay_outlined, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(child: Text(t('Yöarvot'), style: _title)),
                  ],
                ),
                const SizedBox(height: 8),
                ...children,
                const SizedBox(height: 6),
                Text(
                  t(
                    'Omaan tasoosi verrattuna, kun öitä on vähintään 2 viikkoa. Vain vihjeitä, ei diagnoosia. Lähteet: Lisää → Tietoa.',
                  ),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _hint(BuildContext context, (String, Color, IconData) h) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: h.$2.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(h.$3, size: 18, color: h.$2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(h.$1, style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

/// Uni-kortin vihje ⚠-kuvakkeen takana (käyttäjä 18.11.).
Future<void> showSleepTip(BuildContext context, String msg, Color c) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (ctx) => SafeArea(
    child: Padding(
      key: const ValueKey('sleepTipSheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ],
      ),
    ),
  ),
);

/// Uni-kortin kertakysymys: kaksi sovellusta kirjasi saman yön eri arvoin; valinta on oletus tästä eteenpäin
/// (Asetukset → Etusivu → Unen lähde), yksittäisen yön voi vaihtaa kalenterin päivästä.
class _SleepSourceQuestion extends StatelessWidget {
  final List<SleepNight> nights;
  const _SleepSourceQuestion({required this.nights});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = nights.first.day;
    return Container(
      key: const ValueKey('sleepSourceQuestion'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Kaksi sovellusta kirjasi yön {0}: kumpaa käytetään?', [shortDate(day)]),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final n in nights)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OutlinedButton(
                key: ValueKey('sleepSourcePick_${n.app}'),
                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => sleepData.setDefault(n.app),
                child: Row(
                  children: [
                    Expanded(child: Text(n.app, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Text(fmtDuration(n.asleep.inMinutes), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          Text(
            t(
              'Valinta on oletus tästä eteenpäin; muuta: Asetukset → Etusivu → Unen lähde. Yksittäisen yön voi vaihtaa kalenterin päivästä.',
            ),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('sleepSourceLater'),
              onPressed: sleepData.dismissConflict,
              child: Text(t('Pidä automaattinen')),
            ),
          ),
        ],
      ),
    );
  }
}
