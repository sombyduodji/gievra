import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/csv_export.dart';
import 'package:treenipaivakirja/home_layout.dart';
import 'package:treenipaivakirja/import_export.dart';
import 'package:treenipaivakirja/models.dart';
import 'package:treenipaivakirja/sleep.dart';
import 'package:treenipaivakirja/theme.dart';
import 'package:treenipaivakirja/ui/home_extras_ui.dart';

// Uni-kortti (17.11.): öiden valinta Health Connectin jaksoista, uni.md, luvut, vihjeet, tallennus, vienti ja
// palautus. Kaikki tiedot keksittyjä.
void main() {
  final today = DateTime(2026, 11, 18);
  DateTime at(int dayOffset, int h, [int m = 0]) => DateTime(2026, 11, 18 + dayOffset, h, m);

  test('yöt jaksoista: yöllinen herääminen yhdistetään, päiväunet pois, eniten öitä kirjannut sovellus', () {
    final n = nightsFrom([
      // Oura: yö katkesi klo 3 (20 min väli) -> yksi yö, valveilla 30 min.
      SleepSession(at(-1, 23, 10), at(0, 3), awake: const Duration(minutes: 10), app: 'Oura', lowHr: 52),
      SleepSession(at(0, 3, 20), at(0, 7, 5), awake: const Duration(minutes: 20), app: 'Oura', lowHr: 50),
      // Päiväunet (alle 3 h) eivät ole yö.
      SleepSession(at(0, 14), at(0, 15), app: 'Oura'),
      // Edellinen yö: Oura ja Fitbit kirjaavat saman yön; Oura valitaan (enemmän öitä).
      SleepSession(at(-2, 23), at(-1, 6, 30), app: 'Oura'),
      SleepSession(at(-2, 22, 30), at(-1, 7), app: 'Fitbit'),
      // Fitbit yksin: yö, jolta Ouralla ei ole mitään.
      SleepSession(at(-3, 23), at(-2, 7), app: 'Fitbit', lowHr: 55),
      // Oura on kirjannut enemmän öitä (3 vs. 2), joten se valitaan, kun molemmilla on sama yö.
      SleepSession(at(-5, 23), at(-4, 7), app: 'Oura'),
    ]);
    expect(n.keys.toSet(), {
      DateTime(2026, 11, 18),
      DateTime(2026, 11, 17),
      DateTime(2026, 11, 16),
      DateTime(2026, 11, 14),
    });
    final last = n[DateTime(2026, 11, 18)]!;
    expect(last.bed, at(-1, 23, 10));
    expect(last.wake, at(0, 7, 5));
    expect(last.asleep, const Duration(hours: 7, minutes: 5)); // 3 h 50 + 3 h 45 jaksoissa − 30 min valveilla
    expect(last.lowHr, 50);
    expect(n[DateTime(2026, 11, 17)]!.app, 'Oura');
    expect(n[DateTime(2026, 11, 16)]!.app, 'Fitbit');
  });

  test('uni.md: tiedostoon ja takaisin, virheelliset rivit ohitetaan', () {
    final nights = {
      DateTime(2026, 11, 18): SleepNight(
        DateTime(2026, 11, 18),
        at(-1, 23, 41),
        at(0, 7, 15),
        const Duration(minutes: 422),
        lowHr: 51,
        app: 'Oura',
      ),
      DateTime(2026, 11, 17): SleepNight(
        DateTime(2026, 11, 17),
        DateTime(2026, 11, 17, 0, 30),
        DateTime(2026, 11, 17, 8),
        const Duration(minutes: 400),
      ),
    };
    final md = sleepToMarkdown(nights);
    expect(md, contains('- 2026-11-18: 23:41–07:15, 7 h 02 min, syke 51 (Oura)'));
    expect(md, contains('- 2026-11-17: 00:30–08:00, 6 h 40 min'));
    expect(parseSleep(md), nights);
    expect(parseSleep('- 2026-02-30: 23:00–07:00, 8 h 00 min\n- 2026-11-01: 25:00–07:00, 8 h 00 min\nroskaa'), isEmpty);
  });

  SleepNight night(int offset, int minutes, {int bedH = 23, int bedM = 0}) {
    final d = addDays(today, offset);
    final bed = DateTime(d.year, d.month, d.day - 1, bedH, bedM);
    return SleepNight(d, bed, bed.add(Duration(minutes: minutes + 20)), Duration(minutes: minutes));
  }

  test('luvut: 7 päivän keskiarvo, alle 7 h, tavallinen taso ja säännöllisyys; vihjeet', () {
    final nights = {
      for (var i = 7; i < 30; i++) addDays(today, -i): night(-i, 450), // tavallisesti 7 h 30 min
      for (var i = 1; i < 7; i++) addDays(today, -i): night(-i, 400, bedM: i * 10), // 6 h 40 min, vaihteleva
      today: night(0, 340), // 5 h 40 min
    };
    final s = sleepStats(nights, today);
    expect(s.last!.asleep, const Duration(minutes: 340));
    expect(s.usual, const Duration(minutes: 450));
    expect(s.n7, 7);
    expect(s.short7, 7);
    expect(s.avg7, const Duration(minutes: 391)); // (6 × 400 + 340) / 7 = 391,4
    expect(s.bedSpread, greaterThan(10));
    expect(sleepHint(s), SleepHint.short);
    expect(sleepHint(s, hrDelta: 6), SleepHint.shortAndHr);
    final week = sleepStats({...nights, today: night(0, 400)}, today);
    expect(sleepHint(week), SleepHint.lowWeek);
    final ok = sleepStats({for (var i = 0; i < 10; i++) addDays(today, -i): night(-i, 460)}, today);
    expect(sleepHint(ok), SleepHint.ok);
    expect(ok.usual, isNull); // alle 7 yötä vertailujaksolla
    expect(sleepStats(const {}, today).last, isNull);
  });

  test('oma unitavoite ja univaje (Walsh 2021)', () {
    final nights = {for (var i = 0; i < 7; i++) addDays(today, -i): night(-i, 450)}; // 7 h 30 min
    final s7 = sleepStats(nights, today);
    expect(s7.short7, 0);
    expect(s7.debt7, Duration.zero);
    final s8 = sleepStats(nights, today, goal: const Duration(hours: 8));
    expect(s8.short7, 7);
    expect(s8.debt7, const Duration(minutes: 7 * 30));
    expect(sleepHint(s8, goal: const Duration(hours: 8)), SleepHint.lowWeek);
    expect(sleepHint(s7), SleepHint.ok);
  });

  test('yötesti 18.11.: tallennettu lähde pysyy, päällekkäiset jaksot, kesäaikaviikko', () {
    // 3 yön päivityshaussa molemmilla sovelluksilla 3 yötä: ennen aakkosjärjestys (Fitbit) voitti tallennetun Ouran.
    final both = [
      for (var i = 0; i < 3; i++) ...[
        SleepSession(at(-i - 1, 23), at(-i, 7), app: 'Oura'),
        SleepSession(at(-i - 1, 22, 30), at(-i, 6, 30), app: 'Fitbit'),
      ],
    ];
    expect(nightsFrom(both).values.map((n) => n.app).toSet(), {'Fitbit'});
    expect(nightsFrom(both, prefer: 'Oura').values.map((n) => n.app).toSet(), {'Oura'});
    // Suosittu puuttuu yöltä: toinen sovellus täyttää.
    final gap = nightsFrom([...both.where((s) => !(s.app == 'Oura' && s.end == at(0, 7)))], prefer: 'Oura');
    expect(gap[DateTime(2026, 11, 18)]!.app, 'Fitbit');
    // Sama jakso kahdesti (uudelleensynkronointi): uni ei ole 16 h.
    final dup = nightsFrom([
      SleepSession(at(-1, 23), at(0, 7), app: 'Oura'),
      SleepSession(at(-1, 23), at(0, 7), app: 'Oura'),
    ]);
    expect(dup[DateTime(2026, 11, 18)]!.asleep, const Duration(hours: 8));
    // Kesäaikaan siirtymän viikolla (29.3.2026) 3 päivää vanha yö ei ole "viime yö".
    final march = {
      DateTime(2026, 3, 27): SleepNight(
        DateTime(2026, 3, 27),
        DateTime(2026, 3, 26, 23),
        DateTime(2026, 3, 27, 7),
        const Duration(hours: 8),
      ),
    };
    expect(sleepStats(march, DateTime(2026, 3, 30)).last, isNull);
    expect(sleepStats(march, DateTime(2026, 3, 29)).last, isNotNull);
    expect(daysBetween(DateTime(2026, 3, 27), DateTime(2026, 3, 30)), 3);
    expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26, 23)), 2);
  });

  group('tallennus', () {
    late Directory dir;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('gievra-sleep');
      settings
        ..folder = dir.path
        ..homeHidden = {};
      await sleepData.load();
    });
    tearDown(() {
      sleepData.debugSource = null;
      sleepData.nights.clear();
      // Kortin testi voi jättää Health Connect -haun kesken (kanava ei vastaa testissä): seuraava haku ei saa
      // jäädä odottamaan sitä (siemen 1118 ajoi kortin testin ensin, haku palasi heti).
      sleepData.loading = false;
      settings
        ..folder = null
        ..homeHidden = {...homeCardsOffByDefault};
      dir.deleteSync(recursive: true);
    });

    test('oletuksena pois: ei hakua; päällä haku tallentaa uni.md:hen, varmuuskopio yhdistää', () async {
      final now = DateTime.now();
      final t0 = dateOnly(now);
      var calls = 0;
      sleepData.debugSource = (a, b) async {
        calls++;
        return [
          SleepSession(
            DateTime(t0.year, t0.month, t0.day - 1, 23),
            DateTime(t0.year, t0.month, t0.day, 7),
            app: 'Oura',
          ),
        ];
      };
      settings.homeHidden = {...homeCardsOffByDefault};
      await sleepData.refresh(force: true);
      expect(calls, 0);
      settings.homeHidden = {};
      await sleepData.refresh(force: true);
      expect(calls, greaterThan(0));
      expect(sleepData.nights[t0]!.asleep, const Duration(hours: 8));
      final md = File('${dir.path}/$sleepFileName').readAsStringSync();
      expect(md, contains('${isoDate(t0)}: 23:00–07:00, 8 h 00 min (Oura)'));
      // Varmuuskopiosta: puuttuva yö lisätään, tämän laitteen yö pysyy.
      await sleepData.mergeFrom('- ${isoDate(t0)}: 22:00–05:00, 7 h 00 min\n- 2026-01-02: 23:00–06:00, 7 h 00 min\n');
      expect(sleepData.nights[t0]!.asleep, const Duration(hours: 8));
      expect(sleepData.nights[DateTime(2026, 1, 2)], isNotNull);
      // Tuonti tunnistaa uni.md:n (ei lukukelvoton treeni).
      final r = readMdFiles({'uni.md': md});
      expect(r.sleepMd, md);
      expect(r.workouts, isEmpty);
      // CSV-vienti.
      final csv = buildCsvExport(
        const [],
        settings.body,
        CsvExportOptions(from: DateTime(2026), to: t0, gym: false, cardio: false, sleep: true),
        sleep: sleepData.nights,
      );
      expect(csv.single.text, contains('23:00'));
    });

    test('unen lähde (19.11.): kysytään kerran, oletus tästä eteenpäin, yksittäisen yön valinta pysyy', () async {
      final t0 = dateOnly(DateTime.now());
      settings
        ..sleepApp = null
        ..sleepSourceAsked = false;
      // Kello kirjaa 10 yötä 6 h, sormus 5 viimeistä yötä 7 h (keksityt).
      SleepSession night(int i, String app, int h) {
        final d = addDays(t0, -i);
        return SleepSession(
          DateTime(d.year, d.month, d.day - 1, 23),
          DateTime(d.year, d.month, d.day - 1, 23 + h),
          app: app,
        );
      }

      sleepData.debugSource = (a, b) async => [
        for (var i = 0; i < 10; i++)
          if (!night(i, 'Kello', 6).start.isBefore(a) && !night(i, 'Kello', 6).end.isAfter(b)) night(i, 'Kello', 6),
        for (var i = 0; i < 5; i++)
          if (!night(i, 'Oura', 7).start.isBefore(a) && !night(i, 'Oura', 7).end.isAfter(b)) night(i, 'Oura', 7),
      ];
      await sleepData.refresh(force: true, from: addDays(t0, -12));
      expect(sleepData.nights[t0]!.app, 'Kello', reason: 'automaattinen: eniten öitä');
      expect(sleepData.conflict!.map((n) => n.app), ['Kello', 'Oura'], reason: 'kysytään viimeisimmästä yöstä');
      expect(sleepData.conflict!.first.day, t0);

      // Vastaus: oletus tästä eteenpäin; vain viimeiset yöt haetaan uudelleen, vanhemmat pysyvät (ei "vaihda kaikki").
      await sleepData.setDefault('Oura');
      expect((settings.sleepApp, settings.sleepSourceAsked, sleepData.conflict), ('Oura', true, null));
      expect(sleepData.nights[t0]!.app, 'Oura');
      expect(sleepData.nights[addDays(t0, -4)]!.app, 'Kello', reason: 'vanha yö ennallaan');
      expect(settings.settingsToMarkdown(), allOf(contains('sleep_app: Oura'), contains('sleep_source_asked: true')));

      // Kalenterin päivä: kummankin arvo, ja yhden yön valinta pysyy päivityksessä.
      final alts = await sleepData.alternatives(t0);
      expect(alts.map((n) => (n.app, n.asleep.inHours)), [('Kello', 6), ('Oura', 7)]);
      await sleepData.pickNight(alts.first);
      await sleepData.refresh(force: true);
      expect(sleepData.nights[t0]!.app, 'Kello');
      expect(sleepData.nights[t0]!.picked, isTrue);
      expect(sleepData.nights[addDays(t0, -1)]!.app, 'Oura');
      final md = File('${dir.path}/$sleepFileName').readAsStringSync();
      expect(md, contains('(Kello · valittu)'));
      expect(parseSleep(md)[t0]!.picked, isTrue);
      expect(parseSleep(md)[t0]!.app, 'Kello');
      settings
        ..sleepApp = null
        ..sleepSourceAsked = false;
    });

    test('unen lähde: "Pidä automaattinen" ei kysy uudelleen', () async {
      final t0 = dateOnly(DateTime.now());
      settings
        ..sleepApp = null
        ..sleepSourceAsked = false;
      sleepData.debugSource = (a, b) async => [
        SleepSession(DateTime(t0.year, t0.month, t0.day - 1, 23), DateTime(t0.year, t0.month, t0.day, 5), app: 'Kello'),
        SleepSession(DateTime(t0.year, t0.month, t0.day - 1, 23), DateTime(t0.year, t0.month, t0.day, 6), app: 'Oura'),
      ];
      await sleepData.refresh(force: true);
      expect(sleepData.conflict, isNotNull);
      sleepData.dismissConflict();
      await sleepData.refresh(force: true);
      expect(sleepData.conflict, isNull);
      expect(settings.sleepApp, isNull);
      settings.sleepSourceAsked = false;
    });

    test('yötesti 18.11.: muuttumaton haku ei kirjoita uni.md:tä uudelleen (sekunnit ja millisekunnit)', () async {
      final t0 = dateOnly(DateTime.now());
      sleepData.debugSource = (a, b) async => [
        SleepSession(
          DateTime(t0.year, t0.month, t0.day - 1, 23, 0, 31, 250),
          DateTime(t0.year, t0.month, t0.day, 7, 0, 12),
          app: 'Oura',
        ),
      ];
      await sleepData.refresh(force: true);
      final f = File('${dir.path}/$sleepFileName');
      expect(f.existsSync(), isTrue);
      f.deleteSync();
      await sleepData.refresh(force: true);
      expect(f.existsSync(), isFalse, reason: 'mikään ei muuttunut tiedoston tarkkuudella');
    });

    testWidgets('kortti: kesto, kellonajat, pylväät ja vihje', (tester) async {
      final t0 = dateOnly(DateTime.now());
      sleepData.nights
        ..clear()
        ..addAll({
          for (var i = 0; i < 10; i++)
            addDays(t0, -i): () {
              final d = addDays(t0, -i);
              final bed = DateTime(d.year, d.month, d.day - 1, 23, 30);
              final m = i == 0 ? 330 : 450;
              return SleepNight(
                d,
                bed,
                bed.add(Duration(minutes: m + 15)),
                Duration(minutes: m),
                app: 'Oura',
              );
            }(),
        });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: SleepCard())),
        ),
      );
      expect(find.byKey(const ValueKey('sleepCard')), findsOneWidget);
      expect(find.text('5:30'), findsOneWidget);
      expect(find.text('Oura'), findsOneWidget);
      // Vihje ⚠-kuvakkeen takana (18.11.): ei tekstilaatikkoa kortissa.
      expect(find.textContaining('Lyhyt yö'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sleepTip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lyhyt yö'), findsOneWidget);
      expect(find.textContaining('Tavoitteesi'), findsNothing, reason: 'ei unitavoitetta');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('värit omaan tavalliseen verrattuna: 30 min sisällä vihreä, enemmän keltainen, 6 h tai alle punainen', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => (ctx = c, const SizedBox()).$2)));
    const usual = Duration(hours: 7, minutes: 31);
    Color col(int min) => SleepCard.durationColor(ctx, Duration(minutes: min), usual);
    expect(col(425), greenText(ctx), reason: '7 h 05: 26 min alle');
    expect(col(400), SleepCard.amber(ctx), reason: '6 h 40: yli 30 min alle');
    expect(col(360), redText(ctx), reason: '6 h');
    expect(SleepCard.usualOf(const SleepStats()), const Duration(hours: 7), reason: 'alussa 7 h');
  });
}
