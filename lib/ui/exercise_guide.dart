import 'package:flutter/material.dart';

import '../anim/cue_lang.dart';
import '../anim/figure.dart';
import '../anim/motions.dart';
import '../exercises.dart';
import '../l10n.dart';
import '../theme.dart';
import 'widgets.dart';

/// Onko liikkeelle animaatio tai vinkit (liikevalitsimen ▶-painike).
bool hasExerciseGuide(String name) => exerciseMotions[name] != null || cuesFor(name).isNotEmpty;

/// Liikkeen ohje liikevalitsimesta (käyttäjä 16.11.: "animaatio, miten liike tehdään, myös liikettä valitessa"):
/// sama animaatio ja vinkit kuin sarjanäkymän ohjeessa. [pickButton]: Valitse tämä liike -painike.
/// Palauttaa true, kun liike valittiin.
Future<bool> showExerciseGuide(BuildContext context, String name, {bool pickButton = true}) async {
  final picked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final sub = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
      final motion = exerciseMotions[name];
      final cues = cuesFor(name);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            Text(exerciseLabel(name), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(t('Näin teet'), style: sub),
            if (motion != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(child: FigureAnimation(motion: motion, size: 200)),
              ),
            if (cues.isNotEmpty)
              LangNotice(
                healthTextLang == 'en'
                    ? t('Ei saatavilla saameksi: liikevinkit näkyvät englanniksi.')
                    : t('Ei saatavilla saameksi: liikevinkit näkyvät suomeksi.'),
                show: isSami,
              ),
            for (final c in cues)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: TextStyle(color: yellowText(ctx))),
                    Expanded(child: Text(c, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              t(
                '⚠️ Kokeellinen: animaatio ja vinkit ovat suuntaa antavia eikä niitä ole vielä tarkistanut '
                'ammattilainen. Varmista oikea tekniikka valmentajalta tai fysioterapeutilta ennen kuin '
                'nostat raskaita painoja. Jos ohje näyttää oudolta, kerro siitä: Lisää → Ilmoita ongelmasta.',
              ),
              style: sub,
            ),
            if (pickButton) ...[
              const SizedBox(height: 14),
              FilledButton(
                key: const ValueKey('pickFromGuide'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('Valitse tämä liike')),
              ),
            ],
          ],
        ),
      );
    },
  );
  return picked == true;
}
