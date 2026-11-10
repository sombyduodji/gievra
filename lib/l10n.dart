import 'package:flutter/services.dart' show rootBundle;

import 'exercises.dart' show exerciseLabel;
import 'injury_data.dart' show injuryRegions;
import 'models.dart' show decimalComma;

/// Käyttöliittymän kieli. Suomi on lähdekieli: koodissa teksti kirjoitetaan suomeksi `t('…')`-kutsuun,
/// ja käännökset ovat gettext-tiedostossa assets/l10n/KIELI.po (msgid = suomenkielinen teksti).
/// Puuttuva käännös näkyy suomeksi, joten keskeneräinenkin käännös toimii.
///
/// Muuttujat: `t('Tuotiin {0} treeniä.', [n])`. Paikkamerkit {0}, {1}… voivat olla käännöksessä eri
/// järjestyksessä. Liikkeiden nimet, .md-tiedostojen sisältö ja tiedostomuoto pysyvät aina suomeksi.
///
/// Käännösten päivitys ja tarkistus: python3 tools/l10n.py (ks. docs/kaannokset.md).
class UiLang {
  final String code;
  final String name; // kielen oma nimi
  final String note; // näytetään kielivalinnassa
  const UiLang(this.code, this.name, this.note);
}

const uiLanguages = [
  UiLang('fi', 'Suomi', ''),
  UiLang('se', 'Davvisámegiella', 'Geahččaleapmi: hárjehusaid namat leat suomagillii dahje eaŋgalsgillii.'),
  UiLang('en', 'English', ''),
];

String _lang = 'fi';
Map<String, String> _catalog = const {};
Map<String, String> _en = const {}; // englanninkieliset nimet suomen- ja saamenkielisen rinnalle

/// Liikkeiden ja lajien nimet: 'fi' (käyttöliittymän kielellä), 'en' tai 'both'. Asetus (app_state) päivittää.
/// Englanninkielisessä käyttöliittymässä nimet ovat aina englanniksi.
String nameMode = 'fi';
String get effectiveNameMode => _lang == 'en' ? 'en' : nameMode;

/// Saamenkielisessä käyttöliittymässä vammatilan tekstit (ei käännetty saameksi): 'fi' suomeksi tai 'en'
/// englanniksi. Asetus (app_state) päivittää.
String healthTextLang = 'fi';

/// Vammatilan tekstit, jotka näytetään saamenkielisessä käyttöliittymässä suomeksi tai englanniksi.
final Set<String> _health = {
  for (final r in injuryRegions) ...[r.name, r.explanation, r.tendon, ...r.modify.values],
};
String? _healthText(String key) {
  if (_lang != 'se' || healthTextLang != 'en' || !_health.contains(key)) return null;
  final e = _en[key];
  return e == null || e.isEmpty ? null : e;
}

String get uiLang => _lang;
bool get isSami => _lang == 'se';
bool get isEnglish => _lang == 'en';

/// Vaihtaa kielen ja lataa sen käännökset. Tuntematon kieli = suomi.
Future<void> setUiLang(String code) async {
  if (_en.isEmpty) {
    try {
      _en = parsePo(await rootBundle.loadString('assets/l10n/en.po'));
    } catch (_) {}
  }
  if (!uiLanguages.any((l) => l.code == code) || code == 'fi') {
    _lang = 'fi';
    _catalog = const {};
    _patternCache = null;
    decimalComma = true;
    return;
  }
  try {
    _catalog = parsePo(await rootBundle.loadString('assets/l10n/$code.po'));
    _patternCache = null;
    _lang = code;
    decimalComma = code != 'en';
  } catch (_) {
    _lang = 'fi';
    _catalog = const {};
  }
}

/// Testeille: kieli ja käännökset suoraan.
void debugSetCatalog(String code, Map<String, String> catalog, {Map<String, String>? english}) {
  if (english != null) _en = english;
  _lang = code;
  decimalComma = code != 'en';
  _catalog = catalog;
  _patternCache = null;
}

/// Käännä. [args] korvaavat paikkamerkit {0}, {1}…
String t(String fi, [List<Object?> args = const []]) {
  final s = _healthText(fi) ?? _catalog[fi];
  return fill(s == null || s.isEmpty ? fi : s, args);
}

/// Tallennettava teksti (esim. ohjelma.md:n huomiot): aina suomeksi, mutta merkitään käännettäväksi.
/// Näytetään käyttöliittymässä tr()-funktiolla.
String fi(String template, [List<Object?> args = const []]) => fill(template, args);

/// Virheen teksti käyttäjälle: sovelluksen omat virheviestit (kirjoitettu fi()-merkinnällä) käännetään, muiden
/// virheiden teksti näytetään sellaisenaan ilman luokan nimeä.
String errorText(Object e) {
  final s = e is FormatException
      ? e.message
      : e.toString().replaceFirst(RegExp(r'^(HttpException|Exception|FileSystemException|StateError): '), '');
  return tr(s);
}

