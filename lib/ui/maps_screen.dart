import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../gps_recorder.dart';
import '../l10n.dart';
import '../maps/map_store.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Viimeisin tunnettu sijainti (tallennuksesta tai sijainnin hausta) karttojen ehdotusta varten. Vain puhelimeen.
Future<(double, double)?> lastLocation() async {
  final sp = await SharedPreferences.getInstance();
  final lat = sp.getDouble('map_last_lat'), lon = sp.getDouble('map_last_lon');
  return lat == null || lon == null ? null : (lat, lon);
}

Future<void> saveLastLocation(double lat, double lon) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setDouble('map_last_lat', lat);
  await sp.setDouble('map_last_lon', lon);
}

/// Oletussäde lajin mukaan: juoksu ja kävely 20 km, pyöräily 100 km, hiihto ja luistelu 40 km.
double defaultRadiusKm(String? sport) => switch (sport) {
  'Pyöräily' => 100,
  'Hiihto' || 'Luistelu' || 'Melonta' || 'Soutu' => 40,
  _ => 20,
};

String fmtBytes(int b) =>
    b >= 1e9 ? t('{0} Gt', [fmtDec(b / 1e9, 2)]) : t('{0} Mt', [fmtDec(b / 1e6, b < 10e6 ? 1 : 0)]);

