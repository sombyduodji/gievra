import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/main.dart';

// Ensimmäinen käynnistys jokaisella kielellä: nimi, Aloitetaan ja seuraava näkymä aukeaa ilman virhettä.
void main() {
  for (final lang in ['fi', 'en', 'se']) {
    for (final mode in ['gym', 'cardio', 'both']) {
      testWidgets('Aloitus: $lang, $mode', (tester) async {
        settings
          ..name = null
          ..introDone = false
          ..trainMode = mode;
        await tester.runAsync(() => setUiLang(lang));
        await tester.pumpWidget(const TreeniApp());
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Testi');
        await tester.pump();
        final start = find.widgetWithText(FilledButton, t('Aloitetaan'));
        await tester.dragUntilVisible(start, find.byType(ListView).first, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(start).onPressed, isNotNull, reason: 'Aloitetaan käytössä');
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(settings.name, 'Testi');
        expect(
          find.byType(TextField).evaluate().isEmpty || find.text('Testi').evaluate().isEmpty,
          isTrue,
          reason: 'nimikysely ei saa jäädä näkyviin',
        );
      });
    }
  }

  // Oikea ensimmäinen käynnistys: sovellus alkaa suomeksi ja kieli vaihdetaan aloitussivulla.
  for (final lang in ['en', 'se']) {
    for (final mode in ['gym', 'cardio']) {
      testWidgets('Aloitus, kieli vaihdetaan aloitussivulla: $lang, $mode', (tester) async {
        settings
          ..name = null
          ..introDone = false
          ..trainMode = mode;
        await tester.runAsync(() => setUiLang('fi'));
        await tester.pumpWidget(const TreeniApp());
        await tester.pumpAndSettle();
        final name = uiLanguages.firstWhere((l) => l.code == lang).name;
        await tester.runAsync(() async {
          await tester.tap(find.text(name));
          await tester.pump();
          if (lang == 'se') {
            await tester.pumpAndSettle();
            await tester.tap(find.text('Kyllä · Juo'));
          }
          await Future<void>.delayed(const Duration(milliseconds: 500)); // käännösten luku
        });
        await tester.pumpAndSettle();
        expect(uiLang, lang);
        await tester.enterText(find.byType(TextField).first, 'Testi');
        await tester.pump();
        final start = find.widgetWithText(FilledButton, t('Aloitetaan'));
        await tester.dragUntilVisible(start, find.byType(ListView).first, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(settings.name, 'Testi');
        expect(
          find.widgetWithText(FilledButton, t('Aloitetaan')).evaluate(),
          isEmpty,
          reason: 'aloitussivu ei saa jäädä',
        );
      });
    }
  }
}
