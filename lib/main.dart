import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_info.dart';
import 'app_state.dart';
import 'demo.dart';
import 'open_files.dart';
import 'rest.dart';
import 'l10n.dart';
import 'sync/sync_service.dart';
import 'theme.dart';
import 'ui/home.dart';
import 'ui/intro.dart';
import 'ui/onboarding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Käynnistyksen ajoitus mittauksiin: --dart-define=STARTUP_TIMING=true
  const timing = bool.fromEnvironment('STARTUP_TIMING');
  final sw = Stopwatch()..start();
  await initializeDateFormatting('fi');
  await settings.load();
  final tSettings = sw.elapsedMilliseconds;
  if (isDemo) await seedDemo();
  await store.reload();
  final tStore = sw.elapsedMilliseconds;
  await sync.load();
  // ignore: avoid_print
  if (timing) print('STARTUP asetukset $tSettings ms, treenit ${tStore - tSettings} ms (${store.workouts.length})');
  // Palautus ohi: värinä, ääni ja lyhyt ilmoitus (vain kun sovellus on auki).
  rest.onDone = () {
    // Androidilla ilmoitus soittaa valitun äänen ja värisee; ilman ilmoituslupaa (tai verkossa) varalla tämä.
    if (!RestTimer.native || !RestTimer.notificationsOk) {
      HapticFeedback.vibrate();
      SystemSound.play(SystemSoundType.alert);
    }
    appMessenger.currentState?.showSnackBar(SnackBar(content: Text(t('⏱ Palautus ohi – seuraava sarja!'))));
  };
  if (RestTimer.native) {
    unawaited(Permission.notification.isGranted.then((v) => RestTimer.notificationsOk = v));
  }
  runApp(const TreeniApp());
  listenOpenedFiles();
  // Drive: PC:n tai toisen puhelimen muutokset taustalla; kalenteri päivittyy, kun valmista.
  if (syncReleased) unawaited(sync.startup());
}

// Teemat rakennetaan kerran (ColorScheme.fromSeed on raskas).
final _lightTheme = buildTheme(Brightness.light);
final _darkTheme = buildTheme(Brightness.dark);

class TreeniApp extends StatefulWidget {
  const TreeniApp({super.key});

  @override
  State<TreeniApp> createState() => _TreeniAppState();
}

/// Koko sovellus rakennetaan uudelleen vain, kun teema, kieli tai aloitusvaihe muuttuu, ei jokaisesta
/// asetuksesta (painon lisäys, vinkit …): muuten asetusten säätö tuntuu hitaalta.
class _TreeniAppState extends State<TreeniApp> {
  late Object _key;

  Object _rootKey() =>
      (settings.themeMode, uiLang, settings.name == null || settings.name!.isEmpty, settings.introDone);

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
    scaffoldMessengerKey: appMessenger,
    title: AppInfo.fullName,
    debugShowCheckedModeBanner: false,
    theme: _lightTheme,
    darkTheme: _darkTheme,
    themeMode: settings.themeMode,
    locale: const Locale('fi'),
    supportedLocales: const [Locale('fi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    // Android 15+ piirtää sovelluksen järjestelmän navigointipalkin alle (edge-to-edge). Sivujen omat
    // ListView-reunukset ohittavat MediaQueryn alareunan, joten kolmen painikkeen palkki peitti sivujen lopun
    // (sitä ei voinut vierittää esiin). Koko sovellukselle tila palkin yläpuolelle; palkin taakse sivun tausta.
    builder: (context, child) => ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox.shrink()),
    ),
    // Ensimmäisellä käynnistyskerralla kysytään nimi.
    home: settings.name == null || settings.name!.isEmpty
        ? const OnboardingScreen()
        : !settings.introDone
        ? const IntroScreen(firstRun: true)
        : const HomeScreen(),
  );
}
