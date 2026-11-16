import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../share_text.dart';
import '../l10n.dart';
import 'share_card.dart';

/// Jaa treeni: kuvana, yhteenveto tekstinä tai .md-tiedostona.
Future<void> shareWorkout(BuildContext context, Workout w) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(t('Jaa kuvana')),
            subtitle: Text(t('Siisti kuva treenistä (WhatsApp ym.)')),
            onTap: () => Navigator.pop(ctx, 'image'),
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: Text(t('Jaa yhteenveto')),
            subtitle: Text(t('Liikkeet, parhaat sarjat, ennätykset ja fiilis tekstinä')),
            onTap: () => Navigator.pop(ctx, 'text'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(t('Jaa .md-tiedosto')),
            subtitle: Text(t('Koko treeni tiedostona (aukeaa muistiinpanosovelluksissa)')),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'image') {
    final name = '${isoDate(w.date)}${w.session > 1 ? '-${w.session}' : ''}.png';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareCardScreen(card: WorkoutShareCard(w), fileName: name),
      ),
    );
    return;
  }
  if (choice == 'text') {
    await SharePlus.instance.share(
      ShareParams(
        text: shareText(w),
        subject: '${w.activity != null ? sportName(w.activity!) : trName(w.title)} ${isoDate(w.date)}',
      ),
    );
    return;
  }
  final dir = await getTemporaryDirectory();
  final name = '${isoDate(w.date)}${w.session > 1 ? '-${w.session}' : ''}.md';
  final f = File(p.join(dir.path, name));
  await f.writeAsString(workoutToMarkdown(w));
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(f.path, mimeType: 'text/markdown')],
      subject: name,
    ),
  );
}
