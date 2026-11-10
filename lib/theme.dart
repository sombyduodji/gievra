import 'package:flutter/material.dart';

/// Saamen lipun värit.
class Sami {
  static const red = Color(0xFFD52B1E);
  static const blue = Color(0xFF0035AD);
  static const green = Color(0xFF007229);
  static const yellow = Color(0xFFFFCE00);
  static const all = [red, green, yellow, blue];

  /// Punainen tekstinä tummassa teemassa: lipun punainen jää tummalla pohjalla himmeäksi (2,8–3,7:1,
  /// pieni teksti vaatii 4,5:1), joten teksteissä vaaleampi sävy (5,9–7,7:1). Täytöt pysyvät lipun punaisina.
  static const redLight = Color(0xFFFF8378);

  /// Sama vihreälle: lipun vihreä tummalla pohjalla 2,3–3,0:1, vaaleampi 7,3–9,5:1.
  static const greenLight = Color(0xFF5BD08A);

  /// Vaaleassa teemassa punainen tekstinä hieman tummempana: dialogin pohjalla lipun punainen 4,1:1, tämä 4,8:1.
  static const redDark = Color(0xFFC0261B);

  /// Sininen tekstinä tummassa teemassa: lipun sininen 1,4–1,9:1, tämä 6,2–8,1:1.
  static const blueLight = Color(0xFF8FA8FF);

  /// Keltainen tekstinä vaaleassa teemassa: lipun keltainen 1,2–1,5:1, tämä 5,1–6,3:1.
  static const yellowDark = Color(0xFF7A5C00);
}

/// Punainen tekstin väri teeman mukaan (vaaleassa [Sami.redDark], tummassa [Sami.redLight]).
Color redText(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Sami.redLight : Sami.redDark;

/// Sininen tekstin väri teeman mukaan (tummassa [Sami.blueLight]).
Color blueText(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Sami.blueLight : Sami.blue;

/// Keltainen tekstin (ja pienen kuvakkeen) väri teeman mukaan (vaaleassa [Sami.yellowDark]).
Color yellowText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Sami.yellow : Sami.yellowDark;

/// Vihreä tekstin väri teeman mukaan (vaaleassa lipun vihreä, tummassa [Sami.greenLight]).
Color greenText(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Sami.greenLight : Sami.green;

/// Varoitus korostettuna: punertava pohja, lähes valkoinen (tai tummanpunainen) teksti ja punainen reuna.
/// Pienet punaiset varoitustekstit (vältettävä liike, tauko, lasku) erottuvat näin kummassakin teemassa.
class RedNote extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight? weight;
  final int? maxLines;

  /// Pilleri (ympäri reunus) tai rivi (vasen reuna).
  final bool pill;
  final TextAlign? textAlign;
  const RedNote(
    this.text, {
    super.key,
    this.fontSize = 11,
    this.weight,
    this.maxLines,
    this.pill = false,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = BorderSide(color: Sami.red, width: pill ? 1 : 3);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pill ? 10 : 6, vertical: pill ? 2 : 1),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3A1E22) : const Color(0xFFFBE0DC),
        borderRadius: BorderRadius.circular(pill ? 999 : 4),
        border: pill ? Border.fromBorderSide(border) : Border(left: border),
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: dark ? const Color(0xFFFFD2CC) : const Color(0xFF8E1A10),
        ),
      ),
    );
  }
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
  // Tekstinä käytettävä punainen (tekstipainikkeet, kehyspainikkeet, kentän otsikko, kalenterin tänään).
  final textRed = dark ? Sami.redLight : Sami.redDark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: textRed)),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (s) => TextStyle(
          color: s.contains(WidgetState.error)
              ? scheme.error
              : s.contains(WidgetState.focused)
              ? textRed
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : textRed,
      ),
    ),
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
        foregroundColor: textRed,
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