/// Tallennettu huomio, jossa osat on erotettu " · ":llä (esim. vammatilan muutosohjeet): kukin osa käännetään.
String trNote(String stored) => stored.split(' · ').map(tr).join(' · ');

/// Kääntää tallennetun suomenkielisen tekstin: suora osuma tai fi()-mallin mukainen teksti, jonka
/// muuttujat poimitaan ja sijoitetaan käännökseen (muuttujat käännetään, jos niille on käännös).
String tr(String stored) {
  if (_lang == 'fi') return stored;
  final direct = _healthText(stored) ?? _catalog[stored];
  if (direct != null && direct.isNotEmpty) return direct;
  for (final (re, tmpl) in _patterns) {
    final m = re.firstMatch(stored);
    if (m == null) continue;
    final order = [for (final x in RegExp(r'\{(\d+)\}').allMatches(tmpl)) int.parse(x[1]!)];
    final args = List<Object?>.filled(order.isEmpty ? 0 : order.reduce((a, b) => a > b ? a : b) + 1, '');
    for (var i = 0; i < order.length; i++) {
      final v = m.group(i + 1)!;
      // Luettelo (esim. "rinta, takareisi, selkä"): jos koko tekstille ei ole käännöstä, osat käännetään erikseen.
      // Liikkeiden nimet (esim. suosikkiliikkeet) nimiasetuksen mukaan, muut käännöksestä.
      String one(String x) {
        final y = t(x);
        return y != x ? y : exerciseLabel(x);
      }

      final whole = one(v);
      args[order[i]] = whole != v || !v.contains(', ') ? whole : v.split(', ').map(one).join(', ');
    }
    return fill(_catalog[tmpl]!, args);
  }
  return stored;
}

List<(RegExp, String)>? _patternCache;
List<(RegExp, String)> get _patterns => _patternCache ??= [
  for (final k in _catalog.keys)
    if (k.contains(RegExp(r'\{\d+\}')))
      (RegExp('^${k.split(RegExp(r'\{\d+\}')).map(RegExp.escape).join('(.+?)')}\$'), k),
];

/// Nimi (treenin otsikko, ohjelmapäivä) käyttöliittymään: "Koko keho A" -> käännetty perusosa + " A".
/// Liikkeiden ja lajien nimet jäävät ennalleen, koska niille ei ole käännöstä.
String trName(String name) {
  if (_lang == 'fi') return name;
  final direct = _catalog[name];
  if (direct != null && direct.isNotEmpty) return direct;
  final m = RegExp(r'^(.+?) ([A-Z]|\d+)$').firstMatch(name);
  if (m != null) {
    final base = _catalog[m[1]!];
    if (base != null && base.isNotEmpty) return '$base ${m[2]}';
  }
  return name;
}

/// Lajin nimi (Juoksu, Pyöräily …) nimiasetuksen mukaan: käyttöliittymän kielellä, englanniksi tai molemmilla
/// ("Juoksu (Running)"). Englanninkielisessä käyttöliittymässä aina englanniksi.
String sportName(String name) {
  final local = trName(name);
  if (_lang == 'en') return local;
  final en = _en[name];
  if (en == null || en.isEmpty || en == local) return local;
  return switch (nameMode) {
    'en' => en,
    'both' => '$local ($en)',
    _ => local,
  };
}

String fill(String s, List<Object?> args) {
  if (args.isEmpty) return s;
  return s.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
    final i = int.parse(m[1]!);
    return i < args.length ? '${args[i]}' : m[0]!;
  });
}

/// Yksinkertainen .po-lukija: msgid/msgstr, monirivinen jatko, kommentit. Sumeat (#, fuzzy) ohitetaan.
Map<String, String> parsePo(String text) {
  final out = <String, String>{};
  String? id, str;
  String? field;
  var fuzzy = false;
  void flush() {
    if (id != null && str != null && str!.isNotEmpty && id!.isNotEmpty && !fuzzy) out[id!] = str!;
    id = str = field = null;
    fuzzy = false;
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('#')) {
      if (line.startsWith('#,') && line.contains('fuzzy')) fuzzy = true;
      continue;
    }
    if (line.startsWith('msgid ')) {
      if (id != null && str != null) flush();
      id = _unquote(line.substring(6));
      field = 'id';
    } else if (line.startsWith('msgstr ')) {
      str = _unquote(line.substring(7));
      field = 'str';
    } else if (line.startsWith('"')) {
      if (field == 'id') id = id! + _unquote(line);
      if (field == 'str') str = str! + _unquote(line);
    }
  }
  flush();
  return out;
}

String _unquote(String s) {
  s = s.trim();
  if (s.length < 2 || !s.startsWith('"') || !s.endsWith('"')) return '';
  s = s.substring(1, s.length - 1);
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '\\' && i + 1 < s.length) {
      final n = s[++i];
      b.write(switch (n) {
        'n' => '\n',
        't' => '\t',
        '"' => '"',
        '\\' => '\\',
        _ => n,
      });
    } else {
      b.write(c);
    }
  }
  return b.toString();
}
