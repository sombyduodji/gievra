import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treenipaivakirja/ui/tap_guard.dart';

// Napautussuoja näkymän vaihtuessa (käyttäjä 15.11.): kolmoisnapautuksen ylimääräiset napautukset eivät osu
// juuri avautuneeseen näkymään eivätkä suljetun ikkunan alle.
void main() {
  late DateTime now;
  setUp(() {
    now = DateTime(2026, 11, 15, 12);
    NavTapGuard.clock = () => now;
    NavTapGuard.duration = const Duration(milliseconds: 300);
    NavTapGuard.debugReset();
  });
  tearDown(() {
    NavTapGuard.clock = DateTime.now;
    NavTapGuard.duration = Duration.zero;
  });

  testWidgets('avautunut näkymä ja suljetun ikkunan alusta eivät ota napautuksia 300 ms:iin', (tester) async {
    var under = 0, next = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [NavTapGuard()],
        builder: (context, child) => TapGuard(child: child),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(onPressed: () => under++, child: const Text('alla')),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: TextButton(onPressed: () => next++, child: const Text('seuraava')),
                      ),
                    ),
                  ),
                  child: const Text('avaa'),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hylkää'))],
                    ),
                  ),
                  child: const Text('ikkuna'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Ensimmäinen näkymä: ei suojaa.
    await tester.tap(find.text('alla'));
    expect(under, 1);

    // Uusi näkymä: heti tullut napautus niellään, 300 ms:n jälkeen toimii.
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('seuraava'), warnIfMissed: false);
    expect(next, 0);
    now = now.add(const Duration(milliseconds: 301));
    await tester.tap(find.text('seuraava'));
    expect(next, 1);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 1));

    // Ikkunan sulkeminen: seuraava napautus ei osu alla olevaan painikkeeseen.
    await tester.tap(find.text('ikkuna'));
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 1));
    await tester.tap(find.text('Hylkää'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alla'), warnIfMissed: false);
    expect(under, 1, reason: 'napautus heti ikkunan sulkeuduttua niellään');
    now = now.add(const Duration(milliseconds: 301));
    await tester.tap(find.text('alla'));
    expect(under, 2);
  });

  testWidgets('kello taaksepäin näkymän vaihdon jälkeen: kosketukset eivät jää nielluiksi (yötesti 16.11.)', (
    tester,
  ) async {
    var n = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [NavTapGuard()],
        builder: (context, child) => TapGuard(child: child),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: TextButton(onPressed: () => n++, child: const Text('nappi')),
                  ),
                ),
              ),
              child: const Text('avaa'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('avaa'));
    await tester.pumpAndSettle();
    expect(NavTapGuard.active, isTrue);
    now = now.subtract(const Duration(hours: 2)); // verkkoaika korjasi kelloa taaksepäin
    expect(NavTapGuard.active, isFalse);
    await tester.tap(find.text('nappi'));
    expect(n, 1);
  });

  testWidgets('yötesti 18.11.: listan rivin poiston jälkeen seuraavan rivin poistonappi ei ota tuplanapautusta', (
    tester,
  ) async {
    final items = ['a', 'b', 'c'];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TapGuard(child: child),
        home: StatefulBuilder(
          builder: (context, set) => Scaffold(
            body: Column(
              children: [
                for (final (i, x) in items.indexed)
                  ListTile(
                    title: Text(x),
                    trailing: IconButton(
                      key: ValueKey('del_$i'),
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        set(() => items.removeAt(i));
                        NavTapGuard.markListChange();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('del_0')));
    await tester.pump();
    now = now.add(const Duration(milliseconds: 120));
    await tester.tap(find.byKey(const ValueKey('del_0')));
    await tester.pump();
    expect(items, ['b', 'c'], reason: 'toinen napautus nielty');
    now = now.add(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('del_0')));
    await tester.pump();
    expect(items, ['c']);
  });
}
