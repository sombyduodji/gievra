import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'body.dart';
import 'l10n.dart';
import 'models.dart';
import 'program.dart';
import 'exercises.dart';

final settings = Settings();
final store = WorkoutStore();

/// Synkronoinnin koukku: kutsutaan jokaisen tallennuksen ja poiston jälkeen polulla treenikansiossa
/// ("asetukset.md", "ohjelma.md", "2026/2026-11-06.md"). Asetetaan lib/sync/sync_service.dart:ssa.
void Function(String path)? onLocalChange;

String workoutPath(DateTime d, [int session = 1]) => '${d.year}/${isoDate(d)}${session > 1 ? '-$session' : ''}.md';

/// Treenin GPS-reitti samassa kansiossa: vvvv/vvvv-kk-pp[-n].gpx.
String routePath(DateTime d, [int session = 1]) => workoutPath(d, session).replaceFirst(RegExp(r'\.md$'), '.gpx');

/// Reittitiedoston polku treenikansiossa .md-tiedoston nimen perusteella.
String routeRel(Workout w) => '${w.date.year}/${w.route}';

/// Saman päivän treenin numero tiedostonimestä (vvvv-kk-pp-2.md -> 2).
int sessionFromName(String base) =>
    int.tryParse(RegExp(r'^\d{4}-\d{2}-\d{2}-(\d+)\.md$').firstMatch(base)?[1] ?? '') ?? 1;

class Equipment {
  final String icon;
  final String name;
  const Equipment(this.icon, this.name);
}

/// Tauko treenaamisesta: sairaus tai loma. end == null = tauko on päällä.
class Pause {
  final DateTime start;
  DateTime? end;
  final String reason; // 'sairas' | 'loma'
  Pause(this.start, this.reason, [this.end]);
  bool get sick => reason == 'sairas';
  int get days => (end ?? dateOnly(DateTime.now())).difference(start).inDays + 1;
}

/// Treenityyli: aloituskyselyn vastaukset ja itse valitut liikkeet (asetukset.md, ## Treenityyli).
/// Kulkee varmuuskopion ja synkronoinnin mukana, joten uusi laite tietää heti, miten treenaat.
class TrainingStyle {
  String? goal, experience, repStyle;
  int? days, minutes;
  Set<String> equipment;
  List<String> moves;
  String? kbFocus; // kahvakuulaohjelman painotus
  TrainingStyle({
    this.goal,
    this.experience,
    this.repStyle,
    this.days,
    this.minutes,
    Set<String>? equipment,
    List<String>? moves,
    this.kbFocus,
  }) : equipment = equipment ?? {},
       moves = moves ?? [];
  bool get isEmpty => goal == null && days == null && moves.isEmpty;
}

class Settings extends ChangeNotifier {
  static const defaultEquipment = [
    Equipment('🚶', 'Kävelymatto'),
    Equipment('🚴', 'Kuntopyörä'),
    Equipment('🏃', 'Crosstrainer'),
    Equipment('🪜', 'Porraskone'),
    Equipment('🚣', 'Soutulaite'),
    Equipment('🧘', 'Venyttely'),
  ];
  static const _oldDefaults = ['Kävelymatto', 'Kuntopyörä', 'Crosstrainer', 'Porraskone', 'Soutulaite'];

  SharedPreferences? _p;
  String? name;
  String? folder;
  ThemeMode themeMode = ThemeMode.system; // oletus: järjestelmän asetus
  double weightStep = 2.5;
  bool tips = true;

  /// Kehonpainon seuranta (asetukset.md: body_tracker). Punnitukset ja pituus kehonpaino.md:ssä ([body]).
  bool bodyTracker = false;
  BodyLog body = BodyLog();

  /// Päivä, jolta etusivun painokortti on ohitettu (laitekohtainen).
  String? bodySkipped;

  /// Mitä treenataan: 'gym' sali, 'cardio' kestävyys (juoksu, pyöräily …), 'both' molemmat (etusivulla
  /// Sali / Kestävyys -valinta). Kestävyyslajit näkyvät, kun tila ei ole pelkkä sali.
  String trainMode = 'gym';
  bool get sports => trainMode != 'gym';
  set sports(bool v) => trainMode = v ? (trainMode == 'cardio' ? 'cardio' : 'both') : 'gym';

