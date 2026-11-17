import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/models.dart';

// Uinnin vauhti asetuksen mukaan min/km tai min/100 m (käyttäjä 15.11.). Tiedostoon aina /km. Keksitty uinti.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => settings.setSwimPer100(false));

  Workout swim() =>
      Workout(date: DateTime(2026, 11, 15), title: 'Uinti', activity: 'Uinti', distanceKm: 1.5)
        ..seconds = 1680; // 28:00 → 18:40 /km, 1:52 /100 m

  test('oletus min/km; asetuksella uinti min/100 m, muut lajit ennallaan', () {
    expect(swim().pace, '18:40 min/km');
    settings.setSwimPer100(true);
    expect(swim().pace, '1:52 min/100 m');
    expect(paceText(swim().paceSecPerKm!, 'Uinti', short: true), '1:52 /100 m');
    final run = Workout(date: DateTime(2026, 11, 15), title: 'Juoksu', activity: 'Juoksu', distanceKm: 10)
      ..seconds = 3000;
    expect(run.pace, '5:00 min/km');
  });

  test('tiedostoon aina /km; asetus tallentuu ja palautuu', () {
    settings.setSwimPer100(true);
    expect(workoutToMarkdown(swim()), contains('18:40 /km'));
    final md = settings.settingsToMarkdown();
    expect(md, contains('swim_pace: 100m'));
    settings.setSwimPer100(false);
    expect(settings.settingsToMarkdown(), isNot(contains('swim_pace')));
    final s2 = Settings()..applyMarkdown(md);
    expect(s2.swimPer100m, isTrue);
  });
}
