import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../body.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Kysyy painon (kg) tai pituuden (cm). Pilkku ja piste käyvät; väärä arvo näyttää virheen eikä sulje.
/// [title] korvaa otsikon (esim. Aamupaino); [previous] näytetään vihjeenä kentän alla.
Future<double?> askBodyValue(
  BuildContext context, {
  required bool height,
  double? current,
  String? title,
  (DateTime, double)? previous,
}) {
  final c = TextEditingController(text: current == null ? '' : (height ? '${current.round()}' : fmtNum(current)));
  String? error;
  return showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final v = height ? parseHeight(c.text)?.toDouble() : parseWeight(c.text);
          if (v == null) {
            setState(() => error = height ? t('Anna pituus 100–250 cm.') : t('Anna paino 20–400 kg.'));
            return;
          }
          Navigator.pop(ctx, v);
        }

        return AlertDialog(
          title: Text(title ?? (height ? t('Pituus') : t('Paino'))),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: !height),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(height ? r'[0-9]' : r'[0-9.,]')),
              LengthLimitingTextInputFormatter(height ? 3 : 5),
            ],
            decoration: InputDecoration(
              suffixText: height ? 'cm' : 'kg',
              errorText: error,
              helperText: previous == null
                  ? null
                  : t('Edellinen {0} kg ({1})', [fmtNum(previous.$2), shortDate(previous.$1)]),
            ),
            onChanged: (_) => setState(() => error = null),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
            FilledButton(onPressed: submit, child: const Text('OK')),
          ],
        );
      },
    ),
  );
}

/// ☰ → Asetukset → Paino ja pituus: punnitukset (lisää, korjaa, poista) ja pituus.
class BodyScreen extends StatelessWidget {
  const BodyScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final d = await pickDate(context, initial: DateTime.now(), first: DateTime(2000), last: DateTime.now());
    if (d == null || !context.mounted) return;
    final kg = await askBodyValue(context, height: false, current: settings.body.weights[dateOnly(d)]);
    if (kg != null) await settings.setWeight(d, kg);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(t('Paino ja pituus'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: Text(t('Lisää punnitus')),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final b = settings.body;
          final list = b.sorted.reversed.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
            children: [
              const SamiBand(height: 4, pattern: false),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.height),
                title: Text(t('Pituus')),
                subtitle: Text(b.heightCm == null ? t('Ei asetettu (tarvitaan painoindeksiin)') : '${b.heightCm} cm'),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final v = await askBodyValue(context, height: true, current: b.heightCm?.toDouble());
                  if (v != null) await settings.setBody(b.copy()..heightCm = v.round());
                },
              ),
              SectionLabel(t('Punnitukset')),
              if (list.isEmpty)
                Text(t('Ei vielä punnituksia. Lisää paino etusivulta tai tästä.'), style: sub)
              else
                for (final (d, kg) in list)
                  Dismissible(
                    key: ValueKey(d),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      color: Sami.red.withValues(alpha: .15),
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) => settings.setWeight(d, null),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(longDateYear(d)),
                      subtitle: b.heightCm == null
                          ? null
                          : Text('${t('painoindeksi')} ${fmtNum(bmi(kg, b.heightCm!))}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${fmtNum(kg)} kg', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          IconButton(
                            tooltip: t('Muokkaa'),
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () async {
                              final v = await askBodyValue(context, height: false, current: kg);
                              if (v != null) await settings.setWeight(d, v);
                            },
                          ),
                          IconButton(
                            tooltip: t('Poista'),
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => settings.setWeight(d, null),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
              Text(
                t('Tallentuu treenikansioon tiedostoon kehonpaino.md, ja se kulkee varmuuskopion ja tuonnin mukana.'),
                style: sub,
              ),
            ],
          );
        },
      ),
    );
  }
}
