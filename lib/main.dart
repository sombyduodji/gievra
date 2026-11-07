import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_info.dart';
import 'app_state.dart';
import 'demo.dart';
import 'open_files.dart';
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
  runApp(const TreeniApp());
  listenOpenedFiles();
  // Drive: PC:n tai toisen puhelimen muutokset taustalla; kalenteri päivittyy, kun valmista.
  if (syncReleased) unawaited(sync.startup());
}

class TreeniApp extends StatelessWidget {
  const TreeniApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      // Kielen vaihto rakentaa koko sovelluksen uudelleen.
      key: ValueKey(uiLang),
      navigatorKey: appNavigator,
      title: AppInfo.fullName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
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
    ),
  );
}
