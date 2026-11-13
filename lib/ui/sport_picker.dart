import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../sports.dart';
import '../theme.dart';
import 'widgets.dart';

// Lajivalinta: haku, viimeksi tehdyt isoina ruutuina ja ryhmät kolmen ruudun ruudukkona (kuusi ensin,
// loput "Näytä kaikki" -napautuksella). Englanninkielinen nimi pienellä toisella rivillä (nimiasetus).

class SportPicker extends StatefulWidget {
  final ValueChanged<String> onPick;
  const SportPicker({super.key, required this.onPick});

  /// Ruutuja ryhmässä ennen "Näytä kaikki".
  static const firstRows = 6;

  @override
  State<SportPicker> createState() => _SportPickerState();
}

class _SportPickerState extends State<SportPicker> {
  final _query = TextEditingController();
  final _open = <String>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Viimeksi tehdyt lajit (uusin ensin, enintään kolme eri lajia).
  List<Sport> get _recent {
    final ws = store.workouts.where((w) => w.activity != null).toList()
      ..sort((a, b) => b.date.compareTo(a.date) != 0 ? b.date.compareTo(a.date) : b.session.compareTo(a.session));
    final out = <Sport>[];
    for (final w in ws) {
      final s = sportOf(w.activity);
      if (s == null || s.retired || out.contains(s)) continue;
      out.add(s);
      if (out.length == 3) break;
    }
    return out;
  }

  bool _matches(Sport s, String q) {
    final (a, b) = sportNameParts(s.name);
    return [s.name, a, ?b, sportName(s.name)].any((x) => x.toLowerCase().contains(q));
  }

  Widget _grid(List<Sport> xs, {bool recent = false}) => LayoutBuilder(
    builder: (context, c) {
      const gap = 8.0;
      final w = (c.maxWidth - 2 * gap) / 3;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final s in xs)
            SizedBox(
              width: w,
              child: _SportTile(sport: s, highlight: recent, onTap: () => widget.onPick(s.name)),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _query.text.trim().toLowerCase();
    final history = store.workouts.map((w) => w.activity);
    final recent = _recent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        TextField(
          controller: _query,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: t('Hae lajia…'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: t('Tyhjennä'),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_query.clear),
                  ),
            filled: true,
            fillColor: cs.surfaceContainer,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        if (q.isNotEmpty) ...[
          const SizedBox(height: 14),
          if (sports.where((s) => !s.retired && _matches(s, q)) case final hits when hits.isNotEmpty)
            _grid(sportsByUse(history, among: hits))
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                t('Ei osumia.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
        ] else ...[
          if (recent.isNotEmpty) ...[SectionLabel(t('Viimeksi')), _grid(recent, recent: true)],
          for (final g in sportGroups)
            if (sportsByUse(history, among: sports.where((s) => s.group == g && !s.retired)) case final all
                when all.isNotEmpty) ...[
              SectionLabel(t(g)),
              _grid(_open.contains(g) ? all : all.take(SportPicker.firstRows).toList()),
              if (all.length > SportPicker.firstRows)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _open.contains(g) ? _open.remove(g) : _open.add(g)),
                    icon: Icon(_open.contains(g) ? Icons.expand_less : Icons.expand_more),
                    label: Text(_open.contains(g) ? t('Näytä vähemmän') : t('Näytä kaikki ({0})', [all.length])),
                  ),
                ),
            ],
        ],
      ],
    );
  }
}

class _SportTile extends StatelessWidget {
  final Sport sport;
  final bool highlight;
  final VoidCallback onTap;
  const _SportTile({required this.sport, required this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (name, en) = sportNameParts(sport.name);
    return Material(
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: highlight ? BorderSide(color: Sami.yellow.withValues(alpha: .6)) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
          child: Column(
            children: [
              Text(sport.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                en ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
