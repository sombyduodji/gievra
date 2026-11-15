import 'package:flutter/material.dart';

import '../rest.dart';
import '../theme.dart';
import '../exercises.dart' show exerciseLabel;
import '../l10n.dart';
import 'hr_ui.dart';
import 'widgets.dart' show textScale;

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Palautusajastin sarjan jälkeen: jäljellä oleva aika, −15 s / +15 s ja Ohita (peruu ajastimen).
/// Näkyy vain, kun ajastin on käynnissä (☰ → Asetukset → Palautusajastin).
class RestBanner extends StatelessWidget {
  const RestBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: rest,
    builder: (context, _) {
      if (!rest.running) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final left = rest.remaining;
      // Sykkeen mukaan: aika kuluu ylöspäin (palkki täyttyy kohti 5 min muistutusta); muuten lähtölaskenta.
      final byHr = rest.byHr;
      final frac = rest.total == 0 ? 0.0 : ((byHr ? rest.elapsed : left) / rest.total).clamp(0.0, 1.0);
      final big = textScale(context) > 1.05;
      // Yhdellä rivillä myös saameksi (Vuoiŋŋasteapmi): pienennetään tarvittaessa.
      final title = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          t('Palautus {0}', [_mmss(byHr ? rest.elapsed : left)]),
          maxLines: 1,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      );
      // Suositus ja syke (sykevyö): palautuminen näkyy tauon aikana.
      final subtitle = Row(
        children: [
          Flexible(
            child: Text(
              byHr
                  ? t('sykkeen mukaan · {0}', [exerciseLabel(rest.exercise)])
                  : t('suositus {0} · {1}', [_mmss(rest.total), exerciseLabel(rest.exercise)]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
      final adjust = [
        TextButton(onPressed: () => rest.adjust(-15), child: const Text('−15 s')),
        TextButton(onPressed: () => rest.adjust(15), child: const Text('+15 s')),
      ];
      final close = IconButton(tooltip: t('Ohita palautus'), onPressed: rest.stop, icon: const Icon(Icons.close));
      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(color: Sami.blue.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
          child: Column(
            mainAxisSize: MainAxisSize.min, // alapalkki: vain sisällön korkuinen
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!big)
                Row(
                  children: [
                    const Text('⏱', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, subtitle]),
                    ),
                    ...adjust,
                    close,
                  ],
                )
              else ...[
                // Suuri teksti (Asetukset → Tekstin koko): otsikko omalle rivilleen, ±15 s alariville, jotta otsikko
                // ei kutistu painikkeiden vieressä.
                Row(
                  children: [
                    const Text('⏱', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: title),
                    close,
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: subtitle),
                    ...adjust,
                  ],
                ),
              ],
              // Sykevyö: syke, suunta ja valmius seuraavaan sarjaan.
              const HrRecovery(),
              // Seuraava sarja omalla rivillään koko leveydeltä (painikkeiden vieressä teksti katkeaisi).
              if (rest.next case final next?)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Text(
                    next,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                // Kuvana: jäljellä oleva aika on tekstinä yllä (ruudunlukija ei lue nimetöntä prosenttia).
                child: ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(3),
                    color: blueText(context),
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
