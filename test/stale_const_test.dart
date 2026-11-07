import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Vanhentuvat näkymät: const-widget ei piirry uudelleen, vaikka ylempi ListenableBuilder piirtyisi. Jos widget lukee
// asetuksia tai treenejä (settings. / store.) eikä kuuntele niitä itse, sitä ei saa upottaa const-muodossa
// toiseen näkymään. Uutena reittinä avattava näkymä (MaterialPageRoute) on sallittu, koska se luodaan aina uudestaan.
void main() {
  test('ei const-upotuksia widgeteistä, jotka lukevat tilaa kuuntelematta', () {
    final files = {
      for (final f in [...Directory('lib/ui').listSync(), File('lib/main.dart')].whereType<File>())
        if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
    };
    final classRe = RegExp(r'^class (\w+) extends (StatelessWidget|StatefulWidget)', multiLine: true);
    final problems = <String>[];
    for (final src in files.values) {
      for (final m in classRe.allMatches(src)) {
        final name = m[1]!;
        String bodyFrom(int start) {
          final next = RegExp(r'^class ', multiLine: true).firstMatch(src.substring(start + 6));
          return src.substring(start, next == null ? src.length : start + 6 + next.start);
        }

        var body = bodyFrom(m.start);
        final st = RegExp('^class _?${name}State extends State<$name>', multiLine: true).firstMatch(src);
        if (st != null) body += bodyFrom(st.start);
        final reads = RegExp(r'\b(settings|store)\.').hasMatch(body);
        final listens = RegExp(r'ListenableBuilder|AnimatedBuilder|addListener').hasMatch(body);
        if (!reads || listens) continue;
        for (final e in files.entries) {
          final lines = e.value.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final l = lines[i];
            if (!l.contains('const $name(') || l.startsWith('  const $name(')) continue; // konstruktori
            if (RegExp(r'MaterialPageRoute|builder: \(_\)|runApp|home:').hasMatch(l)) continue; // oma reitti
            if (RegExp(r'\? const|: const').hasMatch(l) && e.key.endsWith('main.dart')) {
              continue; // juurinäkymän valinta
            }
            problems.add('${e.key}:${i + 1}: $name');
          }
        }
      }
    }
    expect(problems, isEmpty, reason: 'Poista const tai lisää widgetiin ListenableBuilder');
  });
}
