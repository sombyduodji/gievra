import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sport_picker.dart';

import 'package:flutter/services.dart';

import '../app_state.dart';
import '../exercises.dart';
import '../models.dart';
import '../theme.dart';
import 'finish_sheet.dart';
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
    Widget btn(IconData i, VoidCallback f, String tip) => SizedBox.square(
      dimension: 52,
      child: IconButton.filledTonal(
        onPressed: f,
        tooltip: tip, // ruudunlukija
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
          btn(Icons.remove, onMinus, t('Vähennä')),
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
          btn(Icons.add, onPlus, t('Lisää')),
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
/// Päivämäärän valinta: otsikko ja painikkeet käyttöliittymän kielellä (Flutterin omat tekstit tuntevat vain
/// suomen ja englannin, eivät saamea). Vain kalenteri: tekstisyöttötilan ohjeita ei voi kääntää.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) => showDatePicker(
  context: context,
  initialDate: initial,
  firstDate: first,
  lastDate: last,
  initialEntryMode: DatePickerEntryMode.calendarOnly,
  helpText: t('Valitse päivä'),
  cancelText: t('Peruuta'),
  confirmText: 'OK',
  // Suurella tekstillä otsikon päiväys ("maŋŋebárga 10.11.") pienemmällä tyylillä, jotta se mahtuu.
  builder: (context, child) {
    if (!bigText(context)) return child!;
    final th = Theme.of(context);
    return Theme(
      data: th.copyWith(datePickerTheme: th.datePickerTheme.copyWith(headerHeadlineStyle: th.textTheme.headlineSmall)),
      child: child!,
    );
  },
);

/// Kellonajan valinta samoin (vain kellotaulu, 24 h).
Future<TimeOfDay?> pickTime(BuildContext context, TimeOfDay initial, {required String title}) => showTimePicker(
  context: context,
  initialTime: initial,
  initialEntryMode: TimePickerEntryMode.dialOnly,
  helpText: title,
  cancelText: t('Peruuta'),
  confirmText: 'OK',
  builder: (context, child) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
);

/// Kellonaika tekstinä: englanniksi 18:45, suomeksi ja saameksi 18.45.
String fmtClock(TimeOfDay c) =>
    '${c.hour.toString().padLeft(2, '0')}${isEnglish ? ':' : '.'}${c.minute.toString().padLeft(2, '0')}';

/// Numeron syöttö. [min] ja [max]: sallittu väli; muu arvo (tai tyhjä) näyttää välin, ja ikkuna pysyy auki
/// (ennen arvo hylättiin hiljaa, ja vanha arvo jäi näkyviin ilman selitystä).
/// Lukukentän ohjain, jonka arvo on valittuna: kirjoitus korvaa sen eikä jatka sitä (ennen "5" + "30" = 530 km,
/// testikierros 15.11.).
TextEditingController selectedText(String text) => TextEditingController.fromValue(
  TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: 0, extentOffset: text.length),
  ),
);

Future<double?> askNumber(
  BuildContext context,
  String title,
  double current, {
  bool decimals = true,
  double? min,
  double? max,
}) async {
  final c = selectedText(fmtNum(current));
  String? error;
  final range = min != null && max != null ? t('Sallittu {0}–{1}', [fmtNum(min), fmtNum(max)]) : null;
  final r = await showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final v = parseNum(c.text);
          if (v == null || (min != null && v < min) || (max != null && v > max)) {
            setState(() => error = range ?? t('Tarkista luku'));
            return;
          }
          Navigator.pop(ctx, v);
        }

        // Vierittyvä: vaakatasossa näppäimistö vie lähes koko korkeuden, eikä sisältö saa mennä otsikon päälle.
        return AlertDialog(
          scrollable: true,
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: decimals),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimals ? r'[0-9.,]' : r'[0-9]'))],
            decoration: InputDecoration(helperText: range, errorText: error),
            onChanged: (_) {
              if (error != null) setState(() => error = null);
            },
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
            FilledButton(onPressed: submit, child: const Text('OK')),
          ],
        );
      },
    ),
  );
  return r;
}

