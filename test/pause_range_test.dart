import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';

/// Tauko alku- ja päättymispäivällä (käyttäjä 16.11.): loma etukäteen, päättyy itsestään, muokattavissa.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final today = dateOnly(DateTime.now());

  test('Päättymispäivä: päällä viimeiseen päivään asti, sitten ei; tiedostossa ja takaisin', () async {
    final dir = Directory.systemTemp.createTempSync('gievra-tauko');
    settings.folder = dir.path;
    addTearDown(() {
      settings.pauses = [];
      settings.folder = null;
      dir.deleteSync(recursive: true);
    });
    settings.startPause('loma', addDays(today, -2), addDays(today, 3));
    expect(settings.activePause?.reason, 'loma');
    expect(settings.activePause!.days, 3);
    expect(settings.pauseOn(addDays(today, 3)), isNotNull);
    expect(settings.pauseOn(addDays(today, 4)), isNull);
    // Tiedostomuoto ennallaan: "- alku – loppu syy".
    final md = settings.settingsToMarkdown();
    expect(md, contains('- ${isoDate(addDays(today, -2))} – ${isoDate(addDays(today, 3))} loma'));
    // Mennyt päättymispäivä: ei enää päällä, mutta kalenterissa näkyy.
    settings.updatePause(settings.activePause!, 'loma', addDays(today, -9), addDays(today, -3));
    expect(settings.activePause, isNull);
    expect(settings.pauseOn(addDays(today, -5))?.reason, 'loma');
  });

  test('Tuleva loma: ei vielä päällä, upcoming; muokkaus ja avoin tauko', () {
    addTearDown(() => settings.pauses = []);
    settings.pauses = [];
    settings.startPause('loma', addDays(today, 7), addDays(today, 13));
    expect(settings.activePause, isNull);
    expect(settings.upcomingPause?.start, addDays(today, 7));
    // Sairastuminen nyt: avoin tauko rinnalle (ei päällekkäinen tulevan kanssa).
    settings.startPause('sairas', today);
    expect(settings.activePause?.reason, 'sairas');
    expect(settings.pauses.length, 2);
    // Lopetus: tänään alkanut poistuu kokonaan, tuleva jää.
    settings.endPause(addDays(today, -1));
    expect(settings.activePause, isNull);
    expect(settings.pauses.single.reason, 'loma');
  });

  test('Päällekkäinen uusi tauko korvaa vanhan', () {
    addTearDown(() => settings.pauses = []);
    settings.pauses = [];
    settings.startPause('loma', addDays(today, -5), addDays(today, 5));
    settings.startPause('sairas', addDays(today, -1));
    expect(settings.pauses.single.reason, 'sairas');
  });
}
