import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/health.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sami_material.dart';
import 'package:treenipaivakirja/share_text.dart' show thousands;
import 'package:treenipaivakirja/ui/health_sheet.dart';

// Kävelyn ja retkeilyn askeleet Health Connectista: sovelluksen omat tai kaikki lähteet, ja pelkät askeleet
// liikunnan ajalta, kun harjoitusta ei ole. Keksityt luvut ja ajat (ei oikeita tietoja).
const _ch = MethodChannel('fi.somby.gievra/health');
final _start = DateTime(2026, 11, 10, 17, 0);
final _end = _start.add(const Duration(minutes: 40));

Map<String, Object?> _session({int own = 1230, int all = 4560}) => {
  'kind': 'session',
  'start': _start.millisecondsSinceEpoch,
  'end': _end.millisecondsSinceEpoch,
  'title': 'Walking',
  'type': 79,
  'app': 'Oura',
  'hrAvg': 98,
  'hrMax': 121,
  'steps': all,
  'ownSteps': own,
  'allSteps': all,
};

Map<String, Object?> _window({int all = 4560}) => {
  'kind': 'steps',
  'start': _start.millisecondsSinceEpoch,
  'end': _end.millisecondsSinceEpoch,
  'app': '',
  'steps': all,
  'allSteps': all,
};

Workout _walk({String sport = 'Kävely', bool timed = true}) =>
    Workout(date: DateTime(2026, 11, 10), title: sport, activity: sport)
      ..minutes = 40
      ..started = timed ? _start : null;

void main() {
  final po = {
    for (final l in ['en', 'se']) l: parsePo(File('assets/l10n/$l.po').readAsStringSync()),
  };
  void lang(String l) => debugSetCatalog(l, l == 'fi' ? const {} : po[l]!, english: po['en']);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    lang('fi');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_ch, null);
  });

  void mock(List<Map<String, Object?>> candidates) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_ch, (call) async {
        return switch (call.method) {
          'status' => 'available',
          'granted' => true,
          'candidates' => candidates,
          _ => null,
        };
      });

  Future<void> open(WidgetTester tester, Workout w, String l) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: flutterLocale(l),
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => showHealthSheet(c, w), child: const Text('x')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('x'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('Tarkista')));
    await tester.pumpAndSettle();
  }

  test('Askelvaihtoehdot: sovelluksen omat ja kaikki lähteet, sama luku vain kerran', () {
    HealthCandidate c(Map<String, Object?> m) => HealthCandidate.fromMap(m);
    expect(stepOptions(c(_session())), [('Oura', 1230), (null, 4560)]);
    expect(stepOptions(c(_session(own: 4560))), [('Oura', 4560)]);
    expect(stepOptions(c(_session(own: 0))), [(null, 4560)]);
    expect(stepOptions(c(_window())), [(null, 4560)]);
    expect(c(_window()).stepsWindow, isTrue);
    expect(c(_session()).stepsWindow, isFalse);
    expect(stepChoiceSport('Kävely') && stepChoiceSport('Retkeily'), isTrue);
    expect(stepChoiceSport('Juoksu') || stepChoiceSport('Sauvakävely') || stepChoiceSport(null), isFalse);
  });

  for (final l in ['fi', 'en', 'se']) {
    testWidgets('Oura-kävely ($l): valinta omien ja kaikkien välillä, oletuksena suurempi', (tester) async {
      lang(l);
      mock([_session()]);
      final w = _walk();
      await open(tester, w, l);
      expect(find.text(t('Mitkä askeleet lisätään?')), findsOneWidget);
      expect(find.text(t('{0}: {1} askelta', ['Oura', thousands(1230)])), findsOneWidget);
      expect(find.text(t('Kaikki lähteet yhteensä: {0} askelta', [thousands(4560)])), findsOneWidget);
      // Oletus: kaikki lähteet (suurempi). Valitaan Ouran omat.
      await tester.tap(find.text(t('{0}: {1} askelta', ['Oura', thousands(1230)])));
      await tester.pump();
      await tester.tap(find.text(t('Lisää')));
      await tester.pumpAndSettle();
      expect((w.steps, w.hrAvg), (1230, 98));
    });

    testWidgets('Kävely ilman harjoitusta ($l): askeleet liikunnan ajalta', (tester) async {
      lang(l);
      mock([_window()]);
      final w = _walk();
      await open(tester, w, l);
      expect(find.text(t('Askeleet liikunnan ajalta')), findsOneWidget);
      expect(find.text(t('Mitkä askeleet lisätään?')), findsNothing);
      expect(find.textContaining(thousands(4560)), findsWidgets);
      await tester.tap(find.text(t('Lisää')));
      await tester.pumpAndSettle();
      expect(w.steps, 4560);
    });
  }

  testWidgets('Oletusvalinta: kaikki lähteet, kun Oura ei kirjannut askelia harjoitukseen', (tester) async {
    mock([_session(own: 69, all: 4560)]);
    final w = _walk(sport: 'Retkeily');
    await open(tester, w, 'fi');
    await tester.tap(find.text('Lisää'));
    await tester.pumpAndSettle();
    expect(w.steps, 4560);
  });

  testWidgets('Pelkät askeleet eivät tule juoksuun, salitreeniin eikä kävelyyn ilman alkuaikaa', (tester) async {
    mock([_window()]);
    for (final w in [
      _walk(sport: 'Juoksu'),
      Workout(date: DateTime(2026, 11, 10), title: 'Koko keho A')
        ..minutes = 40
        ..started = _start,
    ]) {
      await open(tester, w, 'fi');
      expect(find.text('Tätä treeniä vastaavaa harjoitusta ei vielä löytynyt.'), findsOneWidget);
      expect(find.text('Lisää liikunnalle aloitusaika, niin askeleet haetaan sen ajalta.'), findsNothing);
      Navigator.of(tester.element(find.text('Tarkista uudelleen'))).pop();
      await tester.pumpAndSettle();
    }
    // Kävely ilman alkuaikaa: ei koko päivän askelia, vaan vihje alkuajasta.
    await open(tester, _walk(timed: false), 'fi');
    expect(find.text('Askeleet liikunnan ajalta'), findsNothing);
    expect(find.text('Lisää liikunnalle aloitusaika, niin askeleet haetaan sen ajalta.'), findsOneWidget);
  });

  testWidgets('Muu laji kuin kävely: askeleet kuten ennen (yksi luku, ei valintaa)', (tester) async {
    mock([_session()]);
    final w = _walk(sport: 'Juoksu');
    await open(tester, w, 'fi');
    expect(find.text('Mitkä askeleet lisätään?'), findsNothing);
    expect(find.text('Tarkista'), findsNothing);
    await tester.tap(find.text('Lisää'));
    await tester.pumpAndSettle();
    expect(w.steps, 4560);
  });
}
