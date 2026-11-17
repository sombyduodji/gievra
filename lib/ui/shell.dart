import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import 'drawer.dart' show MoreScreen;
import 'home.dart';
import 'program_screen.dart';
import 'running_bar.dart';
import 'stats_screen.dart';

/// Sovelluksen runko: alapalkki Tänään · Ohjelma · Tilastot · Lisää (ulkoasun kohennus 16.11., luonnokset
/// docs/facelift). Jokainen välilehti säilyttää tilansa (IndexedStack). Takaisin muualla kuin Tänään-välilehdellä
/// palaa Tänään-välilehdelle; Tänään-välilehdellä se sulkee sovelluksen kuten ennenkin.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Välilehden vaihto muualta (esim. etusivun linkki tilastoihin).
  static void goTo(BuildContext context, int index) => context.findAncestorStateOfType<_MainShellState>()?._go(index);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  /// Välilehdet rakennetaan vasta ensimmäisellä avauksella (tilastot laskevat paljon).
  final _built = <int>{0};

  void _go(int i) => setState(() {
    _index = i;
    _built.add(i);
  });

  static const _pages = <Widget>[HomeScreen(), ProgramScreen(), StatsScreen(), MoreScreen()];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Alapalkki luonnoksen mukaan (etusivu4): kuvake korostepillerissä, nimi ja saamenkielinen nimi pienenä alla
    // (fi/en-kielissä; saameksi vain saame). Nimet kielittäin: "Lisää" on käännöksissä verbi (Add, Lasit).
    const tabs = [
      (Icons.home_outlined, Icons.home, 'Tänään', 'Today', 'Odne'),
      (Icons.event_note_outlined, Icons.event_note, 'Ohjelma', 'Program', 'Prográmma'),
      (Icons.insights_outlined, Icons.insights, 'Tilastot', 'Stats', 'Statistihkka'),
      (Icons.more_horiz, Icons.more_horiz, 'Lisää', 'More', 'Eanet'),
    ];
    Widget tab(int i) {
      final (icon, onIcon, fi, en, se) = tabs[i];
      final on = _index == i;
      final label = isSami ? se : (isEnglish ? en : fi);
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: '$label, ${i + 1}/${tabs.length}',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('tab_$fi'),
            onTap: () => _go(i),
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 30,
                    decoration: BoxDecoration(
                      color: on ? Sami.red.withValues(alpha: .22) : null,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(on ? onIcon : icon, size: 22, color: on ? cs.onSurface : cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (!isSami)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        se,
                        maxLines: 1,
                        style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant.withValues(alpha: .8)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _pages.length; i++)
              _built.contains(i) ? KeyedSubtree(key: ValueKey('tab$i'), child: _pages[i]) : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_index != 0) const RunningBar(), // Tänään-välilehdellä iso Jatka-kortti
            Material(
              key: const ValueKey('mainNav'),
              color: cs.surfaceContainer,
              child: SafeArea(
                top: false,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  // Koko palkin korkeus napautettavaksi (OnePlus 16.11.: välilehden yläreunan napautus ei osunut).
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (var i = 0; i < tabs.length; i++) tab(i)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
