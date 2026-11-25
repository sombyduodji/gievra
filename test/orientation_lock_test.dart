import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/orientation_lock.dart';

// Salitreeni pystyssä (käyttäjä 18.11.); puhelimessa koko sovellus pystyssä, tabletissa kääntyy (24.11.).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(debugResetOrientationLock);

  test('tabletti: lukitus pinottuna, vapautuu vasta viimeisen treeninäkymän sulkeutuessa', () {
    updatePhoneLock(const Size(800, 1280));
    expect(debugLastOrientations, isEmpty);
    lockPortrait();
    expect(debugLastOrientations, [DeviceOrientation.portraitUp]);
    lockPortrait();
    unlockPortrait();
    expect(debugLastOrientations, [DeviceOrientation.portraitUp]);
    unlockPortrait();
    expect(debugLastOrientations, isEmpty);
    unlockPortrait(); // ylimääräinen ei mene miinukselle
    lockPortrait();
    expect(debugLastOrientations, [DeviceOrientation.portraitUp]);
    unlockPortrait();
  });

  test('puhelin aina pystyssä, myös treenin jälkeen; taittopuhelimen avaus vapauttaa', () {
    updatePhoneLock(const Size(412, 915)); // tavallinen puhelin
    expect(debugLastOrientations, [DeviceOrientation.portraitUp]);
    lockPortrait();
    unlockPortrait();
    expect(debugLastOrientations, [DeviceOrientation.portraitUp], reason: 'treenin jälkeenkin pystyssä');
    updatePhoneLock(const Size(915, 412)); // vaakasuunnassa sama puhelin
    expect(debugLastOrientations, [DeviceOrientation.portraitUp]);
    updatePhoneLock(const Size(720, 840)); // taittopuhelin auki
    expect(debugLastOrientations, isEmpty);
    expect(isPhoneSize(const Size(599, 900)), isTrue);
    expect(isPhoneSize(const Size(600, 960)), isFalse);
  });
}
