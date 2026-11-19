import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/ui/home.dart';

import 'test_fonts.dart';

// Liikunta-paneelin VIIMEKSI-rivit ja MUUT-ruudut (yötesti 19.11., OnePlus suurella tekstillä: "Sauvakävel / y"): lajin nimi ei katkea
// kesken sanan millään kielellä tai tekstikoolla. Pitkät saamen nimet saavat jakautua vain yhdysosien rajalta
// (tileLabel: "-\n"), joten rivejä on enintään yhtä monta kuin nimessä on rivinvaihtoja + 1.
void main() {
  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('gievra-paneltile').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp,
    );
    await loadRoboto();
  });
  tearDown(() {
    debugSetCatalog('fi', const {});
    store.workouts = [];
  });

  final today = dateOnly(DateTime.now());
  Workout act(String sport, int daysAgo) =>
      Workout(date: addDays(today, -daysAgo), title: sport, activity: sport)..minutes = 30;
  // Ei viimeksi käytettyjä tänään: kaikki kuusi lajia MUUT/LAJIT-ruuduissa (viimeisimmät 3 ovat rivinä yläpuolella).
  const sports = ['Sauvakävely', 'Kamppailulajit', 'Ryhmäliikunta', 'Lumikenkäily', 'Melonta', 'Pyöräily'];

  for (final lang in ['fi', 'en', 'se']) {
    for (final (w, scale) in [(360.0, 1.0), (360.0, 1.3), (360.0, 2.0), (412.0, 1.3)]) {
      testWidgets('$lang ${w.round()} dp ${(scale * 100).round()} %: lajiruudun nimi ei katkea kesken sanan',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(w * 3, 2400 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        debugSetCatalog(lang, lang == 'fi' ? const {} : po[lang]!);
        settings
          ..introDone = true
          ..program = null
          ..trainMode = 'both';
        // Useampi kerta kutakin, jotta ne ovat käytetyimpiä; viimeisimmät kolme ovat eri lajeja (Kävely).
        store.workouts = [
          for (var i = 0; i < sports.length; i++) ...[act(sports[i], 20 + i), act(sports[i], 30 + i)],
          act('Kävely', 1),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const HomeScreen(),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('homeStartActivity')));
        await tester.pumpAndSettle();
        var checked = 0;
        for (final s in sports) {
          final tile = find.byKey(ValueKey('panelSport_$s'));
          if (tile.evaluate().isEmpty) continue;
          for (final p in tester.renderObjectList<RenderParagraph>(
            find.descendant(of: tile, matching: find.byType(RichText)),
          )) {
            final text = p.text.toPlainText();
            if (text.runes.length <= 2) continue; // lajin kuvake
            final lines = {
              for (final b in p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length)))
                b.top.round(),
            }.length;
            // Rivitys vain sanojen välistä tai tileLabelin rivinvaihdosta.
            expect(lines, lessThanOrEqualTo(RegExp(r'[ \n]').allMatches(text).length + 1), reason: '$s: "$text" $lines riviä');
            expect(p.didExceedMaxLines, isFalse, reason: text);
            checked++;
          }
        }
        expect(checked, greaterThanOrEqualTo(3));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
