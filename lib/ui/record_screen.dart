import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../gps_filter.dart';
import '../gps_recorder.dart';
import '../l10n.dart';
import '../maps/map_view.dart';
import '../models.dart';
import '../theme.dart';
import 'maps_screen.dart' show saveLastLocation;

/// Reitin tallennus GPS:llä: ensin signaalin haku, sitten aika, matka ja vauhti livenä. Palauttaa
/// [RouteResult]in (tai null, jos tallennus hylättiin).
class RecordScreen extends StatefulWidget {
  final String sport;

  /// Palautetaan kesken jäänyt tallennus (sovellus suljettiin kesken lenkin).
  final bool recover;

  /// Testejä varten: oma paikannuslähde ja kello.
  final GpsRecorder? recorder;

  const RecordScreen({super.key, required this.sport, this.recover = false, this.recorder});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final GpsRecorder rec = widget.recorder ?? GpsRecorder();
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    rec.addListener(_changed);
    _init();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    // Sama ilmoitus kuin muillakin käynnissä olevilla treeneillä (lib/ongoing.dart päivittää sen heti).
    final title = t('{0} käynnissä', [sportName(widget.sport)]);
    final text = t('Etsitään GPS-signaalia…');
    final channel = t('Käynnissä oleva treeni');
    try {
      if (widget.recorder == null) {
        final st = await Permission.locationWhenInUse.request();
        if (!st.isGranted) {
          setState(() {
            _busy = false;
            _error = t('Sijaintilupa tarvitaan reitin tallentamiseen. Voit kirjata lenkin myös ilman GPS:ää.');
          });
          return;
        }
        // Ilmoitus näyttää, että tallennus on käynnissä; ilman lupaa tallennus toimii silti.
        await Permission.notification.request();
      }
      if (widget.recover) {
        if (!await rec.recover(title: title, text: text, channel: channel)) {
          await rec.open(widget.sport, title: title, text: text, channel: channel);
        }
      } else {
        await rec.open(widget.sport, title: title, text: text, channel: channel);
      }
    } catch (e) {
      _error = t('GPS:ää ei voitu käynnistää: {0}', [errorText(e)]);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    rec.removeListener(_changed);
    if (widget.recorder == null) rec.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final f = rec.lastFix;
    if (f != null) await saveLastLocation(f.lat, f.lon);
    final r = await rec.finish(name: sportName(widget.sport));
    if (!mounted) return;
    Navigator.of(context).pop(r);
  }

