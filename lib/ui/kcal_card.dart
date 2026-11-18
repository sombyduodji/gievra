import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// Kalorit renkaana (käyttäjä 17.11., luonnos A): keskellä kokonaiskulutus, kaari aktiivisten osuus, vieressä
/// aktiiviset ja lepokulutus. Aktiiviset = kokonaiskulutus − oma lepokulutus treenin ajalta (ks. activeKcal).
class KcalRing extends StatelessWidget {
  final int total, active;

  /// Napautus (esim. kellon tietojen muokkaus); null = ei napautettava.
  final VoidCallback? onTap;

  /// Taustaväri näkymän muiden ruutujen mukaan (oletus surfaceContainerHighest).
  final Color? color;
  const KcalRing({super.key, required this.total, required this.active, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = dark ? Sami.yellow : Sami.yellowDark;
    final restColor = cs.onSurfaceVariant.withValues(alpha: .35);
    final rest = math.max(0, total - active);
    final sub = TextStyle(fontSize: 14, color: cs.onSurfaceVariant);
    Widget legend(Color c, String text, {bool strong = false}) => Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text, style: strong ? const TextStyle(fontSize: 16, fontWeight: FontWeight.w700) : sub),
        ),
      ],
    );
    return Semantics(
      label: t('{0} kcal yhteensä, aktiivisia {1}, lepokulutus {2}', [total, active, rest]),
      // Napautus (kellon tietojen muokkaus) myös TalkBackille: excludeSemantics pudotti InkWellin toiminnon.
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: const ValueKey('kcalRing'),
        color: color ?? cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CustomPaint(
                    painter: _RingPainter(total == 0 ? 0 : active / total, activeColor, restColor),
                    child: Center(
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              child: Text(
                                '$total',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.1),
                              ),
                            ),
                            Text('kcal', style: sub.copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      legend(activeColor, t('{0} aktiivisia', [active]), strong: true),
                      const SizedBox(height: 6),
                      legend(restColor, t('{0} lepokulutusta', [rest])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double share;
  final Color active, rest;
  _RingPainter(this.share, this.active, this.rest);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, p..color = rest);
    final s = share.clamp(0.0, 1.0);
    if (s > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * s,
        false,
        p
          ..color = active
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.share != share || old.active != active || old.rest != rest;
}