  /// Etusivun näkymä molemmat-tilassa ('gym' tai 'cardio'); vain tällä laitteella.
  String homeView = 'gym';

  /// Etusivun näkymä: molemmat-tilassa valinnan mukaan, muuten tila.
  String get homeShows => trainMode == 'both' ? homeView : trainMode;

  /// Liikkeiden nimet näytössä: 'fi' suomeksi, 'en' englanniksi, 'both' molemmat. Tiedostoihin aina suomeksi.
  String moveNames = 'fi'; // suomen- ja saamenkielinen käyttöliittymä; englanniksi aina 'en'
  bool watch = false; // sykemittarin / älykellon tiedot näkyvissä
  bool restTimer = false; // palautusajastin sarjan tallennuksen jälkeen (oletus pois)
  String restSound = 'pling'; // pling / boop / chime / none (vain värinä)
  /// Oma säätö palautukseen (s) kuormaluokittain: kevyt, keskiraskas, raskas (ks. rest.dart).
  List<int> restAdjust = [0, 0, 0];
  int deloadEvery = 6;

  /// Viikko (maanantai), jolta kevennysvinkki on piilotettu. Vain tällä laitteella.
  String? deloadDismissed;
  List<Equipment> equipment = [...defaultEquipment];
  List<String> customExercises = [];
  List<Pause> pauses = [];

  /// Liikkeiden mittaustavat, jotka poikkeavat oletuksesta.
  Map<String, Measure> customMeasure = {};

  /// Vammatilan alueet (injury_data.dart id:t).
  List<String> injuries = [];

  /// Aloituskysely tehty tai ohitettu.
  bool introDone = false;

  /// Treeniohjelma (ohjelma.md). null = treenataan vapaasti.
  Program? program;
  Pause? get activePause => pauses.where((p) => p.end == null).firstOrNull;

  /// Omien liikkeiden kategoriat (nimi -> kategoria). Puuttuva = "Omat".
  Map<String, String> customCategory = {};

  /// Asetukset luetaan ensin laitteen välimuistista ja sitten treenikansion asetukset.md:stä,
  /// joka voittaa (näin asetukset kulkevat synkan, varmuuskopion ja palautuksen mukana).
  /// Vain kansion sijainti on pelkästään laitteella, koska sitä tarvitaan tiedoston löytämiseen.
  Future<void> load() async {
    // Verkkodemo: ei selaimen tallennusta, aloitetaan aina puhtaalta pöydältä. Kieli osoitteesta (?lang=en),
    // jotta englanninkielinen kotisivu avaa demon englanniksi.
    if (isDemo) {
      // Videota varten myös käännösaikainen kieli: --dart-define=DEMO_LANG=en
      final lang =
          Uri.base.queryParameters['lang'] ??
          (const String.fromEnvironment('DEMO_LANG').isEmpty ? null : const String.fromEnvironment('DEMO_LANG'));
      if (lang != null) {
        await setUiLang(lang);
        nameMode = 'fi';
      }
      return;
    }
    final sp = _p = await SharedPreferences.getInstance();
    folder = sp.getString('folder');
    deloadDismissed = sp.getString('deloadDismissed');
    bodySkipped = sp.getString('bodySkipped');
    homeView = sp.getString('homeView') == 'cardio' ? 'cardio' : 'gym';
    await setUiLang(sp.getString('lang') ?? 'fi');
    final cached = sp.getString('settingsMd');
    if (cached != null) applyMarkdown(cached);
    await loadFromFolder();
  }

  Future<File> settingsFile() async => File(p.join((await store.rootDir()).path, settingsFileName));