/// Viisi fiilisnappia (😫 … 🤩). Uusi napautus samaan poistaa valinnan.
/// Treenin lopussa: "Miltä tuntui?" ponnahdusikkunana. Kasvon napautus valitsee ja sulkee.
/// Palauttaa 1–5, [feelingSkipped] (Ohita) tai null (takaisin tai napautus ohi: lopetus peruttiin).
/// [askFeeling]: Ohita (ei fiilistä, jatketaan).
const feelingSkipped = 0;

/// Viimeisin [askFeeling]-kyselyssä valittu rasitus (kun kysyttiin).
String? askedIntensity;

Future<int?> askFeeling(BuildContext context, {bool askIntensity = false, String? intensity}) async {
  // Uusi Treeni valmis -ikkuna (finish_sheet.dart); tämä säilyy yksinkertaisena kutsuna ilman yhteenvetoa.
  askedIntensity = intensity;
  final r = await showFinishSheet(context, askIntensity: askIntensity, intensity: intensity);
  if (r != null) askedIntensity = r.intensity;
  return r?.feeling;
}

class FeelingPicker extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const FeelingPicker({super.key, required this.value, required this.onChanged});

  /// Sama ulkoasu kuin Treeni valmis -ikkunassa (isot kasvot); uusi napautus valittuun poistaa valinnan.
  @override
  Widget build(BuildContext context) => FaceRow(value: value, onTap: (v) => onChanged(value == v ? null : v));
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
                                  ? 'WARNING: Not everything is translated. Injury mode guidance and exercise tips are not available '
                                        'in Sámi: choose below whether they are shown in Finnish or English. The rest are '
                                        'machine translations checked only with a spell checker, not yet by a native '
                                        'speaker: they may contain errors.'
                                  : 'VAROITUS: Kaikkea ei ole käännetty. Vammatilan ohjeita ja liikevinkkejä ei ole saameksi: '
                                        'valitse alta, näytetäänkö ne suomeksi vai englanniksi. Muut käännökset ovat '
                                        'konekäännöksiä, jotka on tarkistettu vain oikolukijalla, ei vielä natiivipuhujalla: '
                                        'niissä voi olla virheitä.',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'VÁRUHUS: Sámegiel geavahanlávdi lea geahččaleapmi. Buot ii leat jorgaluvvon: vahátrávvagat ja '
                            'hárjehusaid rávvagat eai leat sámegillii, vállje vuolábealde, čájehuvvojitgo dat suomagillii '
                            'vai eaŋgalsgillii. Eará jorgalusat leat '
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
                  '${en ? 'Injury guidance and exercise tips' : 'Vammatilan ohjeet ja liikevinkit'} · Rávvagat',
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
/// Suurempi teksti (Asetukset → Tekstin koko tai puhelimen oma fonttikoko yli 105 %).
/// Tekstin kerroin leipätekstin koossa (14). Android 14+ skaalaa isoja kokoja vähemmän, joten 100:n koko ei kerro
/// järjestelmän suurta fonttia.
double textScale(BuildContext context) => MediaQuery.textScalerOf(context).scale(14) / 14;

bool bigText(BuildContext context) => textScale(context) > 1.05;

/// Rivimäärä: suurella tekstillä yksi lisää, jotta teksti ei katkea (Pieni ennallaan).
int linesFor(BuildContext context, int lines) => bigText(context) ? lines + 1 : lines;

/// Yläpalkin otsikko: suurella tekstillä pienennetään mahtumaan, ei katkaista ("Kahvakuula-askelky…").
class BarTitle extends StatelessWidget {
  final Widget child;
  const BarTitle(this.child, {super.key});

