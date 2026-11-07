import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../models.dart';
import '../theme.dart';
import '../l10n.dart';

const fiMonths = [
  'Tammikuu',
  'Helmikuu',
  'Maaliskuu',
  'Huhtikuu',
  'Toukokuu',
  'Kesäkuu',
  'Heinäkuu',
  'Elokuu',
  'Syyskuu',
  'Lokakuu',
  'Marraskuu',
  'Joulukuu',
];
const seMonths = [
  'ođđajagemánnu',
  'guovvamánnu',
  'njukčamánnu',
  'cuoŋománnu',
  'miessemánnu',
  'geassemánnu',
  'suoidnemánnu',
  'borgemánnu',
  'čakčamánnu',
  'golggotmánnu',
  'skábmamánnu',
  'juovlamánnu',
];
const fiWeekdays = ['maanantai', 'tiistai', 'keskiviikko', 'torstai', 'perjantai', 'lauantai', 'sunnuntai'];
const fiWeekdaysShort = ['ma', 'ti', 'ke', 'to', 'pe', 'la', 'su'];

/// Pohjoissaamen viikonpäivät (ma–su).
const seWeekdaysShort = ['vu', 'ma', 'ga', 'du', 'be', 'lá', 'so'];
const seWeekdays = ['vuossárga', 'maŋŋebárga', 'gaskavahkku', 'duorastat', 'bearjadat', 'lávvardat', 'sotnabeaivi'];

/// Saamenkielinen päiväys: "lávvardat, skábmamánu 7. beaivi" (kuukausi genetiivissä + järjestysluku + beaivi,
/// kuten Sámedikki kalentereissa: "Skábmamánu 16.–20. b."). Sanat tarkistettu Divvunin oikolukijalla.
String seDate(DateTime d) =>
    '${seWeekdays[d.weekday - 1]}, ${seMonths[d.month - 1].replaceFirst(RegExp(r'mánnu$'), 'mánu')} ${d.day}. beaivi';

/// Tervehdys on aina saameksi käyttöliittymän kielestä riippumatta.
String seGreeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h >= 5 && h < 10) return 'Buorre iđit';
  if (h >= 10 && h < 17) return 'Buorre beaivi';
  if (h >= 17 && h < 23) return 'Buorre eahket';
  return 'Buorre idja';
}

/// Vuorokaudenajan mukainen tervehdys suomeksi (käytössä, jos saamenkielistä ei haluta).
String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 5) return t('Hyvää yötä');
  if (h < 10) return t('Hyvää huomenta');
  if (h < 12) return t('Hyvää aamupäivää');
  if (h < 18) return t('Hyvää päivää');
  if (h < 22) return t('Hyvää iltaa');
  return t('Hyvää yötä');
}

/// "perjantai 6. marraskuuta"
/// Saamenkielisessä käyttöliittymässä saamenkielinen päiväys (seDate).
String longDate(DateTime d) =>
    isSami ? seDate(d) : '${fiWeekdays[d.weekday - 1]} ${d.day}. ${fiMonths[d.month - 1].toLowerCase()}ta';

/// Päiväys vuoden kanssa: "lauantai 7. marraskuuta 2026" / "lávvardat 7.11.2026".
String longDateYear(DateTime d) =>
    isSami ? '${seWeekdays[d.weekday - 1]} ${d.day}.${d.month}.${d.year}' : '${longDate(d)} ${d.year}';

/// Kalenterin viikonpäivälyhenteet.
List<String> get uiWeekdaysShort => isSami ? seWeekdaysShort : fiWeekdaysShort;

/// Kuukauden nimi otsikkoon: "Marraskuu" / "skábmamánnu".
String uiMonth(int month) => isSami ? seMonths[month - 1] : fiMonths[month - 1];

/// "pe 6.11."
String shortDate(DateTime d) => '${uiWeekdaysShort[d.weekday - 1]} ${d.day}.${d.month}.';

/// Iso +/- -säädin. Arvoa napauttamalla voi kirjoittaa luvun.
class ValueStepper extends StatelessWidget {
  final String value;
  final String unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onTap;
  const ValueStepper({
    super.key,
    required this.value,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(IconData i, VoidCallback f) => SizedBox.square(
      dimension: 52,
      child: IconButton.filledTonal(
        onPressed: f,
        icon: Icon(i),
        style: IconButton.styleFrom(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          btn(Icons.remove, onMinus),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: '  ${t(unit)}',
                        style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          btn(Icons.add, onPlus),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 12, letterSpacing: .6, color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// Kysyy luvun näppäimistöllä. Palauttaa null, jos peruttiin.
Future<double?> askNumber(BuildContext context, String title, double current, {bool decimals = true}) async {
  final c = TextEditingController(text: fmtNum(current));
  final r = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: decimals),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimals ? r'[0-9.,]' : r'[0-9]'))],
        onSubmitted: (v) => Navigator.pop(ctx, parseNum(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(c.text)), child: const Text('OK')),
      ],
    ),
  );
  return r;
}