  /// Lukee kansion asetukset.md:n, jos sellainen on. Palauttaa true, jos löytyi.
  Future<bool> loadFromFolder() async {
    try {
      await _loadProgram();
      await _loadBody();
      final text = await files.read(settingsFileName);
      if (text == null) return false;
      applyMarkdown(text);
      await _p?.setString('settingsMd', settingsToMarkdown());
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File> programFile() async => File(p.join((await store.rootDir()).path, programFileName));

  Future<void> _loadProgram() async {
    try {
      final text = await files.read(programFileName);
      program = text == null ? null : parseProgram(text);
    } catch (_) {
      program = null;
    }
  }

  Future<void> _loadBody() async {
    try {
      final text = await files.read(bodyFileName);
      body = text == null ? BodyLog() : parseBody(text);
    } catch (_) {
      body = BodyLog();
    }
  }

  /// Tallentaa punnitukset ja pituuden kehonpaino.md:hen.
  Future<void> setBody(BodyLog b) async {
    body = b;
    notifyListeners();
    try {
      await files.write(bodyFileName, bodyToMarkdown(b));
      onLocalChange?.call(bodyFileName);
    } catch (_) {}
  }

  Future<void> setWeight(DateTime day, double? kg) async {
    final b = body.copy();
    kg == null ? b.weights.remove(dateOnly(day)) : b.weights[dateOnly(day)] = kg;
    await setBody(b);
  }

  void setBodyTracker(bool v) {
    bodyTracker = v;
    _persist();
  }

  void skipBodyToday(String day) {
    bodySkipped = day;
    _p?.setString('bodySkipped', day);
    notifyListeners();
  }

  TrainingStyle? style;

  void setStyle(TrainingStyle? s) {
    style = s;
    _persist();
  }

  Future<void> setProgram(Program? prog) async {
    program = prog;
    introDone = true;
    try {
      if (prog == null) {
        await files.delete(programFileName);
      } else {
        await files.write(programFileName, programToMarkdown(prog));
      }
      onLocalChange?.call(programFileName);
    } catch (_) {}
    await _persist();
  }

  void setMeasure(String exercise, Measure m) {
    customMeasure = {...customMeasure, exercise: m};
    _persist();
  }

  void setInjuries(List<String> ids) {
    injuries = ids;
    _persist();
  }

  void setIntroDone() {
    introDone = true;
    _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    final md = settingsToMarkdown();
    await _p?.setString('settingsMd', md);
    try {
      await files.write(settingsFileName, md);
      onLocalChange?.call(settingsFileName);
    } catch (_) {
      // Kansio ei ehkä ole käytettävissä (lupa puuttuu); välimuisti riittää siihen asti.
    }
  }

  String settingsToMarkdown() {
    final b = StringBuffer()
      ..writeln('---')
      ..writeln('name: ${name ?? ''}')
      ..writeln('theme: ${themeMode.name}')
      ..writeln('weightStep: ${fileNum(weightStep)}')
      ..writeln('tips: $tips')
      ..writeln('body_tracker: $bodyTracker')
      ..writeln('sports: $sports') // vanhemmat versiot lukevat tämän
      ..writeln('mode: $trainMode')
      ..writeln('move_names: $moveNames')
      ..writeln('watch: $watch')
      ..writeln('rest_timer: $restTimer')
      ..writeln('rest_sound: $restSound')
      ..writeln('rest_adjust: ${restAdjust.join(', ')}')
      ..writeln('deloadEvery: $deloadEvery')
      ..writeln('introDone: $introDone')
      ..writeln('---')
      ..writeln()
      ..writeln('# Gievran asetukset')
      ..writeln()
      ..writeln('Tämän tiedoston voi muokata käsin. Sovellus lukee sen käynnistyessään.')
      ..writeln()
      ..writeln('## Lämmittelylaitteet');
    final st = style;
    for (final e in equipment) {
      b.writeln('- ${e.icon} ${e.name}');
    }
    if (st != null && !st.isEmpty) {
      b
        ..writeln()
        ..writeln('## Treenityyli');
      if (st.goal != null) b.writeln('- tavoite: ${st.goal}');
      if (st.experience != null) b.writeln('- kokemus: ${st.experience}');
      if (st.days != null) b.writeln('- päivät: ${st.days}');
      if (st.minutes != null) b.writeln('- kesto: ${st.minutes}');
      if (st.repStyle != null) b.writeln('- toistot: ${st.repStyle}');
      if (st.equipment.isNotEmpty) b.writeln('- välineet: ${st.equipment.join(', ')}');
      if (st.moves.isNotEmpty) b.writeln('- liikkeet: ${st.moves.join(', ')}');
      if (st.kbFocus != null) b.writeln('- kahvakuula: ${st.kbFocus}');
    }
    b
      ..writeln()
      ..writeln('## Omat liikkeet');
    if (customMeasure.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Mittaustavat');
      for (final e in customMeasure.entries) {
        b.writeln('- ${e.key}: ${e.value.label}');
      }
    }
    if (injuries.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Vammat');
      for (final i in injuries) {
        b.writeln('- $i');
      }
    }
    if (pauses.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Tauot');
      for (final t in pauses) {
        b.writeln('- ${isoDate(t.start)} – ${t.end == null ? '' : isoDate(t.end!)} ${t.reason}'.replaceAll('  ', ' '));
      }
    }
    final byCat = <String, List<String>>{};
    for (final n in customExercises) {
      (byCat[customCategory[n] ?? ownCategory] ??= []).add(n);
    }
    for (final e in byCat.entries) {
      b
        ..writeln()
        ..writeln('### ${e.key}');
      for (final n in e.value) {
        b.writeln('- $n');
      }
    }
    return b.toString();
  }

  void applyMarkdown(String md) {
    final lines = md.split('\n').map((l) => l.trimRight()).toList();
    var i = 0;
    if (lines.isNotEmpty && lines[0].trim() == '---') {
      for (i = 1; i < lines.length && lines[i].trim() != '---'; i++) {
        final idx = lines[i].indexOf(':');
        if (idx <= 0) continue;
        final k = lines[i].substring(0, idx).trim();
        final v = lines[i].substring(idx + 1).trim();
        switch (k) {
          case 'name':
            if (v.isNotEmpty) name = v;
          case 'theme':
            themeMode = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => themeMode);
          case 'weightStep':
            weightStep = parseNum(v) ?? weightStep;
          case 'tips':
            tips = v != 'false';
          case 'body_tracker':
            bodyTracker = v == 'true';
          case 'sports': // vanha asetus: liikunta päällä -> molemmat (mode: voittaa, jos se on mukana)
            if (!lines.any((l) => l.trim().startsWith('mode:'))) trainMode = v == 'true' ? 'both' : 'gym';
          case 'mode':
            trainMode = const {'gym', 'cardio', 'both'}.contains(v) ? v : 'gym';
          case 'english_names': // vanha asetus (0.1.2-kehitysversio)
            if (v == 'true') moveNames = 'both';
          case 'move_names':
            moveNames = const {'fi', 'en', 'both'}.contains(v) ? v : 'fi';
            nameMode = moveNames;
          case 'watch':
            watch = v == 'true';
          case 'rest_timer':
            restTimer = v == 'true';
          case 'rest_adjust':
            final a = v.split(',').map((x) => int.tryParse(x.trim()) ?? 0).toList();
            restAdjust = [for (var i = 0; i < 3; i++) i < a.length ? a[i].clamp(-300, 300) : 0];
          case 'rest_sound':
            restSound = const {'pling', 'boop', 'chime', 'none'}.contains(v) ? v : 'pling';
          case 'introDone':
            introDone = v == 'true';
          case 'deloadEvery':
            deloadEvery = int.tryParse(v) ?? deloadEvery;
        }
      }
    }
    String? section;
    String sub = ownCategory;
    List<Equipment>? eq;
    List<String>? custom;
    Map<String, String>? cats;
    List<Pause>? pauseList;
    List<String>? inj;
    Map<String, Measure>? meas;
    TrainingStyle? st;
    for (; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.startsWith('## ')) {
        section = t.substring(3).trim();
        if (section == 'Lämmittelylaitteet') eq = [];
        if (section == 'Tauot') pauseList = [];
        if (section == 'Vammat') inj = [];
        if (section == 'Mittaustavat') meas = {};
        if (section == 'Treenityyli') st = TrainingStyle();
        if (section == 'Omat liikkeet') {
          custom = [];
          cats = {};
        }
        continue;
      }
      if (t.startsWith('### ')) {
        sub = t.substring(4).trim();
        continue;
      }
      if (!t.startsWith('- ')) continue;
      final item = t.substring(2).trim();
      if (item.isEmpty) continue;
      if (section == 'Lämmittelylaitteet') {
        // Ensimmäinen "sana" on kuvake, jos se ei ole kirjain.
        final sp = item.indexOf(' ');
        final head = sp > 0 ? item.substring(0, sp) : '';
        final isIcon = head.isNotEmpty && !RegExp(r'[A-Za-zÅÄÖåäöÁáČčĐđŊŋŠšŦŧŽž0-9]').hasMatch(head);
        eq!.add(isIcon ? Equipment(head, item.substring(sp + 1).trim()) : Equipment('⭐', item));
      } else if (section == 'Mittaustavat') {
        final k = item.lastIndexOf(':');
        final m = k > 0 ? Measure.byName(item.substring(k + 1).trim()) : null;
        if (m != null) meas![item.substring(0, k).trim()] = m;
      } else if (section == 'Treenityyli') {
        final k = item.indexOf(':');
        if (k <= 0) continue;
        final v = item.substring(k + 1).trim();
        List<String> list() => [
          for (final x in v.split(','))
            if (x.trim().isNotEmpty) x.trim(),
        ];
        switch (item.substring(0, k).trim()) {
          case 'tavoite':
            st!.goal = v.isEmpty ? null : v;
          case 'kokemus':
            st!.experience = v.isEmpty ? null : v;
          case 'päivät':
            st!.days = int.tryParse(v);
          case 'kesto':
            st!.minutes = int.tryParse(v);
          case 'toistot':
            st!.repStyle = v.isEmpty ? null : v;
          case 'välineet':
            st!.equipment = list().toSet();
          case 'liikkeet':
            st!.moves = list();
          case 'kahvakuula':
            st!.kbFocus = v.isEmpty ? null : v;
        }
      } else if (section == 'Vammat') {
        inj!.add(item.split(' ').first);
      } else if (section == 'Tauot') {
        final m = RegExp(r'^(\d{4}-\d{2}-\d{2})\s*[–-]\s*(\d{4}-\d{2}-\d{2})?\s*(\S+)?').firstMatch(item);
        if (m != null) {
          pauseList!.add(Pause(DateTime.parse(m[1]!), m[3] ?? 'loma', m[2] == null ? null : DateTime.parse(m[2]!)));
        }
      } else if (section == 'Omat liikkeet') {
        if (!custom!.contains(item)) custom.add(item);
        if (sub != ownCategory) cats![item] = sub;
      }
    }
    if (eq != null) {
      // Vanha oletuslista ilman muutoksia saa uuden oletuksen (venyttely) mukaan.
      if (eq.map((e) => e.name).join('|') == _oldDefaults.join('|')) eq.add(defaultEquipment.last);
      equipment = eq;
    }
    if (st != null) style = st;
    if (pauseList != null) pauses = pauseList;
    if (inj != null) injuries = inj;
    if (meas != null) customMeasure = meas;
    if (custom != null) {
      customExercises = custom;
      customCategory = cats!;
    }
  }

