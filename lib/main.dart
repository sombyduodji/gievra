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
  await initializeDateFormatting('fi');
  await settings.load();
  if (isDemo) await seedDemo();
  await store.reload();
  await sync.load();
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
    // Ensimmäisellä käynnistyskerralla kysytään nimi.
    home: settings.name == null || settings.name!.isEmpty
        ? const OnboardingScreen()
        : !settings.introDone
        ? const IntroScreen(firstRun: true)
        : const HomeScreen(),
  );
}
