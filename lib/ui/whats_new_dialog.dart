import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../auto_backup.dart';
import '../l10n.dart';
import '../whats_new.dart';

// "Uutta tässä versiossa" kerran päivityksen jälkeen. OK kuittaa, eikä ikkuna tule uudelleen ennen kuin
// uudempi versio tuo uusia ominaisuuksia. Uusi asennus ei näe sitä (aloitus esittelee sovelluksen).

const _seenKey = 'whatsNewSeen';

/// Ensimmäinen versio, jossa tämä ikkuna on: aiemmilta versioilta päivittäneet ovat nähneet kaiken tätä vanhemman.
const _firstWithDialog = '0.6.2';

/// Näyttää uudet ominaisuudet, jos niitä on näkemättä. [version] testeille (muuten sovelluksen versio).
Future<void> maybeShowWhatsNew(BuildContext context, {String? version}) async {
  final current = version ?? AutoBackup.shortVersion((await PackageInfo.fromPlatform()).version);
  final sp = await SharedPreferences.getInstance();
  var seen = sp.getString(_seenKey);
  if (seen == null) {
    // Uusi asennus (ei treenejä): ei uutisia, kaikki on uutta. Muuten päivitys aiemmasta versiosta.
    if (store.workouts.isEmpty) {
      await sp.setString(_seenKey, current);
      return;
    }
    seen = _firstWithDialog;
  }
  final items = unseenFeatures(current, seen);
  if (items.isEmpty) {
    if (compareVersions(current, seen) > 0) await sp.setString(_seenKey, current);
    return;
  }
  if (!context.mounted) return;
  await showWhatsNew(context, items, current);
  await sp.setString(_seenKey, current);
}

/// Uudet ominaisuudet listana; OK sulkee.
Future<void> showWhatsNew(BuildContext context, List<NewFeature> items, String version) => showDialog<void>(
  context: context,
  builder: (ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return AlertDialog(
      title: Text(t('Uutta versiossa {0}', [version])),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(f.icon, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t(f.title), style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(t(f.text), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    );
  },
);
