import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, listEquals, setEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'body.dart';
import 'custom_merge.dart' show builtinExercises;
import 'l10n.dart';
import 'plates.dart';
import 'durable_write.dart';
import 'models.dart';
import 'home_layout.dart';
import 'program.dart';
import 'running.dart' show RunBand, defaultRunBands, runBandsFromFile, runBandsToFile;
import 'exercises.dart';
import 'recovery.dart' show recoveryOrderDefault, recoveryTileKeys;
import 'heart_rate.dart' show hrProfile, repairLowCoverageKcal, repairWalkKcal;

final settings = Settings();
final store = WorkoutStore();

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

/// Treenitiedosto muussa merkistössä kuin UTF-8: UTF-16 (BOM) tai Windowsin Latin-1. Palauttaa tekstin vain, jos
/// se näyttää Gievran treeniltä (etusivun --- tai # -otsikko) eikä siinä ole ohjausmerkkejä (ei binääritiedostoa).
/// Kelvollinen UTF-8 palauttaa null: silloin vika ei ole merkistössä.
String? decodeLegacyText(List<int> bytes) {
  String text;
  if (bytes.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    final le = bytes[0] == 0xFF;
    final units = <int>[
      for (var i = 2; i + 1 < bytes.length; i += 2)
        le ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
    ];
    text = String.fromCharCodes(units);
  } else {
    try {
      utf8.decode(bytes);
      return null;
    } on FormatException {
      text = latin1.decode(bytes);
    }
  }
  text = text.replaceAll('\r\n', '\n');
  if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(text)) return null;
  final head = text.trimLeft();
  return head.startsWith('---') || head.startsWith('# ') ? text : null;
}

/// Miksi treenitiedostoa ei voitu lukea, käyttäjän kielellä: näytetään ilmoituksessa ja ongelmaraportissa.
/// [bytes] null = tiedostoa ei saatu auki; [error] = sisällön tulkinta epäonnistui.
String unreadableReason(List<int>? bytes, {Object? error}) {
  if (bytes == null) return t('Tiedostoa ei voitu avata: {0}', [error == null ? '?' : errorText(error)]);
  if (error != null) return t('Sisältöä ei voitu tulkita: {0}', [errorText(error)]);
  if (bytes.isEmpty) return t('Tiedosto on tyhjä');
  if (decodeLegacyText(bytes) != null) return t('Väärä merkistö (voidaan korjata)');
  final sample = bytes.take(4096);
  if (sample.any((b) => b < 9 || (b > 13 && b < 32 && b != 27))) {
    return t('Ei tekstitiedosto: vaurioitunut tai väärä tiedosto');
  }
  return t('Merkistöä ei tunnistettu');
}

/// Onko teksti luettava tiedosto: ei tyhjä eikä ohjausmerkkejä (sarkain ja rivinvaihdot sallittu).
bool looksLikeText(String text) => text.trim().isNotEmpty && !_controlChars.hasMatch(text);
final _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1A\x1C-\x1F]');

/// Tekstitiedoston luku tuonnissa: UTF-8, tai Windowsin Latin-1 / UTF-16 korjattuna ([decodeLegacyText]).
/// Palauttaa (teksti, korjattiin) tai null, jos tiedostoa ei voi lukea. Ennen tuonti luki väärän merkistön
/// hiljaa korvausmerkeillä (Kävely → K\uFFFDvely).
(String, bool)? decodeTextFile(List<int> bytes) {
  try {
    final text = utf8.decode(bytes);
    // Tyhjä tai ohjausmerkkejä (binääri, joka sattuu olemaan kelvollista UTF-8:aa): ei treeni.
    return looksLikeText(text) ? (text, false) : null;
  } on FormatException {
    final text = decodeLegacyText(bytes);
    return text == null ? null : (text, true);
  }
}

/// vvvv-kk-pp vain, jos päivä on olemassa (ei 2026-13-40 tai 2026-02-30).
DateTime? _validDate(String s) {
  final d = DateTime.tryParse(s);
  return d != null && isoDate(d) == s ? d : null;
}

/// Tauko treenaamisesta: sairaus tai loma. end == null = tauko on päällä.
class Pause {
  final DateTime start;
  DateTime? end;
  final String reason; // 'sairas' | 'loma' | 'vamma'
  Pause(this.start, this.reason, [this.end]);

  /// Sairaus tai vamma: paluu varovaisemmin (vamma kolmantena syynä, käyttäjä 16.11.).
  bool get sick => reason == 'sairas' || reason == 'vamma';
  bool get injury => reason == 'vamma';

  /// Päättymispäivä voi olla etukäteen tiedossa (loma 16.–22.11.): tauko on päällä alkupäivästä päättymispäivään
  /// asti ja päättyy itsestään (käyttäjä 16.11.). Ilman päättymispäivää jatkuu, kunnes käyttäjä lopettaa sen.
  bool activeOn(DateTime d) {
    final x = dateOnly(d);
    if (stopped && !x.isBefore(dateOnly(DateTime.now()))) return false;
    return !x.isBefore(start) && (end == null || !x.isAfter(end!));
  }

  /// Lopetettu käsin tänään (viimeinen päivä tänään): ei enää päällä, vaikka päivä kuuluu taukoon.
  bool stopped = false;

  /// Päivä [d] tauon aikana (myös mennyt tauko, kalenteri).
  bool covers(DateTime d) {
    final x = dateOnly(d);
    return !x.isBefore(start) && (end == null || !x.isAfter(end!));
  }

  /// Taukopäiviä tähän mennessä (enintään päättymispäivään).
  int get days {
    final today = dateOnly(DateTime.now());
    final last = end != null && end!.isBefore(today) ? end! : today;
    return last.difference(start).inDays + 1;
  }
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
  /// Päivä tai vuorokaudenaika vaihtui sovelluksen ollessa auki (DayWatch): näkymät rakentuvat uudelleen.
  void dayChanged() => notifyListeners();

  // l10n: data
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
  String? folder;
  ThemeMode themeMode = ThemeMode.system; // oletus: järjestelmän asetus

  /// Tekstin koko: small = alkuperäinen koko (oletus), normal 115 %, large 130 %. Kerrotaan puhelimen oman
  /// fonttikoon päälle.
  String textSize = 'small';
  static const textSizes = {'small': 1.0, 'normal': 1.15, 'large': 1.3};
  double get textFactor => textSizes[textSize] ?? 1.0;
  double weightStep = 2.5;

  /// Levylaskuri: omat levyt (kg) ja tangon paino.
  List<double> plates = [...defaultPlates];
  double barKg = defaultBarKg;

