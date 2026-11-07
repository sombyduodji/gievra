import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/program_check.dart';

void main() {
  test('Ohjelma rakennetaan valittujen liikkeiden ympärille', () {
    const chosen = [
      'Etukyykky',
      'Vinokäsipainopenkki',
      'T-tankosoutu',
      'Kahvakuulaheilautus',
      'Scott-kääntö',
      'Lankku',
    ];
    for (final days in [2, 3, 4, 5]) {
      final p = generateProgram(
        goal: 'lihaskasvu',
        experience: 'keski',
        days: days,
        minutes: 75,
        injuries: const [],
        chosen: chosen,
      );
      final names = p.plan.expand((d) => d.items).map((i) => i.exercise).toSet();
      expect(names, containsAll(chosen), reason: '$days päivää');
      expect(validateProgram(p), isEmpty, reason: '$days päivää: ${validateProgram(p)}');
      expect(p.notes.join(), contains('valitsemiesi'));
    }
  });

  test('Valitut liikkeet ja lyhyt aika: ohjelman omat lisäliikkeet karsitaan ensin', () {
    const chosen = [
      'Penkkipunnerrus',
      'Takakyykky',
      'Maastaveto',
      'Vinopenkki',
      'Farmer walk',
      'Face pull',
      'Kulmasoutu',
      'Pystypunnerrus',
      'Askelkyykkykävely',
      'Vipunosto sivulle',
    ];
    for (final goal in ['voimanosto', 'lihaskasvu']) {
      final p = generateProgram(
        goal: goal,
        experience: 'keski',
        days: 2,
        minutes: 45,
        injuries: const [],
        chosen: chosen,
      );
      final names = p.plan.expand((d) => d.items).map((i) => i.exercise).toSet();
      expect(names, containsAll(chosen));
      final longest = p.plan.map((d) => estimateMinutes(d.items)).reduce((a, b) => a > b ? a : b);
      // ignore: avoid_print
      print('$goal 2 pv / 45 min: pisin ${longest.round()} min');
      if (longest > 60) expect(p.notes.join(), contains('Valitsit 10 liikettä 2 treenipäivälle'));
    }
  });

  test('Treenityyli tallentuu asetukset.md:hen ja luetaan takaisin', () {
    final a = Settings()
      ..name = 'Elle'
      ..style = TrainingStyle(
        goal: 'voimanosto',
        experience: 'keski',
        days: 3,
        minutes: 75,
        repStyle: 'raskas',
        equipment: {'vapaat'},
        moves: ['Takakyykky', 'Penkkipunnerrus', 'Kulmasoutu'],
      );
    final md = a.settingsToMarkdown();
    expect(md, contains('## Treenityyli'));
    expect(md, contains('- liikkeet: Takakyykky, Penkkipunnerrus, Kulmasoutu'));
    final b = Settings()..applyMarkdown(md);
    final s = b.style!;
    expect((s.goal, s.experience, s.days, s.minutes, s.repStyle), ('voimanosto', 'keski', 3, 75, 'raskas'));
    expect(s.equipment, {'vapaat'});
    expect(s.moves, ['Takakyykky', 'Penkkipunnerrus', 'Kulmasoutu']);
    // Vanha asetukset.md ilman osiota: ei tyyliä, ei virhettä.
    expect((Settings()..applyMarkdown('---\nname: X\n---\n## Lämmittelylaitteet\n- 🚴 Kuntopyörä\n')).style, isNull);
  });

  test('Venyttely lämmittelyvaihtoehdoissa, myös vanhaan oletuslistaan', () {
    expect(Settings().equipment.map((e) => e.name), contains('Venyttely'));
    const old =
        '## Lämmittelylaitteet\n- 🚶 Kävelymatto\n- 🚴 Kuntopyörä\n- 🏃 Crosstrainer\n- 🪜 Porraskone\n- 🚣 Soutulaite\n';
    expect((Settings()..applyMarkdown(old)).equipment.last.name, 'Venyttely');
    // Käyttäjän muokattuun listaan ei lisätä mitään.
    expect((Settings()..applyMarkdown('## Lämmittelylaitteet\n- 🚴 Kuntopyörä\n')).equipment.length, 1);
  });
}
