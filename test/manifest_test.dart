import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Kovennus (yötesti 15.11., käyttäjä: "do what is best"): sovelluksen ulkoa avattavat osat ja luvat lukitaan tähän.
// Jos testi kaatuu, uusi vienti (exported="true") tai lupa on lisätty: tarkista, onko se tarpeen, ja päivitä listat
// tarkoituksella. Vain lähdemanifesti (liitännäisten omat osat lisätään koonnissa).
void main() {
  final xml = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final body = xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  Iterable<String> tags(String name) => RegExp('<$name\\b[^>]*>', dotAll: true).allMatches(body).map((m) => m[0]!);
  String? attr(String tag, String a) => RegExp('android:$a="([^"]*)"').firstMatch(tag)?[1];

  test('luvat: vain nämä', () {
    final perms = tags('uses-permission').map((t) => attr(t, 'name')!).toSet();
    expect(perms, {
      'android.permission.MANAGE_EXTERNAL_STORAGE', // treenikansio (Nextcloud/Seafile); SAF-vaihto myöhemmin
      'android.permission.INTERNET', // karttapaketit
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.VIBRATE',
      'android.permission.USE_EXACT_ALARM', // palautusajastin
      'android.permission.SCHEDULE_EXACT_ALARM',
      'android.permission.ACCESS_FINE_LOCATION', // GPS-lenkki
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_LOCATION',
      'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
      'android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE', // sykevyö taustalla
      'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      'android.permission.BLUETOOTH',
      'android.permission.BLUETOOTH_ADMIN',
      'android.permission.BLUETOOTH_SCAN',
      'android.permission.BLUETOOTH_CONNECT',
      'android.permission.health.READ_HEART_RATE',
      'android.permission.health.READ_EXERCISE',
      'android.permission.health.READ_TOTAL_CALORIES_BURNED',
      'android.permission.health.READ_STEPS',
      'android.permission.health.READ_HEALTH_DATA_HISTORY',
      'android.permission.health.READ_DISTANCE',
      'android.permission.health.READ_SLEEP',
      'android.permission.health.READ_HEART_RATE_VARIABILITY',
      'android.permission.health.READ_OXYGEN_SATURATION',
      'android.permission.health.READ_RESPIRATORY_RATE',
      'android.permission.health.READ_RESTING_HEART_RATE',
      'android.permission.health.READ_SKIN_TEMPERATURE',
    });
    // Ei kirjoitusoikeuksia Health Connectiin (vain luku, ks. muistio: ei takaisinkirjoitusta).
    expect(perms.where((p) => p.contains('health.WRITE')), isEmpty);
  });

  test('ulkoa avattavat osat: vain pääikkuna, tiedoston avaus ja Health Connectin lupanäkymä', () {
    final exported = [
      for (final kind in ['activity', 'activity-alias', 'service', 'receiver', 'provider'])
        for (final t in tags(kind))
          if (attr(t, 'exported') == 'true') attr(t, 'name')!,
    ];
    expect(exported.toSet(), {'.MainActivity', '.OpenFileActivity', '.PrivacyActivity', 'ViewPermissionUsageActivity'});
    // Avaa sovelluksella / Jaa menee läpikulkuaktiviteetin kautta (yötesti 16.11.: ei toista Gievraa muistiin).
    final main = tags('activity').firstWhere((t) => attr(t, 'name') == '.MainActivity');
    final mainBody = body.substring(body.indexOf(main), body.indexOf('</activity>', body.indexOf(main)));
    expect(mainBody, isNot(contains('android.intent.action.VIEW"')));
    expect(mainBody, isNot(contains('android.intent.action.SEND"')));
    final open = tags('activity').firstWhere((t) => attr(t, 'name') == '.OpenFileActivity');
    expect(attr(open, 'noHistory'), 'true');
    expect(attr(open, 'excludeFromRecents'), 'true');
    // Lupanäkymä vain järjestelmälle.
    final alias = tags('activity-alias').single;
    expect(attr(alias, 'permission'), 'android.permission.START_VIEW_PERMISSION_USAGE');
    // Health Connectin tietosuojalinkit avaavat oman tietosuojanäkymän (yötesti 18.11.: pääikkuna jäi taakse).
    expect(attr(alias, 'targetActivity'), '.PrivacyActivity');
    final privacy = tags('activity').firstWhere((t) => attr(t, 'name') == '.PrivacyActivity');
    final privacyBody = body.substring(body.indexOf(privacy), body.indexOf('</activity>', body.indexOf(privacy)));
    expect(privacyBody, contains('androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE'));
    expect(mainBody, isNot(contains('ACTION_SHOW_PERMISSIONS_RATIONALE')));
    // Jokaisella palvelulla, vastaanottimella ja tarjoajalla on exported näkyvästi.
    for (final kind in ['service', 'receiver', 'provider']) {
      for (final t in tags(kind)) {
        expect(attr(t, 'exported'), isNotNull, reason: '$kind ${attr(t, 'name')}: exported puuttuu');
      }
    }
  });

  test('tiedostot avataan vain content://-osoitteista; varmuuskopiosäännöt käytössä', () {
    final app0 = body.substring(body.indexOf('<application'), body.indexOf('</application>'));
    final data = RegExp(r'<data\b[^>]*>')
        .allMatches(app0)
        .map((m) => m[0]!)
        .where((t) => attr(t, 'scheme') != null)
        .map((t) => attr(t, 'scheme'))
        .toSet();
    expect(data, {'content'}, reason: 'ei file://, http:// tms. VIEW-suodattimissa');
    final app = tags('application').single;
    expect(attr(app, 'dataExtractionRules'), '@xml/data_extraction_rules');
    expect(attr(app, 'fullBackupContent'), '@xml/backup_rules');
    expect(attr(app, 'usesCleartextTraffic'), isNot('true'));
    expect(attr(app, 'debuggable'), isNull);
    // Avatut tiedostot eivät ole Flutterin reittejä (ks. manifestin kommentti).
    final deeplink = tags('meta-data').where((t) => attr(t, 'name') == 'flutter_deeplinking_enabled');
    expect(deeplink.map((t) => attr(t, 'value')), ['false']);
  });

  // Testikierros 16.11.: kun Gievra käynnistyi tiedoston avauksesta, tehtävän pohja-aikomukseksi jäi VIEW + tiedosto.
  // Takaisin-poistumisen jälkeen kuvake teki toisen Gievra-kortin Viimeisimpiin, ja vanha kortti avasi tuonnin
  // esikatselun uudelleen toiseen MainActivityyn. Välitys on siksi käynnistimen aikomus (MAIN + LAUNCHER) ja tiedosto
  // lisätietona, eikä historiasta tai tallennetusta tilasta palautettu käynnistys avaa tiedostoa toista kertaa.
  test('tiedoston avaus välitetään käynnistimen aikomuksena, eikä historiasta avata uudelleen', () {
    const dir = 'android/app/src/main/kotlin/fi/somby/gievra';
    final open = File('$dir/OpenFileActivity.kt').readAsStringSync();
    expect(open, contains('Intent(Intent.ACTION_MAIN)'));
    expect(open, contains('addCategory(Intent.CATEGORY_LAUNCHER)'));
    expect(open, contains('putExtra(MainActivity.EXTRA_OPEN'));
    expect(open, isNot(contains('setDataAndType')));
    final main = File('$dir/MainActivity.kt').readAsStringSync();
    expect(main, contains('FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY'));
    expect(main, contains('pendingIntent = if (restored) null else intent'));
  });
}
