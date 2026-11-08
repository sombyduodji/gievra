import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

// Sivukuvan tikku-ukko liikeohjeisiin. Kaikki kulmat asteina, absoluuttisina segmentin suuntina:
// 0 = suoraan alas, 90 = eteenpäin (oikealle, katseen suuntaan), 180 = suoraan ylös, -90 = taaksepäin.
// Esim. seisova: vartalo 180, reisi 0, sääri 0, olkavarsi 0, kyynärvarsi 0.

enum Anchor { feet, hip, hands }

enum Implement { none, barbell, dumbbell, cable, machine, kettlebell }

class Pose {
  final double torso, thigh, shin, arm, fore;
  final double? thigh2, shin2, arm2, fore2; // toinen raaja (askelkyykky, kävely); oletus sama
  final double armLen; // olkavarren näkyvä pituus (1 = koko; alle 1, kun käsivarsi osoittaa sivulle kohti katsojaa)
  final Offset anchorAt; // kiinnityspiste (0..1 × 0..1), lattia y = 0.92
  const Pose({
    this.torso = 180,
    this.thigh = 0,
    this.shin = 0,
    this.arm = 0,
    this.fore = 0,
    this.thigh2,
    this.shin2,
    this.arm2,
    this.fore2,
    this.armLen = 1,
    this.anchorAt = const Offset(.5, .92),
  });

  static double _l(double a, double b, double t) => a + (b - a) * t;
  static double? _ln(double? a, double? b, double fa, double fb, double t) =>
      a == null && b == null ? null : _l(a ?? fa, b ?? fb, t);

  Pose lerp(Pose o, double t) => Pose(
    torso: _l(torso, o.torso, t),
    thigh: _l(thigh, o.thigh, t),
    shin: _l(shin, o.shin, t),
    arm: _l(arm, o.arm, t),
    fore: _l(fore, o.fore, t),
    thigh2: _ln(thigh2, o.thigh2, thigh, o.thigh, t),
    shin2: _ln(shin2, o.shin2, shin, o.shin, t),
    arm2: _ln(arm2, o.arm2, arm, o.arm, t),
    fore2: _ln(fore2, o.fore2, fore, o.fore, t),
    armLen: _l(armLen, o.armLen, t),
    anchorAt: Offset.lerp(anchorAt, o.anchorAt, t)!,
  );
}

/// Kiinteä apuväline kuvassa (penkki, tanko, laatikko, taljan pylväs).
class Prop {
  final Rect? rect; // penkki, laatikko (0..1-koordinaatit)
  final double rotate; // penkin kallistus asteina (vinopenkki)
  final Offset? barFrom, barTo; // leuanvetotanko tms. viiva
  const Prop({this.rect, this.rotate = 0, this.barFrom, this.barTo});
}

class Motion {
  final Anchor anchor;
  final Pose start, end;
  final Implement implement;
  final Offset? cableFrom; // taljan väkipyörä
  final List<Prop> props;
  final bool bothArmsHold; // tanko molemmissa käsissä (piirretään yksi levy)
  final double seconds; // yksi toisto
  final double scale; // pienennys lattian keskipisteen ympäri, jotta pään yli -liikkeet mahtuvat

  /// Kädet (tanko) kulkevat suoraa linjaa alku- ja loppuasennon välillä, ja kyynärpää lasketaan siitä
  /// (punnerrukset: tanko ei kaarra sivulle, vaikka olkavarren kulma muuttuu paljon).
  final bool straightHands;
  const Motion({
    required this.anchor,
    required this.start,
    required this.end,
    this.implement = Implement.none,
    this.cableFrom,
    this.props = const [],
    this.bothArmsHold = true,
    this.seconds = 2.4,
    this.scale = .8,
    this.straightHands = false,
  });

  /// Asento hetkellä t (0 = alku, 1 = loppu).
  Pose at(double t) {
    final p = start.lerp(end, t);
    if (!straightHands) return p;
    // Ranteen paikka olkapäästä: suora viiva alku- ja loppuasennon välillä.
    Offset wrist(Pose q) => _dir(q.arm) * _arm * q.armLen + _dir(q.fore) * _fore;
    final w0 = wrist(start), w1 = wrist(end);
    final target = w0 + (w1 - w0) * t;
    // Kyynärvarsi pysyy alku- ja loppuasennon suunnassa (punnerruksissa lähes pystyssä, kyynärpää tangon alla).
    // Olkavarsi osoittaa liikkeen keskellä sivulle, joten sivukuvassa se näkyy lyhyempänä.
    final elbow = target - _dir(p.fore) * _fore;
    final len = elbow.distance;
    double arm, fore = p.fore, armLen;
    if (len <= _arm) {
      arm = len < 1e-3 ? p.arm : _deg(elbow);
      armLen = (len / _arm).clamp(.05, 1.0);
    } else {
      (arm, fore) = _reach(target, p.fore);
      armLen = 1;
    }
    return Pose(
      torso: p.torso,
      thigh: p.thigh,
      shin: p.shin,
      arm: arm,
      fore: fore,
      thigh2: p.thigh2,
      shin2: p.shin2,
      armLen: armLen,
      anchorAt: p.anchorAt,
    );
  }
}