  /// Hex barin (kuusikulmatangon) paino; null = ei asetettu, jolloin levylaskuri ei ole käytössä hex bar
  /// -liikkeissä (käyttäjä 18.11.: hex barit painavat mitä tahansa, tyypillisesti 20–30 kg).
  double? hexBarKg;

  /// Liikekohtainen tangon paino (käyttäjä 18.11.: esim. ranteen koukistus 10 kg:n tangolla). Vain levylaskuriin ja
  /// hex barin alkupainoon; kirjatut sarjat ovat aina kokonaispainoja, joten tämä ei muuta tallennettua dataa.
  Map<String, double> exerciseBars = {};
  bool tips = true;

  /// Kehonpainon seuranta (asetukset.md: body_tracker). Punnitukset ja pituus kehonpaino.md:ssä ([body]).
  bool bodyTracker = false;

  /// Painon kehitys etusivulla (oma kortti käyrineen; käyttäjä 17.11.): erillään punnitusten kysymisestä.
  bool weightOnHome = false;

  /// Juoksun matkaryhmät etusivun Juoksun kehitys -kortissa (1–3, käyttäjä 17.11.).
  List<RunBand> runBands = defaultRunBands;

  /// Yöarvot-kortin näytettävät arvot (käyttäjä 17.11.: muokattava; oletus kaikki): hrv, rest, rr, spo2, temp.
  /// Palautuminen-kortin ruudut (yöarvot sekä uni ja kuormitus, 18.11.); oletuksena kaikki.
  Set<String> nightTiles = {...recoveryTileKeys};

  /// Palautuminen-kortin ruutujen järjestys (käyttäjä 18.11.: valittavissa ja järjestettävissä).
  List<String> recoveryOrder = [...recoveryOrderDefault];

  void setRecoveryOrder(List<String> v) {
    recoveryOrder = v;
    _persist();
  }

  void setNightTile(String k, bool on) {
    on ? nightTiles.add(k) : nightTiles.remove(k);
    _persist();
  }

  /// Oma unitavoite minuutteina (käyttäjä 17.11.; Walsh ym. 2021: yksilöllinen; oletus 7 h = 420).
  int sleepGoal = 420;

  /// Terveys ja hyvinvointi käytössä (askeleet, kehonpaino, palautuminen tai uni). Pois = pelkkä treenipäiväkirja:
  /// etusivu näyttää treenin luvut (treeniputki, sarjat ja treeniaika) WHO:n terveysluvuista (käyttäjä 19.11.).
  bool get wellness =>
      dailySteps || bodyTracker || homeCardOn('recovery') || homeCardOn('sleep') || homeCardOn('night');

  /// Treenipäivien viikkotavoite: ohjelman salipäivät (liikunnassa ja molemmissa ohjelman päivät), muuten 2.
  int get weeklyTrainingTarget {
    final p = program;
    if (p == null || p.plan.isEmpty) return 2;
    return trainMode == 'gym' ? p.plan.length : (p.days > p.plan.length ? p.days : p.plan.length);
  }

  /// Unen lähde (käyttäjä 19.11.: kaksi unimittaria, esim. Oura ja kello, kirjaavat saman yön eri arvoin).
  /// null = automaattinen: sovellus, jolla on eniten tallennettuja öitä.
  String? sleepApp;

  void setSleepApp(String? v) {
    sleepApp = (v == null || v.trim().isEmpty) ? null : v.trim();
    _persist();
  }

  /// Uni-kortti on jo kysynyt oletuslähteen (kahden sovelluksen yö): ei kysytä uudelleen.
  bool sleepSourceAsked = false;

  void setSleepSourceAsked(bool v) {
    sleepSourceAsked = v;
    _persist();
  }

  void setSleepGoal(int v) {
    sleepGoal = v.clamp(300, 720);
    _persist();
  }

  /// Päivän askeltavoite (käyttäjä 17.11.: muokattava; oletus 10 000). Asetukset → Etusivu.
  int stepsGoal = 10000;

  void setStepsGoal(int v) {
    stepsGoal = v.clamp(1000, 50000);
    _persist();
  }

  /// Etusivun omat tavoitteet (0–3; käyttäjä 17.11.). Ohjelman salipäivät eivät ole oletustavoite: ne ovat
  /// lihaskuntopäivien renkaan tavoite (käyttäjä 17.11.: lihaskuntopäivä ja sali yhdeksi renkaaksi).
  List<Goal>? _goals;
  List<Goal> get goals => _goals ?? const [];

  /// Etusivun korttien järjestys ja piilotetut (kehonpainon näkyvyys: [weightOnHome]).
  List<String> homeOrder = [...homeCardIds];
  Set<String> homeHidden = {...homeCardsOffByDefault};

  bool homeCardOn(String id) => id == 'weight' ? bodyTracker && weightOnHome : !homeHidden.contains(id);

  /// Kalorilaskennan perustiedot (sykevyö): syntymävuosi ja sukupuoli ('mies' / 'nainen'). Pituus ja paino
  /// kehonpainon seurannasta ([body]).
  int? birthYear;
  String? sex;

  /// Palautuminen sarjojen välillä: valmis, kun syke on alle tämän %:n maksimisykkeestä (oletus 60).
  int hrRecoveryPct = 60;

  /// Oma mitattu maksimisyke (esim. maksimitesti); null = arvio iästä (Tanaka 2001).
  int? maxHr;

  /// Kalorien oma korjaus −10…+10 % (oletus 0 = tutkimuksen arvo), jos käyttäjä tietää kulutuksensa paremmin
  /// (esim. kuntotesti tai pitkä seuranta).
  int kcalAdjustPct = 0;
  BodyLog body = BodyLog();

  /// Päivä, jolta etusivun painokortti on ohitettu (laitekohtainen).
  String? bodySkipped;

  /// Omat tiedot (syntymävuosi ym.) kysytty kerran kellon sykkeen haun jälkeen (laitekohtainen, ei asetukset.md:ssä).
  bool hrProfileAsked = false;

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
  /// Saamenkielisessä käyttöliittymässä vammatilan ohjeet: 'fi' suomeksi tai 'en' englanniksi.
  String healthLang = 'fi';
  String moveNames = 'fi'; // suomen- ja saamenkielinen käyttöliittymä; englanniksi aina 'en'
  bool watch = false; // sykemittarin / älykellon tiedot näkyvissä
  bool restTimer = false; // palautusajastin sarjan tallennuksen jälkeen (oletus pois)

  /// Palautus sykkeen mukaan (sykevyö): ajastin odottaa sykkeen laskua ajan sijaan. Tiedostossa "rest_hr: true".
  bool restByHr = false;
  String restSound = 'pling'; // pling / boop / chime / none (vain värinä)
  /// Oma säätö palautukseen (s) kuormaluokittain: kevyt, keskiraskas, raskas (ks. rest.dart).
  List<int> restAdjust = [0, 0, 0];
  int deloadEvery = 6;

