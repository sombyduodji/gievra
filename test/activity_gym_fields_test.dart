import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/models.dart';

// Käyttäjän vienti 18.11.: kävelytiedostoon oli tallentunut salin lämmittely ja supersarja. Keksityt arvot.
void main() {
  test('pelkkä liikunta ei saa salin lämmittelyä eikä supersarjaa tiedostoon', () {
    final walk = Workout(date: DateTime(2030, 1, 1), title: 'Kävely')
      ..activity = 'Kävely'
      ..distanceKm = 2
      ..seconds = 1800
      ..warmup = Warmup('Crosstrainer', 5)
      ..supersets = [
        ['Liike A', 'Liike B'],
      ];
    final md = workoutToMarkdown(walk);
    expect(md, isNot(contains('warmup:')));
    expect(md, isNot(contains('superset:')));
    expect(md, isNot(contains('## Lämmittely')));
    final gym = Workout(date: DateTime(2030, 1, 1), title: 'Treeni')..warmup = Warmup('Crosstrainer', 5);
    expect(workoutToMarkdown(gym), contains('warmup: Crosstrainer, 5 min'));
  });
}
