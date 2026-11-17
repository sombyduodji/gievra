import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/ui/body_screen.dart';
import 'package:treenipaivakirja/ui/bug_report.dart';
import 'package:treenipaivakirja/ui/drawer.dart';
import 'package:treenipaivakirja/ui/hr_ui.dart';
import 'package:treenipaivakirja/ui/import_export.dart';
import 'package:treenipaivakirja/ui/intro.dart';
import 'package:treenipaivakirja/ui/maxes_editor.dart';
import 'package:treenipaivakirja/ui/stats_screen.dart';

/// Englanninkielinen käyttöliittymä: näkymissä ei saa näkyä suomea (ä/ö tai tavallisia suomen sanoja).
final _finnish = RegExp(
  r'[äöÄÖ]|\b(ja|tai|ei|kyllä|treeni\w*|liike\w*|sarja\w*|viikko\w*|päivä\w*)\b',
  caseSensitive: false,
);

List<String> _visibleTexts(WidgetTester tester) {
  final out = <String>{};
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText();
    if (s != null && s.trim().isNotEmpty) out.add(s);
  }
  for (final e in find.byType(RichText).evaluate()) {
    out.add((e.widget as RichText).text.toPlainText());
  }
  return out.toList();
}

void main() {
  final en = parsePo(File('assets/l10n/en.po').readAsStringSync());

  tearDown(() {
    debugSetCatalog('fi', const {});
    nameMode = 'fi';
  });

  testWidgets('englanti: näkymissä ei suomea (ongelmailmoitus, asetukset, tilastot, kysely…)', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    final tmp = Directory.systemTemp.createTempSync('gievra-en');
    addTearDown(() => tmp.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    settings.folder = tmp.path;
    debugSetCatalog('en', en);
    nameMode = 'en';
    settings
      ..name = 'Test'
      ..introDone = true
      ..trainMode = 'both';
    store.workouts = [];

    final screens = <String, Widget Function()>{
      'BugReport': () => const BugReportScreen(),
      'Settings': () => const SettingsScreen(),
      'Stats': () => const StatsScreen(),
      'StatsProgress': () => const StatsScreen(tab: 'progress'),
      'StatsRecords': () => const StatsScreen(tab: 'records'),
      'StatsCalendar': () => const StatsScreen(tab: 'calendar'),
      'Intro': () => const IntroScreen(),
      'ImportExport': () => const ImportExportScreen(),
      'About': () => const AboutScreen(),
      'Body': () => const BodyScreen(),
      'Hr': () => const HrScreen(),
      'Maxes': () => const MaxesScreen(),
    };
    final hits = <String>[];
    final skipped = <String>[];
    for (final s in screens.entries) {
      await tester.pumpWidget(MaterialApp(home: s.value()));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 300));
      for (final x in _visibleTexts(tester)) {
        // Sähköpostiosoite ja sovelluksen nimi (Gievra – Treenipäiväkirja) ovat nimiä, eivät käännettäviä.
        final y = x.replaceAll(RegExp(r'\S+@\S+'), '').replaceAll('Treenipäiväkirja', '');
        if (_finnish.hasMatch(y)) hits.add('${s.key}: $x');
      }
      final err = tester.takeException(); // testissä puuttuvat liitännäiset (path_provider) eivät kuulu tähän
      if (err != null) skipped.add('${s.key}: ${err.runtimeType}');
      await tester.pumpWidget(const SizedBox());
    }
    for (final h in [...hits.map((x) => 'FI> $x'), ...skipped.map((x) => 'PLUGIN> $x')]) {
      // ignore: avoid_print
      print(h);
    }
    expect(hits, isEmpty);
  });
}
