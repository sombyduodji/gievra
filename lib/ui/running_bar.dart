import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../heart_rate.dart';
import '../l10n.dart';
import '../models.dart';
import '../ongoing.dart';
import '../sports.dart';
import '../theme.dart';
import 'home.dart' show openPendingActivity, openWorkout;

/// Kesken oleva treeni alapalkin yläpuolella kaikilla välilehdillä (käyttäjä 17.11.): kesken lenkin voi katsoa
/// kalenteria, ohjelmaa ja vanhoja treenejä, ja palkista palataan takaisin. Liikunta (ajanotto tai GPS), jonka
/// näkymästä poistuttiin Takaisin-painikkeella, tai tämän päivän keskeneräinen salitreeni.
class RunningBar extends StatefulWidget {
  /// Etusivun iso kortti (Sali / Liikunta -aloituksen tilalla) palkin sijaan.
  final bool big;
  const RunningBar({super.key, this.big = false});

  /// Taustalle jäänyt liikunta tai keskeneräinen salitreeni: etusivu näyttää aloituksen tilalla Jatka-kortin.
  static bool active(DateTime now) =>
      (AwayActivity.away && (Ongoing.gps ?? Ongoing.activity) != null) ||
      Ongoing.gymInProgress(store.workouts, now) != null;

  @override
  State<RunningBar> createState() => _RunningBarState();
}

class _RunningBarState extends State<RunningBar> {
  Timer? _tick;
  bool _opening = false;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Kello käy vain palkin näkyessä.
  void _ticking(bool on) {
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on) {
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _open(Workout? gym) async {
    if (_opening) return; // tuplanapautus ei avaa kahta näkymää
    _opening = true;
    try {
      if (gym != null) {
        openWorkout(context, gym);
      } else {
        await openPendingActivity(context);
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AwayActivity.changes, store, hr]),
      builder: (context, _) {
        final now = DateTime.now();
        final a = AwayActivity.away ? (Ongoing.gps ?? Ongoing.activity) : null;
        final gym = a == null ? Ongoing.gymInProgress(store.workouts, now) : null;
        final show = a != null || gym != null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ticking(show);
        });
        if (!show) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final String icon, title, time;
        if (a != null) {
          icon = sportOf(a.sport)?.icon ?? '🏃';
          title = sportName(a.sport);
          time = a.note != null
              ? a.note!
              : a.paused
              ? t('tauolla · {0}', [fmtDurationSec(a.elapsed.inSeconds)])
              : fmtDurationSec(now.difference(a.since!).inSeconds);
        } else {
          icon = '💪';
          title = t('Salitreeni');
          time = fmtDurationSec(now.difference(gym!.started!).inSeconds);
        }
        final bpm = hr.recording ? hr.bpm : null;
        final parts = [time, if (bpm != null) '♥ $bpm'];
        if (widget.big) return _card(context, cs, icon, title, parts, gym);
        return Semantics(
          button: true,
          label: t('{0} käynnissä, {1}. Jatka', [title, parts.join(', ')]),
          excludeSemantics: true,
          child: Material(
            key: const ValueKey('runningBar'),
            color: Sami.green.withValues(alpha: .22),
            child: InkWell(
              onTap: () => _open(gym),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.4,
                  child: Row(
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title, // palkissa vain laji: "käynnissä" katkaisi pitkät nimet; kello kertoo, että treeni on käynnissä
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            Text(
                              parts.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _open(gym),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(t('Jatka')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Etusivun kortti: iso kello ja yksi Jatka-painike (Sali- ja Liikunta-aloitukset palaavat, kun treeni on valmis).
  Widget _card(BuildContext context, ColorScheme cs, String icon, String title, List<String> parts, Workout? gym) =>
      Card(
        key: const ValueKey('runningCard'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t('{0} käynnissä', [title]),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                parts.join(' · '),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  // Vaaleassa teemassa tumma keltainen: kirkas keltainen valkoisella ei erotu (tarkistus 17.11.).
                  color: yellowText(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('runningContinue'),
                style: FilledButton.styleFrom(
                  backgroundColor: Sami.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                onPressed: () => _open(gym),
                icon: const Icon(Icons.play_arrow_rounded, size: 28),
                label: Text(t('Jatka treeniä')),
              ),
              const SizedBox(height: 8),
              Text(
                t('Uuden treenin voi aloittaa, kun tämä on valmis.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
}
