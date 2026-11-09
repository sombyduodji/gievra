import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../models.dart';
import '../sports.dart';
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

const enWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const enWeekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const enMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "perjantai 6. marraskuuta" / "Friday, November 6"
/// Saamenkielisessä käyttöliittymässä saamenkielinen päiväys (seDate).
String longDate(DateTime d) => isSami
    ? seDate(d)
    : isEnglish
    ? '${enWeekdays[d.weekday - 1]}, ${enMonths[d.month - 1]} ${d.day}'
    : '${fiWeekdays[d.weekday - 1]} ${d.day}. ${fiMonths[d.month - 1].toLowerCase()}ta';

/// Päiväys vuoden kanssa: "lauantai 7. marraskuuta 2026" / "lávvardat 7.11.2026" / "Saturday, November 7, 2026".
String longDateYear(DateTime d) => isSami
    ? '${seWeekdays[d.weekday - 1]} ${d.day}.${d.month}.${d.year}'
    : isEnglish
    ? '${longDate(d)}, ${d.year}'
    : '${longDate(d)} ${d.year}';

/// Kalenterin viikonpäivälyhenteet.
List<String> get uiWeekdaysShort => isSami
    ? seWeekdaysShort
    : isEnglish
    ? enWeekdaysShort
    : fiWeekdaysShort;

/// Kuukauden nimi otsikkoon: "Marraskuu" / "skábmamánnu" / "November".
String uiMonth(int month) => isSami
    ? seMonths[month - 1]
    : isEnglish
    ? enMonths[month - 1]
    : fiMonths[month - 1];

/// Numeerinen päiväys: "6.11." / "11/6", vuoden kanssa "6.11.2026" / "11/6/2026".
String numDate(DateTime d, {bool year = false}) =>
    isEnglish ? '${d.month}/${d.day}${year ? '/${d.year}' : ''}' : '${d.day}.${d.month}.${year ? d.year : ''}';

