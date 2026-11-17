import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import 'battery.dart';
import 'heart_rate.dart' show hr;

import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_info.dart';
import 'app_state.dart';
import 'daily_steps.dart';
import 'auto_backup.dart';
import 'demo.dart';
import 'open_files.dart';
import 'rest.dart';
import 'l10n.dart';
import 'sami_material.dart';
import 'sync/sync_service.dart';
import 'ongoing.dart';
import 'theme.dart';
import 'ui/shell.dart';
import 'ui/intro.dart';
import 'ui/onboarding.dart';
import 'ui/tap_guard.dart';
import 'time_zone.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Julkaisuversiossa Flutter karsii virheen pinosta rivit, joita se ei tunnista; Dart-symbolit ovat erillään
  // (tools/build_apk.sh), joten karsittuna pinosta ei jäisi mitään. Raaka pino lokiin, jotta
  // tools/symbolize.py saa sen luettavaksi.
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    if (kReleaseMode && d.stack != null) debugPrint('Raaka pino (${d.exceptionAsString()}):\n${d.stack}');
  };
  // Käynnistyksen ajoitus mittauksiin: --dart-define=STARTUP_TIMING=true
  const timing = bool.fromEnvironment('STARTUP_TIMING');
  final sw = Stopwatch()..start();
  await initializeDateFormatting('fi');
  await settings.load();
  final tSettings = sw.elapsedMilliseconds;
  if (isDemo) await seedDemo();
  await store.reload();
  final tStore = sw.elapsedMilliseconds;
  // Päivän askeleet tallennetusta tiedostosta (Health Connect -haku etusivulla).
  unawaited(dailySteps.load());
  unawaited(hr.load()); // valittu sykevyö (tällä puhelimella)
  // Akunsäästö: saako Gievra toimia taustalla (tila päivittyy, kun palataan asetuksista).
  WidgetsBinding.instance.addObserver(battery);
  unawaited(battery.refresh());
  await sync.load();
  // Käynnissä oleva treeni pudotusvalikossa: päivittyy treenien ja asetusten muuttuessa.
  store.addListener(Ongoing.refresh);
  settings.addListener(Ongoing.refresh);
  hr.addListener(Ongoing.refresh); // syke ilmoitukseen (enintään 5 s välein)
  rest.addListener(Ongoing.refresh); // palautuksen lähtölaskenta ja seuraava sarja
  unawaited(Ongoing.refresh());
  Ongoing.listenActions();
  // Aikavyöhyke vaihtui (matka): treenit ja asetukset uudelleen tiedostoista, jotta päivät täsmäävät taas.
  tzWatch.addListener(() async {
    try {
      await store.reload();
      await settings.loadFromFolder();
      unawaited(dailySteps.load());
    } catch (_) {
      // Kansio ei hetkeksi luettavissa: seuraava käynnistys tai muutos lukee sen uudelleen.
    }
  });
  // Päivä tai tervehdyksen vuorokaudenaika vaihtui (sovellus auki yön yli): tänään, viikko ja tervehdys ajan tasalle.
  dayWatch.addListener(settings.dayChanged);
  tzWatch.start();
  // ignore: avoid_print
  if (timing) print('STARTUP asetukset $tSettings ms, treenit ${tStore - tSettings} ms (${store.workouts.length})');
  // Palautus ohi: värinä, ääni ja lyhyt ilmoitus (vain kun sovellus on auki).
  rest.onDone = (message) {
    // Androidilla ilmoitus soittaa valitun äänen ja värisee; ilman ilmoituslupaa (tai verkossa) varalla tämä.
    if (!RestTimer.native || !RestTimer.notificationsOk) {
      HapticFeedback.vibrate();
      SystemSound.play(SystemSoundType.alert);
    }
    appMessenger.currentState?.showSnackBar(SnackBar(content: Text(message)));
  };
  if (RestTimer.native) {
    unawaited(Permission.notification.isGranted.then((v) => RestTimer.notificationsOk = v));
  }
  runApp(const TreeniApp());
  listenOpenedFiles();
  // Uuden version ensimmäinen käynnistys: treenikansio backup/-kansioon (etusivulla edistymisrivi).
  unawaited(
    PackageInfo.fromPlatform().then((i) => autoBackup.runIfUpdated(i.version, '${i.version}+${i.buildNumber}')),
  );
  // Drive: PC:n tai toisen puhelimen muutokset taustalla; kalenteri päivittyy, kun valmista.
  if (syncReleased) unawaited(sync.startup());
}

