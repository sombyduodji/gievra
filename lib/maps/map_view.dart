import 'dart:convert';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as m show Theme;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show Theme, ThemeReader;

import '../app_info.dart';
import '../gps_filter.dart';
import '../theme.dart';
import 'map_store.dart';
import 'pmtiles.dart';

// Reitti offline-kartalla: ladatut OpenStreetMap-paketit (map_store.dart) vektorikarttana, tyyli Protomapsin
// vaalea tai tumma teema (CC0, assets/map/). Ei verkkoliikennettä. Kulmassa aina © OpenStreetMap contributors.

/// Laatat ladatuista tiedostoista: ensin tarkimmasta (kunta tai koko Suomi), sitten yleiskartasta.
class OfflineTileProvider extends VectorTileProvider {
  final List<PmTilesFile> files;
  OfflineTileProvider(List<PmTilesFile> files) : files = [...files]..sort((a, b) => b.maxZoom.compareTo(a.maxZoom));

  @override
  int get maximumZoom => 15;
  @override
  int get minimumZoom => 0;
  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    for (final f in files) {
      final b = await f.tile(tile.z, tile.x, tile.y);
      if (b != null) return b;
    }
    throw ProviderException(message: 'ei laattaa $tile', retryable: Retryable.none, statusCode: 404);
  }
}

final _themes = <Brightness, Theme>{};

Future<Theme> mapTheme(Brightness b) async {
  final cached = _themes[b];
  if (cached != null) return cached;
  final json = await rootBundle.loadString('assets/map/${b == Brightness.dark ? 'dark' : 'light'}.json');
  return _themes[b] = ThemeReader().read(jsonDecode(json) as Map<String, dynamic>);
}

/// Reitti kartalla. [live]: kartta seuraa viimeisintä pistettä, kunnes käyttäjä siirtää karttaa.
/// Jos karttoja ei ole ladattu, näytetään [fallback] (pelkkä viiva).
class RouteMap extends StatefulWidget {
  final List<List<TrackPoint>> segments;
  final bool live;
  final Widget fallback;
  const RouteMap({super.key, required this.segments, required this.fallback, this.live = false});

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final _map = MapController();
  Future<(Theme, List<PmTilesFile>)>? _load;
  Brightness? _brightness;
  bool _follow = true;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = m.Theme.of(context).brightness;
    if (b != _brightness) {
      _brightness = b;
      _load = () async {
        await MapStore.instance.load(network: false);
        return (await mapTheme(b), await MapStore.instance.openFiles());
      }();
    }
  }

  List<LatLng> get _pts => [
    for (final s in widget.segments)
      for (final p in s) LatLng(p.lat, p.lon),
  ];

  @override
  void didUpdateWidget(RouteMap old) {
    super.didUpdateWidget(old);
    if (widget.live && _follow && _ready && _pts.isNotEmpty) {
      // Ensimmäiset pisteet: lähennetään katutasolle (kartta avautui ennen paikannusta).
      _map.move(_pts.last, _map.camera.zoom < 13 ? 16 : _map.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = m.Theme.of(context).colorScheme;
    return FutureBuilder(
      future: _load,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null || data.$2.isEmpty) return widget.fallback;
        final (theme, files) = data;
        final pts = _pts;
        final MapOptions options;
        if (pts.length >= 2 && !widget.live) {
          options = MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(pts),
              padding: const EdgeInsets.all(32),
              maxZoom: 16,
            ),
            maxZoom: 18,
            onMapReady: () => _ready = true,
          );
        } else {
          options = MapOptions(
            initialCenter: pts.isEmpty ? const LatLng(65, 26) : pts.last,
            initialZoom: pts.isEmpty ? 5 : 15,
            maxZoom: 18,
            onMapReady: () => _ready = true,
            onPositionChanged: (_, gesture) {
              if (gesture) _follow = false;
            },
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: options,
                children: [
                  VectorTileLayer(
                    theme: theme,
                    tileProviders: TileProviders({'protomaps': OfflineTileProvider(files)}),
                    fileCacheMaximumSizeInBytes: 20 << 20,
                  ),
                  PolylineLayer(
                    polylines: [
                      for (final s in widget.segments)
                        if (s.length >= 2)
                          Polyline(
                            points: [for (final p in s) LatLng(p.lat, p.lon)],
                            color: cs.primary,
                            strokeWidth: 5,
                            borderColor: Colors.white,
                            borderStrokeWidth: 1.5,
                          ),
                    ],
                  ),
                  if (pts.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: pts.first,
                          width: 16,
                          height: 16,
                          child: const _Dot(color: Sami.green),
                        ),
                        Marker(
                          point: pts.last,
                          width: 18,
                          height: 18,
                          child: _Dot(color: cs.primary),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                right: 6,
                bottom: 4,
                child: GestureDetector(
                  onTap: () => launchUrl(Uri.parse(MapCredits.osmUrl), mode: LaunchMode.externalApplication),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    color: cs.surface.withValues(alpha: .75),
                    child: Text(MapCredits.osm, style: TextStyle(fontSize: 10, color: cs.onSurface)),
                  ),
                ),
              ),
              if (widget.live && !_follow)
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton.filledTonal(
                    onPressed: () {
                      setState(() => _follow = true);
                      if (pts.isNotEmpty) _map.move(pts.last, _map.camera.zoom);
                    },
                    icon: const Icon(Icons.my_location),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
    ),
  );
}
