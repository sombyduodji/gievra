import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../exercises.dart';
import '../l10n.dart';
import '../models.dart';
import '../picker_guard.dart';

// Oman liikkeen ehdotus Gievraan (käyttäjä 16.11.): samaan tapaan kuin ongelmailmoitus, sähköpostina kehittäjälle.
// Kysytään vain kerran liikettä kohden ja vasta treenin jälkeen (ei kesken treenin). Käsin liikevalitsimesta
// (omat liikkeet) milloin tahansa. Viestissä vain liikkeen tiedot (nimi, kategoria, mittaus, lihakset, kuvaus),
// ei treenejä eikä henkilötietoja. Kun liike myöhemmin tulee Gievraan, oma liike yhdistetään siihen
// (custom_merge.dart): treenit, ohjelma ja ennätykset siirtyvät, ja mukaan tulevat ohje ja animaatio.

const _askedKey = 'suggest_own_asked';
const _channel = MethodChannel('fi.somby.gievra/email');

/// Treenin jälkeen: omat liikkeet, joista ei ole vielä kysytty. Kysytään kerran (vastauksesta riippumatta).
Future<void> maybeSuggestOwnExercises(BuildContext context, Workout w) async {
  if (isDemo) return;
  final own = {
    for (final e in w.exercises)
      if (e.sets.isNotEmpty && settings.customExercises.contains(e.name)) e.name,
  };
  if (own.isEmpty) return;
  final sp = await SharedPreferences.getInstance();
  final asked = {...?sp.getStringList(_askedKey)};
  final ask = own.where((n) => !asked.contains(n)).toList();
  if (ask.isEmpty || !context.mounted) return;
  await sp.setStringList(_askedKey, [...asked, ...ask]);
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Ehdotetaanko liikettä Gievraan?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              'Lisäsit oman liikkeen: {0}. Jos se puuttuu Gievrasta, voit ehdottaa sitä kehittäjälle. Valmiina '
              'liikkeenä siihen tulisi liikeohje, animaatio ja painoehdotukset, ja treenisi siirtyisivät sille.',
              [ask.join(', ')],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('Kysytään vain kerran. Voit ehdottaa myöhemmin liikevalitsimesta (omat liikkeet, 💡).'),
            style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Ei kiitos'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Ehdota'))),
      ],
    ),
  );
  if (go == true && context.mounted) await suggestExercises(context, ask);
}

/// Ehdotuksen viesti: valinnainen kuvaus ja liikkeiden tiedot sähköpostisovellukseen (Android) tai jakoon.
Future<void> suggestExercises(BuildContext context, List<String> names) async {
  final desc = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(t('Ehdota liikettä Gievraan')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(names.join(', '), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          // Kysymys omana tekstinään: kentän otsikkona saamenkielinen katkesi ("Makkár láhkai hárjehus d…").
          Text(t('Miten liike tehdään? (valinnainen)')),
          TextField(
            key: const ValueKey('suggestDesc'),
            controller: desc,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: t('Esim. välineet, asento, mihin se tuntuu')),
          ),
          const SizedBox(height: 8),
          Text(
            t('Sähköpostisovellus avautuu valmiilla viestillä. Mukana vain liikkeen tiedot, ei treenejäsi.'),
            style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Peruuta'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Avaa sähköposti'))),
      ],
    ),
  );
  final text = desc.text.trim();
  desc.dispose();
  if (ok != true) return;
  final version = (await PackageInfo.fromPlatform()).version;
  final subject = 'Gievra $version: ${t('liike-ehdotus')} – ${names.join(', ')}';
  final body = [
    t('Liike-ehdotus [exercise]'),
    '',
    for (final n in names) ...[
      '${t('Nimi')}: $n',
      '${t('Kategoria')}: ${t(settings.customCategory[n] ?? ownCategory)}',
      '${t('Mitataan')}: ${t(measureOf(n).label)}',
      if (settings.customMuscles[n] case final m? when m.isNotEmpty)
        '${t('Lihakset')}: ${m.map((x) => x == 'vatsa' ? t('keskivartalo') : t(x)).join(', ')}',
      '',
    ],
    if (text.isNotEmpty) ...[text, ''],
    '---',
    'Gievra $version · ${isEnglish ? 'en' : (isSami ? 'se' : 'fi')}',
  ].join('\n');
  try {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('send', {
        'to': AppInfo.feedbackEmail,
        'subject': subject,
        'body': body,
        'paths': <String>[],
      });
    } else {
      await pickOnce(
        () => SharePlus.instance.share(ShareParams(text: '${AppInfo.feedbackEmail}\n\n$body', subject: subject)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Virhe: {0}', [errorText(e)]))));
    }
  }
}