  /// Käynnissä oleva treeni Androidin ilmoituksena (oletus päällä).
  bool ongoingNote = true;
  void setOngoingNote(bool v) {
    ongoingNote = v;
    _persist();
  }

  /// Korkeustiedot ladataan karttojen mukana (alueen nousut ja korkeusprofiili; oletus päällä).
  bool elevWithMaps = true;
  void setElevWithMaps(bool v) {
    elevWithMaps = v;
    _persist();
  }

  /// Päivän askeleet Health Connectista (Android; oletus pois): etusivun kortti ja tilastot (daily_steps.dart).
  bool dailySteps = false;
  bool swimPer100m = false; // uinnin vauhti 100 metrille (näyttö)
  void setDailySteps(bool v) {
    dailySteps = v;
    _persist();
  }

  /// Etusivun "Lisää tehty liikunta Health Connectista" (Android; oletus pois).
  bool hcImport = false;
  void setHcImport(bool v) {
    hcImport = v;
    _persist();
  }

  /// GPS-reitin korjaus poluille lajeittain (metrit 3–10, 0 = pois); puuttuva laji = 5 m.
  Map<String, int> snapDefaults = {};
  int snapFor(String sport) => snapDefaults[sport] ?? 5;
  void setSnapDefault(String sport, int m) {
    if (snapDefaults[sport] == m) return;
    snapDefaults = {...snapDefaults, sport: m};
    _persist();
  }

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

  /// Aloitussivu (kieli, mitä treenaat…) käyty. Vanhoissa asetuksissa (ennen 0.6.6) tieto oli vain nimessä: annettu
  /// `name:` luetaan aloituksen merkiksi (applyMarkdown), itse nimeä ei enää tallenneta (käyttäjä 19.11.).
  bool started = false;
  bool get onboarded => started;

  /// Aloitussivun "Aloitetaan": aloitus käydyksi.
  void finishOnboarding() {
    started = true;
    _persist();
  }

  /// Treeniohjelma (ohjelma.md). null = treenataan vapaasti.
  Program? program;
  Pause? get activePause => pauses.where((p) => p.activeOn(DateTime.now())).firstOrNull;

  /// Tuleva tauko (alkaa myöhemmin, esim. loma ensi viikolla).
  Pause? get upcomingPause => pauses.where((p) => p.start.isAfter(dateOnly(DateTime.now()))).firstOrNull;

  /// Tauko, jonka aikana päivä [d] oli (kalenteri ja päivänäkymä).
  Pause? pauseOn(DateTime d) => pauses.where((p) => p.covers(d)).firstOrNull;

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
    hrProfileAsked = sp.getBool('hrProfileAsked') ?? false;
    homeView = sp.getString('homeView') == 'cardio' ? 'cardio' : 'gym';
    await setUiLang(sp.getString('lang') ?? 'fi');
    final cached = sp.getString('settingsMd');
    if (cached != null) applyMarkdown(cached);
    await loadFromFolder();
    await ensureEnglish();
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
      await ensureEnglish();
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

  void setRunBands(List<RunBand> v) {
    runBands = v.isEmpty ? defaultRunBands : v.take(3).toList();
    _persist();
  }

  @visibleForTesting
  set debugGoals(List<Goal>? v) => _goals = v;

  void setGoals(List<Goal> v) {
    _goals = v.take(3).toList();
    _persist();
  }

  void setHomeOrder(List<String> order) {
    homeOrder = order;
    _persist();
  }

  void setHomeCard(String id, bool on) {
    if (id == 'weight') return setWeightOnHome(on);
    on ? homeHidden.remove(id) : homeHidden.add(id);
    _persist();
  }

  void setWeightOnHome(bool v) {
    weightOnHome = v;
    _persist();
  }

  void setMaxHr(int? v) {
    maxHr = v?.clamp(120, 230);
    _persist();
  }

  void setKcalAdjust(int pct) {
    kcalAdjustPct = pct.clamp(-10, 10);
    _persist();
  }

  void setHrRecovery(int pct) {
    hrRecoveryPct = pct.clamp(40, 80);
    _persist();
  }

  /// Tuonti nykyiseen päiväkirjaan: sykevyön tiedot varmuuskopiosta vain niiltä osin, kuin tällä laitteella ei ole
  /// omia (syntymävuosi, sukupuoli, oma maksimisyke, palautumisraja, kalorien korjaus). Omia ei ylikirjoiteta.
  void mergeHrProfile(Settings o) {
    final before = (birthYear, sex, maxHr, hrRecoveryPct, kcalAdjustPct);
    birthYear ??= o.birthYear;
    sex ??= o.sex;
    maxHr ??= o.maxHr;
    if (hrRecoveryPct == 60) hrRecoveryPct = o.hrRecoveryPct;
    if (kcalAdjustPct == 0) kcalAdjustPct = o.kcalAdjustPct;
    if (before != (birthYear, sex, maxHr, hrRecoveryPct, kcalAdjustPct)) _persist();
  }

  /// Sykkeen perustiedot: syntymävuosi (sykealueet), sukupuoli, pituus ja nykyinen paino (punnitus tälle päivälle,
  /// kalorit). Vain syntymävuosi on pakollinen; puuttuvat jäävät ennalleen. [maxHr]: oma mitattu maksimisyke.
  Future<void> setProfile({required int birthYear, String? sex, int? heightCm, double? weightKg, int? maxHr}) async {
    this.birthYear = birthYear;
    if (sex != null) this.sex = sex;
    if (maxHr != null) this.maxHr = maxHr.clamp(120, 230);
    final b = body.copy();
    if (heightCm != null) b.heightCm = heightCm;
    if (weightKg != null && b.sorted.lastOrNull?.$2 != weightKg) b.weights[dateOnly(DateTime.now())] = weightKg;
    await setBody(b);
    _persist();
  }

