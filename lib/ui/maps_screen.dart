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

  /// Välilehden nimi yhdellä rivillä (kapealla näytöllä teksti pienenee eikä katkea kesken sanan).
  static Widget _oneLine(String s) => FittedBox(fit: BoxFit.scaleDown, child: Text(s, maxLines: 1, softWrap: false));

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
      if (loc != null) {
        _setCenter(loc.$1, loc.$2);
        // Maa sijainnin mukaan (esim. Ruotsissa lomalla: Ruotsin kommuner valmiina).
        final here = store.packAt(loc.$1, loc.$2);
        if (here != null) store.country = here.country;
      }
    });
  }

  void _setCenter(double lat, double lon) {
    _center = (lat, lon);
    final k = store.packAt(lat, lon);
    _centerName = k == null ? null : _withCountry(k.label(uiLang), k.country);
  }

  /// Nimi ja maa, kun paketti ei ole Suomesta (esim. "Stockholms kommun, Ruotsi").
  String _withCountry(String name, String cc) =>
      cc == 'fi' || store.catalogs[cc] == null ? name : '$name, ${store.catalogs[cc]!.label(uiLang)}';

  // Pakettien yksikkö maan mukaan: kunnat (Pohjoismaat), alueet (Iso-Britannian council areas), maakunnat (Espanjan
  // provinciat).
  String _unit(MapCatalog c) => switch (c.unit) {
    'council' => 'alue',
    'provincia' => 'maakunta',
    _ => 'kunta',
  };
  String _pickLabel(MapCatalog c) => switch (_unit(c)) {
    'alue' => t('Valitse alueet'),
    'maakunta' => t('Valitse maakunnat'),
    _ => t('Valitse kunnat'),
  };
  String _searchHint(MapCatalog c) => switch (_unit(c)) {
    'alue' => t('Hae aluetta'),
    'maakunta' => t('Hae maakuntaa'),
    _ => t('Hae kuntaa'),
  };
  String _count(MapCatalog c, int n, String size) => switch (_unit(c)) {
    'alue' => t('{0} aluetta · {1}', [n, size]),
    'maakunta' => t('{0} maakuntaa · {1}', [n, size]),
    _ => t('{0} kuntaa · {1}', [n, size]),
  };

  /// Sijainti kerran GPS:llä (enintään minuutti); ei tallennusta.
  Future<void> _locate() async {
    final st = await Permission.locationWhenInUse.request();
    if (!st.isGranted) return;
    setState(() => _locating = true);
    final src = AndroidGpsSource();
    // Kesken jäänyt tai käynnissä oleva reitin tallennus: käytetään sen paikannuksia, eikä palvelua pysäytetä
    // tai tallennettuja paikannuksia poisteta.
    final recording = await GpsRecorder.pendingSport() != null || await src.running();
    final done = Completer<(double, double)?>();
    final sub = src.events.listen((e) {
      final f = fixFromEvent(e);
      if (f != null && f.accuracy <= 100 && !done.isCompleted) done.complete((f.lat, f.lon));
    });
    try {
      if (!recording) {
        await src.start(
          title: t('Haetaan sijaintia'),
          text: t('Karttojen latausta varten'),
          channel: t('Reitin tallennus'),
        );
      }
      final loc = await done.future.timeout(const Duration(seconds: 60), onTimeout: () => null);
      if (loc != null) {
        await saveLastLocation(loc.$1, loc.$2);
        if (mounted) {
          setState(() {
            _setCenter(loc.$1, loc.$2);
            final here = store.packAt(loc.$1, loc.$2);
            if (here != null) store.country = here.country;
          });
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('Sijaintia ei löytynyt. Valitse kunnat listasta.'))));
      }
    } finally {
      await sub.cancel();
      if (!recording) {
        await src.stop();
        await src.clearSaved();
      }
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _download(List<MapPack> packs, {bool update = false}) async {
    final failed = update ? await store.update(packs) : await store.download(packs);
    _used = await store.usedBytes();
    _selected.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? t('Kartat ladattu.')
              : t('{0} karttaa ei voitu ladata: {1}', [failed.length, failed.first.error]),
        ),
      ),
    );
    setState(() {});
    if (_tab == 2) await _refreshInstalled();
  }

  /// Tuo karttapaketti tiedostosta (zip tai .pmtiles), esim. Seafilesta, kun verkkolataus ei onnistu. Tarkistuksen
  /// ajan näkyy edistyminen; tunnistamattomista kartoista kysytään (tarkista verkosta / tuo tarkistamatta / ohita).
  Future<void> _import() async {
    final files = await FilePicker.pickFiles(dialogTitle: t('Valitse karttapaketti (.zip tai .pmtiles)'));
    if (files.isEmpty || !mounted) return;
    setState(() => _importing = true);
    final progress = ValueNotifier<MapImportProgress?>(null);
    final nav = Navigator.of(context);
    var progressOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(canPop: false, child: _ImportProgressDialog(progress)),
      ).whenComplete(() => progressOpen = false),
    );
    MapImportResult? r;
    String? err;
    try {
      r = await store.importFiles(
        [for (final f in files) f.xFile.path],
        onProgress: (x) => progress.value = x,
        onUnverified: (names, {required checkedOnline}) => _askUnverified(names, checkedOnline),
      );
      _used = await store.usedBytes();
    } catch (e) {
      err = t('Karttapakettia ei voitu tuoda: {0}', [e]);
    }
    if (progressOpen) nav.pop();
    progress.dispose();
    if (!mounted) return;
    setState(() {
      _importing = false;
      if (store.catalog != null) _error = null;
    });
    if (r == null || (r.skipped.isEmpty && r.unverified.isEmpty)) {
      final msg =
          err ??
          (r!.imported.isNotEmpty
              ? t('Tuotu {0} karttaa.', [r.imported.length])
              : r.checksums > 0
              ? t('Tarkistetaulukko tuotu: {0} karttatiedoston tarkisteet. Kartat voi nyt tarkistaa ilman verkkoa.', [
                  r.checksums,
                ])
              : t('Tiedostosta ei löytynyt karttoja.'));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    final res = r;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(res.imported.isEmpty ? t('Karttoja ei tuotu') : t('Tuotu {0} karttaa.', [res.imported.length])),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (res.imported.isNotEmpty) ...[
                Text(res.imported.map(_fileLabel).join(', ')),
                const SizedBox(height: 12),
              ],
              if (res.unverified.isNotEmpty) ...[
                Text(
                  t(
                    'Tarkistamatta tuotu: {0}. Ne merkitään tarkistamattomiksi, ja sovellus tarjoaa tarkistettua '
                    'versiota, kun olet verkossa.',
                    [res.unverified.join(', ')],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (res.skipped.isNotEmpty) ...[
                Text(t('Ohitettu:'), style: const TextStyle(fontWeight: FontWeight.w600)),
                for (final (name, why) in res.skipped)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('$name: ${_skipReason(why)}')),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  /// Kysyy, mitä tehdään kartoille, joiden tarkiste ei vastaa mitään tunnettua karttaa.
  Future<UnverifiedChoice> _askUnverified(List<String> names, bool checkedOnline) async {
    if (!mounted) return UnverifiedChoice.skip;
    final v = await showDialog<UnverifiedChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gpp_maybe_outlined),
        title: Text(t('Tarkistus epäonnistui')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                store.catalogs.isEmpty
                    ? t('Karttaluetteloa ei ole vielä haettu, joten karttaa ei voi tarkistaa:')
                    : checkedOnline
                    ? t('Tarkistetta ei löytynyt verkostakaan (tai yhteyttä ei ole):')
                    : t('Tarkiste ei vastaa yhtään tunnettua Gievran karttaa:'),
              ),
              const SizedBox(height: 6),
              Text(names.join('\n'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(
                t(
                  'Tiedosto voi olla vioittunut tai muokattu, tai se on karttajulkaisusta, jota sovellus ei vielä '
                  'tunne. Tarkistamaton kartta voi näyttää virheellisiä tietoja.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, UnverifiedChoice.skip), child: Text(t('Ohita'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, UnverifiedChoice.importAnyway),
            child: Text(t('Tuo tarkistamatta')),
          ),
          if (!checkedOnline)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, UnverifiedChoice.checkOnline),
              child: Text(t('Tarkista verkosta')),
            ),
        ],
      ),
    );
    return v ?? UnverifiedChoice.skip;
  }

  String _skipReason(MapSkip why) => switch (why) {
    MapSkip.notMap => t('ei karttatiedosto (.pmtiles) eikä karttapaketti (.zip)'),
    MapSkip.badCatalog => t('karttaluettelo ei kelpaa'),
    MapSkip.truncated => t('tiedosto on vajaa (lataus jäi kesken). Lataa se uudelleen.'),
    MapSkip.otherVersion => t(
      'tiedosto ei vastaa karttaluettelon versiota: se on vioittunut tai eri karttajulkaisusta. Lataa se uudelleen.',
    ),
    MapSkip.unknown => t('tuntematon kartta: tarkiste ei vastaa yhtään Gievran karttaa'),
    MapSkip.noCatalog => t(
      'karttaa ei voi tarkistaa ilman karttaluetteloa. Avaa Kartat kerran verkkoyhteydellä ja yritä uudelleen.',
    ),
    MapSkip.verifiedExists => t('samanniminen tarkistettu kartta on jo ladattu, eikä tarkistamaton korvaa sitä'),
  };

  Widget _importButton() => OutlinedButton.icon(
    onPressed: _importing || store.downloads.isNotEmpty ? null : _import,
    icon: _importing
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.file_open_outlined),
    label: Text(_importing ? t('Tuodaan…') : t('Tuo karttapaketti tiedostosta')),
  );

  /// Ladattava koko: puuttuvat paketit ja niiden maiden yleiskartat, joita ei vielä ole.
  int _sizeOf(Iterable<MapPack> packs) {
    final todo = packs.where((x) => !store.isInstalled(x)).toList();
    var over = 0;
    for (final cc in {for (final x in todo) x.country}) {
      final c = store.catalogs[cc];
      if (c != null && !store.isInstalled(c.overview) && !(c.all != null && store.isInstalled(c.all!))) {
        over += c.overview.size;
      }
    }
    return todo.fold<int>(0, (a, x) => a + x.size) + over;
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
                ButtonSegment(
                  value: 0,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: _oneLine(t('Verkosta')),
                ),
                ButtonSegment(value: 1, icon: const Icon(Icons.file_open_outlined), label: _oneLine(t('Tiedostosta'))),
                ButtonSegment(value: 2, icon: const Icon(Icons.inventory_2_outlined), label: _oneLine(t('Ladatut'))),
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
                            final within = store.packsWithin(_center!.$1, _center!.$2, _radius);
                            final size = _sizeOf(within);
                            final missing = within.where((x) => !store.isInstalled(x)).length;
                            final kunnat = within.every((x) => _unit(store.catalogs[x.country] ?? c) == 'kunta');
                            return FilledButton(
                              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              onPressed: busy || size == 0 ? null : () => _download(within),
                              child: Text(
                                size == 0
                                    ? t('Alueen kartat on ladattu ✓')
                                    : kunnat
                                    ? t('Lataa {0} kuntaa · {1}', [missing, fmtBytes(size)])
                                    : t('Lataa {0} karttaa · {1}', [missing, fmtBytes(size)]),
                              ),
                            );
                          },
                        ),
                      ],
                      SectionLabel(_pickLabel(c)),
                      if (store.catalogs.length > 1) ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey(c.country),
                          initialValue: c.country,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t('Maa'),
                            isDense: true,
                            prefixIcon: const Icon(Icons.public),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          items: [
                            // Suomi ensin, muut aakkosjärjestyksessä käyttöliittymän kielellä.
                            for (final x
                                in store.catalogs.values.toList()..sort(
                                  (a, b) => a.country == 'fi'
                                      ? -1
                                      : b.country == 'fi'
                                      ? 1
                                      : a.label(uiLang).compareTo(b.label(uiLang)),
                                ))
                              DropdownMenuItem(
                                value: x.country,
                                child: Text(
                                  x.label(uiLang) == x.names['local']
                                      ? x.label(uiLang)
                                      : '${x.label(uiLang)} · ${x.names['local']}',
                                ),
                              ),
                          ],
                          onChanged: busy ? null : (v) => setState(() => store.country = v ?? store.country),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: _searchHint(c),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 6),
                      for (final r in c.regions) _region(r, c, sub),
                      const SizedBox(height: 6),
                      if (c.all case final all?)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.country == 'fi' ? t('Koko Suomi') : t('Koko maa: {0}', [c.label(uiLang)])),
                          subtitle: Text(t('Yksi tiedosto, {0}', [fmtBytes(all.size)]), style: sub),
                          trailing: store.isInstalled(all)
                              ? TextButton(onPressed: busy ? null : () => _delete(all), child: Text(t('Poista')))
                              : OutlinedButton(
                                  onPressed: busy ? null : () => _download([all]),
                                  child: Text(t('Lataa')),
                                ),
                        ),
                      if (_selected.isNotEmpty)
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => _download([
                                  for (final x in store.allPacks)
                                    if (_selected.contains(x.file)) x,
                                ]),
                          child: Text(
                            t('Lataa valitut ({0}) · {1}', [
                              _selected.length,
                              fmtBytes(_sizeOf(store.allPacks.where((x) => _selected.contains(x.file)))),
                            ]),
                          ),
                        ),
                      const Divider(height: 32),
                      Text(t('Ladattu: {0}', [fmtBytes(_used)])),
                      const SizedBox(height: 4),
                      Text(
                        c.country == 'fi'
                            ? t('Karttatiedot {0} ({1}), lisenssi ODbL. Kuntarajat: Tilastokeskus, CC BY 4.0.', [
                                MapCredits.osm,
                                c.osmDate,
                              ])
                            : t('Karttatiedot {0} ({1}), lisenssi ODbL. Aluerajat: {2}.', [
                                MapCredits.osm,
                                c.osmDate,
                                c.boundaries,
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

  /// Ladatun tiedoston nimi: alue (ja maa, jos muu kuin Suomi), yleiskartta tai koko maa.
  String _fileLabel(String f) {
    final label = _baseLabel(f);
    return store.unverified.contains(f) ? '$label (${t('tarkistamaton')})' : label;
  }

  String _baseLabel(String f) {
    for (final c in store.catalogs.values) {
      if (c.overview.file == f) return c.country == 'fi' ? t('Yleiskartta') : '${t('Yleiskartta')}: ${c.label(uiLang)}';
      if (c.all?.file == f) return c.country == 'fi' ? t('Koko Suomi') : t('Koko maa: {0}', [c.label(uiLang)]);
      final x = c.packs.where((x) => x.file == f).firstOrNull;
      if (x != null) return _withCountry(x.label(uiLang), c.country);
    }
    return f == 'yleiskartta.pmtiles' ? t('Yleiskartta') : (f == 'suomi.pmtiles' ? t('Koko Suomi') : f);
  }

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
            onPressed: busy ? null : () => _download(_outdated, update: true),
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
          'Seafilesta tai Nextcloudista. Ilman verkkoa: valitse samalla kertaa myös kotisivun tarkistetaulukko '
          '(kartat-tarkisteet.json), niin kartat tarkistetaan.',
        ),
        style: sub,
      ),
      const SizedBox(height: 16),
      _importButton(),
      const SizedBox(height: 20),
      Text(t('Ladattu: {0}', [fmtBytes(_used)])),
      if (store.installed.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text([for (final f in store.installed.toList()..sort()) _fileLabel(f)].join(', '), style: sub),
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
            ? _count(c, packs.length, fmtBytes(size))
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
            child: Text(c.country == 'fi' ? t('Valitse koko maakunta') : t('Valitse koko alue')),
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

/// Tuonnin edistyminen: pyörivä ympyrä (kilpi keskellä) ja edistymispalkki tarkistetuista tavuista.
class _ImportProgressDialog extends StatelessWidget {
  final ValueNotifier<MapImportProgress?> progress;
  const _ImportProgressDialog(this.progress);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      content: ValueListenableBuilder<MapImportProgress?>(
        valueListenable: progress,
        builder: (context, x, _) {
          final phase = switch (x?.phase) {
            MapImportPhase.unpacking => t('Puretaan pakettia…'),
            MapImportPhase.checkingOnline => t('Haetaan tarkisteita verkosta…'),
            MapImportPhase.installing => t('Tallennetaan…'),
            _ => t('Tarkistetaan karttaa…'),
          };
          final f = x?.fraction;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(strokeWidth: 5, backgroundColor: cs.surfaceContainerHighest),
                    ),
                    Icon(Icons.shield_outlined, color: cs.primary, size: 28),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(phase, style: Theme.of(context).textTheme.titleMedium),
              if (x != null && x.name.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(x.name, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 14),
              LinearProgressIndicator(value: f, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 6),
              Text(
                x == null || x.total <= 0 ? '' : '${fmtBytes(x.done)} / ${fmtBytes(x.total)} · ${(100 * f!).round()} %',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
