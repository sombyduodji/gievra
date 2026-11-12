import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../maps/elevation.dart';
import '../models.dart';

/// Kilometrin vauhti (min/km) tai nopeus (km/h, [speed]); (alku, pituus m, aika s).
String splitText((double, double, double) s, {bool speed = false}) {
  final (_, len, secs) = s;
  if (secs <= 0 || len <= 0) return '–';
  if (speed) return fmtNum((len / secs * 36).round() / 10);
  return fmtPace(secs / len * 1000);
}

/// Reitin korkeusprofiili: nousu, lasku ja käyrä (matka vaaka-akselilla). Korkeus Maanmittauslaitoksen
/// korkeusmallista (ladattu karttojen tapaan alueittain), ei puhelimen GPS:stä.
class ElevationCard extends StatelessWidget {
  final ElevationProfile profile;

  /// Kilometrien alla nopeus (km/h, esim. pyöräily) vauhdin (min/km) sijaan.
  final bool speed;
  const ElevationCard(this.profile, {super.key, this.speed = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final km = profile.points.last.$1 / 1000;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⛰️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  t('Nousu {0} m · Lasku {1} m', [profile.climb.round(), profile.descent.round()]),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            width: double.infinity,
            child: CustomPaint(painter: _ProfilePainter(profile, cs.primary, cs.outlineVariant, cs.outline)),
          ),
          if (profile.splits.length > 1) _splitRow(sub),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(t('{0}–{1} m mpy', [profile.minM.round(), profile.maxM.round()]), style: sub),
              const Spacer(),
              Text('${fmtNum((km * 10).round() / 10)} km', style: sub),
            ],
          ),
          Text(profile.attribution, style: sub.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  /// Tekstin leveys: [every] kilometrin matka (viimeisellä vain jäljellä oleva), vähintään 34 px.
  static double _labelWidth(double maxWidth, double total, double start, int every) =>
      total <= 0 ? 34 : math.max(maxWidth * math.min(1000.0 * every, total - start) / total, 34);

  /// Kilometrien vauhti (tai nopeus) kunkin kilometrin kohdalla; kapeilla kilometreillä vain joka n:s.
  Widget _splitRow(TextStyle sub) => LayoutBuilder(
    builder: (context, box) {
      final total = profile.points.last.$1;
      final splits = profile.splits;
      final perKm = total <= 0 ? 0.0 : box.maxWidth * 1000 / total;
      final every = perKm >= 34 ? 1 : (34 / math.max(perKm, 1)).ceil();
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: SizedBox(
          height: 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < splits.length; i++)
                if (i % every == 0)
                  Positioned(
                    // Viimeinen (vajaa) kilometri ei saa mennä kaavion oikean reunan yli: siirretään vasemmalle.
                    left: math.max(
                      0,
                      math.min(
                        total <= 0 ? 0 : box.maxWidth * splits[i].$1 / total,
                        box.maxWidth - _labelWidth(box.maxWidth, total, splits[i].$1, every),
                      ),
                    ),
                    width: _labelWidth(box.maxWidth, total, splits[i].$1, every),
                    child: Text(
                      splitText(splits[i], speed: speed),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      // Viimeinen vajaa kilometri himmeämpänä (vauhti samassa yksikössä, vertailukelpoinen).
                      style: sub.copyWith(
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: splits[i].$2 < 990 ? sub.color?.withValues(alpha: 0.6) : null,
                        fontStyle: splits[i].$2 < 990 ? FontStyle.italic : null,
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

class _ProfilePainter extends CustomPainter {
  final ElevationProfile p;
  final Color color, grid, kmLine;
  _ProfilePainter(this.p, this.color, this.grid, this.kmLine);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = p.points;
    if (pts.length < 2) return;
    final maxD = pts.last.$1;
    var lo = p.minM, hi = p.maxM;
    if (hi - lo < 20) {
      final mid = (hi + lo) / 2; // tasainen reitti näkyy tasaisena, ei kohinana
      lo = mid - 10;
      hi = mid + 10;
    }
    Offset at((double, double) e) =>
        Offset(maxD <= 0 ? 0 : e.$1 / maxD * size.width, size.height - (e.$2 - lo) / (hi - lo) * size.height);
    final line = Path()..moveTo(at(pts.first).dx, at(pts.first).dy);
    for (final e in pts.skip(1)) {
      final o = at(e);
      line.lineTo(o.dx, o.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = grid);
    // Kilometrien rajat katkoviivoina.
    final dash = Paint()
      ..color = kmLine.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final s in p.splits.skip(1)) {
      final x = maxD <= 0 ? 0.0 : s.$1 / maxD * size.width;
      for (var y = 0.0; y < size.height; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, size.height)), dash);
      }
    }
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ProfilePainter old) => old.p != p;
}

/// Kilometrien vauhti ilman korkeustietoja (alueelle ei ole ladattu korkeustiedostoa tai sitä ei ole saatavilla):
/// palkki ja vauhti (min/km, pyöräilyssä km/h) jokaiselle kilometrille; mitä korkeampi palkki, sitä nopeampi.
class KmSplitsCard extends StatelessWidget {
  final List<(double, double, double)> splits;
  final bool speed;
  const KmSplitsCard(this.splits, {super.key, this.speed = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final speeds = [for (final (_, len, secs) in splits) secs > 0 ? len / secs : 0.0];
    final top = speeds.fold<double>(0, math.max);
    final low = speeds.where((v) => v > 0).fold<double>(top, math.min);
    final total = splits.fold<double>(0, (a, s) => a + s.$2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Kilometrit'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              final perKm = total <= 0 ? 0.0 : box.maxWidth * 1000 / total;
              final every = perKm >= 34 ? 1 : (34 / math.max(perKm, 1)).ceil();
              return Column(
                children: [
                  SizedBox(
                    height: 60,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < splits.length; i++)
                          Expanded(
                            flex: math.max(1, splits[i].$2.round()),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1),
                              child: FractionallySizedBox(
                                // Hitain 35 %, nopein täysi korkeus: erot näkyvät, mutta mikään palkki ei katoa.
                                heightFactor: top <= low
                                    ? 1
                                    : 0.35 + 0.65 * ((speeds[i] - low) / (top - low)).clamp(0, 1),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: splits[i].$2 < 990 ? 0.35 : 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      for (var i = 0; i < splits.length; i++)
                        Expanded(
                          flex: math.max(1, splits[i].$2.round()),
                          child: i % every == 0
                              ? Text(
                                  splitText(splits[i], speed: speed),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                  softWrap: false,
                                  style: sub.copyWith(
                                    fontSize: 11,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                    color: splits[i].$2 < 990 ? sub.color?.withValues(alpha: 0.6) : null,
                                    fontStyle: splits[i].$2 < 990 ? FontStyle.italic : null,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Text(speed ? t('km/h kilometreittäin') : t('min/km kilometreittäin, ilman taukoja'), style: sub),
        ],
      ),
    );
  }
}
