import '../l10n.dart';
import 'cues.dart';
import 'cues_en.dart';

/// Liikkeen tekniikkavinkit käyttäjän kielellä. Suomeksi ja englanniksi omat tekstit; saamenkielisessä
/// käyttöliittymässä suomeksi tai englanniksi asetuksen mukaan (sama valinta kuin vammatilan ohjeilla).
List<String> cuesFor(String exercise) {
  final english = isEnglish || (isSami && healthTextLang == 'en');
  return (english ? exerciseCuesEn[exercise] : null) ?? exerciseCues[exercise] ?? const [];
}