  void markHrProfileAsked() {
    hrProfileAsked = true;
    _p?.setBool('hrProfileAsked', true);
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
    } catch (_) {}
    await _persist();
  }

  /// Omien liikkeiden lihakset (käyttäjä 16.11.): liike → lihakset ja osat (muscleAreas).
  Map<String, List<String>> customMuscles = {};

  void setCustomMuscles(String exercise, List<String> muscles) {
    customMuscles = {...customMuscles, exercise: muscles};
    _syncCustomMuscles();
    _persist();
  }

  /// Viikon kuorman rekisteri: valitut lihakset, muuten kategorian mukaan (vanhat omat liikkeet ilman valintaa).
  void _syncCustomMuscles() {
    const byCategory = {
      'Rinta': ['rinta'],
      'Selkä': ['leveä selkälihas', 'yläselkä'],
      'Olkapäät': ['etuolkapää', 'sivuolkapää'],
      'Keskivartalo': ['vatsa'],
    };
    customExerciseMuscles
      ..clear()
      ..addAll({for (final n in customExercises) n: ?(customMuscles[n] ?? byCategory[customCategory[n]])});
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
    } catch (_) {
      // Kansio ei ehkä ole käytettävissä (lupa puuttuu); välimuisti riittää siihen asti.
    }
  }

  String settingsToMarkdown() {
    final b = StringBuffer()
      ..writeln('---')
      ..writeln('theme: ${themeMode.name}')
      ..writeln('text_size: $textSize')
      ..writeln('weightStep: ${fileNum(weightStep)}')
      ..writeln('plates: ${plates.map(fileNum).join('; ')}')
      ..writeln('bar: ${fileNum(barKg)}')
      ..write(hexBarKg == null ? '' : 'hex_bar: ${fileNum(hexBarKg!)}\n')
      ..write(
        exerciseBars.isEmpty
            ? ''
            : 'exercise_bars: ${exerciseBars.entries.map((e) => '${e.key}=${fileNum(e.value)}').join('; ')}\n',
      )
      ..writeln('tips: $tips')
      ..writeln('body_tracker: $bodyTracker')
      ..writeln('weight_home: $weightOnHome')
      ..write(listEquals(runBands, defaultRunBands) ? '' : 'run_bands: ${runBandsToFile(runBands)}\n')
      ..write(stepsGoal == 10000 ? '' : 'steps_goal: $stepsGoal\n')
      ..write(sleepGoal == 420 ? '' : 'sleep_goal: $sleepGoal\n')
      ..write(sleepApp == null ? '' : 'sleep_app: $sleepApp\n')
      ..write(sleepSourceAsked ? 'sleep_source_asked: true\n' : '')
      ..write(
        setEquals(nightTiles, recoveryTileKeys.toSet())
            ? ''
            : 'night_tiles: ${nightTiles.isEmpty ? '-' : recoveryTileKeys.where(nightTiles.contains).join(', ')}\n',
      )
      ..write(listEquals(recoveryOrder, recoveryOrderDefault) ? '' : 'recovery_order: ${recoveryOrder.join(', ')}\n')
      ..write(_goals == null ? '' : 'home_goals: ${goalsToFile(_goals!)}\n')
      ..write(
        listEquals(homeOrder, homeCardIds) && setEquals(homeHidden, homeCardsOffByDefault)
            ? ''
            : 'home_cards: ${homeCardsToFile(homeOrder, homeHidden)}\n',
      )
      ..write(birthYear == null ? '' : 'birth_year: $birthYear\n')
      ..write(sex == null ? '' : 'sex: $sex\n')
      ..write(hrRecoveryPct == 60 ? '' : 'hr_recovery: $hrRecoveryPct\n')
      ..write(maxHr == null ? '' : 'max_hr: $maxHr\n')
      ..write(kcalAdjustPct == 0 ? '' : 'kcal_adjust: $kcalAdjustPct\n')
      ..writeln('sports: $sports') // vanhemmat versiot lukevat tämän
      ..writeln('mode: $trainMode')
      ..writeln('move_names: $moveNames')
      ..write(swimPer100m ? 'swim_pace: 100m\n' : '')
      ..writeln('health_lang: $healthLang')
      ..writeln('watch: $watch')
      ..writeln('hc_import: $hcImport')
      ..writeln('daily_steps: $dailySteps')
      ..writeln('ongoing_note: $ongoingNote')
      ..writeln('elev_with_maps: $elevWithMaps')
      ..writeln('rest_timer: $restTimer')
      ..write(restByHr ? 'rest_hr: true\n' : '')
      ..writeln('rest_sound: $restSound')
      ..writeln('rest_adjust: ${restAdjust.join(', ')}')
      ..writeln('deloadEvery: $deloadEvery')
      ..writeln('snap: ${[for (final e in snapDefaults.entries) '${e.key}=${e.value}'].join('; ')}')
      ..writeln('introDone: $introDone')
      ..write(started ? 'started: true\n' : '')
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
    // Kategoriat heti otsikon alle: ennen 0.5.5 ne kirjoitettiin tiedoston loppuun (mittaustapojen, vammojen ja
    // taukojen jälkeen), jolloin ne luettiin väärään osioon ja omat liikkeet katosivat.
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
    if (customMeasure.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Mittaustavat');
      for (final e in customMeasure.entries) {
        b.writeln('- ${e.key}: ${e.value.label}');
      }
    }
    if (customMuscles.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Omien liikkeiden lihakset');
      for (final e in customMuscles.entries) {
        if (e.value.isNotEmpty) b.writeln('- ${e.key}: ${e.value.join(', ')}');
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
          case 'name': // vanha asetus (nimi poistettu 19.11.): annettu nimi = aloitus käyty ennen 0.6.6:ta
            if (v.isNotEmpty) started = true;
          case 'theme':
            themeMode = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => themeMode);
          case 'text_size':
            if (textSizes.containsKey(v)) textSize = v;
          case 'weightStep':
            weightStep = parseNum(v) ?? weightStep;
          case 'plates':
            final ps = [
              for (final x in v.split(';'))
                if (parseNum(x) case final p? when p > 0 && p <= 100) p,
            ];
            if (ps.isNotEmpty) plates = (ps.toSet().toList()..sort((a, b) => b.compareTo(a)));
          case 'bar':
            final b = parseNum(v);
            if (b != null && b >= 0 && b <= 50) barKg = b;
          case 'hex_bar':
            final b = parseNum(v);
            if (b != null && b > 0 && b <= 60) hexBarKg = b;
          case 'exercise_bars':
            exerciseBars = {
              for (final part in v.split(';'))
                if (part.split('=') case [final n, final kg] when n.trim().isNotEmpty)
                  if (parseNum(kg) case final b? when b > 0 && b <= 60) n.trim(): b,
            };
          case 'tips':
            tips = v != 'false';
          case 'body_tracker':
            bodyTracker = v == 'true';
          case 'weight_home':
            weightOnHome = v == 'true';
          case 'recovery_order':
            final o = <String>[
              for (final k in v.split(',').map((x) => x.trim()))
                if (recoveryOrderDefault.contains(k)) k,
            ];
            recoveryOrder = [...o.toSet(), ...recoveryOrderDefault.where((k) => !o.contains(k))];
          case 'night_tiles':
            nightTiles = {
              for (final k in v.split(',').map((x) => x.trim()))
                if (recoveryTileKeys.contains(k)) k,
            };
          case 'sleep_source_asked':
            sleepSourceAsked = v.trim() == 'true';
          case 'sleep_app':
            sleepApp = v.trim().isEmpty ? null : v.trim();
          case 'sleep_goal':
            final n = int.tryParse(v.trim());
            if (n != null && n >= 300 && n <= 720) sleepGoal = n;
          case 'steps_goal':
            final n = int.tryParse(v.replaceAll(RegExp(r'\s'), ''));
            if (n != null && n >= 1000 && n <= 50000) stepsGoal = n;
          case 'run_bands':
            runBands = runBandsFromFile(v);
          case 'home_goals':
            _goals = goalsFromFile(v);
          case 'home_cards':
            final (o, h) = homeCardsFromFile(v);
            homeOrder = o;
            // Yöarvot näkyvät Palautuminen-kortissa (18.11.): jos Yöarvot oli päällä omana korttinaan, Palautuminen
            // päälle, jotta arvot eivät katoa.
            if (!h.contains('night')) h.remove('recovery');
            homeHidden = h;
          case 'birth_year':
            final y = int.tryParse(v);
            if (y != null && y > 1900 && y <= DateTime.now().year) birthYear = y;
          case 'sex':
            if (v == 'mies' || v == 'nainen') sex = v;
          case 'max_hr':
            final m = int.tryParse(v);
            if (m != null && m >= 120 && m <= 230) maxHr = m;
          case 'kcal_adjust':
            final r = int.tryParse(v.replaceAll('%', '').replaceAll('+', '').trim());
            if (r != null && r >= -10 && r <= 10) kcalAdjustPct = r;
          case 'hr_recovery':
            final r = int.tryParse(v);
            if (r != null && r >= 40 && r <= 80) hrRecoveryPct = r;
          case 'sports': // vanha asetus: liikunta päällä -> molemmat (mode: voittaa, jos se on mukana)
            if (!lines.any((l) => l.trim().startsWith('mode:'))) trainMode = v == 'true' ? 'both' : 'gym';
          case 'mode':
            trainMode = const {'gym', 'cardio', 'both'}.contains(v) ? v : 'gym';
          case 'english_names': // vanha asetus (0.1.2-kehitysversio)
            if (v == 'true') moveNames = 'both';
          case 'move_names':
            moveNames = const {'fi', 'en', 'both'}.contains(v) ? v : 'fi';
            // Vain sovelluksen omat asetukset: varmuuskopion tarkistus (Settings()..applyMarkdown) ei vaihda nimiä.
            if (identical(this, settings)) nameMode = moveNames;
          case 'swim_pace':
            swimPer100m = v == '100m';
            if (identical(this, settings)) swimPer100 = swimPer100m;
          case 'health_lang':
            healthLang = v == 'en' ? 'en' : 'fi';
            if (identical(this, settings)) healthTextLang = healthLang;
          case 'watch':
            watch = v == 'true';
          case 'hc_import':
            hcImport = v == 'true';
          case 'daily_steps':
            dailySteps = v == 'true';
          case 'ongoing_note':
            ongoingNote = v != 'false';
          case 'elev_with_maps':
            elevWithMaps = v != 'false';
          case 'rest_timer':
            restTimer = v == 'true';
          case 'rest_hr':
            restByHr = v == 'true';
          case 'rest_adjust':
            final a = v.split(',').map((x) => int.tryParse(x.trim()) ?? 0).toList();
            restAdjust = [for (var i = 0; i < 3; i++) i < a.length ? a[i].clamp(-300, 300) : 0];
          case 'rest_sound':
            restSound = const {'pling', 'boop', 'chime', 'none'}.contains(v) ? v : 'pling';
          case 'introDone':
            introDone = v == 'true';
          case 'started':
            started = v == 'true';
          case 'deloadEvery':
            deloadEvery = int.tryParse(v) ?? deloadEvery;
          case 'snap':
            snapDefaults = {
              for (final part in v.split(';'))
                if (RegExp(r'^\s*(.+?)\s*=\s*(\d+)\s*$').firstMatch(part) case final m?)
                  m[1]!: int.parse(m[2]!) == 0 ? 0 : int.parse(m[2]!).clamp(3, 10),
            };
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
    Map<String, List<String>>? cm;
    TrainingStyle? st;
    for (; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.startsWith('## ')) {
        section = t.substring(3).trim();
        if (section == 'Lämmittelylaitteet') eq = [];
        if (section == 'Tauot') pauseList = [];
        if (section == 'Vammat') inj = [];
        if (section == 'Mittaustavat') meas = {};
        if (section == 'Omien liikkeiden lihakset') cm = {};
        if (section == 'Treenityyli') st = TrainingStyle();
        if (section == 'Omat liikkeet') {
          custom = [];
          cats = {};
        }
        continue;
      }
      if (t.startsWith('### ')) {
        // ### on vain omien liikkeiden kategorioissa: vanhat tiedostot, joissa ne ovat muun osion perässä.
        sub = t.substring(4).trim();
        if (section != 'Omat liikkeet') {
          section = 'Omat liikkeet';
          custom ??= [];
          cats ??= {};
        }
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
      } else if (section == 'Omien liikkeiden lihakset') {
        final k = item.lastIndexOf(':');
        if (k <= 0) continue;
        final parts = [
          for (final x in item.substring(k + 1).split(','))
            if (x.trim().isNotEmpty) x.trim(),
        ];
        if (parts.isNotEmpty) cm![item.substring(0, k).trim()] = parts;
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
        // Sama alue vain kerran (käsin muokattu tai yhdistetty tiedosto).
        final id = item.split(' ').first;
        if (id.isNotEmpty && !inj!.contains(id)) inj.add(id);
      } else if (section == 'Tauot') {
        final m = RegExp(r'^(\d{4}-\d{2}-\d{2})\s*[–-]\s*(\d{4}-\d{2}-\d{2})?\s*(\S+)?').firstMatch(item);
        // Mahdoton päivä (esim. 2026-13-40) ohitetaan: DateTime.parse siirtäisi sen tulevaisuuteen, ja siitä
        // tulisi käynnissä oleva tauko. Loppu ennen alkua = yhden päivän tauko.
        final start = m == null ? null : _validDate(m[1]!);
        final end = m?[2] == null ? null : _validDate(m![2]!);
        if (start != null && (m![2] == null || end != null)) {
          pauseList!.add(Pause(start, m[3] ?? 'loma', end == null || !end.isBefore(start) ? end : start));
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
    if (cm != null) customMuscles = cm;
    _syncCustomMuscles();
  }

  /// Vaihtaa treenikansion. Jos uudessa kansiossa on asetukset.md, se otetaan käyttöön,
  /// muuten nykyiset asetukset kirjoitetaan sinne.
  /// Treenikansion .md-tiedostot (treenit, asetukset, ohjelma, punnitukset), GPS-reitit (.gpx) ja tallennetut
  /// ohjelmat (.gmd) suhteellisina polkuina.
  static Future<List<String>> mdFiles(Directory dir) async {
    if (!await dir.exists()) return [];
    final out = <String>[];
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && isDataFile(e.path)) {
          final rel = p.relative(e.path, from: dir.path);
          if (!isAutoBackupPath(rel)) out.add(rel);
        }
      }
    } catch (_) {}
    return out;
  }

  /// Kopioi .md-, .gpx- ja .gmd-tiedostot kansiosta toiseen. Olemassa olevia ei ylikirjoiteta. Palauttaa (kopioitu, ohitettu).
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

  void setTextSize(String v, {bool save = true}) {
    if (!textSizes.containsKey(v)) return;
    textSize = v;
    // Aloituksessa esikatselu heti, tallennus aloituksen lopussa (finishOnboarding).
    save ? _persist() : notifyListeners();
  }

  /// Uusi tauko. [end] = viimeinen taukopäivä, jos tiedossa (tauko päättyy itsestään). Päällekkäiset tauot ja
  /// avoin tauko korvautuvat uudella.
  void startPause(String reason, DateTime start, [DateTime? end]) {
    final s = dateOnly(start), e = end == null ? null : dateOnly(end);
    // Avoin uusi tauko korvaa vain avoimen tai alkupäivän kattavan tauon (tuleva loma säilyy); päättyvä korvaa
    // kaikki, joiden päivät osuvat sen päiville.
    bool overlaps(Pause p) => p.end == null || (e == null ? p.covers(s) : (!p.end!.isBefore(s) && !p.start.isAfter(e)));
    pauses = [...pauses.where((p) => !overlaps(p)), Pause(s, reason, e)]..sort((a, b) => a.start.compareTo(b.start));
    _persist();
  }

  /// Tauon muokkaus jälkikäteen (syy, alku- ja päättymispäivä; null = jatkuu, kunnes lopetetaan).
  void updatePause(Pause old, String reason, DateTime start, DateTime? end) {
    final s = dateOnly(start), e = end == null ? null : dateOnly(end);
    final others = pauses.where((p) => !identical(p, old));
    bool overlaps(Pause p) => (p.end == null || !p.end!.isBefore(s)) && (e == null || !p.start.isAfter(e));
    pauses = [...others.where((p) => !overlaps(p)), Pause(s, reason, e != null && e.isBefore(s) ? s : e)]
      ..sort((a, b) => a.start.compareTo(b.start));
    _persist();
  }

  /// Päättää tauon. [lastDay] = viimeinen taukopäivä (oletus eilen). Jos se on ennen alkupäivää (tauko aloitettiin
  /// tänään tai treeni kirjattiin alkupäivälle), tauko poistetaan: muuten koko päivä näkyisi taukona, myös sen
  /// päivän treenit.
  void endPause([DateTime? lastDay]) {
    final p = activePause;
    if (p == null) return;
    final end = dateOnly(lastDay ?? addDays(DateTime.now(), -1));
    if (end.isBefore(p.start)) {
      removePause(p);
      return;
    }
    p.end = end;
    // Viimeinen päivä tänään tai myöhemmin: lopetettu käsin, ei enää päällä (päivä näkyy silti taukona).
    if (!end.isBefore(dateOnly(DateTime.now()))) p.stopped = true;
    _persist();
  }

  /// Poistaa tauon kokonaan (vahingossa lisätty).
  void removePause(Pause p) {
    pauses = [...pauses.where((x) => !identical(x, p))];
    _persist();
  }

  /// Palauttaa poistetun tauon (kumoa).
  void restorePause(Pause p) {
    if (pauses.any((x) => x.start == p.start)) return;
    if (p.end == null && activePause != null) return;
    pauses = [...pauses, p]..sort((a, b) => a.start.compareTo(b.start));
    _persist();
  }

  /// Varmuuskopion tauot käytössä olevaan päiväkirjaan: lisätään ne, joita täällä ei ole (sama alkupäivä =
  /// sama tauko, tämän laitteen versio pysyy). Käynnissä oleva tauko vain, jos täällä ei ole omaa; jos täällä on
  /// jo treeni sen alkupäivänä tai myöhemmin, tauko päätetään sitä edeltävään päivään.
  void mergePauses(List<Pause> other, {Iterable<DateTime> trainedDays = const []}) {
    final starts = {for (final p in pauses) p.start};
    final days = [for (final d in trainedDays) dateOnly(d)]..sort();
    final add = <Pause>[];
    for (final p in other) {
      if (starts.contains(p.start)) continue;
      if (p.end != null) {
        add.add(Pause(p.start, p.reason, p.end));
      } else if (activePause == null && !add.any((a) => a.end == null)) {
        final back = days.where((d) => !d.isBefore(p.start)).firstOrNull;
        add.add(Pause(p.start, p.reason, back == null ? null : _maxDate(p.start, addDays(back, -1))));
      }
    }
    if (add.isEmpty) return;
    pauses = [...pauses, ...add]..sort((a, b) => a.start.compareTo(b.start));
    _persist();
  }

  static DateTime _maxDate(DateTime a, DateTime b) => b.isBefore(a) ? a : b;

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

  /// Sykkeen mukainen palautus käyttää palautusajastinta, joten se kytketään samalla päälle.
  void setRestByHr(bool v) {
    restByHr = v;
    if (v) restTimer = true;
    _persist();
  }

  void setWatch(bool v) {
    watch = v;
    _persist();
  }

  void setHealthLang(String v) {
    healthLang = v;
    healthTextLang = v;
    _persist();
    ensureEnglish().then((_) => notifyListeners());
  }

  void setSwimPer100(bool v) {
    swimPer100m = v;
    swimPer100 = v;
    _persist();
    notifyListeners();
  }

  void setMoveNames(String v) {
    moveNames = v;
    nameMode = v;
    _persist();
    ensureEnglish().then((_) => notifyListeners());
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

  void setPlates(List<double> v, double bar) {
    plates = v.toSet().toList()..sort((a, b) => b.compareTo(a));
    barKg = bar;
    _persist();
  }

  /// [kg] null = liike käyttää oletustankoa.
  void setExerciseBar(String exercise, double? kg) {
    exerciseBars = {...exerciseBars}..remove(exercise);
    if (kg != null) exerciseBars[exercise] = kg;
    _persist();
  }

  void setHexBarKg(double? v) {
    hexBarKg = v;
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
    customMuscles.remove(n);
    _syncCustomMuscles();
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
    _syncCustomMuscles();
    _persist();
  }
}

