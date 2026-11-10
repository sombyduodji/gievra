import 'package:flutter/material.dart';

import '../exercises.dart';
import '../program.dart';
import '../program_edit.dart';
import '../theme.dart';
import '../l10n.dart';
import 'widgets.dart';

/// Liikkeiden monivalinta ohjelman pohjaksi: haku, kategoriat, valitut ylhäällä.
class MoveSelectScreen extends StatefulWidget {
  final List<String> initial;
  const MoveSelectScreen({super.key, this.initial = const []});
  @override
  State<MoveSelectScreen> createState() => _MoveSelectScreenState();
}

class _MoveSelectScreenState extends State<MoveSelectScreen> {
  late final List<String> _sel = [...widget.initial];
  String _q = '';
  String? _cat; // null = kaikki

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cats = allExercises();
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Valitse liikkeet ({0})', [_sel.length])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, _sel), child: Text(t('Valmis')))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SamiBand(height: 4, pattern: false),
          const SizedBox(height: 10),
          Text(
            t(
              'Valitse liikkeet, joita haluat tehdä. Ohjelma rakennetaan niiden ympärille ja täydentää '
              'puuttuvat liikemallit. Liikkeitä voi vaihtaa myöhemmin.',
            ),
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              hintText: t('Hae liikettä…'),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: cs.surfaceContainer,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 10),
          // Kategoriat: napauta suodattaaksesi, haku etsii aina kaikista.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in [null, ...cats.keys])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(() {
                        final name = c == null ? t('Kaikki') : t(c);
                        final n = c == null ? _sel.length : cats[c]!.where(_sel.contains).length;
                        return n > 0 ? '$name · $n' : name;
                      }()),
                      selected: _q.isEmpty && _cat == c,
                      onSelected: (_) => setState(() => _cat = c),
                    ),
                  ),
              ],
            ),
          ),
          if (_sel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final x in _sel) InputChip(label: Text(exerciseLabel(x)), onDeleted: () => setState(() => _sel.remove(x))),
              ],
            ),
          ],
          for (final c in cats.entries)
            if ((_q.isNotEmpty || _cat == null || _cat == c.key) && c.value.any((x) => matchesSearch(x, _q))) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text(
                  t(c.key).toUpperCase(),
                  style: TextStyle(fontSize: 12, letterSpacing: .6, color: cs.onSurfaceVariant),
                ),
              ),
              for (final x in c.value.where((x) => matchesSearch(x, _q)))
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _sel.contains(x),
                  title: ExName(x),
                  subtitle: slotOf(x).isEmpty ? null : Text(slotName(slotOf(x)), style: const TextStyle(fontSize: 11)),
                  onChanged: (v) => setState(() => v == true ? _sel.add(x) : _sel.remove(x)),
                ),
            ],
        ],
      ),
    );
  }
}
