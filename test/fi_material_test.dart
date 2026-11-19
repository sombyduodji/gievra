import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/sami_material.dart';

// Nothing-testi 18.11.: ruudunlukija luki välilehdet Flutterin suomeksi "Välilehti 1 kautta 5".
void main() {
  testWidgets('suomen välilehden nimi ruudunlukijalle: Välilehti 1/5', (tester) async {
    late MaterialLocalizations l;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fi'),
        supportedLocales: const [Locale('fi'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (c) {
            l = MaterialLocalizations.of(c);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(l.tabLabel(tabIndex: 1, tabCount: 5), 'Välilehti 1/5');
    expect(l.okButtonLabel, 'OK');
  });
}