double _deg(Offset v) => math.atan2(v.dx, v.dy) * 180 / math.pi;

/// Kahden nivelen käänteiskinematiikka: olkavarren ja kyynärvarren kulmat, joilla ranne on pisteessä [v]
/// (olkapäästä). Kahdesta ratkaisusta valitaan se, jossa kyynärvarsi on lähimpänä tavallista suuntaa
/// [foreHint] (punnerruksissa kyynärvarsi pysyy lähes pystyssä ja kyynärpää tangon alla).
(double, double) _reach(Offset v, double foreHint) {
  final d = v.distance.clamp((_arm - _fore).abs() + 1e-4, _arm + _fore - 1e-4);
  final phi = _deg(v);
  final cosA = ((_arm * _arm + d * d - _fore * _fore) / (2 * _arm * d)).clamp(-1.0, 1.0);
  final alpha = math.acos(cosA) * 180 / math.pi;
  double diff(double a) => ((a - foreHint + 540) % 360 - 180).abs();
  (double, double) sol(double arm) => (arm, _deg(v - _dir(arm) * _arm));
  final s1 = sol(phi + alpha), s2 = sol(phi - alpha);
  return diff(s1.$2) <= diff(s2.$2) ? s1 : s2;
}

// Segmenttien pituudet (kuvan korkeus = 1).
const _torso = .30, _thigh = .24, _shin = .24, _arm = .16, _fore = .15, _head = .055, _neck = .03;

Offset _dir(double deg) {
  final r = deg * math.pi / 180;
  return Offset(math.sin(r), math.cos(r));
}

class Joints {
  final Offset hip, shoulder, head, knee, ankle, knee2, ankle2, elbow, wrist, elbow2, wrist2;
  Joints(
    this.hip,
    this.shoulder,
    this.head,
    this.knee,
    this.ankle,
    this.knee2,
    this.ankle2,
    this.elbow,
    this.wrist,
    this.elbow2,
    this.wrist2,
  );
}

Joints solve(Pose p, Anchor a) {
  // Lasketaan lantiosta ja siirretään niin, että kiinnityspiste osuu paikalleen.
  const hip0 = Offset.zero;
  final sh = hip0 + _dir(p.torso) * _torso;
  final head = sh + _dir(p.torso) * (_neck + _head);
  final kn = hip0 + _dir(p.thigh) * _thigh;
  final an = kn + _dir(p.shin) * _shin;
  final kn2 = hip0 + _dir(p.thigh2 ?? p.thigh) * _thigh;
  final an2 = kn2 + _dir(p.shin2 ?? p.shin) * _shin;
  final el = sh + _dir(p.arm) * _arm * p.armLen;
  final wr = el + _dir(p.fore) * _fore;
  final el2 = sh + _dir(p.arm2 ?? p.arm) * _arm * p.armLen;
  final wr2 = el2 + _dir(p.fore2 ?? p.fore) * _fore;
  final ref = switch (a) {
    Anchor.feet => an,
    Anchor.hip => hip0,
    Anchor.hands => wr,
  };
  final d = p.anchorAt - ref;
  return Joints(hip0 + d, sh + d, head + d, kn + d, an + d, kn2 + d, an2 + d, el + d, wr + d, el2 + d, wr2 + d);
}

class FigurePainter extends CustomPainter {
  final Motion m;
  final double t; // 0..1..0 (edestakaisin)
  final Color body, faint, floor;
  FigurePainter(this.m, this.t, {required this.body, required this.faint, required this.floor});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final ox = (size.width - s) / 2;
    final k = m.scale;
    // Skaalaus lattian keskipisteen (0.5, 0.925) ympäri: lattia pysyy paikallaan.
    Offset P(Offset o) => Offset(ox + (.5 + (o.dx - .5) * k) * s, (.925 + (o.dy - .925) * k) * s);
    final pose = m.at(t);
    final j = solve(pose, m.anchor);

