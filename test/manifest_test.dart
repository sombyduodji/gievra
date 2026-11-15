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
    });
    // Ei kirjoitusoikeuksia Health Connectiin (vain luku, ks. muistio: ei takaisinkirjoitusta).
    expect(perms.where((p) => p.contains('health.WRITE')), isEmpty);
  });

  test('ulkoa avattavat osat: vain pääikkuna ja Health Connectin lupanäkymä', () {
    final exported = [
      for (final kind in ['activity', 'activity-alias', 'service', 'receiver', 'provider'])
        for (final t in tags(kind))
          if (attr(t, 'exported') == 'true') attr(t, 'name')!,
    ];
    expect(exported.toSet(), {'.MainActivity', 'ViewPermissionUsageActivity'});
    // Lupanäkymä vain järjestelmälle.
    final alias = tags('activity-alias').single;
    expect(attr(alias, 'permission'), 'android.permission.START_VIEW_PERMISSION_USAGE');
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
}
