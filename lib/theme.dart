import 'package:flutter/material.dart';

/// Saamen lipun värit.
class Sami {
  static const red = Color(0xFFD52B1E);
  static const blue = Color(0xFF0035AD);
  static const green = Color(0xFF007229);
  static const yellow = Color(0xFFFFCE00);
  static const all = [red, green, yellow, blue];
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: Sami.red, brightness: b).copyWith(
    primary: Sami.red,
    onPrimary: Colors.white,
    secondary: Sami.yellow,
    onSecondary: Colors.black,
    tertiary: Sami.green,
    // Valitut sirut ja tonal-napit: keltainen sävy (oletus olisi punaisesta johdettu ruskea).
    secondaryContainer: dark ? const Color(0xFF3B3514) : const Color(0xFFFFEFB0),
    onSecondaryContainer: dark ? const Color(0xFFFFE680) : const Color(0xFF2A2400),
    onTertiary: Colors.white,
    surface: dark ? const Color(0xFF0F1420) : const Color(0xFFF6F4EF),
    onSurface: dark ? const Color(0xFFEEF1F7) : const Color(0xFF151A26),
    onSurfaceVariant: dark ? const Color(0xFF8A94A8) : const Color(0xFF5D6677),
    surfaceContainer: dark ? const Color(0xFF181F2E) : Colors.white,
    surfaceContainerHigh: dark ? const Color(0xFF222B3D) : const Color(0xFFEAE7E0),
    outlineVariant: dark ? const Color(0xFF263047) : const Color(0xFFDDD9D0),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: scheme.surfaceContainer),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
  );
}

/// Gáktin reunuksesta lainattu nauha: lipun värit ja siksak-kuvio.
class SamiBand extends StatelessWidget {
  final double height;
  final bool pattern;
  const SamiBand({super.key, this.height = 10, this.pattern = true});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BandPainter(pattern)),
    ),
  );
}

class _BandPainter extends CustomPainter {
  final bool pattern;
  _BandPainter(this.pattern);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / Sami.all.length;
    for (var i = 0; i < Sami.all.length; i++) {
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w + 1, size.height), Paint()..color = Sami.all[i]);
    }
    if (!pattern) return;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()..moveTo(0, size.height);
    const step = 12.0;
    for (var x = 0.0; x < size.width; x += step) {
      path
        ..lineTo(x + step / 2, size.height * .2)
        ..lineTo(x + step, size.height);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _BandPainter old) => old.pattern != pattern;
}

/// Lipun aurinko/kuu-ympyrä: vasen puoli punainen, oikea sininen.
/// Sovelluksen logo: käytetty valurautainen kahvakuula (tools/make_logo.py).
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/logo_app.png', width: size, height: size, filterQuality: FilterQuality.medium);
}