    // Lattia
    canvas.drawLine(
      P(const Offset(.05, .925)),
      P(const Offset(.95, .925)),
      Paint()
        ..color = floor
        ..strokeWidth = 2,
    );
    // Apuvälineet
    final propPaint = Paint()..color = faint.withValues(alpha: .5);
    for (final pr in m.props) {
      if (pr.rect != null) {
        final r = Rect.fromPoints(P(pr.rect!.topLeft), P(pr.rect!.bottomRight));
        canvas.save();
        canvas.translate(r.center.dx, r.center.dy);
        canvas.rotate(pr.rotate * math.pi / 180);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height),
            const Radius.circular(4),
          ),
          propPaint,
        );
        canvas.restore();
      }
      if (pr.barFrom != null) {
        canvas.drawLine(
          P(pr.barFrom!),
          P(pr.barTo!),
          Paint()
            ..color = faint
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    // Talja
    if (m.cableFrom != null) {
      canvas.drawCircle(P(m.cableFrom!), s * .018 * k, Paint()..color = faint);
      canvas.drawLine(
        P(m.cableFrom!),
        P(j.wrist),
        Paint()
          ..color = faint
          ..strokeWidth = 1.5,
      );
    }

    final w = s * .028 * k;
    Paint line(Color c, [double k = 1]) => Paint()
      ..color = c
      ..strokeWidth = w * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Kaukaiset raajat himmeämpinä
    final far = line(faint);
    canvas.drawPath(
      Path()
        ..moveTo(P(j.hip).dx, P(j.hip).dy)
        ..lineTo(P(j.knee2).dx, P(j.knee2).dy)
        ..lineTo(P(j.ankle2).dx, P(j.ankle2).dy),
      far,
    );
    canvas.drawPath(
      Path()
        ..moveTo(P(j.shoulder).dx, P(j.shoulder).dy)
        ..lineTo(P(j.elbow2).dx, P(j.elbow2).dy)
        ..lineTo(P(j.wrist2).dx, P(j.wrist2).dy),
      far,
    );
    // Vartalo ja lähimmät raajat
    final near = line(body);
    canvas.drawLine(P(j.hip), P(j.shoulder), line(body, 1.25));
    canvas.drawPath(
      Path()
        ..moveTo(P(j.hip).dx, P(j.hip).dy)
        ..lineTo(P(j.knee).dx, P(j.knee).dy)
        ..lineTo(P(j.ankle).dx, P(j.ankle).dy),
      near,
    );
    // Jalkaterät: aina kohtisuoraan sääreen nähden varpaiden puolelle (seistessä eteen, reiden ojennuksessa ja
    // selinmakuulla ylös, punnerrusasennossa lattiaa kohti). Ei hyppäystä asennosta toiseen.
    for (final (kn, a) in [(j.knee2, j.ankle2), (j.knee, j.ankle)]) {
      final d = a - kn;
      final len = d.distance == 0 ? 1.0 : d.distance;
      final foot = a + Offset(d.dy, -d.dx) / len * .055;
      canvas.drawLine(P(a), P(foot), kn == j.knee ? near : far);
    }
    canvas.drawCircle(P(j.head), s * _head * k, Paint()..color = body);
    canvas.drawPath(
      Path()
        ..moveTo(P(j.shoulder).dx, P(j.shoulder).dy)
        ..lineTo(P(j.elbow).dx, P(j.elbow).dy)
        ..lineTo(P(j.wrist).dx, P(j.wrist).dy),
      near,
    );

    // Väline käsissä
    switch (m.implement) {
      case Implement.barbell:
        canvas.drawCircle(P(j.wrist), s * .075 * k, Paint()..color = Sami.red);
        canvas.drawCircle(P(j.wrist), s * .05 * k, Paint()..color = Sami.blue);
        canvas.drawCircle(P(j.wrist), s * .015 * k, Paint()..color = Sami.yellow);
      case Implement.dumbbell:
        for (final wr in [j.wrist2, j.wrist]) {
          canvas.drawCircle(
            P(wr),
            s * .032 * k,
            Paint()..color = wr == j.wrist ? Sami.red : Sami.red.withValues(alpha: .5),
          );
        }
      case Implement.cable:
        canvas.drawCircle(P(j.wrist), s * .016 * k, Paint()..color = Sami.yellow);
      case Implement.kettlebell:
        // Kahva kädessä, kuula roikkuu kyynärvarren jatkeena.
        final dirv = j.wrist - j.elbow;
        final u = dirv / dirv.distance;
        // Kyynärvarsi ylöspäin (etuasento, pään yli): kuula lepää ranteen takana kyynärvartta vasten.
        final c = u.dy < -.5 ? j.wrist + const Offset(-.034, .012) : j.wrist + u * .045;
        canvas.drawCircle(
          P(j.wrist),
          s * .016 * k,
          Paint()
            ..color = Sami.red
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * .008 * k,
        );
        canvas.drawCircle(P(c), s * .034 * k, Paint()..color = Sami.red);
      case Implement.machine:
        canvas.drawCircle(P(j.wrist), s * .02 * k, Paint()..color = Sami.blue);
      case Implement.none:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant FigurePainter old) => old.t != t || old.m != m || old.body != body;
}

/// Toistuva animaatio: alku -> loppu -> alku, pehmeä kiihdytys.
class FigureAnimation extends StatefulWidget {
  final Motion motion;
  final double size;
  const FigureAnimation({super.key, required this.motion, this.size = 220});
  @override
  State<FigureAnimation> createState() => _FigureAnimationState();
}

class _FigureAnimationState extends State<FigureAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (widget.motion.seconds * 1000).round()),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: FigurePainter(
            widget.motion,
            Curves.easeInOut.transform(_c.value),
            body: cs.onSurface,
            faint: cs.onSurfaceVariant,
            floor: cs.outlineVariant,
          ),
        ),
      ),
    );
  }
}