/// Viisi fiilisnappia (😫 … 🤩). Uusi napautus samaan poistaa valinnan.
class FeelingPicker extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const FeelingPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final (v, emoji, label) in feelings) ...[
          if (v != 1) const SizedBox(width: 6),
          Expanded(
            child: Material(
              color: value == v ? Sami.yellow.withValues(alpha: .18) : cs.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: value == v ? Sami.yellow : Colors.transparent, width: 2),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(value == v ? null : v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Text(
                        emoji,
                        style: TextStyle(
                          fontSize: 26,
                          color: value == null || value == v ? null : cs.onSurface.withValues(alpha: .4),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(t(label), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Kielivalinta (aloitus ja ☰ → Asetukset): liuskapainikkeet lippujen kanssa. Suomi on oletus;
/// pohjoissaame on kokeellinen, ja siitä varoitetaan ennen vaihtoa. Kielten nimet omalla kielellään.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  Future<void> _choose(BuildContext context, String code) async {
    if (code == uiLang) return;
    if (code == 'se') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const LangFlag('se', width: 36),
          title: const Text('Davvisámegiella · geahččaleapmi'),
          content: const Text(
            'Pohjoissaamenkielinen käyttöliittymä on kokeellinen. Kaikkea ei ole vielä käännetty: '
            'liikkeiden ja lajien nimet ja liikeohjeet ovat suomeksi, ja käännökset odottavat vielä '
            'natiivipuhujan tarkistusta. Treenitiedostot pysyvät suomeksi.\n\n'
            'Sámegiel geavahanlávdi lea geahččaleapmi. Buot ii leat vel jorgaluvvon: hárjehusaid ja '
            'valáštallamiid namat leat ain suomagillii.\n\nJatketaanko? · Joatkitgo?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ei · Ii')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kyllä · Juo')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await settings.setLang(code);
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: settings, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in uiLanguages)
            Material(
              color: uiLang == l.code ? cs.surface : Colors.transparent,
              elevation: uiLang == l.code ? 1 : 0,
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => _choose(context, l.code),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LangFlag(l.code),
                      const SizedBox(width: 8),
                      Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pieni lippu kielivalintaan (piirretty, ei kuvatiedostoa): Suomi ja saamen lippu.
class LangFlag extends StatelessWidget {
  final String code;
  final double width;
  const LangFlag(this.code, {super.key, this.width = 24});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    // Saamen lippu omissa mittasuhteissaan (808:600), ettei ympyrä veny; muut 3:2.
    height: code == 'se' ? width * 600 / 808 : width * 2 / 3,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(2),
      boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.outlineVariant, spreadRadius: 1)],
    ),
    clipBehavior: Clip.antiAlias,
    child: CustomPaint(painter: _FlagPainter(code)),
  );
}

class _FlagPainter extends CustomPainter {
  final String code;
  _FlagPainter(this.code);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    Paint p(Color col) => Paint()..color = col;
    if (code == 'se') {
      // Saamen lippu Wikimedia Commonsin mukaan (File:Sami_flag.svg, public domain; mitat ja värit
      // Saamelaiskäräjiltä), leveys 808: punainen 0–258, vihreä 258–314, keltainen 314–370, sininen 370–808.
      // Ympyrän keskipiste vihreän ja keltaisen rajalla (314), säde 176/600 korkeudesta, viiva 32/600:
      // punaisella puolella sininen, sinisellä puolella punainen.
      const red = Color(0xFFDC241F), blue = Color(0xFF0035AD), green = Color(0xFF007229), yellow = Color(0xFFFFCE00);
      double x(double v) => w * v / 808;
      c.drawRect(Rect.fromLTWH(0, 0, w, h), p(blue));
      c.drawRect(Rect.fromLTWH(0, 0, x(370), h), p(yellow));
      c.drawRect(Rect.fromLTWH(0, 0, x(314), h), p(green));
      c.drawRect(Rect.fromLTWH(0, 0, x(258), h), p(red));
      final r = Rect.fromCircle(center: Offset(x(314), h / 2), radius: h * 176 / 600);
      Paint ring(Color col) => Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 32 / 600
        ..color = col;
      c.drawArc(r, math.pi / 2, math.pi, false, ring(blue));
      c.drawArc(r, -math.pi / 2, math.pi, false, ring(red));
    } else {
      // Suomen lippu: valkoinen, sininen risti (18:11 → tässä 3:2).
      const blue = Color(0xFF002F6C);
      c.drawRect(Rect.fromLTWH(0, 0, w, h), p(Colors.white));
      c.drawRect(Rect.fromLTWH(w * .28, 0, w * .17, h), p(blue));
      c.drawRect(Rect.fromLTWH(0, h * .37, w, h * .26), p(blue));
    }
  }

  @override
  bool shouldRepaint(covariant _FlagPainter old) => old.code != code;
}

/// Liikkeen nimi ja asetuksen mukaan englanninkielinen nimi pienellä sen alla.
class ExName extends StatelessWidget {
  final String name;
  final TextStyle? style;
  const ExName(this.name, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final en = englishOf(name);
    if (en == null || settings.moveNames == 'en') return Text(en ?? name, style: style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: style),
        Text('($en)', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Treenitila: Sali / Kestävyys / Molemmat (asetukset ja aloituskysely).
class TrainModePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const TrainModePicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    showSelectedIcon: false,
    segments: [
      for (final (v, icon, l) in [
        ('gym', Icons.fitness_center, t('Sali')),
        ('cardio', Icons.directions_run, t('Kestävyys')),
        ('both', Icons.sync_alt, t('Molemmat')),
      ])
        ButtonSegment(
          value: v,
          icon: Icon(icon, size: 18),
          label: FittedBox(fit: BoxFit.scaleDown, child: Text(l, maxLines: 1)),
        ),
    ],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.first),
  );
}