/// Kartat: lataa alue nykyisen sijainnin ympäriltä (säde lajin mukaan) tai valitse kunnat itse.
class MapsScreen extends StatefulWidget {
  /// Laji, jolle karttaa ladataan (oletussäde); null = juoksu/kävely.
  final String? sport;
  const MapsScreen({super.key, this.sport});

  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen> {
  final store = MapStore.instance;
  String? _error;
  bool _loading = true;
  late double _radius = defaultRadiusKm(widget.sport);
  (double, double)? _center;
  String? _centerName;
  bool _locating = false;
  int _used = 0;
  final _selected = <String>{};
  String _query = '';
  bool _importing = false;

  /// Välilehti: 0 = lataa verkosta, 1 = tuo tiedostosta, 2 = ladatut kartat.
  int _tab = 0;
  List<MapPack> _outdated = const [];

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _init();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  Future<void> _init() async {
    final err = await store.load(refresh: true);
    final loc = await lastLocation();
    _used = await store.usedBytes();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = store.catalog == null ? (err ?? '') : null;
      _refreshInstalled();
      if (loc != null) _setCenter(loc.$1, loc.$2);
    });
  }

  void _setCenter(double lat, double lon) {
    _center = (lat, lon);
    _centerName = store.catalog?.packAt(lat, lon)?.label(uiLang);
  }

  /// Sijainti kerran GPS:llä (enintään minuutti); ei tallennusta.
  Future<void> _locate() async {
    final st = await Permission.locationWhenInUse.request();
    if (!st.isGranted) return;
    setState(() => _locating = true);
    final src = AndroidGpsSource();
    final done = Completer<(double, double)?>();
    final sub = src.events.listen((e) {
      final f = fixFromEvent(e);
      if (f != null && f.accuracy <= 100 && !done.isCompleted) done.complete((f.lat, f.lon));
    });
    try {
      await src.start(
        title: t('Haetaan sijaintia'),
        text: t('Karttojen latausta varten'),
        channel: t('Reitin tallennus'),
      );
      final loc = await done.future.timeout(const Duration(seconds: 60), onTimeout: () => null);
      if (loc != null) {
        await saveLastLocation(loc.$1, loc.$2);
        if (mounted) setState(() => _setCenter(loc.$1, loc.$2));
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('Sijaintia ei löytynyt. Valitse kunnat listasta.'))));
      }
    } finally {
      await sub.cancel();
      await src.stop();
      await src.clearSaved();
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _download(List<MapPack> packs) async {
    await store.download(packs);
    _used = await store.usedBytes();
    _selected.clear();
    if (!mounted) return;
    final failed = store.downloads.values.where((d) => d.error != null).toList();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? t('Kartat ladattu.')
              : t('{0} karttaa ei voitu ladata: {1}', [failed.length, failed.first.error]),
        ),
      ),
    );
    store.downloads.clear();
    setState(() {});
  }

  /// Tuo karttapaketti tiedostosta (zip tai .pmtiles), esim. Seafilesta, kun verkkolataus ei onnistu.
  Future<void> _import() async {
    final files = await FilePicker.pickFiles(dialogTitle: t('Valitse karttapaketti (.zip tai .pmtiles)'));
    if (files.isEmpty || !mounted) return;
    setState(() => _importing = true);
    String msg;
    try {
      final n = await store.importFiles([for (final f in files) f.xFile.path]);
      _used = await store.usedBytes();
      msg = n == 0 ? t('Tiedostosta ei löytynyt karttoja.') : t('Tuotu {0} karttaa.', [n]);
    } catch (e) {
      msg = t('Karttapakettia ei voitu tuoda: {0}', [e]);
    }
    if (!mounted) return;
    setState(() {
      _importing = false;
      if (store.catalog != null) _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _importButton() => OutlinedButton.icon(
    onPressed: _importing || store.downloads.isNotEmpty ? null : _import,
    icon: _importing
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.file_open_outlined),
    label: Text(_importing ? t('Tuodaan…') : t('Tuo karttapaketti tiedostosta')),
  );

  int _sizeOf(Iterable<MapPack> packs) {
    final c = store.catalog!;
    final todo = packs.where((x) => !store.isInstalled(x));
    final over = store.isInstalled(c.overview) || store.isInstalled(c.all) ? 0 : c.overview.size;
    return todo.fold<int>(0, (a, x) => a + x.size) + (todo.isEmpty ? 0 : over);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final c = store.catalog;
    final busy = store.downloads.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(t('Kartat'))),
      // Valinta näkyy heti; verkosta ladattava luettelo haetaan taustalla (ei odotusta tuontiin).
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: SamiBand(height: 4, pattern: false)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, icon: const Icon(Icons.cloud_download_outlined), label: Text(t('Verkosta'))),
                ButtonSegment(value: 1, icon: const Icon(Icons.file_open_outlined), label: Text(t('Tiedostosta'))),
                ButtonSegment(value: 2, icon: const Icon(Icons.inventory_2_outlined), label: Text(t('Ladatut'))),
              ],
              selected: {_tab},
              onSelectionChanged: (v) {
                setState(() => _tab = v.first);
                if (_tab == 2) _refreshInstalled();
              },
            ),
          ),
          Expanded(
            child: _tab == 1
                ? _offlineTab(sub)
                : _tab == 2
                ? _installedTab(sub)
                : c == null && _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(t('Haetaan karttaluetteloa…'), style: sub),
                      ],
                    ),
                  )
                : c == null
                ? _onlineError(sub)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                    children: [
                      Text(
                        t(
                          'Offline-kartat näyttävät reitin kartalla ja auttavat korjaamaan sen poluille. Kartat tallentuvat '
                          'vain puhelimeen; sijaintiasi ei lähetetä minnekään.',
                        ),
                        style: sub,
                      ),
                      if (busy) _progress(cs),
                      SectionLabel(t('Lataa alue')),
                      if (_center == null)
                        OutlinedButton.icon(
                          onPressed: _locating || busy ? null : _locate,
                          icon: _locating
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location),
                          label: Text(_locating ? t('Haetaan sijaintia…') : t('Käytä nykyistä sijaintia')),
                        )
                      else ...[
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_centerName ?? t('Nykyinen sijainti'))),
                            TextButton(onPressed: _locating || busy ? null : _locate, child: Text(t('Päivitä'))),
                          ],
                        ),
                        Text(t('Etäisyys joka suuntaan: {0} km', [_radius.round()])),
                        Slider(
                          value: _radius,
                          min: 5,
                          max: 200,
                          divisions: 39,
                          label: '${_radius.round()} km',
                          onChanged: busy ? null : (v) => setState(() => _radius = v),
                        ),
                        Text(t('Juoksu ja kävely 20 km, pyöräily 100 km. Merialueet jäävät pois.'), style: sub),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final within = c.packsWithin(_center!.$1, _center!.$2, _radius);
                            final size = _sizeOf(within);
                            return FilledButton(
                              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              onPressed: busy || size == 0 ? null : () => _download(within),
                              child: Text(
                                size == 0
                                    ? t('Alueen kartat on ladattu ✓')
                                    : t('Lataa {0} kuntaa · {1}', [
                                        within.where((x) => !store.isInstalled(x)).length,
                                        fmtBytes(size),
                                      ]),
                              ),
                            );
                          },
                        ),
                      ],
                      SectionLabel(t('Valitse kunnat')),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: t('Hae kuntaa'),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 6),
                      for (final r in c.regions) _region(r, c, sub),
                      const SizedBox(height: 6),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t('Koko Suomi')),
                        subtitle: Text(t('Yksi tiedosto, {0}', [fmtBytes(c.all.size)]), style: sub),
                        trailing: store.isInstalled(c.all)
                            ? TextButton(onPressed: busy ? null : () => _delete(c.all), child: Text(t('Poista')))
                            : OutlinedButton(
                                onPressed: busy ? null : () => _download([c.all]),
                                child: Text(t('Lataa')),
                              ),
                      ),
                      if (_selected.isNotEmpty)
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => _download([
                                  for (final x in c.packs)
                                    if (_selected.contains(x.file)) x,
                                ]),
                          child: Text(
                            t('Lataa valitut ({0}) · {1}', [
                              _selected.length,
                              fmtBytes(_sizeOf(c.packs.where((x) => _selected.contains(x.file)))),
                            ]),
                          ),
                        ),
                      const Divider(height: 32),
                      Text(t('Ladattu: {0}', [fmtBytes(_used)])),
                      const SizedBox(height: 4),
                      Text(
                        t('Karttatiedot {0} ({1}), lisenssi ODbL. Kuntarajat: Tilastokeskus, CC BY 4.0.', [
                          MapCredits.osm,
                          c.osmDate,
                        ]),
                        style: sub,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Lataa verkosta -välilehti, kun luetteloa ei saatu (ei verkkoa tai palvelin ei vastaa).
  Widget _onlineError(TextStyle sub) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(t('Karttaluetteloa ei saatu. Tarkista verkkoyhteys.'), textAlign: TextAlign.center),
        if (_error != null && _error!.isNotEmpty) Text(_error!, style: sub, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            setState(() => _loading = true);
            _init();
          },
          child: Text(t('Yritä uudelleen')),
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: () => setState(() => _tab = 1), child: Text(t('Tuo tiedostosta'))),
      ],
    ),
  );

  List<(String, int)> _files = const [];

  Future<void> _refreshInstalled() async {
    final files = await store.installedFiles();
    final out = await store.outdated();
    _used = await store.usedBytes();
    if (mounted) {
      setState(() {
        _files = files;
        _outdated = out;
      });
    }
  }

  String _fileLabel(String f) =>
      store.catalog?.packs.where((x) => x.file == f).firstOrNull?.label(uiLang) ??
      (f == 'yleiskartta.pmtiles' ? t('Yleiskartta') : (f == 'suomi.pmtiles' ? t('Koko Suomi') : f));

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Poistetaanko kaikki kartat?')),
        content: Text(t('{0} vapautuu. Kartat voi ladata tai tuoda myöhemmin uudelleen.', [fmtBytes(_used)])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Poista kaikki'))),
        ],
      ),
    );
    if (ok != true) return;
    await store.deleteAll();
    await _refreshInstalled();
  }

  /// Ladatut-välilehti: kartat kokoineen, poisto (yksi tai kaikki) ja päivitys uudempaan versioon.
  Widget _installedTab(TextStyle sub) {
    final busy = store.downloads.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
      children: [
        if (busy) _progress(Theme.of(context).colorScheme),
        Text(t('Ladattu: {0}', [fmtBytes(_used)]), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(t('Poista kartat, joita et tarvitse (esim. matkan jälkeen), niin tilaa vapautuu.'), style: sub),
        if (_outdated.isNotEmpty) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await store.update(_outdated);
                    await _refreshInstalled();
                  },
            icon: const Icon(Icons.system_update_alt),
            label: Text(
              t('Päivitä kartat ({0}) · {1}', [
                _outdated.length,
                fmtBytes(_outdated.fold<int>(0, (a, x) => a + x.size)),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (_files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(t('Ei ladattuja karttoja.'), textAlign: TextAlign.center, style: sub),
          ),
        for (final (f, size) in _files)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _outdated.any((x) => x.file == f) ? Icons.update : Icons.map_outlined,
              color: _outdated.any((x) => x.file == f) ? Sami.yellow : null,
            ),
            title: Text(_fileLabel(f)),
            subtitle: Text(
              _outdated.any((x) => x.file == f)
                  ? t('{0} · uudempi versio saatavilla', [fmtBytes(size)])
                  : fmtBytes(size),
              style: sub,
            ),
            trailing: TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await store.deleteFile(f);
                      await _refreshInstalled();
                    },
              child: Text(t('Poista')),
            ),
          ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : _deleteAll,
            icon: const Icon(Icons.delete_outline),
            label: Text(t('Poista kaikki kartat')),
          ),
        ],
      ],
    );
  }

  /// Tuo tiedostosta -välilehti: karttapaketti (zip tai .pmtiles) ilman verkkoa.
  Widget _offlineTab(TextStyle sub) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
    children: [
      Text(
        t(
          'Tuo kartat tiedostosta, kun verkkolataus ei onnistu tai kartat ovat jo toisella laitteella: '
          'karttapaketti (.zip) tai yksittäinen kartta (.pmtiles). Tiedoston voi valita myös esimerkiksi '
          'Seafilesta tai Nextcloudista.',
        ),
        style: sub,
      ),
      const SizedBox(height: 16),
      _importButton(),
      const SizedBox(height: 20),
      Text(t('Ladattu: {0}', [fmtBytes(_used)])),
      if (store.installed.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          [
            for (final f in store.installed.toList()..sort())
              store.catalog?.packs.where((x) => x.file == f).firstOrNull?.label(uiLang) ??
                  (f == 'yleiskartta.pmtiles'
                      ? t('Yleiskartta')
                      : f == 'suomi.pmtiles'
                      ? t('Koko Suomi')
                      : f),
          ].join(', '),
          style: sub,
        ),
      ],
    ],
  );

  Future<void> _delete(MapPack x) async {
    await store.delete(x);
    _used = await store.usedBytes();
    if (mounted) setState(() {});
  }

  Widget _progress(ColorScheme cs) {
    final total = store.downloads.values.fold<int>(0, (a, d) => a + d.pack.size);
    final got = store.downloads.values.fold<int>(0, (a, d) => a + (d.done ? d.pack.size : d.received));
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('Ladataan karttoja: {0} / {1}', [fmtBytes(got), fmtBytes(total)])),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: total == 0 ? null : got / total),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: store.cancel, child: Text(t('Peruuta'))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _region(String r, MapCatalog c, TextStyle sub) {
    final packs = c.packs
        .where((x) => x.region == r)
        .where(
          (x) => _query.isEmpty || x.label(uiLang).toLowerCase().contains(_query) || r.toLowerCase().contains(_query),
        )
        .toList();
    if (packs.isEmpty) return const SizedBox.shrink();
    final have = packs.where(store.isInstalled).length;
    final size = packs.fold<int>(0, (a, x) => a + x.size);
    final busy = store.downloads.isNotEmpty;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: _query.isNotEmpty,
      title: Text(r),
      subtitle: Text(
        have == 0
            ? t('{0} kuntaa · {1}', [packs.length, fmtBytes(size)])
            : t('{0}/{1} ladattu · {2}', [have, packs.length, fmtBytes(size)]),
        style: sub,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    final all = packs.where((x) => !store.isInstalled(x)).map((x) => x.file);
                    if (all.every(_selected.contains)) {
                      _selected.removeAll(all);
                    } else {
                      _selected.addAll(all);
                    }
                  }),
            child: Text(t('Valitse koko maakunta')),
          ),
        ),
        for (final x in packs)
          store.isInstalled(x)
              ? ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Sami.green),
                  title: Text(x.label(uiLang)),
                  subtitle: Text(fmtBytes(x.size), style: sub),
                  trailing: TextButton(onPressed: busy ? null : () => _delete(x), child: Text(t('Poista'))),
                )
              : CheckboxListTile(
                  dense: true,
                  value: _selected.contains(x.file),
                  title: Text(x.label(uiLang)),
                  subtitle: Text(fmtBytes(x.size), style: sub),
                  onChanged: busy
                      ? null
                      : (v) => setState(() => v == true ? _selected.add(x.file) : _selected.remove(x.file)),
                ),
      ],
    );
  }
}
