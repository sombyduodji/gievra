import 'sleep.dart' show SleepNight;

import 'dart:convert';

import 'package:archive/archive.dart';

import 'body.dart';
import 'exercises.dart';
import 'import_detect.dart' show gievraCsvMarker;
import 'l10n.dart';
import 'models.dart';

/// Luettava CSV-vienti käyttäjän kielellä (taulukkolaskentaan, valmentajalle tai toiseen sovellukseen).
/// Ei varmuuskopio: liikkeet, lajit ja otsikot ovat käyttöliittymän kielellä, eikä Gievra tuo tätä takaisin.
/// Suomeksi ja saameksi erottimena puolipiste ja desimaalipilkku (Excel avaa suoraan), englanniksi pilkku ja piste.
class CsvExportOptions {
  final DateTime from, to; // päivät mukaan lukien
  final bool gym, cardio, body, notes, steps, sleep;
  const CsvExportOptions({
    required this.from,
    required this.to,
    this.gym = true,
    this.cardio = true,
    this.body = false,
    this.notes = false,
    this.steps = false,
    this.sleep = false,
  });
}

class CsvFile {
  final String name, text;
  final int rows;
  const CsvFile(this.name, this.text, this.rows);
}

String get _sep => isEnglish ? ',' : ';';

String _num(double? v) {
  if (v == null) return '';
  // Enintään kaksi desimaalia, ei turhia nollia (82.4 -> "82.4", 100.0 -> "100").
  final s = v == v.truncateToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return isEnglish ? s : s.replaceAll('.', ',');
}

/// Taulukko-ohjelma tulkitsee =, +, -, @, sarkaimella tai rivinvaihdolla alkavan solun kaavaksi (CSV-kaavainjektio:
/// esim. Health Connectista tai tuodusta uni.md:stä tullut sovelluksen nimi "=HYPERLINK(…)"). Tekstisolun eteen
/// heittomerkki; luvut (myös "-0,12" ja "+0,31") jäävät luvuiksi. Yötesti 18.11.
final _formulaStart = RegExp(r'^[=+\-@\t\r]');
final _numberLike = RegExp(r'^[+-]?\d+([.,]\d+)?$');

String csvCell(Object? v) => _cell(v);

