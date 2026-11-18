import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/ui/steps_ui.dart';

// Muokattava askeltavoite (käyttäjä 17.11.): tiedostoon ja takaisin, rajat ja lyhyet merkinnät.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => settings.stepsGoal = 10000);

  test('askeltavoite asetuksissa', () {
    expect(settings.settingsToMarkdown(), isNot(contains('steps_goal')));
    settings.applyMarkdown('---\nsteps_goal: 8000\n---\n');
    expect(stepsGoal, 8000);
    expect(settings.settingsToMarkdown(), contains('steps_goal: 8000'));
    settings.applyMarkdown('---\nsteps_goal: 99\n---\n'); // virheellinen ohitetaan
    expect(stepsGoal, 8000);
    settings.setStepsGoal(200000);
    expect(stepsGoal, 50000);
    expect(stepsK(10000), '10k');
    expect(stepsK(7500), '7,5k');
  });
}
