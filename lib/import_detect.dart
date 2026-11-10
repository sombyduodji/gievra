import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'garmin_import.dart';
import 'program.dart';

/// Tuotavan tiedoston tyyppi: yksi Tuo tiedosto -painike tunnistaa sen sisällöstä (ei tiedostonimestä).
enum ImportKind {
  /// FitNotesin varmuuskopio (SQLite-tietokanta, yleensä .fitnotes).
  fitnotes,

  /// Garmin Connectin suoritusten CSV-vienti.
  garmin,

  /// Gievran varmuuskopio (zip, jossa .md-tiedostoja).
  gievraZip,

  /// Gievran .md-treenitiedostoja.
  md,

  /// Gievran ohjelmapohja (.gmd) tai ohjelmatiedosto.
  template,

  /// Karttapaketti (zip, jossa .pmtiles tai .elev): tuodaan Kartat-sivulla.
  mapPack,

  /// Gievran oma luettava CSV-vienti: ei varmuuskopio, ei tuoda.
  gievraCsv,

  /// Tuntematon.
  unknown,
}

/// Tunnistaa tiedoston [bytes] sisällöstä; [name] vain vihjeenä (.md).
ImportKind detectImport(String name, Uint8List bytes) {
  if (_startsWith(bytes, utf8.encode('SQLite format 3'))) return ImportKind.fitnotes;
  if (_startsWith(bytes, const [0x50, 0x4b, 0x03, 0x04])) {
    try {
      final names = ZipDecoder().decodeBytes(bytes).files.where((f) => f.isFile).map((f) => f.name.toLowerCase());
      if (names.any((n) => n.endsWith('.pmtiles') || n.endsWith('.elev'))) return ImportKind.mapPack;
      if (names.any((n) => n.endsWith('.md'))) return ImportKind.gievraZip;
    } catch (_) {}
    return ImportKind.unknown;
  }
  final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
  if (looksLikeProgram(text)) return ImportKind.template;
  if (isGarminCsv(text)) return ImportKind.garmin;
  if (text.startsWith(gievraCsvMarker)) return ImportKind.gievraCsv;
  final lower = name.toLowerCase();
  if (lower.endsWith('.md') || RegExp(r'^---\s*\n(?:.*\n)*?date:', multiLine: true).hasMatch(text)) {
    return ImportKind.md;
  }
  return ImportKind.unknown;
}

/// Gievran luettavan CSV-viennin ensimmäinen rivi (tunnistusta varten).
const gievraCsvMarker = '# Gievra';

bool _startsWith(Uint8List b, List<int> prefix) {
  if (b.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (b[i] != prefix[i]) return false;
  }
  return true;
}