/// "pe 6.11." / "Fri 11/6"
String shortDate(DateTime d) => isEnglish
    ? '${uiWeekdaysShort[d.weekday - 1]} ${d.month}/${d.day}'
    : '${uiWeekdaysShort[d.weekday - 1]} ${d.day}.${d.month}.';

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
      // Ilmoitus käyttöliittymän nykyisellä kielellä (suomi tai englanti) ja saameksi.
      final en = isEnglish;
      // Vammatilan ohjeita ei ole saameksi: valinta suomi/englanti heti tässä (myös aloituksessa).
      var health = en ? 'en' : settings.healthLang;
      final scroll = ScrollController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            icon: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, color: Sami.red, size: 32),
                SizedBox(width: 10),
                LangFlag('se', height: 28),
              ],
            ),
            title: const Text('Davvisámegiella · geahččaleapmi'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Scrollbar(
                    controller: scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: const EdgeInsets.only(right: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Sami.red.withValues(alpha: .10),
                              border: Border.all(color: Sami.red, width: 1.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              en
                                  ? 'WARNING: Not everything is translated. Injury mode guidance is not available in Sámi: '
                                        'choose below whether it is shown in Finnish or English. Exercise instructions are in '
                                        'Finnish. The rest are machine translations checked only with a spell checker, not yet '
                                        'by a native speaker: they may contain errors.'
                                  : 'VAROITUS: Kaikkea ei ole käännetty. Vammatilan ohjeita ei ole saameksi: valitse alta, '
                                        'näytetäänkö ne suomeksi vai englanniksi. Liikeohjeet ovat suomeksi. Muut käännökset '
                                        'ovat konekäännöksiä, jotka on tarkistettu vain oikolukijalla, ei vielä natiivipuhujalla: '
                                        'niissä voi olla virheitä.',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'VÁRUHUS: Sámegiel geavahanlávdi lea geahččaleapmi. Buot ii leat jorgaluvvon: vahátrávvagat eai '
                            'leat sámegillii, vállje vuolábealde, čájehuvvojitgo dat suomagillii vai eaŋgalsgillii. '
                            'Hárjehusaid rávvagat leat suomagillii. Eará jorgalusat leat '
                            'mašiidnajorgalusat, maid ii leat vel dárkkistan sámegielat olmmoš, dušše čállinmeattáhusdárkkistus. '
                            'Sáhttet leat boasttuvuođat.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            en
                                ? 'Exercise names are in Finnish or English (choose in Settings). Workout files stay in Finnish.'
                                : 'Liikkeiden nimet ovat suomeksi tai englanniksi (valinta asetuksissa). Treenitiedostot pysyvät '
                                      'suomeksi.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${en ? 'Injury guidance' : 'Vammatilan ohjeet'} · Vahátrávvagat',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'fi', label: Text('Suomi')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {health},
                  onSelectionChanged: (v) => setState(() => health = v.first),
                ),
                const SizedBox(height: 4),
                Text(
                  '${en ? 'You can change this later in Settings.' : 'Voit vaihtaa tämän myöhemmin asetuksista.'} '
                  '· Sáhtát rievdadit dán maŋŋelis ásahusain.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text('${en ? 'Continue?' : 'Jatketaanko?'} · Joatkitgo?'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(en ? 'No · Ii' : 'Ei · Ii')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(en ? 'Yes · Juo' : 'Kyllä · Juo')),
            ],
          ),
        ),
      );
      if (ok != true) return;
      settings.setHealthLang(health);
    }
    await settings.setLang(code);
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: settings, builder: (context, _) => _build(context));

  // Kolme kieltä rinnakkain: lippu ja kielen oma nimi; valittu kehystetään keltaisella.
  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final (i, l) in uiLanguages.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: uiLang == l.code ? Sami.yellow.withValues(alpha: .16) : cs.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: uiLang == l.code ? Sami.yellow : cs.outlineVariant,
                  width: uiLang == l.code ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _choose(context, l.code),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
                  child: Column(
                    children: [
                      LangFlag(l.code, height: 22),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          l.name,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: uiLang == l.code ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
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

/// Lippu kielivalintaan (piirretty, ei kuvatiedostoa), omissa mittasuhteissaan: Suomi 18:11,
/// saamen lippu 808:600 (Wikimedia Commons), Yhdistynyt kuningaskunta 2:1.
class LangFlag extends StatelessWidget {
  final String code;
  final double height;
  const LangFlag(this.code, {super.key, this.height = 16});

  static double ratio(String code) => switch (code) {
    'se' => 808 / 600,
    'en' => 2,
    _ => 18 / 11,
  };

  @override
  Widget build(BuildContext context) => Container(
    width: height * ratio(code),
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
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
    } else if (code == 'en') {
      // Yhdistyneen kuningaskunnan lippu (Union Jack) virallisin mittasuhtein 60 × 30: valkoinen vinoristi 6,
      // punainen vinoristi 2 siirrettynä (vastavuoroisesti, kuten oikeassa lipussa), valkoinen risti 10,
      // punainen risti 6.
      const blue = Color(0xFF012169), red = Color(0xFFC8102E);
      c.save();
      c.scale(w / 60, h / 30);
      c.drawRect(const Rect.fromLTWH(0, 0, 60, 30), p(blue));
      Paint stroke(Color col, double width) => Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;
      final diag = Path()
        ..moveTo(0, 0)
        ..lineTo(60, 30)
        ..moveTo(60, 0)
        ..lineTo(0, 30);
      c.drawPath(diag, stroke(Colors.white, 6));
      // Punainen vinoristi vain kunkin lävistäjän toisella puolella: neljä kolmiota keskeltä.
      c.save();
      c.clipPath(
        Path()
          ..moveTo(30, 15)
          ..lineTo(60, 15)
          ..lineTo(60, 30)
          ..close()
          ..moveTo(30, 15)
          ..lineTo(30, 30)
          ..lineTo(0, 30)
          ..close()
          ..moveTo(30, 15)
          ..lineTo(0, 15)
          ..lineTo(0, 0)
          ..close()
          ..moveTo(30, 15)
          ..lineTo(30, 0)
          ..lineTo(60, 0)
          ..close(),
      );
      c.drawPath(diag, stroke(red, 4));
      c.restore();
      c.drawRect(const Rect.fromLTWH(25, 0, 10, 30), p(Colors.white));
      c.drawRect(const Rect.fromLTWH(0, 10, 60, 10), p(Colors.white));
      c.drawRect(const Rect.fromLTWH(27, 0, 6, 30), p(red));
      c.drawRect(const Rect.fromLTWH(0, 12, 60, 6), p(red));
      c.restore();
    } else {
      // Suomen lippu (laki 1978/380): 18 × 11, sininen risti 3 leveä, pystyosa 5:n päässä vasemmasta reunasta,
      // vaakaosa 4:n päässä ylhäältä.
      const blue = Color(0xFF002F6C);
      c.drawRect(Rect.fromLTWH(0, 0, w, h), p(Colors.white));
      c.drawRect(Rect.fromLTWH(w * 5 / 18, 0, w * 3 / 18, h), p(blue));
      c.drawRect(Rect.fromLTWH(0, h * 4 / 11, w, h * 3 / 11), p(blue));
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
    if (en == null || effectiveNameMode == 'en') return Text(en ?? name, style: style);
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
  final bool icons; // kapeassa valikossa ilman kuvakkeita, jotta teksti mahtuu
  const TrainModePicker({super.key, required this.value, required this.onChanged, this.icons = true});

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
          icon: icons ? Icon(icon, size: 18) : null,
          label: FittedBox(fit: BoxFit.scaleDown, child: Text(l, maxLines: 1)),
        ),
    ],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.first),
  );
}

