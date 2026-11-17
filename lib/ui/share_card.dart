import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../exercises.dart';
import '../l10n.dart';
import '../models.dart';
import '../program.dart';
import '../session_compare.dart';
import '../share_text.dart' show thousands;
import '../theme.dart';
import 'widgets.dart' show BarTitle, shortDate;

// Jaa kuvana (käyttäjä 16.11.: "WhatsApp ym., kauniisti, kuvakaappauksen tyyliin"). Kortti näytetään ensin
// esikatseluna, ja Jaa tekee siitä PNG-kuvan (3 × tarkkuus) jakovalikkoon. Kortti on aina vaalea, ettei
// kuva muutu puhelimen teeman mukaan. Muistiinpanoja ei laiteta kuvaan (yksityisiä).

const _ink = Color(0xFF1B1B1F);
const _sub = Color(0xFF5F5F6B);
const _paper = Color(0xFFFFFCF6);
const _line = Color(0xFFE9E3D8);

/// Kortin runko: Sámi-värinauha, otsikko, sisältö ja Gievra-alaviite.
class _CardFrame extends StatelessWidget {
  final String emoji, title, subtitle;
  final List<Widget> children;
  const _CardFrame({required this.emoji, required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    width: 360,
    decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: DefaultTextStyle(
      style: const TextStyle(color: _ink, fontSize: 14, height: 1.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [for (final c in Sami.all) Expanded(child: Container(height: 8, color: c))],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: _sub)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                const Text(
                  'Gievra',
                  style: TextStyle(fontWeight: FontWeight.w800, color: Sami.red),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t('treenipäiväkirja'), style: const TextStyle(fontSize: 12, color: _sub)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Pieni tilastopala (kesto, sarjat, kilot …).
Widget _stat(String value, String label) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  decoration: BoxDecoration(color: const Color(0xFFF3EEE4), borderRadius: BorderRadius.circular(14)),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(fontSize: 11, color: _sub)),
    ],
  ),
);

/// Treeni kuvana: tilastot ja liikkeet sarjoineen, ennätykset 🏆.
class WorkoutShareCard extends StatelessWidget {
  final Workout w;
  const WorkoutShareCard(this.w, {super.key});