  void setName(String v) {
    name = v.trim();
    _persist();
  }

  /// Vaihtaa treenikansion. Jos uudessa kansiossa on asetukset.md, se otetaan käyttöön,
  /// muuten nykyiset asetukset kirjoitetaan sinne.
  /// Treenikansion .md-tiedostot (treenit, asetukset, ohjelma) suhteellisina polkuina.
  static Future<List<String>> mdFiles(Directory dir) async {
    if (!await dir.exists()) return [];
    final out = <String>[];
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && e.path.endsWith('.md')) out.add(p.relative(e.path, from: dir.path));
      }
    } catch (_) {}
    return out;
  }

  /// Kopioi .md-tiedostot kansiosta toiseen. Olemassa olevia ei ylikirjoiteta. Palauttaa (kopioitu, ohitettu).
  static Future<(int, int)> copyMdFiles(Directory from, Directory to) async {
    var copied = 0, skipped = 0;
    for (final rel in await mdFiles(from)) {
      final target = File(p.join(to.path, rel));
      if (await target.exists()) {
        skipped++;
        continue;
      }
      await target.parent.create(recursive: true);
      await File(p.join(from.path, rel)).copy(target.path);
      copied++;
    }
    return (copied, skipped);
  }

  Future<void> setFolder(String? v) async {
    folder = v;
    v == null ? await _p?.remove('folder') : await _p?.setString('folder', v);
    if (!await loadFromFolder()) await _persist();
    notifyListeners();
  }

  /// Käyttöliittymän kieli on laitekohtainen (ei asetukset.md:ssä): treenitiedostot pysyvät suomeksi.
  Future<void> setLang(String code) async {
    await setUiLang(code);
    await _p?.setString('lang', uiLang);
    // Englanninkielisessä käyttöliittymässä liikkeiden ja lajien nimet ovat aina englanniksi (effectiveNameMode);
    // suomen ja saamen nimiasetus (suomi / englanti / molemmat) säilyy ennallaan.
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _persist();
  }

  void startPause(String reason, DateTime start) {
    pauses = [...pauses.where((p) => p.end != null), Pause(dateOnly(start), reason)];
    _persist();
  }

  /// Päättää tauon. [lastDay] = viimeinen taukopäivä (oletus eilen).
  void endPause([DateTime? lastDay]) {
    final p = activePause;
    if (p == null) return;
    var end = dateOnly(lastDay ?? addDays(DateTime.now(), -1));
    if (end.isBefore(p.start)) end = p.start;
    p.end = end;
    _persist();
  }

  /// [cls]: 0 kevyt, 1 keskiraskas, 2 raskas; [delta] ±15 s. Null nollaa.
  void adjustRest(int cls, int? delta) {
    restAdjust = [...restAdjust];
    restAdjust[cls] = delta == null ? 0 : (restAdjust[cls] + delta).clamp(-300, 300);
    _persist();
  }

  void setRestSound(String v) {
    restSound = v;
    _persist();
  }

  void setRestTimer(bool v) {
    restTimer = v;
    _persist();
  }

  void setWatch(bool v) {
    watch = v;
    _persist();
  }

  void setMoveNames(String v) {
    moveNames = v;
    nameMode = v;
    _persist();
  }

  void setSports(bool v) {
    sports = v;
    _persist();
  }

  void setTrainMode(String v) {
    trainMode = v;
    _persist();
  }

  void setHomeView(String v) {
    homeView = v;
    _p?.setString('homeView', v);
    notifyListeners();
  }

  void setTips(bool v) {
    tips = v;
    _persist();
  }

  void setDeloadEvery(int v) {
    deloadEvery = v;
    _persist();
  }

  void dismissDeload(String week) {
    deloadDismissed = week;
    _p?.setString('deloadDismissed', week);
    notifyListeners();
  }

  void setWeightStep(double v) {
    weightStep = v;
    _persist();
  }

  void setEquipment(List<Equipment> list) {
    equipment = list;
    _persist();
  }

  void addCustomExercise(String n) => addCustomExercises({n: ownCategory});

  /// Oma liike pois (esim. yhdistetty valmiiseen liikkeeseen). Treenit eivät muutu.
  void removeCustomExercise(String n) {
    if (!customExercises.contains(n)) return;
    customExercises = [...customExercises]..remove(n);
    customCategory.remove(n);
    customMeasure.remove(n);
    _persist();
  }

  /// nimi -> kategoria
  void addCustomExercises(Map<String, String> names) {
    final add = names.keys.where((n) => !customExercises.contains(n)).toList();
    if (add.isEmpty) return;
    customExercises = [...customExercises, ...add];
    for (final n in add) {
      if (names[n] != ownCategory) customCategory[n] = names[n]!;
    }
    _persist();
  }
}

