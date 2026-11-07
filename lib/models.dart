import 'dart:convert';

import 'exercises.dart';

/// Yksi sarja: paino, toistot, valinnainen RPE ja ennätysmerkintä.
class SetEntry {
  double kg;
  int reps;
  double? rpe;
  bool pr;

  /// Toistoja varastossa: 0 = ei yhtään, 1 = 1–2, 3 = 3 tai enemmän. null = ei merkitty.
  int? rir;

  /// Lämmittelysarja: ei lasketa volyymiin, ennätyksiin eikä painoehdotuksiin. Tiedostossa "(lämmittely)".
  bool warmup;
  SetEntry(this.kg, this.reps, {this.rpe, this.pr = false, this.rir, this.warmup = false});
}

const rirLabels = {0: '0', 1: '1-2', 3: '3+'};

class ExerciseEntry {
  final String name;
  final List<SetEntry> sets;
  ExerciseEntry(this.name, [List<SetEntry>? sets]) : sets = sets ?? [];

  /// Työsarjat (ilman lämmittelysarjoja).
  List<SetEntry> get workSets => sets.where((s) => !s.warmup).toList();
}

class Warmup {
  String equipment;
  int minutes;
  Warmup(this.equipment, this.minutes);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Kalenteripäivien lisäys (Duration ei kelpaa: kesäaikasiirtymä siirtää kellonaikaa).
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

class Workout {
  DateTime date;
  String title;
  Warmup? warmup;
  final List<ExerciseEntry> exercises;
  String notes;
  double? bodyweight;
  DateTime? started; // aloitusaika (kello)
  int? minutes; // kesto, kun treeni merkittiin valmiiksi
  int? feeling; // 1–5, ks. feelings

  /// Liikekohtainen fiilis (1–5), kysytään kun koko treeni tuntui raskaalta (1–2).
  Map<String, int> moveFeeling = {};

  /// Liikkeet, jotka olivat liian raskaita: seuraavalla kerralla ehdotetaan kevyempää.
  Set<String> tooHeavy = {};

  /// Päivän syyt (väsynyt, huonosti nukuttu …): seuraavalla kerralla ei nosteta painoja niiden takia.
  List<String> dayReasons = [];
  String? programDay; // ohjelmapäivän pysyvä nimi (esim. "Koko keho A"), vaikka otsikko olisi oma
  int session; // saman päivän treenin numero: 1 = vvvv-kk-pp.md, 2 = vvvv-kk-pp-2.md …
  String? activity; // urheilulaji tai liikunta (esim. Juoksu); null = salitreeni
  double? distanceKm;
  String? intensity; // kevyt / reipas / kova
  int? kcal, hrAvg, hrMax; // sykemittarin tai älykellon tiedot (valinnainen)
  bool watchTime; // kesto tuli kellosta (ei sovelluksen ajastimesta)

  Workout({
    required DateTime date,
    this.title = 'Treeni',
    this.warmup,
    List<ExerciseEntry>? exercises,
    this.notes = '',
    this.bodyweight,
    this.started,
    this.minutes,
    this.feeling,
    this.programDay,
    this.session = 1,
    this.activity,
    this.distanceKm,
    this.intensity,
    this.kcal,
    this.hrAvg,
    this.hrMax,
    this.watchTime = false,
  }) : date = dateOnly(date),
       exercises = exercises ?? [];

  bool get isEmpty =>
      warmup == null && activity == null && exercises.every((e) => e.sets.isEmpty) && notes.trim().isEmpty;

  /// Vauhti min/km (kestävyyslajit).
  String? get pace {
    if (minutes == null || distanceKm == null || distanceKm! <= 0) return null;
    final s = (minutes! * 60 / distanceKm!).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} /km';
  }

  /// Ohjelmapäivän tunniste vertailuihin: pysyvä nimi tai otsikko (vanhat tiedostot).
  String get dayKey => programDay ?? title;

  /// Itsenäinen kopio (muokkaus ei koske tallennettua versiota ennen tallennusta).
  Workout copy() => parseWorkout(workoutToMarkdown(this));
}

