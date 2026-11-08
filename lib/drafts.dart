import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

// Keskeneräinen liikuntakirjaus (lomake, ajanotto, GPS-reitti ennen Tallenna-painiketta) talteen muutaman sekunnin
// välein, jotta se ei katoa, jos Android sulkee sovelluksen muistin vähyyden vuoksi. Tiedosto on sovelluksen
// omassa kansiossa (ei treenikansiossa: luonnos ei ole vielä treeni). Poistetaan tallennettaessa tai kun
// kirjauksesta poistutaan itse.

class ActivityDraft {
  /// Testejä varten: luonnoksen kansio.
  @visibleForTesting
  static Directory? dirOverride;

  /// Yli vuorokauden vanha luonnos ei palaudu enää.
  static const maxAge = Duration(hours: 24);

  static Future<File> _file() async =>
      File(p.join((dirOverride ?? await getApplicationSupportDirectory()).path, 'liikunta-luonnos.json'));

  static String? _last;

  /// Tallentaa luonnoksen, jos se on muuttunut. [extra]: näkymän oma tila (ajanotto, reitti …).
  static Future<void> save(Workout w, {Map<String, Object?> extra = const {}}) async {
    if (kIsWeb) return;
    final text = jsonEncode({
      'saved': DateTime.now().toIso8601String(),
      'md': workoutToMarkdown(w),
      'session': w.session,
      'extra': extra,
    });
    // Aika muuttuu joka kerta: verrataan ilman sitä.
    final key = jsonEncode([workoutToMarkdown(w), w.session, extra]);
    if (key == _last) return;
    try {
      await (await _file()).writeAsString(text, flush: true);
      _last = key;
    } catch (_) {}
  }

  /// Palautettava luonnos: treeni ja näkymän oma tila; null, jos ei ole tai se on vanhentunut.
  static Future<(Workout, Map<String, Object?>)?> load() async {
    if (kIsWeb) return null;
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final saved = DateTime.tryParse(m['saved'] as String? ?? '');
      if (saved == null || DateTime.now().difference(saved) > maxAge) {
        await clear();
        return null;
      }
      final w = parseWorkout(m['md'] as String, fallbackSession: m['session'] as int? ?? 1);
      if (w.activity == null) return null;
      return (w, Map<String, Object?>.from(m['extra'] as Map? ?? const {}));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    _last = null;
    if (kIsWeb) return;
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