  /// Takaisin-painike tai Lopeta: tallennetaanko, hylätäänkö vai jatketaanko.
  Future<void> _askStop() async {
    if (rec.state == RecState.idle || rec.state == RecState.searching) {
      await rec.discard();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    // Kello pysähtyy, kun Lopeta painetaan; Jatka jatkaa siitä.
    final wasRecording = rec.state == RecState.recording;
    if (wasRecording) await rec.pause();
    if (!mounted) return;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Lopetetaanko tallennus?')),
        content: Text(t('{0} km, {1}', [fmtDec(rec.distanceKm, 2), fmtDurationSec(rec.elapsed.inSeconds)])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(t('Hylkää'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Jatka'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(t('Lopeta ja tallenna'))),
        ],
      ),
    );
    if (v == null && wasRecording) await rec.resume();
    if (v == 'save') await _finish();
    if (v == 'discard' && mounted) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Hylätäänkö reitti?')),
          content: Text(t('Aikaa, matkaa ja reittiä ei tallenneta.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Hylkää'))),
          ],
        ),
      );
      if (sure == true) {
        await rec.discard();
        if (mounted) Navigator.of(context).pop();
      } else if (wasRecording) {
        await rec.resume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _error != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _askStop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('📍 ${sportName(widget.sport)}')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : rec.state == RecState.searching
                ? _searching(cs)
                : _recording(cs),
          ),
        ),
      ),
    );
  }

  Widget _signal(ColorScheme cs) {
    final f = rec.lastFix;
    final fresh = f != null && rec.now().difference(f.time).inSeconds < 5;
    final acc = fresh ? f.accuracy : null;
    final level = acc == null ? 0 : (acc <= 10 ? 3 : (acc <= 20 ? 2 : 1));
    final label = acc == null
        ? t('Ei signaalia')
        : level == 3
        ? t('Hyvä signaali')
        : level == 2
        ? t('Kohtalainen signaali')
        : t('Heikko signaali');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 3; i++)
          Container(
            width: 6,
            height: 6.0 + i * 5,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i <= level ? (level == 1 ? Sami.yellow : Sami.green) : cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          acc == null ? label : '$label · ±${acc.round()} m',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _searching(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SamiBand(height: 4, pattern: false),
        const Spacer(),
        Icon(Icons.satellite_alt_outlined, size: 72, color: cs.primary),
        const SizedBox(height: 16),
        Text(
          rec.goodSignal ? t('GPS valmis') : t('Etsitään GPS-signaalia…'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Center(child: _signal(cs)),
        const SizedBox(height: 14),
        if (rec.gpsDisabled) ...[
          Text(
            t('Sijainti on pois päältä puhelimen asetuksista.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.error),
          ),
          TextButton(onPressed: rec.source.openSettings, child: Text(t('Avaa sijaintiasetukset'))),
        ] else if (!rec.goodSignal)
          Text(
            t('Ulkona avoimella paikalla ensimmäinen paikannus kestää yleensä alle minuutin.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
          onPressed: rec.goodSignal ? rec.start : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(t('Aloita'), style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(height: 8),
        if (!rec.goodSignal)
          TextButton(onPressed: rec.start, child: Text(t('Aloita silti (matka alkaa, kun signaali löytyy)'))),
      ],
    );
  }

  Widget _recording(ColorScheme cs) {
    final paused = rec.state == RecState.paused;
    final cur = rec.currentPace, avg = rec.avgPace;
    Widget metric(String v, String unit, String label) => Expanded(
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: v,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SamiBand(height: 4, pattern: false),
        const SizedBox(height: 8),
        Center(child: _signal(cs)),
        const SizedBox(height: 8),
        Text(
          fmtDurationSec(rec.elapsed.inSeconds),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: paused ? cs.onSurfaceVariant : null,
          ),
        ),
        if (paused)
          Text(
            t('Tauko'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            metric(fmtDec(rec.distanceKm, 2), 'km', t('matka')),
            metric(cur == null ? '–' : fmtPace(cur), 'min/km', t('vauhti nyt')),
            metric(avg == null ? '–' : fmtPace(avg), 'min/km', t('keskivauhti')),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(16)),
            child: RouteMap(
              segments: rec.filter.segments,
              live: true,
              fallback: rec.filter.points.length < 2
                  ? Center(
                      child: Text(t('Reitti piirtyy tähän'), style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : CustomPaint(painter: RoutePainter(rec.filter.segments, cs.primary), child: const SizedBox.expand()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                onPressed: paused ? rec.resume : rec.pause,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                label: Text(paused ? t('Jatka') : t('Tauko'), style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                onPressed: _askStop,
                icon: const Icon(Icons.stop),
                label: Text(t('Lopeta'), style: const TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Reitti viivana ilman karttaa (karttapohja tulee myöhemmin): mittakaava pidetään samana molempiin suuntiin.
class RoutePainter extends CustomPainter {
  final List<List<TrackPoint>> segments;
  final Color color;
  RoutePainter(this.segments, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in segments) ...s];
    if (all.length < 2) return;
    final lat0 = all.first.lat;
    final kx = math.cos(lat0 * math.pi / 180);
    double x(TrackPoint p) => p.lon * kx;
    double y(TrackPoint p) => -p.lat;
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final p in all) {
      minX = math.min(minX, x(p));
      maxX = math.max(maxX, x(p));
      minY = math.min(minY, y(p));
      maxY = math.max(maxY, y(p));
    }
    const pad = 20.0;
    final span = math.max(maxX - minX, maxY - minY);
    final scale = span <= 0 ? 1.0 : math.min(size.width - 2 * pad, size.height - 2 * pad) / span;
    final ox = (size.width - (maxX - minX) * scale) / 2, oy = (size.height - (maxY - minY) * scale) / 2;
    Offset o(TrackPoint p) => Offset(ox + (x(p) - minX) * scale, oy + (y(p) - minY) * scale);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in segments) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(o(s.first).dx, o(s.first).dy);
      for (final p in s.skip(1)) {
        path.lineTo(o(p).dx, o(p).dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(o(all.first), 6, Paint()..color = Sami.green);
    canvas.drawCircle(o(all.last), 7, Paint()..color = color);
    canvas.drawCircle(o(all.last), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(RoutePainter old) => true;
}