  @override
  Widget build(BuildContext context) {
    final feel = feelingOf(w.feeling);
    final when = shortDate(w.date);
    if (w.activity != null) {
      return _CardFrame(
        emoji: '🏃',
        title: sportName(w.activity!),
        subtitle: when,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (durationText(w) case final d?) _stat(d, t('kesto')),
              if (w.distanceKm != null) _stat('${fmtNum(w.distanceKm!)} km', t('matka')),
              if (w.pace case final pace?) _stat(pace, t('vauhti')),
              if (w.steps != null) _stat(thousands(w.steps!), t('askelta')),
              if (w.hrAvg != null) _stat('${w.hrAvg}', t('keskisyke')),
              if (w.kcal != null) _stat('${w.kcal}', 'kcal'),
              if (feel != null) _stat(feel.$2, t(feel.$3)),
            ],
          ),
        ],
      );
    }
    final moves = w.exercises.where((e) => e.sets.isNotEmpty).toList();
    final sets = moves.fold(0, (a, e) => a + e.workSets.length);
    final vol = workVolume(w);
    return _CardFrame(
      emoji: '💪',
      title: trName(w.title),
      subtitle: when,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Sama kesto kuin treenin näkymässä (sekunnit, jos tallessa; yötesti 17.11.: kuvassa "1 min", näkymässä 0:33).
            if (durationText(w) case final d?) _stat(d, t('kesto')),
            _stat('$sets', t(sets == 1 ? 'sarja' : 'sarjaa')),
            if (vol > 0) _stat('${thousands(vol.round())} kg', t('volyymi')),
            if (feel != null) _stat(feel.$2, t(feel.$3)),
          ],
        ),
        const SizedBox(height: 12),
        for (final e in moves)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exerciseLabel(e.name), style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(fmtSetsUnit(e.name, e.workSets), style: const TextStyle(fontSize: 13, color: _sub)),
                    ],
                  ),
                ),
                if (e.sets.any((s) => s.pr)) const Text('🏆', style: TextStyle(fontSize: 18)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ohjelma kuvana: päivät liikkeineen (sarjat × toistot, vaihtoehdot).
class ProgramShareCard extends StatelessWidget {
  final Program program;
  const ProgramShareCard(this.program, {super.key});

  String _target(PlanItem i) => switch (i.kind) {
    'H' => t('raskas, viikon mukaan'),
    'V' => t('volyymi, viikon mukaan'),
    _ =>
      '${i.sets} × ${i.lo == i.hi ? i.lo : '${i.lo}–${i.hi}'}'
          '${measureOf(i.exercise) == Measure.reps ? '' : ' ${t(measureOf(i.exercise).unit)}'}',
  };

  @override
  Widget build(BuildContext context) => _CardFrame(
    emoji: '📋',
    title: program.displayTitle.split(' · ').first,
    subtitle: program.plan.length == 1 ? t('1 päivä viikossa') : t('{0} päivää viikossa', [program.plan.length]),
    children: [
      for (final (k, d) in program.plan.indexed) ...[
        if (k > 0) const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Sami.all[k % Sami.all.length].withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(d.uiName, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            Text(t('~{0} min', [estimateMinutes(d.items).round()]), style: const TextStyle(fontSize: 12, color: _sub)),
          ],
        ),
        const SizedBox(height: 4),
        for (final i in d.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exerciseLabel(i.exercise), style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (i.alts.isNotEmpty)
                        Text(
                          t('tai: {0}', [i.alts.map(exerciseLabel).join(', ')]),
                          style: const TextStyle(fontSize: 12, color: _sub),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(_target(i), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    ],
  );
}

/// Esikatselu ja jako: kortti näkyy sellaisenaan, Jaa tekee siitä kuvan.
class ShareCardScreen extends StatefulWidget {
  final Widget card;
  final String fileName;
  final String? text;
  const ShareCardScreen({super.key, required this.card, required this.fileName, this.text});

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  /// Kortti PNG:ksi (myös näytön ulkopuolelle jäävä osa: koko kortti on piirretty).
  Future<File> _render() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await shareDir();
    final f = File(p.join(dir.path, widget.fileName));
    await f.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    return f;
  }

  Future<void> _share() async {
    if (_busy) return; // tuplanapautus: yksi jakovalikko
    setState(() => _busy = true);
    try {
      final f = await _render();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(f.path, mimeType: 'image/png')],
          text: widget.text,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Kuvan jakaminen epäonnistui.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: BarTitle(Text(t('Jaa kuvana'))), bottom: samiBarBand),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                // Kuvaan vain kortti (ei taustaa); kortti on aina vaalea.
                child: RepaintBoundary(
                  key: _key,
                  child: MediaQuery.withNoTextScaling(child: widget.card),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('shareImage'),
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.share),
                label: Text(t('Jaa')),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Jaa ohjelma: kuvana (WhatsApp ym.) tai ohjelmapohjana (.gmd), jonka vastaanottaja voi tuoda Gievraan.
Future<void> shareProgram(BuildContext context, Program program) async {
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
            subtitle: Text(t('Siisti kuva viikon päivistä ja liikkeistä (WhatsApp ym.)')),
            onTap: () => Navigator.pop(ctx, 'image'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(t('Jaa ohjelmapohjana (.gmd)')),
            subtitle: Text(t('Vastaanottaja voi ottaa ohjelman käyttöön omassa Gievrassaan')),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final name = program.displayTitle.split(' · ').first;
  // Enintään 80 merkkiä: pitkä nimi (saamen kirjaimet 2 tavua) ylitti tiedostonimen 255 tavun rajan (yötesti 17.11.).
  final safe = name.replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '').characters.take(80).toString().trim();
  final base = safe.isEmpty ? 'gievra' : safe;
  if (choice == 'image') {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareCardScreen(card: ProgramShareCard(program), fileName: '$base.png'),
      ),
    );
    return;
  }
  final dir = await shareDir();
  final f = File(p.join(dir.path, '$base.$templateExtension'));
  await f.writeAsBytes(utf8.encode(programToTemplate(program, name: name)), flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/octet-stream')]));
}

/// Jaettavien kuvien ja pohjien kansio välimuistissa. Yli tunnin vanhat aiemmat jaot poistetaan (yötesti 17.11.:
/// treenikuvat sykkeineen jäivät välimuistiin); tuoreet jätetään, koska vastaanottava sovellus voi vielä lukea niitä.
Future<Directory> shareDir({DateTime? now}) async {
  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'share'))..createSync(recursive: true);
  cleanShareDir(dir, now: now);
  return dir;
}

@visibleForTesting
void cleanShareDir(Directory dir, {DateTime? now}) {
  final limit = (now ?? DateTime.now()).subtract(const Duration(hours: 1));
  for (final f in dir.listSync().whereType<File>()) {
    try {
      if (f.lastModifiedSync().isBefore(limit)) f.deleteSync();
    } catch (_) {}
  }
}