// Teemat rakennetaan kerran (ColorScheme.fromSeed on raskas).
final _lightTheme = buildTheme(Brightness.light);
final _darkTheme = buildTheme(Brightness.dark);
final _tapGuard = NavTapGuard();

class TreeniApp extends StatefulWidget {
  const TreeniApp({super.key});

  @override
  State<TreeniApp> createState() => _TreeniAppState();
}

/// Koko sovellus rakennetaan uudelleen vain, kun teema, kieli tai aloitusvaihe muuttuu, ei jokaisesta
/// asetuksesta (painon lisäys, vinkit …): muuten asetusten säätö tuntuu hitaalta.
class _TreeniAppState extends State<TreeniApp> {
  late Object _key;

  Object _rootKey() => (settings.themeMode, uiLang, settings.onboarded, settings.introDone, settings.textSize);

  void _changed() {
    final k = _rootKey();
    if (k != _key) setState(() => _key = k);
  }

  @override
  void initState() {
    super.initState();
    _key = _rootKey(); // heti, ei laiskasti: muuten ensimmäinen muutos jäisi huomaamatta
    settings.addListener(_changed);
  }

  @override
  void dispose() {
    settings.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    // Kielen vaihto rakentaa koko sovelluksen uudelleen.
    key: ValueKey(uiLang),
    navigatorKey: appNavigator,
    navigatorObservers: [_tapGuard],
    scaffoldMessengerKey: appMessenger,
    title: AppInfo.fullName,
    debugShowCheckedModeBanner: false,
    theme: _lightTheme,
    darkTheme: _darkTheme,
    themeMode: settings.themeMode,
    // Flutterin omat tekstit (kalenteri, kellonaika, kopioi/liitä, vihjeet) käyttöliittymän kielellä.
    locale: flutterLocale(uiLang),
    supportedLocales: appSupportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    // Android 15+ piirtää sovelluksen järjestelmän navigointipalkin alle (edge-to-edge). Sivujen omat
    // ListView-reunukset ohittavat MediaQueryn alareunan, joten kolmen painikkeen palkki peitti sivujen lopun
    // (sitä ei voinut vierittää esiin). Koko sovellukselle tila palkin yläpuolelle; palkin taakse sivun tausta.
    builder: (context, child) {
      // TapGuard: lyhyt napautussuoja näkymän vaihtuessa (ks. ui/tap_guard.dart).
      final page = ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: TapGuard(child: child ?? const SizedBox.shrink()),
        ),
      );
      // Tekstin koko (Asetukset → Yleiset): Pieni = puhelimen oma koko sellaisenaan.
      final f = settings.textFactor;
      if (f == 1.0) return page;
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: AppTextScaler(mq.textScaler, f)),
        child: page,
      );
    },
    home: const _StartGate(),
  );
}

/// Ensimmäinen näkymä asetusten mukaan: nimi kysymättä → aloitus, ohjelma valitsematta → ohjelmakysely, muuten
/// etusivu. Oma kuuntelija eikä MaterialAppin home: kielen vaihto rakentaa MaterialAppin uudelleen, mutta
/// navigaattori (yhteinen GlobalKey) säilyy, eikä vaihtunut home enää päivittynyt (englanniksi ja saameksi
/// aloitussivu jäi näkyviin nimen antamisen jälkeen).
class _StartGate extends StatelessWidget {
  const _StartGate();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => !settings.onboarded
        ? const OnboardingScreen()
        : !settings.introDone
        ? const IntroScreen(firstRun: true)
        : const MainShell(),
  );
}

/// Sovelluksen tekstikoko puhelimen oman koon päälle. Android 14+ skaalaa fonttikoot epälineaarisesti (isoja
/// kokoja vähemmän), joten kerrointa ei voi lukea yhdestä koosta: ennen 100 px:n koosta luettu kerroin oli noin
/// 1,0, ja järjestelmän suuri fontti katosi, kun sovelluksen koko ei ollut Pieni (päivätesti 14.11.). Nyt
/// puhelimen skaalain lasketaan jokaiselle koolle ja sovelluksen kerroin sen päälle; yhteensä enintään 200 %
/// (tai puhelimen oma, jos se on jo suurempi).
class AppTextScaler extends TextScaler {
  final TextScaler phone;
  final double factor;
  const AppTextScaler(this.phone, this.factor);

  @override
  double scale(double fontSize) {
    final p = phone.scale(fontSize);
    final cap = p > fontSize * 2 ? p : fontSize * 2;
    final v = p * factor;
    return v < p ? p : (v > cap ? cap : v);
  }

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => phone.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is AppTextScaler && other.phone == phone && other.factor == factor;

  @override
  int get hashCode => Object.hash(phone, factor);
}