// ---------------------------------------------------------------------------
// Markdown-muoto. Yksi tiedosto päivää kohden: <kansio>/<vuosi>/<vvvv-kk-pp>.md
//
// ---
// date: 2026-11-06
// title: Jalkapäivä
// warmup: Crosstrainer, 10 min
// bodyweight: 86,5
// start: 17:30
// duration: 62 min
// feeling: 4 🙂 Hyvä
// tags: [treeni]
// ---
//
// # Jalkapäivä 2026-11-06
//
// ## Lämmittely
// - Crosstrainer: 10 min
//
// ## Takakyykky
// 1. 100 kg × 5
// 2. 125 kg × 5 RIR 1-2 🏆 ennätys
//
// ## Muistiinpanot
// vapaata tekstiä
// ---------------------------------------------------------------------------

/// "Miltä tuntui?" yhdellä napautuksella.
/// Päivän syyt raskaalle treenille (tallennetaan suomeksi, näytetään käännettynä).
// l10n: data
const dayReasonChoices = [
  'väsynyt',
  'huonosti nukuttu',
  'rankka päivä',
  'stressi',
  'sairastumassa',
  'huono ruokailu',
  'kipua',
];

// l10n: data
const feelings = [(1, '😫', 'Raskas'), (2, '😕', 'Tahmea'), (3, '😐', 'Ok'), (4, '🙂', 'Hyvä'), (5, '🤩', 'Loistava')];
(int, String, String)? feelingOf(int? v) => feelings.where((f) => f.$1 == v).firstOrNull;

const warmupHeading = 'Lämmittely';
const activityHeading = 'Liikunta';
const notesHeading = 'Muistiinpanot';

