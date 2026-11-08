import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/exercises.dart';
import 'package:treenipaivakirja/ui/set_logger.dart';

void main() {
  test('Käsipaino- ja kahvakuulaliikkeiden painon otsikko ja kokonaispaino', () {
    // Kaksi käsipainoa: per käsipaino, kokonaispaino näkyy.
    expect(weightTitle('Käsipainopenkki'), 'Paino per käsipaino (2 käsipainoa)');
    expect(weightTotal('Käsipainopenkki', 22), 'Molemmissa käsissä · yhteensä 44 kg');
    expect(weightTitle('Rintatuettu kulmasoutu käsipainoilla'), 'Paino per käsipaino (2 käsipainoa)');
    // Yhden käden liike: per käsipaino, ei kokonaispainoa.
    expect(weightTitle('Käsipainosoutu'), 'Paino per käsipaino');
    expect(weightTotal('Käsipainosoutu', 30), isNull);
    // Kahvakuula: yksi kuula / kaksi kuulaa.
    expect(weightTitle('Kahvakuulaheilautus'), 'Paino per kuula');
    expect(weightTitle('Tuplakahvakuulapystypunnerrus'), 'Paino per kuula (2 kuulaa)');
    expect(weightTotal('Tuplakahvakuulapystypunnerrus', 16), 'Molemmissa käsissä · yhteensä 32 kg');
    expect(weightTitle('Goblet-kyykky'), 'Paino (yksi käsipaino tai kuula)');
    // Tanko tai käsipainot: ei voida tietää, tavallinen otsikko.
    expect(weightTitle('Romanialainen maastaveto'), isNull);
    expect(weightTitle('Takakyykky'), isNull);
    // Volyymi: kaksi painoa lasketaan kahdesti.
    expect(loadMultiplier('Käsipainopenkki'), 2);
    expect(loadMultiplier('Käsipainosoutu'), 1);
    // Jokainen luokiteltu liike on luettelossa.
    final all = exerciseCatalog.values.expand((x) => x).toSet();
    expect(pairedDumbbell.difference(all), isEmpty);
    expect(singleWeight.difference(all), isEmpty);
  });
}
