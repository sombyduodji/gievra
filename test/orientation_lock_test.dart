import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/orientation_lock.dart';

// Salitreeni pystyssä (käyttäjä 18.11.); muut näkymät kääntyvät.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('lukitus pinottuna: vapautuu vasta viimeisen treeninäkymän sulkeutuessa', () {
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
}