const settingsFileName = 'asetukset.md';
const ownCategory = 'Omat';

/// Lukee ja kirjoittaa treenit .md-tiedostoina valittuun kansioon.
class WorkoutStore extends ChangeNotifier {
  List<Workout> workouts = []; // uusin ensin

  /// Kasvaa jokaisella muutoksella: raskaat laskelmat (oivallukset, päiväehdotus) välimuistiin tämän mukaan.
  int rev = 0;

  @override
  void notifyListeners() {
    rev++;
    super.notifyListeners();
  }

  String? error;

  Future<Directory> defaultDir() async {
    if (Platform.isAndroid) {
      // Sovelluksen oma kansio Android/data/... (ei vaadi lupia). Synkattava kansio valitaan asetuksista.
      final ext = await getExternalStorageDirectory();
      if (ext != null) return Directory(p.join(ext.path, 'Treenit'));
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'Treenit'));
  }

  Future<Directory> rootDir() async => settings.folder != null ? Directory(settings.folder!) : await defaultDir();

  String fileName(DateTime d, [int session = 1]) => p.joinAll(workoutPath(d, session).split('/'));

  Future<void> reload() async {
    error = null;
    final list = <Workout>[];
    try {
      for (final e in (await files.all()).entries) {
        final base = p.basename(e.key);
        final m = RegExp(r'^(\d{4}-\d{2}-\d{2}).*\.md$').firstMatch(base);
        if (m == null) continue;
        try {
          list.add(parseWorkout(e.value, fallbackDate: DateTime.parse(m[1]!), fallbackSession: sessionFromName(base)));
        } catch (_) {
          // Rikkinäinen tai vieras tiedosto: ohitetaan.
        }
      }
    } catch (e) {
      error = 'Kansiota ei voitu lukea: $e';
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    workouts = list;
    notifyListeners();
  }

  /// Päivän ensimmäinen treeni.
  Workout? forDate(DateTime d) => onDay(d).firstOrNull;

  /// Päivän kaikki treenit järjestyksessä (sali, illan juoksu …).
  List<Workout> onDay(DateTime d) {
    final day = dateOnly(d);
    return workouts.where((w) => w.date == day).toList()..sort((a, b) => a.session.compareTo(b.session));
  }

  /// Seuraava vapaa treeninumero päivälle.
  int nextSession(DateTime d) => onDay(d).fold(0, (a, w) => w.session > a ? w.session : a) + 1;

  /// Kirjoittaa treenin tallentamattoman reitin .gpx-tiedostoksi ja liittää sen treeniin.
  Future<void> _writeRoute(Workout w) async {
    final gpx = w.routeGpx;
    if (gpx == null) return;
    final rel = routePath(w.date, w.session);
    await files.write(rel, gpx);
    onLocalChange?.call(rel);
    w.route = rel.split('/').last;
    w.routeGpx = null;
  }

  /// Treenin reitti GPX-tekstinä (null = ei reittiä tai tiedosto puuttuu).
  Future<String?> readRoute(Workout w) async => w.routeGpx ?? (w.route == null ? null : files.read(routeRel(w)));

  Future<String> save(Workout w) async {
    await _writeRoute(w);
    final path = await files.write(workoutPath(w.date, w.session), workoutToMarkdown(w));
    onLocalChange?.call(workoutPath(w.date, w.session));
    workouts
      ..removeWhere((x) => x.date == w.date && x.session == w.session)
      ..add(w.copy())
      ..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    return path;
  }

  /// Tuonti: kirjoittaa treenit levylle. Olemassa olevat päivät ohitetaan (ei ylikirjoitusta).
  /// Palauttaa tallennettujen määrän.
  Future<int> saveMany(Iterable<Workout> list) async {
    var n = 0;
    for (final w in list) {
      if (onDay(w.date).any((x) => x.session == w.session)) continue;
      final rel = workoutPath(w.date, w.session);
      if (await files.exists(rel)) continue;
      await _writeRoute(w);
      await files.write(rel, workoutToMarkdown(w));
      onLocalChange?.call(workoutPath(w.date, w.session));
      n++;
    }
    await reload();
    return n;
  }

  Future<void> delete(DateTime d, [int session = 1]) async {
    final old = onDay(d).where((x) => x.session == session).firstOrNull;
    if (old?.route != null) {
      await files.delete(routeRel(old!));
      onLocalChange?.call(routeRel(old));
    }
    await files.delete(workoutPath(d, session));
    onLocalChange?.call(workoutPath(d, session));
    workouts.removeWhere((x) => x.date == dateOnly(d) && x.session == session);
    notifyListeners();
  }

  /// Raskain aiempi sarja liikkeessä ennen annettua päivää.
  double maxKgBefore(String exercise, DateTime before) {
    var best = 0.0;
    for (final w in workouts) {
      if (!w.date.isBefore(before)) continue;
      for (final e in w.exercises) {
        if (e.name != exercise) continue;
        for (final s in e.sets) {
          if (s.kg > best) best = s.kg;
        }
      }
    }
    return best;
  }

  /// Edellinen kerta, kun liike tehtiin ennen annettua päivää.
  (DateTime, ExerciseEntry)? lastBefore(String exercise, DateTime before) {
    for (final w in workouts) {
      if (!w.date.isBefore(before)) continue;
      for (final e in w.exercises) {
        if (e.name == exercise && e.sets.isNotEmpty) return (w.date, e);
      }
    }
    return null;
  }
}

