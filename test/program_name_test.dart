import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/program.dart';
import 'package:treenipaivakirja/ui/program_template.dart';

// Testikierros 16.11.: ohjelmapohjan nimi katosi käyttöönotossa ("Testipohja" → "voima · 2 päivää viikossa").
void main() {
  Program program({String? name}) => Program(
    goal: 'voima',
    experience: 'keski',
    days: 1,
    minutes: 60,
    start: DateTime(2026, 11, 2),
    deloadEvery: 0,
    name: name,
    plan: [
      PlanDay('Koko keho A', [PlanItem('Penkkipunnerrus', 'VT', 3, 5, 5, '1–2', 180)]),
    ],
  );

  test('pohjan nimi säilyy käyttöönotossa ja ohjelma.md:ssä', () {
    final tpl = programToTemplate(program(), name: 'Testipohja');
    expect(RegExp(r'^name: ', multiLine: true).allMatches(tpl).length, 1);
    final p = parseProgram(tpl)!;
    expect(p.name, 'Testipohja');
    expect(p.displayTitle, 'Testipohja · 1 päivä viikossa');
    expect(p.kindTitle, isNot(contains('Testipohja')), reason: 'alarivi ilman nimeä (nimi on jo otsikkona)');
    // Käytössä oleva ohjelma (ohjelma.md) muistaa nimen.
    final again = parseProgram(programToMarkdown(p))!;
    expect(again.name, 'Testipohja');
    expect(again.displayTitle.split(' · ').first, 'Testipohja');
  });

  test('ilman nimeä otsikko tavoitteesta kuten ennen', () {
    final p = parseProgram(programToMarkdown(program()))!;
    expect(p.name, isNull);
    expect(p.displayTitle.split(' · ').first, isNot(contains('name')));
    expect(programToMarkdown(p), isNot(contains('name:')));
  });

  test('tallennus toisella nimellä kirjoittaa vain sen nimen', () {
    final md = programToMarkdown(program(name: 'Vanha'), name: 'Uusi');
    expect(RegExp(r'^name: (.+)$', multiLine: true).allMatches(md).map((m) => m[1]), ['Uusi']);
  });

  test('tallennetun ohjelman tiedostonimi säilyttää saamen kirjaimet (testi 16.11.)', () {
    expect(savedProgramPath('Čielggis ŋ-prográmma/../x:*?'), 'ohjelmat/Čielggis ŋ-prográmmax.gmd');
    expect(savedProgramPath(' ../ '), 'ohjelmat/ohjelma.gmd');
  });

  test('yhden päivän ohjelma yksikössä', () {
    expect(program(name: 'Yksi').displayTitle, endsWith('1 päivä viikossa'));
  });
}
