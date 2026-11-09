import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../maps/elevation.dart';
import '../models.dart';

/// Reitin korkeusprofiili: nousu, lasku ja käyrä (matka vaaka-akselilla). Korkeus Maanmittauslaitoksen
/// korkeusmallista (ladattu karttojen tapaan alueittain), ei puhelimen GPS:stä.
class ElevationCard extends StatelessWidget {
  final ElevationProfile profile;

  /// Kilometrien alla nopeus (km/h, esim. pyöräily) vauhdin (min/km) sijaan.
  final bool speed;
  const ElevationCard(this.profile, {super.key, this.speed = false});

  String _split((double, double, double) s) {
    final (_, len, secs) = s;
    if (secs <= 0 || len <= 0) return '–';
    if (speed) return fmtNum((len / secs * 36).round() / 10);
    return fmtPace(secs / len * 1000);
  }

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
              Text(
                t('Nousu {0} m · Lasku {1} m', [profile.climb.round(), profile.descent.round()]),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
          Text(elevAttribution, style: sub.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

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
                    left: total <= 0 ? 0 : box.maxWidth * splits[i].$1 / total,
                    width: math.max(perKm * every, 34),
                    child: Text(
                      _split(splits[i]),
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
