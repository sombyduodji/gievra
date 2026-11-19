import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/widgets.dart' show seGreeting;
import 'package:treenipaivakirja/app_state.dart';
import 'package:treenipaivakirja/l10n.dart';
import 'package:treenipaivakirja/main.dart';

// Ensimmäinen käynnistys jokaisella kielellä: nimi, Aloitetaan ja seuraava näkymä aukeaa ilman virhettä.
void main() {
  for (final lang in ['fi', 'en', 'se']) {
    for (final mode in ['gym', 'cardio', 'both']) {
      testWidgets('Aloitus: $lang, $mode', (tester) async {
        settings
          ..started = false
          ..introDone = false
          ..trainMode = mode;
        await tester.runAsync(() => setUiLang(lang));
        await tester.pumpWidget(const TreeniApp());
        await tester.pumpAndSettle();
        final start = find.widgetWithText(FilledButton, t('Aloitetaan'));
        await tester.dragUntilVisible(start, find.byType(ListView).first, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(start).onPressed, isNotNull, reason: 'Aloitetaan käytössä');
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Nimeä ei kysytä (käyttäjä 18.11.).
        expect(find.text(t('Miksi haluat, että sinua kutsutaan?')), findsNothing);
        expect(settings.settingsToMarkdown(), isNot(contains('name:')));
      });
    }
  }

  // Oikea ensimmäinen käynnistys: sovellus alkaa suomeksi ja kieli vaihdetaan aloitussivulla.
  for (final lang in ['en', 'se']) {
    for (final mode in ['gym', 'cardio']) {
      testWidgets('Aloitus, kieli vaihdetaan aloitussivulla: $lang, $mode', (tester) async {
        settings
          ..started = false
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
        final start = find.widgetWithText(FilledButton, t('Aloitetaan'));
        await tester.dragUntilVisible(start, find.byType(ListView).first, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(settings.settingsToMarkdown(), isNot(contains('name:')));
        expect(
          find.widgetWithText(FilledButton, t('Aloitetaan')).evaluate(),
          isEmpty,
          reason: 'aloitussivu ei saa jäädä',
        );
      });
    }
  }

  testWidgets('Aloitus ilman nimeä: menee läpi ja tervehdys on ilman nimeä', (tester) async {
    settings
      ..started = false
      ..introDone = true
      ..trainMode = 'gym';
    await tester.runAsync(() => setUiLang('fi'));
    await tester.pumpWidget(const TreeniApp());
    await tester.pumpAndSettle();
    final start = find.widgetWithText(FilledButton, t('Aloitetaan'));
    await tester.dragUntilVisible(start, find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((settings.started, settings.onboarded), (true, true));
    expect(find.widgetWithText(FilledButton, t('Aloitetaan')), findsNothing);
    // Tervehdys on aina ilman nimeä ja huutomerkkiä (18.11.: otsikossa vain "Buorre iđit" ym.).
    expect(find.text(seGreeting(DateTime.now())), findsWidgets, reason: 'tervehdys ilman nimeä');
    expect(settings.settingsToMarkdown(), contains('started: true'));
  });

  test('Vanhat asetukset: nimi annettu = aloitus käyty; started luetaan tiedostosta', () {
    settings.started = false;
    settings.applyMarkdown('---\nname: Testi\n---\n');
    expect(settings.onboarded, isTrue);
    settings.started = false;
    expect(settings.onboarded, isFalse);
    settings.applyMarkdown('---\nstarted: true\n---\n');
    expect(settings.onboarded, isTrue);
  });
}
