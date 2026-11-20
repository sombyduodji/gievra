import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../health.dart';
import '../health_update.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'health_import.dart' show HealthImportButton;

/// Tallennetun treenin Health Connect -rivi (`hc-paivitys`): sivu hakee treenin ajan Health Connectista avatessa.
/// Jos siellä on jotain uutta (puuttuva tai selvästi parempi tieto), näkyy rivi "Uutta tietoa: syke, kalorit ›",
/// joka avaa tieto kerrallaan -listan; muuten ei mitään. Juuri tallennetussa treenissä ([waiting]) rivi odottaa
/// kellon tietoja ja tarkistaa itse 30 s välein (enintään 10 min), jos kelloa on käytetty viime aikoina.
class HcUpdateRow extends StatefulWidget {
  final Workout w;
  final Future<void> Function() onApplied;
  final bool waiting;
  const HcUpdateRow({super.key, required this.w, required this.onApplied, this.waiting = false});

  /// Testejä varten: ehdokkaiden haku ja valmiustila (muuten Health Connect ja luvat).
  static Future<List<HealthCandidate>> Function(DateTime start, DateTime end)? debugFetch;
  static bool? debugReady;

  /// Haetaan vain ajastetuille treeneille (alkuaika tiedossa) viimeisen 30 päivän ajalta (Health Connectin
  /// oletushistoria).
  static bool wanted(Workout w) =>
      (HealthImportButton.available || debugFetch != null) &&
      w.started != null &&
      !w.started!.isBefore(DateTime.now().subtract(const Duration(days: 30)));

  /// Kelloa on käytetty viime aikoina (jokin 30 päivän treeneistä sai tietoja Health Connectista).
  static bool get watchInUse {
    final since = DateTime.now().subtract(const Duration(days: 30));
    return store.workouts.any((w) => w.healthSource != null && w.date.isAfter(since));
  }

  /// Paras ehdokas ja sen erot treeniin.
  static Future<(HealthCandidate, List<HcChange>)?> find(Workout w) async {
    final fetch = debugFetch;
    if (fetch == null) {
      if (debugReady == false) return null;
      if (debugReady == null) {
        if (await HealthConnect.status() != 'available') return null;
        if (!await HealthConnect.granted().catchError((_) => false)) return null;
      }
    }
    final (start, end, _) = workoutWindow(w);
    final all = await (fetch ?? HealthConnect.candidates)(start, end);
    final c = rankCandidates(w, all, others: store.workouts).where((c) => c.session || !c.stepsWindow).firstOrNull;
    if (c == null) return null;
    final ch = hcChanges(w, c);
    return ch.isEmpty ? null : (c, ch);
  }

  @override
  State<HcUpdateRow> createState() => _HcUpdateRowState();
}

class _HcUpdateRowState extends State<HcUpdateRow> {
  HealthCandidate? _c;
  List<HcChange> _changes = const [];
  bool _waiting = false;
  Timer? _poll;
  int _tries = 0;

  @override
  void initState() {
    super.initState();
    _waiting = widget.waiting && HcUpdateRow.watchInUse;
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    (HealthCandidate, List<HcChange>)? r;
    try {
      r = await HcUpdateRow.find(widget.w);
    } catch (_) {
      r = null;
    }
    if (!mounted) return;
    final news = r?.$2.where((c) => c.preselect).toList() ?? const [];
    setState(() {
      _c = r?.$1;
      _changes = r?.$2 ?? const [];
      if (news.isNotEmpty) _waiting = false;
    });
    // Odotus: tarkistetaan uudelleen, kunnes jotain uutta tulee tai 10 min on kulunut.
    if (_waiting && news.isEmpty && _tries++ < 20) {
      _poll = Timer(const Duration(seconds: 30), _check);
    } else if (_waiting && news.isEmpty) {
      setState(() => _waiting = false);
    }
  }