/// Treenikansion tiedostot: puhelimessa ja tietokoneella oikeat .md-tiedostot, verkkodemossa muistissa
/// (mitään ei tallenneta). Polut ovat suhteellisia treenikansioon, erotin '/'.
abstract class TrainingFiles {
  Future<String?> read(String rel);

  /// Kirjoittaa ja palauttaa näytettävän polun.
  Future<String> write(String rel, String text);
  Future<void> delete(String rel);
  Future<bool> exists(String rel);

  /// Kaikki .md-tiedostot (suhteellinen polku -> sisältö).
  Future<Map<String, String>> all();
}

class IoTrainingFiles implements TrainingFiles {
  Future<File> _f(String rel) async => File(p.joinAll([(await store.rootDir()).path, ...rel.split('/')]));

  @override
  Future<String?> read(String rel) async {
    final f = await _f(rel);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<String> write(String rel, String text) async {
    final f = await _f(rel);
    await f.parent.create(recursive: true);
    await f.writeAsString(text);
    return f.path;
  }

  @override
  Future<void> delete(String rel) async {
    final f = await _f(rel);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<bool> exists(String rel) async => (await _f(rel)).exists();

  @override
  Future<Map<String, String>> all() async {
    final dir = await store.rootDir();
    final out = <String, String>{};
    if (!await dir.exists()) return out;
    final files = <File>[
      await for (final e in dir.list(recursive: true, followLinks: false))
        if (e is File && (e.path.endsWith('.md') || e.path.endsWith('.gmd'))) e,
    ];
    // Luetaan 32 tiedostoa kerrallaan rinnakkain: satojen treenien kansio aukeaa nopeammin kuin yksi kerrallaan.
    for (var i = 0; i < files.length; i += 32) {
      final chunk = files.sublist(i, i + 32 > files.length ? files.length : i + 32);
      final texts = await Future.wait(chunk.map((f) => f.readAsString().then<String?>((t) => t, onError: (_) => null)));
      for (var j = 0; j < chunk.length; j++) {
        if (texts[j] != null) out[p.relative(chunk[j].path, from: dir.path).replaceAll(r'\', '/')] = texts[j]!;
      }
    }
    return out;
  }
}

/// Verkkodemo: tiedostot vain muistissa, katoavat kun sivu suljetaan.
class MemoryTrainingFiles implements TrainingFiles {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String rel) async => data[rel];

  @override
  Future<String> write(String rel, String text) async {
    data[rel] = text;
    return 'demo/$rel';
  }

  @override
  Future<void> delete(String rel) async => data.remove(rel);

  @override
  Future<bool> exists(String rel) async => data.containsKey(rel);

  @override
  Future<Map<String, String>> all() async => {...data};
}

/// Verkkoversio on demo: ei tiedostoja eikä pysyvää tallennusta.
// Verkossa aina demo; muualla vain kuvakaappauksia ja esittelyä varten: --dart-define=DEMO=true.
const bool isDemo = kIsWeb || bool.fromEnvironment('DEMO');
final TrainingFiles files = isDemo ? MemoryTrainingFiles() : IoTrainingFiles();
