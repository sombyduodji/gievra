import 'package:flutter/material.dart';

import '../l10n.dart';
import '../session_compare.dart' show fmtDuration;
import '../sleep.dart';
import 'widgets.dart' show SectionLabel, WordFitText, fmtClock;

// Univaiheet (käyttäjä 23.11.): unen napautus näyttää yön vaiheet Health Connectista. Vain näyttö, unen määrä
// lasketaan kuten ennenkin (yö miinus hereillä), eikä tiedostoihin tallenneta mitään.

/// Yön [night] univaiheet: haetaan Health Connectista, kun ruutu avautuu.
class SleepStagesBox extends StatefulWidget {
  final SleepNight night;
  final Future<List<SleepSession>> Function(DateTime, DateTime)? source;
  const SleepStagesBox({super.key, required this.night, this.source});

  @override
  State<SleepStagesBox> createState() => _SleepStagesBoxState();
}

class _SleepStagesBoxState extends State<SleepStagesBox> {
  late final Future<SleepStages?> _f = nightStages(widget.night, source: widget.source).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    return FutureBuilder<SleepStages?>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t('Haetaan univaiheita…'), style: sub),
          );
        }
        final s = snap.data;
        if (s == null || s.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t('Tälle yölle ei ole univaiheita Health Connectissa.'), style: sub),
          );
        }
        final total = s.asleep.inMinutes;
        String pct(Duration d) => total <= 0 ? '' : ' · ${(d.inMinutes * 100 / total).round()} %';
        Widget row(String label, Duration d, {bool share = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              if (color != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => WordFitText(label, style: const TextStyle(), width: c.maxWidth),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    '${fmtDuration(d.inMinutes)}${share ? pct(d) : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
        const purple = Color(0xFF8E7CC3), blue = Color(0xFF5B8DEF), light = Color(0xFF9EC5FE);
        final grey = cs.outline;
        return Column(
          key: const ValueKey('sleepStages'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(t('Univaiheet')),
            if (s.light > Duration.zero) row(t('Kevyt uni'), s.light, share: true, color: light),
            if (s.deep > Duration.zero) row(t('Syvä uni'), s.deep, share: true, color: blue),
            if (s.rem > Duration.zero) row(t('REM-uni'), s.rem, share: true, color: purple),
            if (s.sleeping > Duration.zero) row(t('Uni, vaihe ei tiedossa'), s.sleeping, share: true, color: light),
            row(t('Univaiheet yhteensä'), s.asleep),
            const Divider(height: 14),
            row(t('Hereillä'), s.awake, color: grey),
            if (s.outOfBed > Duration.zero) row(t('Poissa sängystä'), s.outOfBed, color: grey),
            if (s.unknown > Duration.zero) row(t('Tuntematon vaihe'), s.unknown, color: grey),
            if (s.uncovered.inMinutes > 0) row(t('Ei vaihetta'), s.uncovered, color: grey),
            row(t('Sängyssä'), s.span),
            const SizedBox(height: 6),
            Text(
              t(
                'Gievran uni: sängyssä {0} − hereillä = {1}. Unisovellus voi laskea lyhyet heräämiset uneksi, '
                'joten sen luku voi olla hieman suurempi.',
                [fmtDuration(s.span.inMinutes), fmtDuration(widget.night.asleep.inMinutes)],
              ),
              style: sub,
            ),
          ],
        );
      },
    );
  }
}

/// Viime yön univaiheet omana paneelinaan (Uni-kortin "viime yö" -renkaan napautus).
Future<void> showSleepStagesSheet(BuildContext context, SleepNight night) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('Uni'), style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${fmtDuration(night.asleep.inMinutes)} · ${_clock(night.bed)}–${_clock(night.wake)}'
            '${night.app.isEmpty ? '' : ' · ${night.app}'}',
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
          SleepStagesBox(night: night),
        ],
      ),
    ),
  ),
);

String _clock(DateTime d) => fmtClock(TimeOfDay.fromDateTime(d));