  @override
  Widget build(BuildContext context) => bigText(context)
      // Pieni väli oikeaan reunaan: pitkä otsikko ei osu näytön reunaan (testikierros 16.11., saame).
      ? Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: child),
        )
      : child;
}

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
/// Tekstin koko: Pieni (entinen koko), Normaali ja Suuri. Jokaisessa vaihtoehdossa "Aa" omassa koossaan, jotta
/// ero näkyy ennen valintaa (aloitus ja Asetukset → Yleiset).
class TextSizePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const TextSizePicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    key: const ValueKey('textSize'),
    showSelectedIcon: false,
    // Kulmikkaampi muoto ja reilumpi reunus: suurella tekstillä pyöreät päädyt leikkasivat sanan (testikierros 16.11.:
    // saame, fontti 1,3: "Stuoris" alareunasta, "Dábálaš" reunoissa kiinni).
    style: const ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
    ),
    segments: [
      for (final (v, l) in [('small', t('Pieni')), ('normal', t('Normaali')), ('large', t('Suuri'))])
        ButtonSegment(
          value: v,
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Näyte valitun koon suhteessa nykyiseen: sama kerroin kuin sovelluksessa.
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 16 * Settings.textSizes[v]! / settings.textFactor,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              FittedBox(fit: BoxFit.scaleDown, child: Text(l, maxLines: 1)),
            ],
          ),
        ),
    ],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.first),
  );
}

class TrainModePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final bool icons; // kapeassa valikossa ilman kuvakkeita, jotta teksti mahtuu
  const TrainModePicker({super.key, required this.value, required this.onChanged, this.icons = true});

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    showSelectedIcon: false,
    // Kapeassa valikossa vähemmän reunatilaa, jotta pitkä nimi (esim. saameksi Sávrivuohta) pienenee vähemmän.
    style: icons ? null : const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4))),
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
      icon: Icon(Icons.lock_outline, color: greenText(context)),
    ),
  );
}

/// Sarjojen määrä oikeassa luvussa: 1 sarja, 2 sarjaa.
String setsLabel(int n) => n == 1 ? t('1 sarja') : t('{0} sarjaa', [n]);

/// Lajivalinta toisen sovelluksen lajille: [message] kertoo, mistä on kyse. null = ohita (ei tuoda).
Future<String?> pickSport(BuildContext context, String message) async {
  final v = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      maxChildSize: .95,
      builder: (_, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Mikä laji tämä on?'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          // Sama lajivalinta kuin uudessa liikunnassa: haku, viimeksi tehdyt ja ruudukko.
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              children: [SportPicker(onPick: (s) => Navigator.pop(ctx, s))],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 8 + MediaQuery.viewInsetsOf(ctx).bottom),
              child: OutlinedButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(t('Ohita, älä tuo'))),
            ),
          ),
        ],
      ),
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

/// Lyhyt nimike kapeaan ruutuun. Tavallisella fontilla yksi rivi (pienenee tarvittaessa); järjestelmän suurella
/// fontilla (yli 1,15×) sanat omille riveilleen ja tarvittaessa pienennettynä: ei katkaisua sanan keskeltä eikä
/// lukukelvotonta kutistusta yhdelle riville. Ei LayoutBuilderia, joten toimii IntrinsicHeightin sisällä.
class FitLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const FitLabel(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).scale(10) > 11.5;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(big ? text.split(' ').join('\n') : text, style: style, textAlign: TextAlign.center, softWrap: false),
    );
  }
}

/// Teksti, jonka pisin sana mahtuu aina riville: fontti pienenee, ettei sana katkea kesken (saame, suuri teksti:
/// "Áigemihti/deapmi", "viehkanmátt/u"; yötesti 16.11.). Rivittyy edelleen sanojen välistä. [width] = käytettävissä
/// oleva leveys (annetaan ulkopuolelta, koska IntrinsicHeight ei salli LayoutBuilderia).
class WordFitText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double width;
  final TextAlign textAlign;
  const WordFitText(this.text, {super.key, required this.style, required this.width, this.textAlign = TextAlign.start});

  /// Tyyli, jolla pisin sana mahtuu leveyteen [width].
  static TextStyle fitted(BuildContext context, String text, TextStyle style, double width) {
    final st = DefaultTextStyle.of(context).style.merge(style);
    if (!width.isFinite || width <= 0 || st.fontSize == null) return st;
    var widest = 0.0;
    for (final w in text.split(RegExp(r'\s+'))) {
      if (w.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(text: w, style: st),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      widest = math.max(widest, tp.width);
      tp.dispose();
    }
    return widest > width ? st.copyWith(fontSize: st.fontSize! * width / widest * 0.98) : st;
  }

  @override
  Widget build(BuildContext context) => Text(text, style: fitted(context, text, style, width), textAlign: textAlign);
}