String _cell(Object? v) {
  var s = v == null ? '' : '$v';
  if (v is! num && _formulaStart.hasMatch(s) && !_numberLike.hasMatch(s.trim())) s = "'$s";
  final sep = _sep;
  if (s.contains(sep) || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _table(List<String> header, List<List<Object?>> rows) {
  final b = StringBuffer('﻿')
    // Ensimmäinen rivi: mistä tiedosto on (tunnistus, jos joku yrittää tuoda sen takaisin).
    ..writeln('$gievraCsvMarker · ${t('luettava vienti, ei varmuuskopio')}')
    ..writeln(header.map(_cell).join(_sep));
  for (final r in rows) {
    b.writeln(r.map(_cell).join(_sep));
  }
  return b.toString();
}

bool _inRange(DateTime d, CsvExportOptions o) => !d.isBefore(dateOnly(o.from)) && !d.isAfter(dateOnly(o.to));

/// Liikkeen nimi viennissä: käyttöliittymän kielellä (englanniksi aina englanninkielinen nimi).
String _exerciseName(String name) => isEnglish ? (englishOf(name) ?? exerciseDisplay(name)) : exerciseLabel(name);

/// Sykkeen tai kalorien lähde: sykevyö, älykello (Health Connect) tai käsin syötetty.
String _source(String? s) => switch (s) {
  'sykevyö' || 'syke' => t('Sykevyö'),
  'kello' => t('Älykello'),
  'käsin' => t('Käsin syötetty'),
  _ => '',
};

String _clock(DateTime d) => [d.hour, d.minute, d.second].map((v) => v.toString().padLeft(2, '0')).join(':');

/// Useampi CSV-tiedosto yhtenä zippinä. Archive.files on vain luku -lista, joten tiedostot lisätään addFile-kutsulla.
List<int> csvZip(List<CsvFile> files) {
  final a = Archive();
  for (final f in files) {
    a.addFile(ArchiveFile.bytes(f.name, utf8.encode(f.text)));
  }
  return ZipEncoder().encodeBytes(a);
}

/// Tekee valitut CSV-tiedostot. Tyhjiä tiedostoja ei tehdä.
List<CsvFile> buildCsvExport(
  List<Workout> workouts,
  BodyLog body,
  CsvExportOptions o, {
  Map<DateTime, int> steps = const {},
  Map<DateTime, SleepNight> sleep = const {},
}) {
  final ws = [...workouts.where((w) => _inRange(w.date, o))]
    ..sort((a, b) => a.date == b.date ? a.session.compareTo(b.session) : a.date.compareTo(b.date));
  final out = <CsvFile>[];
  final yes = t('kyllä');

  if (o.gym) {
    final rows = <List<Object?>>[];
    for (final w in ws.where((w) => w.activity == null)) {
      var first = true;
      for (final e in w.exercises) {
        final m = measureOf(e.name);
        for (final (i, s) in e.sets.indexed) {
          rows.add([
            isoDate(w.date),
            trName(w.title),
            _exerciseName(e.name),
            i + 1,
            // Kahden käsipainon tai kuulan liikkeet yhteispainona (kuten historia sovelluksessa ja vanhoissa vienneissä).
            _num(s.kg * loadMultiplier(e.name)),
            s.reps,
            t(m.label),
            s.rir == null ? '' : rirLabels[s.rir],
            s.warmup ? yes : '',
            s.pr ? yes : '',
            if (o.notes) first && w.notes.trim().isNotEmpty ? w.notes.trim() : '',
          ]);
          first = false;
        }
      }
    }
    if (rows.isNotEmpty) {
      out.add(
        CsvFile(
          _fileName(t('salisarjat')),
          _table([
            t('Päivä'),
            t('Treeni'),
            t('Liike'),
            t('Sarja'),
            t('Paino (kg)'),
            t('Määrä'),
            t('Mittaustapa'),
            t('Varaa (toistoja)'),
            t('Lämmittely'),
            t('Ennätys'),
            if (o.notes) t('Muistiinpanot'),
          ], rows),
          rows.length,
        ),
      );
    }
  }

  if (o.cardio) {
    final rows = <List<Object?>>[
      for (final w in ws.where((w) => w.activity != null))
        [
          isoDate(w.date),
          sportName(w.activity!),
          w.seconds != null ? fmtDurationSec(w.seconds!) : (w.minutes == null ? '' : fmtDurationSec(w.minutes! * 60)),
          _num(w.distanceKm),
          w.paceSecPerKm == null ? '' : fmtPace(w.paceSecPerKm!),
          w.hrAvg,
          w.hrMax,
          w.kcal,
          _source(w.hrSource),
          _source(w.kcalSource),
          w.steps,
          w.strideM == null ? '' : _num((w.strideM! * 100).round() / 100),
          w.feeling == null ? '' : t(feelingOf(w.feeling)!.$3),
          if (o.notes) w.notes.trim(),
        ],
    ];
    if (rows.isNotEmpty) {
      out.add(
        CsvFile(
          _fileName(t('liikunta')),
          _table([
            t('Päivä'),
            t('Laji'),
            t('Kesto'),
            t('Matka (km)'),
            t('Vauhti (min/km)'),
            t('Keskisyke'),
            t('Maksimisyke'),
            t('Kalorit (kcal)'),
            t('Sykkeen lähde'),
            t('Kalorien lähde'),
            t('Askeleet'),
            t('Askelpituus (m)'),
            t('Fiilis'),
            if (o.notes) t('Muistiinpanot'),
          ], rows),
          rows.length,
        ),
      );
    }
  }

  // Salitreenit yhteenvetona (kesto, syke ja kalorit treeniä kohden; sarjat ovat salisarjat-tiedostossa).
  if (o.gym) {
    final rows = <List<Object?>>[
      for (final w in ws.where((w) => w.activity == null && w.exercises.any((e) => e.sets.isNotEmpty)))
        [
          isoDate(w.date),
          trName(w.title),
          w.minutes == null ? '' : fmtDurationSec(w.minutes! * 60),
          w.hrAvg,
          w.hrMax,
          w.kcal,
          _source(w.hrSource),
          _source(w.kcalSource),
          w.feeling == null ? '' : t(feelingOf(w.feeling)!.$3),
        ],
    ];
    if (rows.any((r) => r.skip(2).take(4).any((v) => v != null && v != ''))) {
      out.add(
        CsvFile(
          _fileName(t('salitreenit')),
          _table([
            t('Päivä'),
            t('Treeni'),
            t('Kesto'),
            t('Keskisyke'),
            t('Maksimisyke'),
            t('Kalorit (kcal)'),
            t('Sykkeen lähde'),
            t('Kalorien lähde'),
            t('Fiilis'),
          ], rows),
          rows.length,
        ),
      );
    }
  }

  // Sykekäyrät (sykevyö tai kello Health Connectista): lukema käyrän välein treeneistä, jotka kuuluvat valittuihin (sali / liikunta).
  final hrRows = <List<Object?>>[
    for (final w in ws)
      if (w.hrSeries case final h? when (w.activity == null ? o.gym : o.cardio))
        for (final (i, v) in h.values.indexed)
          if (v > 0)
            [
              isoDate(w.date),
              w.activity == null ? trName(w.title) : sportName(w.activity!),
              _clock(h.start.add(Duration(seconds: i * h.interval))),
              v,
            ],
  ];
  if (hrRows.isNotEmpty) {
    out.add(
      CsvFile(
        _fileName(t('syke')),
        _table([t('Päivä'), t('Treeni'), t('Kellonaika'), t('Syke')], hrRows),
        hrRows.length,
      ),
    );
  }

  if (o.body) {
    final rows = <List<Object?>>[
      for (final (d, kg) in body.sorted)
        if (_inRange(d, o)) [isoDate(d), _num(kg), body.heightCm],
    ];
    if (rows.isNotEmpty) {
      out.add(
        CsvFile(
          _fileName(t('punnitukset')),
          _table([t('Päivä'), t('Paino (kg)'), t('Pituus (cm)')], rows),
          rows.length,
        ),
      );
    }
  }
  // Päivän askeleet (askeleet.md): yksi rivi päivää kohden.
  if (o.steps) {
    final days = steps.keys.where((d) => _inRange(d, o)).toList()..sort();
    final rows = [
      for (final d in days) [isoDate(d), steps[d]],
    ];
    if (rows.isNotEmpty) {
      out.add(CsvFile(_fileName(t('askeleet')), _table([t('Päivä'), t('Askeleet')], rows), rows.length));
    }
  }
  // Yöunet (uni.md): herätyspäivä, nukkumaan, herätys, uni minuutteina, yön alin syke ja sovellus.
  if (o.sleep) {
    final days = sleep.keys.where((d) => _inRange(d, o)).toList()..sort();
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final rows = [
      for (final d in days)
        [
          isoDate(d),
          hm(sleep[d]!.bed),
          hm(sleep[d]!.wake),
          sleep[d]!.asleep.inMinutes,
          sleep[d]!.lowHr ?? '',
          sleep[d]!.app,
        ],
    ];
    if (rows.isNotEmpty) {
      out.add(
        CsvFile(
          _fileName(t('uni')),
          _table([t('Päivä'), t('Nukkumaan'), t('Herätys'), t('Uni (min)'), t('Yön alin syke'), t('Lähde')], rows),
          rows.length,
        ),
      );
    }
  }
  return out;
}

/// Tiedostonimi samaan muotoon kaikilla kielillä (käyttäjä 16.11.): pienet kirjaimet, välit ja alaviivat
/// väliviivoiksi ("heart rate" → heart-rate.csv, "gym_workouts" → gym-workouts.csv).
String _fileName(String word) => '${word.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-')}.csv';