/// Valmiin (tallennetun) treenin lukutila: sisältöä voi vierittää ja lukea, mutta napautus kysyy ensin,
/// muokataanko tallennettua treeniä. [ask] palauttaa true, kun käyttäjä haluaa muokata.
class EditGuard extends StatelessWidget {
  final bool locked;
  final VoidCallback onTap;
  final Widget child;
  const EditGuard({super.key, required this.locked, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => locked
      ? GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AbsorbPointer(child: child),
        )
      : child;
}

/// Kysyy, muokataanko tallennettua treeniä (true = muokataan).
Future<bool> askEditSaved(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Muokataanko tallennettua treeniä?')),
        content: Text(t('Treeni on merkitty valmiiksi. Muutokset tallentuvat sen tiedostoon.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Muokkaa'))),
        ],
      ),
    ) ==
    true;

/// Lukutilan lukko yläpalkin oikeassa reunassa: kertoo, että treeni on tallennettu; napautus kysyy, muokataanko.
class LockButton extends StatelessWidget {
  final VoidCallback onTap;
  const LockButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: IconButton(
      tooltip: t('Tallennettu treeni: muokkaa'),
      onPressed: onTap,
      icon: const Icon(Icons.lock_outline, color: Sami.green),
    ),
  );
}

/// Sarjojen määrä oikeassa luvussa: 1 sarja, 2 sarjaa.
String setsLabel(int n) => n == 1 ? t('1 sarja') : t('{0} sarjaa', [n]);

/// Lajivalinta toisen sovelluksen lajille: [message] kertoo, mistä on kyse. null = ohita (ei tuoda).
Future<String?> pickSport(BuildContext context, String message) async {
  final cs = Theme.of(context).colorScheme;
  final v = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(t('Mikä laji tämä on?')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            for (final g in sportGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(t(g), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in sports.where((s) => s.group == g && !s.retired))
                    ActionChip(
                      avatar: Text(s.icon),
                      label: Text(sportName(s.name)),
                      onPressed: () => Navigator.pop(ctx, s.name),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(t('Ohita, älä tuo')))],
    ),
  );
  return v == null || v.isEmpty ? null : v;
}

/// Huomautus sisällöstä, jota ei ole käyttöliittymän kielellä (esim. vammatila saameksi englanniksi, liikevinkit vain
/// suomeksi). Näkyy vain, kun [show] on tosi.
class LangNotice extends StatelessWidget {
  final String text;
  final bool show;
  const LangNotice(this.text, {super.key, this.show = true});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Sami.red.withValues(alpha: .08),
        border: Border.all(color: Sami.red.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('⚠️ $text', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}
