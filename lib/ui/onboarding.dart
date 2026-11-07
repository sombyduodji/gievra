import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Ensimmäinen käynnistys: kysytään, miksi käyttäjää kutsutaan.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _c = TextEditingController();
  String _mode = settings.trainMode;

  void _done() {
    if (_c.text.trim().isEmpty) return;
    settings.trainMode = _mode;
    // Pelkkä kestävyys: salin ohjelmakysely ohitetaan (sen voi tehdä myöhemmin valikosta).
    if (_mode == 'cardio') settings.introDone = true;
    settings.setName(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            const Center(child: AppLogo(size: 84)),
            const SizedBox(height: 28),
            const SamiBand(),
            const SizedBox(height: 20),
            const Text('Kieli · Giella', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            const LanguagePicker(),
            const SizedBox(height: 24),
            Text(
              t('Bures!'),
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.light ? const Color(0xFFB07D00) : Sami.yellow,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t('Tervetuloa Gievraan'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              t(
                'Sinun treenisi, sinun tiedostosi: Gievra tallentaa treenit tavallisina .md-tiedostoina '
                'omaan kansioosi. Ei tiliä, ei mainoksia.',
              ),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            SectionLabel(t('Miksi haluat, että sinua kutsutaan?')),
            TextField(
              controller: _c,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: t('Nimi, lempinimi tai mitä vain'),
                filled: true,
                fillColor: cs.surfaceContainer,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _done(),
            ),
            if (_c.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('${seGreeting()}, ${_c.text.trim()}!', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            SectionLabel(t('Mitä treenaat?')),
            TrainModePicker(value: _mode, onChanged: (v) => setState(() => _mode = v)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(switch (_mode) {
                'cardio' => t('Juoksu, pyöräily, hiihto ja muut lajit: aika, matka, vauhti ja kehitys.'),
                'both' => t('Etusivulla valitset Sali tai Kestävyys. Kalenterissa näkyy kaikki.'),
                _ => t('Salitreenit, treeniohjelma ja voiman kehitys.'),
              }, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('Voit vaihtaa tätä myöhemmin asetuksista.'),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _c.text.trim().isEmpty ? null : _done,
              child: Text(t('Aloitetaan'), style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