String _two(int n) => n.toString().padLeft(2, '0');
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// 2.5 -> "2,5", 100.0 -> "100"
String fmtNum(double v) {
  final s = v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
  return s.replaceAll('.', ',');
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String workoutToMarkdown(Workout w) {
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('date: ${isoDate(w.date)}')
    ..writeln('title: ${w.title}');
  if (w.programDay != null && w.programDay != w.title) b.writeln('day: ${w.programDay}');
  if (w.session > 1) b.writeln('session: ${w.session}');
  if (w.activity != null) b.writeln('activity: ${w.activity}');
  if (w.distanceKm != null) b.writeln('distance: ${fmtNum(w.distanceKm!)} km');
  if (w.intensity != null) b.writeln('intensity: ${w.intensity}');
  if (w.warmup != null) b.writeln('warmup: ${w.warmup!.equipment}, ${w.warmup!.minutes} min');
  if (w.bodyweight != null) b.writeln('bodyweight: ${fmtNum(w.bodyweight!)}');
  if (w.started != null) b.writeln('start: ${_two(w.started!.hour)}:${_two(w.started!.minute)}');
  if (w.minutes != null) b.writeln('duration: ${w.minutes} min${w.watchTime ? ' (kello)' : ''}');
  if (w.kcal != null) b.writeln('kcal: ${w.kcal}');
  if (w.hrAvg != null) b.writeln('hr_avg: ${w.hrAvg}');
  if (w.hrMax != null) b.writeln('hr_max: ${w.hrMax}');
  if (w.feeling != null) b.writeln('feeling: ${w.feeling} ${feelingOf(w.feeling)!.$2} ${feelingOf(w.feeling)!.$3}');
  if (w.moveFeeling.isNotEmpty) {
    b.writeln(
      'move_feeling: ${w.moveFeeling.entries.map((e) => '${e.key}=${e.value}${w.tooHeavy.contains(e.key) ? ' liian raskas' : ''}').join('; ')}',
    );
  }
  if (w.dayReasons.isNotEmpty) b.writeln('day_feeling: ${w.dayReasons.join(', ')}');
  b
    ..writeln('tags: [treeni]')
    ..writeln('---')
    ..writeln()
    ..writeln('# ${w.title} ${isoDate(w.date)}');
  if (w.activity != null) {
    b
      ..writeln()
      ..writeln('## $activityHeading')
      ..writeln(
        '- ${w.activity}${w.minutes == null ? '' : ': ${w.minutes} min'}'
        '${w.distanceKm == null ? '' : ', ${fmtNum(w.distanceKm!)} km'}${w.pace == null ? '' : ', ${w.pace}'}'
        '${w.intensity == null ? '' : ', ${w.intensity}'}',
      );
  }
  if (w.warmup != null) {
    b
      ..writeln()
      ..writeln('## $warmupHeading')
      ..writeln('- ${w.warmup!.equipment}: ${w.warmup!.minutes} min');
  }
  for (final e in w.exercises) {
    if (e.sets.isEmpty) continue;
    b
      ..writeln()
      ..writeln('## ${e.name}');
    final m = measureOf(e.name);
    for (var i = 0; i < e.sets.length; i++) {
      final s = e.sets[i];
      if (m == Measure.reps) {
        b.write('${i + 1}. ${fmtNum(s.kg)} kg × ${s.reps}');
      } else if (s.kg == 0) {
        b.write('${i + 1}. ${s.reps} ${m.suffix}');
      } else {
        b.write('${i + 1}. ${fmtNum(s.kg)} kg × ${s.reps} ${m.suffix}');
      }
      if (s.rpe != null) b.write(' @${fmtNum(s.rpe!)}');
      if (s.rir != null) b.write(' RIR ${rirLabels[s.rir]}');
      if (s.pr) b.write(' 🏆 ennätys');
      if (s.warmup) b.write(' (lämmittely)');
      b.writeln();
    }
  }
  if (w.notes.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('## $notesHeading')
      ..writeln(w.notes.trim());
  }
  return b.toString();
}

const _unitRe = r'(?:\s*(?:s|sek|sekuntia|askelta|askel|edestakaisin|m|metriä)\b)?';
final _setRe = RegExp(r'^(?:\d+[.)]|[-*])\s*(\d+(?:[.,]\d+)?)\s*kg\s*[×xX*]\s*(\d+)' + _unitRe + r'(.*)$');
// Ilman painoa: "1. 45 s", "2. 20 askelta"
final _bwSetRe = RegExp(r'^(?:\d+[.)]|[-*])\s*(\d+)\s*(?:s|sek|sekuntia|askelta|askel|edestakaisin|m|metriä)\b(.*)$');
final _rpeRe = RegExp(r'@\s*(\d+(?:[.,]\d+)?)');
final _rirRe = RegExp(r'RIR\s*(3\+|1\s*[-–]\s*2|[0-9])');
final _warmupRe = RegExp(r'^[-*]\s*(.+?):\s*(\d+)\s*min');
final _trailingDate = RegExp(r'\s*\d{4}-\d{2}-\d{2}\s*$');

/// Lukee treenin Markdownista. Sietää käsin muokattuja tiedostoja: tuntemattomat rivit ohitetaan.
int? _parseRir(String rest) {
  final r = _rirRe.firstMatch(rest)?[1];
  if (r == null) return null;
  if (r.startsWith('3') || (int.tryParse(r) ?? 0) >= 3) return 3;
  if (r.startsWith('1') || r == '2') return 1;
  return 0;
}

Workout parseWorkout(String text, {DateTime? fallbackDate, int fallbackSession = 1}) {
  final lines = const LineSplitter().convert(text);
  final meta = <String, String>{};
  var i = 0;
  if (lines.isNotEmpty && lines[0].trim() == '---') {
    i = 1;
    while (i < lines.length && lines[i].trim() != '---') {
      final idx = lines[i].indexOf(':');
      if (idx > 0) meta[lines[i].substring(0, idx).trim()] = lines[i].substring(idx + 1).trim();
      i++;
    }
    i++;
  }
  final date = DateTime.tryParse(meta['date'] ?? '') ?? fallbackDate;
  if (date == null) throw const FormatException('Päivämäärä puuttuu');
  final w = Workout(date: date, title: meta['title'] ?? 'Treeni', bodyweight: parseNum(meta['bodyweight'] ?? ''));
  final st = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(meta['start'] ?? '');
  if (st != null && int.parse(st[1]!) < 24 && int.parse(st[2]!) < 60) {
    w.started = DateTime(date.year, date.month, date.day, int.parse(st[1]!), int.parse(st[2]!));
  }
  w.session = int.tryParse(meta['session'] ?? '') ?? fallbackSession;
  final act = meta['activity']?.trim();
  if (act != null && act.isNotEmpty) w.activity = act;
  w.distanceKm = parseNum(RegExp(r'[\d.,]+').firstMatch(meta['distance'] ?? '')?[0] ?? '');
  final inten = meta['intensity']?.trim();
  if (inten != null && inten.isNotEmpty) w.intensity = inten;
  int? num(String k) => int.tryParse(RegExp(r'\d+').firstMatch(meta[k] ?? '')?[0] ?? '');
  w.kcal = num('kcal');
  w.hrAvg = num('hr_avg');
  w.hrMax = num('hr_max');
  w.watchTime = (meta['duration'] ?? '').contains('kello');
  final day = meta['day']?.trim();
  if (day != null && day.isNotEmpty) w.programDay = day;
  w.feeling = int.tryParse(RegExp(r'^\d').firstMatch(meta['feeling'] ?? '')?[0] ?? '');
  if (feelingOf(w.feeling) == null) w.feeling = null;
  for (final part in (meta['move_feeling'] ?? '').split(';')) {
    final m = RegExp(r'^\s*(.+?)=([1-5])(\s+liian raskas)?\s*$').firstMatch(part);
    if (m == null) continue;
    w.moveFeeling[m[1]!] = int.parse(m[2]!);
    if (m[3] != null) w.tooHeavy.add(m[1]!);
  }
  w.dayReasons = [
    for (final r in (meta['day_feeling'] ?? '').split(','))
      if (r.trim().isNotEmpty) r.trim(),
  ];
  w.minutes = int.tryParse(RegExp(r'\d+').firstMatch(meta['duration'] ?? '')?[0] ?? '');

  String? section;
  final notes = <String>[];
  for (; i < lines.length; i++) {
    final line = lines[i];
    final t = line.trim();
    if (t.startsWith('## ')) {
      section = t.substring(3).trim();
      section = exerciseRenames[section] ?? section;
      if (section != warmupHeading && section != notesHeading && section != activityHeading) {
        w.exercises.add(ExerciseEntry(section));
      }
      continue;
    }
    if (t.startsWith('# ')) {
      if (!meta.containsKey('title')) {
        final title = t.substring(2).replaceAll(_trailingDate, '').trim();
        if (title.isNotEmpty) w.title = title;
      }
      continue;
    }
    if (section == null) continue;
    if (section == warmupHeading) {
      final m = _warmupRe.firstMatch(t);
      if (m != null) w.warmup = Warmup(m[1]!, int.parse(m[2]!));
    } else if (section == notesHeading) {
      notes.add(line);
    } else {
      final m = _setRe.firstMatch(t);
      final bw = m == null ? _bwSetRe.firstMatch(t) : null;
      if (bw != null) {
        w.exercises.last.sets.add(
          SetEntry(
            0,
            int.parse(bw[1]!),
            pr: (bw[2] ?? '').contains('🏆'),
            rir: _parseRir(bw[2] ?? ''),
            warmup: (bw[2] ?? '').contains('lämmittely'),
          ),
        );
        continue;
      }
      if (m != null) {
        final rest = m[3] ?? '';
        final rpe = _rpeRe.firstMatch(rest);
        final rir = _rirRe.firstMatch(rest)?[1];
        w.exercises.last.sets.add(
          SetEntry(
            parseNum(m[1]!)!,
            int.parse(m[2]!),
            rpe: rpe == null ? null : parseNum(rpe[1]!),
            pr: rest.contains('🏆'),
            warmup: rest.contains('lämmittely'),
            rir: rir == null
                ? null
                : rir.startsWith('3') || (int.tryParse(rir) ?? 0) >= 3
                ? 3
                : rir.startsWith('1') || rir == '2'
                ? 1
                : 0,
          ),
        );
      }
    }
  }
  w.notes = notes.join('\n').trim();
  if (w.notes == '-') w.notes = '';
  return w;
}