const settingsFileName = 'asetukset.md';

/// Treenikansion omat tiedostot (kansion vaihto, varmuuskopio): .md (treenit, asetukset, ohjelma, punnitukset),
/// .gpx (GPS-reitit) ja .gmd (tallennetut ohjelmat).
bool isDataFile(String path) => path.endsWith('.md') || path.endsWith('.gpx') || path.endsWith('.gmd');

/// Sovelluksen automaattiset varmuuskopiot treenikansion alikansiossa ([AutoBackup]): ei käyttäjän tietoa.
const autoBackupDir = 'backup';

/// Onko polku (treenikansion suhteen) varmuuskopiokansiossa: sitä ei lueta, viedä eikä kopioida.
bool isAutoBackupPath(String rel) => rel.replaceAll(r'\', '/').split('/').first == autoBackupDir;
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

  /// Treenitiedostot (vvvv-kk-pp*.md), joita ei voitu lukea viimeksi: etusivu kertoo niistä, ja ne voi yrittää
  /// korjata ([repairUnreadable]) tai lähettää ongelmaraporttina. Ennen ne ohitettiin hiljaa.
  Map<String, String> unreadable = {}; // polku -> syy käyttäjän kielellä ([unreadableReason])

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

  static final _workoutName = RegExp(r'^(\d{4}-\d{2}-\d{2}).*\.md$');

  /// Yrittää korjata lukukelvottomat treenitiedostot: väärä merkistö (Windowsin Latin-1 tai UTF-16, esim.
  /// käsin muokattu Muistiossa) tallennetaan UTF-8:na, alkuperäinen talteen viereen (.bak). Muita ei kosketa.
  /// Palauttaa korjattujen määrän; jäljelle jääneet ovat [unreadable]-listassa.
  Future<int> repairUnreadable() async {
    final root = (await rootDir()).path;
    var fixed = 0;
    for (final rel in [...unreadable.keys]) {
      try {
        final f = File(p.joinAll([root, ...rel.split('/')]));
        final text = decodeLegacyText(await f.readAsBytes());
        if (text == null) continue;
        final m = _workoutName.firstMatch(p.basename(rel))!;
        parseWorkout(text, fallbackDate: strictDate(m[1]!), fallbackSession: sessionFromName(p.basename(rel)));
        final bak = File('${f.path}.bak');
        if (!await bak.exists()) await f.copy(bak.path);
        await f.writeAsString(text);
        fixed++;
      } catch (_) {
        // Ei korjattavissa: jää listaan raporttia varten.
      }
    }
    await reload();
    return fixed;
  }

  Future<void> reload() async {
    error = null;
    final list = <Workout>[];
    final failed = <String, String>{};
    try {
      final notRead = <String>[];
      final all = await files.all(failed: notRead);
      // Syy jokaiselle, jota ei voitu lukea: luetaan tavuina uudelleen (vain epäonnistuneet).
      final root = notRead.isEmpty ? null : (await rootDir()).path;
      for (final rel in notRead.where((rel) => _workoutName.firstMatch(p.basename(rel)) != null)) {
        try {
          failed[rel] = unreadableReason(await File(p.joinAll([root!, ...rel.split('/')])).readAsBytes());
        } catch (e) {
          failed[rel] = unreadableReason(null, error: e);
        }
      }
      for (final e in all.entries) {
        final base = p.basename(e.key);
        final m = _workoutName.firstMatch(base);
        if (m == null) continue;
        if (!looksLikeText(e.value)) {
          failed[e.key] = unreadableReason(utf8.encode(e.value));
          continue;
        }
        try {
          list.add(parseWorkout(e.value, fallbackDate: strictDate(m[1]!), fallbackSession: sessionFromName(base)));
        } catch (err) {
          // Rikkinäinen tai vieras tiedosto: ei näytetä historiassa, mutta etusivu kertoo siitä ja syyn.
          failed[e.key] = unreadableReason(utf8.encode(e.value), error: err);
        }
      }
    } catch (e) {
      error = t('Kansiota ei voitu lukea: {0}', [errorText(e)]);
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    // Vanhojen kävelyjen ja juoksujen kalorit, kun sykettä oli vain osalta ajasta (ks. repairLowCoverageKcal).
    final profile = hrProfile();
    for (final w in list) {
      // Kävely nopeudesta (käyttäjä 17.11.); muistissa, tiedosto korjautuu seuraavassa tallennuksessa.
      if (!repairWalkKcal(w, profile)) repairLowCoverageKcal(w, profile);
    }
    workouts = list;
    unreadable = Map.fromEntries(failed.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    _recoverCustomExercises();
    notifyListeners();
  }

  /// Treeneissä olevat liikkeet, joita ei ole luettelossa eikä omissa liikkeissä, lisätään omiin liikkeisiin.
  /// Palauttaa ennen 0.5.5:ttä kadonneet omat liikkeet (asetukset.md:n järjestysvirhe) liikevalintaan.
  void _recoverCustomExercises() {
    final known = {...builtinExercises(), ...settings.customExercises};
    final missing = <String, String>{};
    for (final w in workouts) {
      for (final e in w.exercises) {
        if (e.name.trim().isNotEmpty && !known.contains(e.name)) missing[e.name] = ownCategory;
      }
    }
    if (missing.isNotEmpty) settings.addCustomExercises(missing);
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
    w.route = rel.split('/').last;
    w.routeGpx = null;
  }

  /// Treenin reitti GPX-tekstinä (null = ei reittiä tai tiedosto puuttuu).
  Future<String?> readRoute(Workout w) async => w.routeGpx ?? (w.route == null ? null : files.read(routeRel(w)));

  /// Saman treenitiedoston tallennukset ja poistot peräkkäin: päällekkäiset kirjoitukset saattoivat päätyä
  /// levylle väärässä järjestyksessä (vanhempi sisältö jäi voimaan), ja poisto kesken tallennuksen toi
  /// tiedoston takaisin.
  final _fileQueue = <String, Future<void>>{};

  Future<R> _inOrder<R>(String rel, Future<R> Function() f) async {
    // Oma portti jonoon; vain päällekkäinen kutsu odottaa edellistä. Portti aukeaa aina (myös virheestä), joten
    // epäonnistunut tallennus ei pysäytä seuraavia.
    // Avain kansion kanssa: sama suhteellinen polku toisessa treenikansiossa on eri tiedosto.
    final key = '${settings.folder ?? ''}|$rel';
    final prev = _fileQueue[key];
    final gate = Completer<void>();
    _fileQueue[key] = gate.future;
    try {
      if (prev != null) await prev;
      return await f();
    } finally {
      if (identical(_fileQueue[key], gate.future)) _fileQueue.remove(key);
      gate.complete();
    }
  }

  Future<String> save(Workout w) => _inOrder(workoutPath(w.date, w.session), () async {
    await _writeRoute(w);
    // Sisältö luetaan vasta omalla vuorolla: viimeisin tila tallentuu.
    final path = await files.write(workoutPath(w.date, w.session), workoutToMarkdown(w));
    workouts
      ..removeWhere((x) => x.date == w.date && x.session == w.session)
      ..add(w.copy())
      ..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    return path;
  });

  /// Tuonti: kirjoittaa treenit levylle. Olemassa olevat päivät ohitetaan (ei ylikirjoitusta).
  /// Palauttaa tallennettujen määrän.
  Future<int> saveMany(Iterable<Workout> list) async {
    var n = 0;
    for (final w in list) {
      if (onDay(w.date).any((x) => x.session == w.session)) continue;
      final rel = workoutPath(w.date, w.session);
      // Samassa jonossa kuin save/delete: samanaikainen tallennus samaan päivään ei mene ristiin (yötesti 16.11.).
      final wrote = await _inOrder(rel, () async {
        if (await files.exists(rel)) return false;
        await _writeRoute(w);
        // Varmuuskopiosta palautettu: alkuperäinen teksti sellaisenaan (tuntemattomat rivit säilyvät).
        await files.write(rel, w.originalMd ?? workoutToMarkdown(w));
        w.originalMd = null;
        return true;
      });
      if (wrote) n++;
    }
    await reload();
    return n;
  }

  Future<void> delete(DateTime d, [int session = 1]) => _inOrder(workoutPath(d, session), () async {
    final old = onDay(d).where((x) => x.session == session).firstOrNull;
    // Vain treenin oma reitti (vvvv-kk-pp[-n].gpx): muokattu tai synkattu route:-rivi ei saa poistaa muuta tiedostoa.
    if (old?.route != null && routeRel(old!) == routePath(old.date, old.session)) {
      await files.delete(routeRel(old));
    }
    await files.delete(workoutPath(d, session));
    workouts.removeWhere((x) => x.date == dateOnly(d) && x.session == session);
    notifyListeners();
  });

  /// Raskain aiempi sarja liikkeessä ennen annettua päivää.
  /// Paras paino ennen päivää [before]; [session]: myös saman päivän aiemmat treenit (testikierros 17.11.: toisessa
  /// treenissä Paras näytti eilisen, ja sama paino merkittiin uudeksi ennätykseksi). Lämmittelysarjat eivät ole mukana.
  double maxKgBefore(String exercise, DateTime before, {int? session}) {
    var best = 0.0;
    final day = dateOnly(before);
    for (final w in workouts) {
      final earlier = w.date.isBefore(day) || (session != null && w.date == day && w.session < session);
      if (!earlier) continue;
      for (final e in w.exercises) {
        if (e.name != exercise) continue;
        for (final s in e.sets) {
          if (!s.warmup && s.kg > best) best = s.kg;
        }
      }
    }
    return best;
  }

  /// Edellinen kerta, kun liike tehtiin ennen annettua päivää tai saman päivän aiemmassa treenissä ([session]:
  /// nykyisen treenin numero; testikierros 16.11.: päivän toinen salitreeni ei nähnyt ensimmäistä).
  (DateTime, ExerciseEntry)? lastBefore(String exercise, DateTime before, [int session = 1]) {
    final w = latestEarlier(
      workouts.where((w) => w.exercises.any((e) => e.name == exercise && e.sets.isNotEmpty)),
      before,
      session,
    );
    return w == null ? null : (w.date, w.exercises.firstWhere((e) => e.name == exercise && e.sets.isNotEmpty));
  }
}

/// Treeni on ennen päivän [date] treeniä numero [session]: aiempi päivä tai saman päivän aiempi treeni.
bool earlierThan(Workout w, DateTime date, [int session = 1]) {
  final d = dateOnly(date);
  final wd = dateOnly(w.date);
  return wd.isBefore(d) || (wd == d && w.session < session);
}

/// Uusin treeni ennen päivän [date] treeniä numero [session] (päivä, sitten saman päivän treenin numero).
Workout? latestEarlier(Iterable<Workout> list, DateTime date, [int session = 1]) {
  Workout? best;
  for (final w in list) {
    if (!earlierThan(w, date, session)) continue;
    if (best == null || w.date.isAfter(best.date) || (w.date == best.date && w.session > best.session)) best = w;
  }
  return best;
}

/// Treenikansion tiedostot: puhelimessa ja tietokoneella oikeat .md-tiedostot, verkkodemossa muistissa
/// (mitään ei tallenneta). Polut ovat suhteellisia treenikansioon, erotin '/'.
abstract class TrainingFiles {
  Future<String?> read(String rel);

  /// Kirjoittaa ja palauttaa näytettävän polun.
  Future<String> write(String rel, String text);
  Future<void> delete(String rel);
  Future<bool> exists(String rel);

  /// Kaikki .md-tiedostot (suhteellinen polku -> sisältö). [failed]: tiedostot, joita ei voitu lukea.
  Future<Map<String, String>> all({List<String>? failed});
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
    await writeDurable(f, text);
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
  Future<Map<String, String>> all({List<String>? failed}) async {
    final dir = await store.rootDir();
    final out = <String, String>{};
    if (!await dir.exists()) return out;
    final files = <File>[
      await for (final e in dir.list(recursive: true, followLinks: false))
        if (e is File &&
            (e.path.endsWith('.md') || e.path.endsWith('.gmd')) &&
            !isAutoBackupPath(p.relative(e.path, from: dir.path)))
          e,
    ];
    // Luetaan 32 tiedostoa kerrallaan rinnakkain: satojen treenien kansio aukeaa nopeammin kuin yksi kerrallaan.
    for (var i = 0; i < files.length; i += 32) {
      final chunk = files.sublist(i, i + 32 > files.length ? files.length : i + 32);
      final texts = await Future.wait(chunk.map((f) => f.readAsString().then<String?>((t) => t, onError: (_) => null)));
      for (var j = 0; j < chunk.length; j++) {
        final rel = p.relative(chunk[j].path, from: dir.path).replaceAll(r'\', '/');
        if (texts[j] != null) {
          out[rel] = texts[j]!;
        } else {
          failed?.add(rel);
        }
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
  Future<Map<String, String>> all({List<String>? failed}) async => {...data};
}

/// Verkkoversio on demo: ei tiedostoja eikä pysyvää tallennusta.
// Verkossa aina demo; muualla vain kuvakaappauksia ja esittelyä varten: --dart-define=DEMO=true.
const bool isDemo = kIsWeb || bool.fromEnvironment('DEMO');
final TrainingFiles files = isDemo ? MemoryTrainingFiles() : IoTrainingFiles();