  Future<void> _open() async {
    final c = _c;
    if (c == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final pick = await showHcUpdateSheet(context, c, _changes);
    if (pick == null || pick.isEmpty || !mounted) return;
    final before = HcSnapshot(widget.w);
    applyHcChanges(widget.w, c, pick);
    await widget.onApplied();
    final names = [
      for (final ch in _changes)
        if (pick.contains(ch.field)) ch.label.toLowerCase(),
    ].join(', ');
    messenger.showSnackBar(
      SnackBar(
        content: Text(t('✓ Päivitetty: {0}', [names])),
        // Toiminnollinen ilmoitus ei muuten katoa itsestään (persist oletuksena true): "Kumoa" jäi etusivulle vielä
        // seuraavan treenin aloituksen jälkeen (käyttäjä 17.11.).
        persist: false,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: t('Kumoa'),
          onPressed: () async {
            before.restore(widget.w);
            await widget.onApplied();
            if (mounted) _check();
          },
        ),
      ),
    );
    if (mounted) _check();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final news = _changes.where((c) => c.preselect).toList();
    if (news.isEmpty && !_waiting) return const SizedBox.shrink();
    final title = news.isEmpty
        ? t('Odotetaan kellon tietoja…')
        : t('Uutta tietoa: {0}', [news.map((c) => c.label.toLowerCase()).join(', ')]);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('hcUpdateRow'),
          borderRadius: BorderRadius.circular(14),
          onTap: news.isEmpty ? null : _open,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: Sami.blue, width: 4)),
            ),
            child: Row(
              children: [
                Text(news.isEmpty ? '⏳' : '🔄', style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HEALTH CONNECT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .6,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (news.isEmpty)
                        Text(
                          t('tarkistetaan itse; voit jatkaa jo nyt'),
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (news.isNotEmpty) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tieto kerrallaan -lista: uusi arvo ja nykyinen; valmiiksi valittu vain puuttuva tai selvästi parempi.
/// Palauttaa valitut (null = Peruuta).
Future<Set<HcField>?> showHcUpdateSheet(BuildContext context, HealthCandidate c, List<HcChange> changes) =>
    showModalBottomSheet<Set<HcField>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pick = {
          for (final ch in changes)
            if (ch.preselect) ch.field,
        };
        String hm(DateTime d) => '${d.hour}.${d.minute.toString().padLeft(2, '0')}';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final cs = Theme.of(ctx).colorScheme;
            final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
            final emoji = {
              HcField.hr: '❤️',
              HcField.kcal: '🔥',
              HcField.steps: '👣',
              HcField.distance: '📏',
              HcField.duration: '⏱',
            };
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .85),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Health Connect', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      Text(
                        [
                          if (c.app.isNotEmpty) c.app,
                          '${hm(c.start)}–${hm(c.end)}',
                          if (c.title != null && c.title!.isNotEmpty) c.title!,
                        ].join(' · '),
                        style: sub,
                      ),
                      const SizedBox(height: 8),
                      for (final ch in changes)
                        CheckboxListTile(
                          key: ValueKey('hcPick_${ch.field.name}'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: pick.contains(ch.field),
                          onChanged: (v) => setSheet(() => v == true ? pick.add(ch.field) : pick.remove(ch.field)),
                          title: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '${emoji[ch.field]} ${ch.label}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  ch.value,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            [
                              t('nyt: {0}', [ch.now]),
                              if (ch.note != null) ch.note!,
                            ].join('\n'),
                            style: sub,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        t('Vain valitut päivitetään. Käsin kirjattuja ei ylikirjoiteta ilman valintaa.'),
                        style: sub,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t('Peruuta'))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              key: const ValueKey('hcApply'),
                              onPressed: pick.isEmpty ? null : () => Navigator.of(ctx).pop(Set.of(pick)),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  pick.length == 1 ? t('Päivitä 1 tieto') : t('Päivitä {0} tietoa', [pick.length]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
