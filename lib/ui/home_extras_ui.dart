import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../health.dart';
import '../exercises.dart' show exerciseDisplay;
import '../home_extras.dart';
import '../l10n.dart';
import '../models.dart';
import '../program_edit.dart' show suggestDay;
import '../theme.dart';
import 'start_panels.dart' show showGymPanel;

const _title = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

/// Viikkoputki (käyttäjä 17.11.): montako viikkoa peräkkäin WHO:n molemmat suositukset täyttyivät, paras putki ja
/// viimeiset 8 viikkoa pisteinä.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = whoStreak(store.workouts, DateTime.now(), pauses: settings.pauses);
    if (store.workouts.isEmpty) return const SizedBox.shrink();
    final open = s.weeks.last.$2 == WeekMark.open;
    return Card(
      key: const ValueKey('streakCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('Viikkoputki'), style: _title),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${s.current}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.current == 1
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
              open
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

  static bool get available => !kIsWeb && !isDemo && Platform.isAndroid && settings.hcImport;

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
      if (await HealthConnect.status() != 'available' || !await HealthConnect.granted()) return;
      final today = dateOnly(now);
      nights.value = await HealthConnect.nightLowHr(addDays(today, -34), today);
      _at = now;
    } catch (_) {
      // Ei lupaa tai Health Connect ei vastaa: kortti pysyy piilossa.
    } finally {
      _busy = false;
    }
  }
}

class NightHrCard extends StatelessWidget {
  const NightHrCard({super.key});

  @override
  Widget build(BuildContext context) {
    // Haku taustalla etusivun piirron jälkeen (enintään puolen tunnin välein).
    WidgetsBinding.instance.addPostFrameCallback((_) => NightHrData.refresh());
    return _build(context);
  }

  Widget _build(BuildContext context) => ValueListenableBuilder(
    valueListenable: NightHrData.nights,
    builder: (context, nights, _) {
      final n = nightHr(nights, DateTime.now());
      if (n == null) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final d = n.delta;
      final (String msg, Color c) = d == null
          ? (t('Vertailu tavalliseen tasoon, kun öitä on viikon verran.'), cs.onSurfaceVariant)
          : d >= 5
          ? (
              t(
                'Selvästi tavallista korkeampi: palautuminen voi olla kesken (sairaus, rasitus, alkoholi, huono uni). Kevyempi päivä?',
              ),
              redText(context),
            )
          : d >= 3
          ? (t('Hieman tavallista korkeampi.'), yellowText(context))
          : (t('Tavallisella tasolla.'), greenText(context));
      String bpm(num v) => '${v.round()}';
      return Card(
        key: const ValueKey('nightHrCard'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('Palautuminen'), style: _title),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(bpm(n.last), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(t('bpm, yön alin syke'), style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                  if (n.base != null)
                    Text(
                      t('Tavallisesti {0}', [bpm(n.base!)]),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(msg, style: TextStyle(fontSize: 13, color: c)),
              const SizedBox(height: 2),
              Text(
                t(
                  '3 viimeisen yön keskiarvo {0}; tavallinen = mediaani 28 yöstä. Kellon yöllä mittaamasta sykkeestä.',
                  [bpm(n.recent)],
                ),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    },
  );
}
