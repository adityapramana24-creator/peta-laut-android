import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_constants.dart';
import '../../../data/repositories/offline_repository.dart';
import '../../../data/services/settings_service.dart';
import '../../../domain/models/map_layers.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../ais/view_models/ais_viewmodel.dart';
import '../../ais/widgets/ais_panel.dart';
import '../../ais/widgets/vessel_sheet.dart';
import '../../core/widgets/compass_dial.dart';
import '../../core/widgets/notice_banner.dart';
import '../../core/widgets/own_ship_marker.dart';
import '../../core/widgets/safety_banner.dart';
import '../../core/widgets/ship_marker.dart';
import '../../core/widgets/version_stamp.dart';
import '../../marine/view_models/marine_viewmodel.dart';
import '../../marine/widgets/marine_panel.dart';
import '../../more/widgets/more_sheet.dart';
import '../../navigation/view_models/navigation_viewmodel.dart';
import '../../navigation/widgets/anchor_mob_sheet.dart';
import '../../navigation/widgets/navigation_sheet.dart';
import '../../navigation/widgets/waypoint_dialog.dart';
import '../../offline/view_models/offline_viewmodel.dart';
import '../../offline/widgets/offline_sheet.dart';
import '../../settings/settings_screen.dart';
import '../../tides/view_models/tides_viewmodel.dart';
import '../../tides/widgets/tides_panel.dart';
import '../../weather/view_models/weather_viewmodel.dart';
import '../../weather/widgets/weather_panel.dart';
import '../../windy/view_models/windy_viewmodel.dart';
import '../../windy/widgets/wind_particles.dart';
import '../../windy/widgets/windy_panel.dart';
import '../view_models/map_viewmodel.dart';
import 'depth_sheet.dart';
import 'layers_sheet.dart';
import 'long_press_sheet.dart';
import 'manual_position_dialog.dart';
import 'saved_area_tile_provider.dart';

/// Layar utama: peta + kontrol ringkas + panel data.
/// MapController dibuat di sini (State) dan dipasang ke ViewModel.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  late final SavedAreaTileProvider _savedAreaProvider;
  String _currentBasemap = 'standard';

  @override
  void initState() {
    super.initState();
    final vm = context.read<MapViewModel>();
    vm.attachController(_mapController);
    WidgetsBinding.instance.addPostFrameCallback((_) => vm.init());
    // Offline: siapkan direktori area tersimpan + polling status.
    final offlineRepo = context.read<OfflineRepository>();
    unawaited(offlineRepo.warmUpBaseDir());
    context.read<OfflineViewModel>().startOnlinePolling();
    _savedAreaProvider = SavedAreaTileProvider(
      repository: offlineRepo,
      basemapGetter: () => _currentBasemap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MapViewModel>();
    final nav = context.watch<NavigationViewModel>();
    final windy = context.watch<WindyViewModel>();
    final offline = context.watch<OfflineViewModel>();
    final settings = context.watch<SettingsService>();
    final layers = vm.layers;
    final scheme = Theme.of(context).colorScheme;
    _currentBasemap = layers.basemap.name;

    final isNight = settings.themeMode == ThemeMode.dark ||
        (settings.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final timelineVisible =
        windy.particlesEnabled && windy.grid != null;
    // Partikel aktif dari sesi sebelumnya (preferensi tersimpan) tapi
    // grid belum dimuat — muat otomatis saat bounds tersedia.
    if (windy.particlesEnabled &&
        windy.grid == null &&
        !windy.gridLoading &&
        vm.visibleBounds != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (windy.particlesEnabled &&
            windy.grid == null &&
            !windy.gridLoading &&
            vm.visibleBounds != null) {
          windy.loadGrid(vm.visibleBounds!);
        }
      });
    }
    // Grid basi: user menggeser peta jauh (>200 km) dari tengah grid —
    // muat ulang agar partikel tidak menampilkan angin area lama.
    final grid = windy.grid;
    if (windy.particlesEnabled &&
        grid != null &&
        !windy.gridLoading &&
        vm.visibleBounds != null) {
      final gridCenterLat = (grid.south + grid.north) / 2;
      final gridCenterLon = (grid.west + grid.east) / 2;
      final distFromGrid = NavMath.distanceMeters(
        vm.center.latitude,
        vm.center.longitude,
        gridCenterLat,
        gridCenterLon,
      );
      if (distFromGrid > 200000) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (windy.particlesEnabled &&
              !windy.gridLoading &&
              vm.visibleBounds != null) {
            windy.loadGrid(vm.visibleBounds!);
          }
        });
      }
    }
    // Tata letak vertikal bergeser bila timeline tampil.
    final chipsBottom = timelineVisible ? 132.0 : 76.0;
    final recordingBottom = timelineVisible ? 164.0 : 108.0;
    final hintBottom = timelineVisible ? 208.0 : 120.0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SafetyBanner(),
            if (!offline.isOnline) const _OfflineBanner(),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const LatLng(
                        AppConstants.defaultLat,
                        AppConstants.defaultLon,
                      ),
                      initialZoom: AppConstants.defaultZoom,
                      minZoom: AppConstants.minZoom,
                      maxZoom: AppConstants.maxZoom,
                      onMapReady: () => vm.onMapReady(),
                      onPositionChanged: vm.onCameraChanged,
                      onTap: (_, point) => _onMapTap(vm, point),
                      onLongPress: (_, point) =>
                          showLongPressSheet(context, point),
                    ),
                    children: [
                      if (isNight)
                        ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            0.55, 0, 0, 0, 0,
                            0, 0.62, 0, 0, 10,
                            0, 0, 0.80, 0, 20,
                            0, 0, 0, 1, 0,
                          ]),
                          child: _basemapLayer(layers.basemap),
                        )
                      else
                        _basemapLayer(layers.basemap),
                      // Tile area tersimpan (offline) di atas basemap.
                      if (offline.areas.any(
                        (a) => a.basemap == layers.basemap.name,
                      ))
                        TileLayer(
                          urlTemplate: layers.basemap.urlTemplate,
                          tileProvider: _savedAreaProvider,
                          userAgentPackageName: AppConstants.packageId,
                        ),
                      // GEBCO_LATEST_2 tidak transparan — redupkan agar
                      // basemap di bawahnya tetap terbaca.
                      if (layers.showGebco)
                        Opacity(opacity: 0.55, child: _gebcoLayer()),
                      if (layers.showSeamark)
                        TileLayer(
                          urlTemplate: AppConstants.seamarkTemplate,
                          userAgentPackageName: AppConstants.packageId,
                        ),
                      if (layers.showRain && vm.rainTemplate != null)
                        Opacity(
                          opacity: 0.7,
                          child: TileLayer(
                            urlTemplate: vm.rainTemplate!,
                            userAgentPackageName: AppConstants.packageId,
                          ),
                        ),
                      if (layers.showGibs)
                        Opacity(
                          opacity: 0.6,
                          child: TileLayer(
                            urlTemplate: vm.gibsTemplate,
                            maxNativeZoom: 9,
                            userAgentPackageName: AppConstants.packageId,
                          ),
                        ),
                      if (vm.ownPosition != null &&
                          vm.ownAccuracyM != null)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: vm.ownPosition!,
                              radius: vm.ownAccuracyM!,
                              useRadiusInMeter: true,
                              color: scheme.primary
                                  .withValues(alpha: 0.15),
                              borderColor: scheme.primary
                                  .withValues(alpha: 0.4),
                              borderStrokeWidth: 1,
                            ),
                          ],
                        ),
                      // Lingkaran radius jangkar.
                      if (nav.anchor != null)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: LatLng(
                                nav.anchor!.latitude,
                                nav.anchor!.longitude,
                              ),
                              radius: nav.anchor!.radiusM,
                              useRadiusInMeter: true,
                              color: Colors.red.withValues(alpha: 0.08),
                              borderColor:
                                  Colors.red.withValues(alpha: 0.6),
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                      PolylineLayer(
                        polylines: _buildPolylines(nav),
                      ),
                      MarkerLayer(
                        markers: _buildMarkers(vm, nav),
                      ),
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            layers.basemap.fullAttribution,
                            onTap: () {},
                          ),
                          if (layers.showGebco)
                            const TextSourceAttribution(
                              'GEBCO',
                              onTap: null,
                            ),
                          if (layers.showSeamark)
                            const TextSourceAttribution(
                              'OpenSeaMap',
                              onTap: null,
                            ),
                        ],
                      ),
                    ],
                  ),
                  // Partikel angin (di atas tile, di bawah UI).
                  if (windy.particlesEnabled && windy.grid != null)
                    Positioned.fill(
                      child: WindParticlesOverlay(
                        grid: windy.grid!,
                        hourIndex: windy.hourIndex,
                        centerLat: vm.center.latitude,
                        centerLon: vm.center.longitude,
                        zoom: vm.zoom,
                        rotationDeg: vm.rotation,
                      ),
                    ),
                  // Notifikasi satu slot.
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: Center(
                      child: NoticeBanner(
                        controller: context.read<NoticeController>(),
                      ),
                    ),
                  ),
                  // Kolom status atas: alarm jangkar, GoTo, ukur, pilih.
                  Positioned(
                    top: 48,
                    left: 12,
                    right: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (nav.anchorAlarm) _AnchorAlarmBanner(nav: nav),
                        if (nav.gotoTarget != null) _GotoChip(nav: nav),
                        if (nav.visibleRoute != null)
                          _VisibleOverlayChip(
                            icon: Icons.route,
                            color: Colors.blue,
                            label: 'Rute: ${nav.visibleRoute!.name}',
                            onClear: () => nav.showRouteOnMap(null),
                          ),
                        if (nav.visibleTrack != null)
                          _VisibleOverlayChip(
                            icon: Icons.timeline,
                            color: Colors.orange,
                            label: 'Jejak: ${nav.visibleTrack!.name}',
                            onClear: () => nav.showTrackOnMap(null),
                          ),
                        if (nav.measureMode) _MeasureChip(nav: nav),
                        if (windy.pickMode) _PickModeHint(windy: windy),
                      ],
                    ),
                  ),
                  // Dial kompas (kanan atas).
                  Positioned(
                    top: 48,
                    right: 12,
                    child: CompassDial(
                      mapRotation: vm.rotation,
                      headingUp: vm.headingUp,
                      onTap: vm.toggleHeadingUp,
                    ),
                  ),
                  // Tombol kontrol kanan (bawah dial).
                  Positioned(
                    top: 104,
                    right: 12,
                    child: Column(
                      children: [
                        _MapButton(
                          icon: Icons.my_location,
                          tooltip: vm.followMode
                              ? 'Berhenti mengikuti'
                              : 'Posisi saya',
                          active: vm.followMode,
                          onTap: vm.toggleFollow,
                        ),
                        const SizedBox(height: 8),
                        _MapButton(
                          icon: Icons.layers,
                          tooltip: 'Lapisan peta',
                          onTap: () => showLayersSheet(context),
                        ),
                        const SizedBox(height: 8),
                        _MapButton(
                          icon: Icons.edit_location_alt,
                          tooltip: 'Ketik koordinat',
                          onTap: () => showManualPositionDialog(context),
                        ),
                        const SizedBox(height: 8),
                        _MapButton(
                          icon: Icons.add_location_alt,
                          tooltip: 'Tambah titik di tengah peta',
                          onTap: () => _addWaypointAtCenter(vm, nav),
                        ),
                        const SizedBox(height: 8),
                        _MapButton(
                          icon: Icons.fiber_manual_record,
                          tooltip: nav.isRecording
                              ? 'Berhenti merekam jejak'
                              : 'Mulai merekam jejak',
                          active: nav.isRecording,
                          onTap: () {
                            if (nav.isRecording) {
                              nav.stopRecording();
                            } else {
                              nav.startRecording();
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        _MapButton(
                          icon: Icons.straighten,
                          tooltip: nav.measureMode
                              ? 'Selesai mengukur'
                              : 'Ukur jarak',
                          active: nav.measureMode,
                          onTap: () {
                            // Mode ukur dan mode pilih titik saling
                            // meniadakan (keduanya memakai ketukan peta).
                            if (!nav.measureMode) windy.setPickMode(false);
                            nav.setMeasureMode(!nav.measureMode);
                          },
                        ),
                        const SizedBox(height: 8),
                        _MapButton(
                          icon: isNight
                              ? Icons.light_mode
                              : Icons.dark_mode,
                          tooltip: isNight
                              ? 'Mode siang'
                              : 'Mode malam',
                          active: isNight,
                          onTap: () => settings.setThemeMode(
                            isNight ? ThemeMode.light : ThemeMode.dark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Indikator merekam (kiri, di atas chip posisi).
                  if (nav.isRecording)
                    Positioned(
                      left: 12,
                      bottom: recordingBottom,
                      child: _RecordingChip(nav: nav),
                    ),
                  // Chip posisi + SOG/COG (kiri bawah).
                  if (vm.ownPosition != null)
                    Positioned(
                      left: 12,
                      bottom: chipsBottom,
                      child: _PositionChip(vm: vm, nav: nav),
                    ),
                  // Timeline partikel angin.
                  if (timelineVisible)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 76,
                      child: _TimelineBar(windy: windy),
                    ),
                  // Stempel versi (kanan bawah).
                  Positioned(
                    right: 8,
                    bottom: chipsBottom,
                    child: const VersionStamp(),
                  ),
                  // Hint pemakaian pertama.
                  if (vm.showFirstUseHint)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: hintBottom,
                      child: _FirstUseHint(vm: vm),
                    ),
                  // Bar panel bawah.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _BottomPanelBar(vm: vm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TileLayer _basemapLayer(BasemapKind basemap) {
    // Fallback otomatis ke OSM.de bila tile basemap lain gagal.
    final fallback = basemap == BasemapKind.standard
        ? null
        : AppConstants.osmDeTemplate;
    return TileLayer(
      urlTemplate: basemap.urlTemplate,
      fallbackUrl: fallback,
      maxNativeZoom: basemap.maxNativeZoom,
      userAgentPackageName: AppConstants.packageId,
    );
  }

  TileLayer _gebcoLayer() {
    return TileLayer(
      wmsOptions: WMSTileLayerOptions(
        baseUrl: AppConstants.gebcoWmsBase,
        layers: const ['GEBCO_LATEST_2'],
        format: 'image/png',
        version: '1.1.1',
        transparent: true,
        crs: const Epsg4326(),
      ),
      userAgentPackageName: AppConstants.packageId,
    );
  }

  List<Polyline> _buildPolylines(NavigationViewModel nav) {
    final polylines = <Polyline>[];
    // Rute yang dipilih (biru).
    final route = nav.visibleRoute;
    if (route != null) {
      final points = nav
          .routeWaypoints(route)
          .map((w) => LatLng(w.latitude, w.longitude))
          .toList();
      if (points.length >= 2) {
        polylines.add(
          Polyline(
            points: points,
            color: Colors.blue,
            strokeWidth: 3,
          ),
        );
      }
    }
    // Jejak yang dipilih (oranye).
    final track = nav.visibleTrack;
    if (track != null && track.points.length >= 2) {
      polylines.add(
        Polyline(
          points: track.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(),
          color: Colors.orange,
          strokeWidth: 3,
        ),
      );
    }
    // Jejak yang sedang direkam (oranye).
    if (nav.activePoints.length >= 2) {
      polylines.add(
        Polyline(
          points: nav.activePoints
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(),
          color: Colors.deepOrange,
          strokeWidth: 3,
        ),
      );
    }
    // Garis GoTo (hijau, dari posisi sendiri ke target).
    final target = nav.gotoTarget;
    final own = nav.ownPosition;
    if (target != null && own != null) {
      polylines.add(
        Polyline(
          points: [own, LatLng(target.latitude, target.longitude)],
          color: Colors.green,
          strokeWidth: 2,
        ),
      );
    }
    // Garis ukur (ungu).
    if (nav.measurePoints.length >= 2) {
      polylines.add(
        Polyline(
          points: nav.measurePoints,
          color: Colors.purple,
          strokeWidth: 2,
        ),
      );
    }
    return polylines;
  }

  List<Marker> _buildMarkers(MapViewModel vm, NavigationViewModel nav) {
    final markers = <Marker>[];
    // Posisi sendiri: panah berputar mengikuti heading.
    final own = vm.ownPosition;
    if (own != null) {
      final heading = vm.effectiveHeading ?? 0;
      markers.add(
        Marker(
          point: own,
          width: 40,
          height: 40,
          child: Transform.rotate(
            angle: heading * math.pi / 180,
            child: OwnShipMarker(manual: vm.positionIsManual),
          ),
        ),
      );
    }
    // Waypoint (angka urut) — ketuk membuka daftar titik.
    for (var i = 0; i < nav.waypoints.length; i++) {
      final wp = nav.waypoints[i];
      markers.add(
        Marker(
          point: LatLng(wp.latitude, wp.longitude),
          width: 28,
          height: 28,
          child: GestureDetector(
            onTap: () => showNavigationSheet(context, initialTab: 0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }
    // Target GoTo (bendera hijau).
    final target = nav.gotoTarget;
    if (target != null) {
      markers.add(
        Marker(
          point: LatLng(target.latitude, target.longitude),
          width: 36,
          height: 36,
          child: const Icon(
            Icons.flag,
            color: Colors.green,
            size: 32,
          ),
        ),
      );
    }
    // Titik jangkar.
    final anchor = nav.anchor;
    if (anchor != null) {
      markers.add(
        Marker(
          point: LatLng(anchor.latitude, anchor.longitude),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => showAnchorMobSheet(context),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: const Icon(Icons.anchor, color: Colors.red, size: 22),
            ),
          ),
        ),
      );
    }
    // Tanda MOB (merah).
    for (final mob in nav.mobMarks) {
      markers.add(
        Marker(
          point: LatLng(mob.latitude, mob.longitude),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => showAnchorMobSheet(context),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.person_pin_circle,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
      );
    }
    // Titik ukur (ungu, berangka).
    for (var i = 0; i < nav.measurePoints.length; i++) {
      markers.add(
        Marker(
          point: nav.measurePoints[i],
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.purple,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }
    // Kapal AIS (declutter menurut zoom).
    if (vm.layers.showAis) {
      final vessels = vm.vessels.values
          .where((v) => v.hasPosition)
          .toList(growable: false);
      final cap = vm.zoom < 7
          ? 25
          : vm.zoom < 10
              ? 60
              : 200;
      vessels.sort((a, b) {
        final da = NavMath.distanceMeters(
          vm.center.latitude,
          vm.center.longitude,
          a.latitude!,
          a.longitude!,
        );
        final db = NavMath.distanceMeters(
          vm.center.latitude,
          vm.center.longitude,
          b.latitude!,
          b.longitude!,
        );
        return da.compareTo(db);
      });
      final size = vm.zoom < 7
          ? 18.0
          : vm.zoom < 10
              ? 24.0
              : 30.0;
      for (final vessel in vessels.take(cap)) {
        final heading = vessel.headingDeg ?? vessel.courseDeg ?? 0;
        markers.add(
          Marker(
            point: LatLng(vessel.latitude!, vessel.longitude!),
            width: size,
            height: size * 1.4,
            child: GestureDetector(
              onTap: () {
                vm.selectVessel(vessel);
                showVesselSheet(context, vessel);
              },
              child: Transform.rotate(
                angle: heading * math.pi / 180,
                child: ShipMarker(
                  size: size,
                  selected: vm.selectedVessel?.mmsi == vessel.mmsi,
                ),
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  void _onMapTap(MapViewModel vm, LatLng point) {
    final nav = context.read<NavigationViewModel>();
    final windy = context.read<WindyViewModel>();
    if (nav.measureMode) {
      nav.addMeasurePoint(point);
      return;
    }
    if (windy.pickMode) {
      windy.loadPointForecast(point);
      showWindyPanel(context);
      return;
    }
    vm.lookupDepth(point);
    showDepthSheet(context);
  }

  Future<void> _addWaypointAtCenter(
    MapViewModel vm,
    NavigationViewModel nav,
  ) async {
    final name = await showWaypointDialog(
      context,
      point: vm.center,
      title: 'Waypoint baru',
    );
    if (name == null || !mounted) return;
    await nav.addWaypoint(
      name: name,
      latitude: vm.center.latitude,
      longitude: vm.center.longitude,
    );
  }
}

/// Tombol peta ringkas 44x44 dengan tooltip.
class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 3,
        shape: const CircleBorder(),
        color: active ? scheme.primaryContainer : scheme.surface,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 22,
              color: active
                  ? scheme.onPrimaryContainer
                  : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner mode offline (strip kuning di bawah banner keselamatan).
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — peta tersimpan tetap bisa dilihat.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => showOfflineSheet(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Peta Offline', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Banner alarm jangkar (merah, atas peta).
class _AnchorAlarmBanner extends StatelessWidget {
  const _AnchorAlarmBanner({required this.nav});

  final NavigationViewModel nav;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Alarm jangkar! Kapal '
              '${nav.anchorDistanceM?.toStringAsFixed(0) ?? '—'} m '
              'dari titik jangkar.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: nav.silenceAnchorAlarm,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Diamkan', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Chip GoTo: target, jarak, bearing, ETA + batal.
class _GotoChip extends StatelessWidget {
  const _GotoChip({required this.nav});

  final NavigationViewModel nav;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = nav.gotoTarget!;
    final distance = nav.gotoDistanceM;
    final bearing = nav.gotoBearingDeg;
    final eta = nav.gotoEta;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Row(
        children: [
          const Icon(Icons.navigation, size: 18, color: Colors.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              distance == null
                  ? 'Ke "${target.name}" — posisi belum tersedia'
                  : 'Ke "${target.name}" · '
                      '${NavMath.formatDistance(distance)} · '
                      'arah ${bearing!.toStringAsFixed(0)}° · '
                      'ETA ${NavMath.formatEta(eta)}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Batalkan navigasi',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: nav.cancelGoto,
          ),
        ],
      ),
    );
  }
}

/// Chip rute/jejak yang sedang ditampilkan di peta (+ sembunyikan).
class _VisibleOverlayChip extends StatelessWidget {
  const _VisibleOverlayChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.onClear,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Sembunyikan dari peta',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

/// Chip mode ukur: total jarak + aksi urungkan/hapus/selesai.
class _MeasureChip extends StatelessWidget {
  const _MeasureChip({required this.nav});

  final NavigationViewModel nav;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple),
      ),
      child: Row(
        children: [
          const Icon(Icons.straighten, size: 18, color: Colors.purple),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              nav.measurePoints.isEmpty
                  ? 'Ketuk peta untuk mengukur'
                  : 'Ukur: ${NavMath.formatDistance(nav.measureTotalM)} '
                      '(${nav.measurePoints.length} titik)',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo, size: 18),
            tooltip: 'Urungkan titik terakhir',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: nav.measurePoints.isEmpty
                ? null
                : nav.undoMeasurePoint,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Selesai mengukur',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => nav.setMeasureMode(false),
          ),
        ],
      ),
    );
  }
}

/// Hint mode pilih titik prakiraan.
class _PickModeHint extends StatelessWidget {
  const _PickModeHint({required this.windy});

  final WindyViewModel windy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app, size: 18, color: scheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Ketuk peta untuk memilih titik prakiraan.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => windy.setPickMode(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Batal', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Indikator merekam jejak (kiri, di atas chip posisi).
class _RecordingChip extends StatelessWidget {
  const _RecordingChip({required this.nav});

  final NavigationViewModel nav;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Merekam · ${nav.activePoints.length} titik',
            style: TextStyle(fontSize: 11, color: scheme.onSurface),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: nav.stopRecording,
            child: const Icon(Icons.stop, size: 16, color: Colors.red),
          ),
        ],
      ),
    );
  }
}

/// Timeline partikel angin (scrubber per jam, 3 hari).
class _TimelineBar extends StatelessWidget {
  const _TimelineBar({required this.windy});

  final WindyViewModel windy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hours = windy.timelineHours;
    if (hours < 2) return const SizedBox.shrink();
    final time = windy.selectedTime ?? DateTime.now();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              windy.playing ? Icons.pause : Icons.play_arrow,
              size: 22,
            ),
            tooltip: windy.playing ? 'Jeda' : 'Putar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: windy.togglePlay,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Slider(
              value: windy.hourIndex.toDouble(),
              min: 0,
              max: (windy.timelineHours - 1).toDouble(),
              divisions: windy.timelineHours - 1,
              onChanged: (v) => windy.setHourIndex(v.round()),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${IdFormat.dateTimeShort(time)} WIB',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Chip koordinat posisi sendiri + SOG/COG (kiri bawah peta).
class _PositionChip extends StatelessWidget {
  const _PositionChip({required this.vm, required this.nav});

  final MapViewModel vm;
  final NavigationViewModel nav;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pos = vm.ownPosition!;
    final sog = nav.sogKnots;
    final cog = nav.cogDeg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${NavMath.formatDecimal(pos.latitude, fractionDigits: 4)}, '
        '${NavMath.formatDecimal(pos.longitude, fractionDigits: 4)}'
        '${vm.positionIsManual ? ' (manual)' : ''}'
        '${sog == null ? '' : ' · SOG ${sog.toStringAsFixed(1)} kt'}'
        '${cog == null ? '' : ' · COG ${cog.toStringAsFixed(0)}°'}',
        style: TextStyle(fontSize: 11, color: scheme.onSurface),
      ),
    );
  }
}

/// Hint pemakaian pertama (sekali saja, bisa ditutup).
class _FirstUseHint extends StatelessWidget {
  const _FirstUseHint({required this.vm});

  final MapViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Ketuk titik laut untuk kedalaman. Tahan peta untuk '
                'waypoint / posisi manual. Menu Lainnya berisi titik, '
                'rute, jejak, jangkar, angin, dan peta offline.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: vm.dismissFirstUseHint,
              child: const Text('Mengerti'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bar bawah: Pasang, Cuaca, Gelombang, Kapal (dengan badge jumlah),
/// Lainnya, Pengaturan.
class _BottomPanelBar extends StatelessWidget {
  const _BottomPanelBar({required this.vm});

  final MapViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface.withValues(alpha: 0.96),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BarItem(
            icon: Icons.waves,
            label: 'Pasang',
            onTap: () => showTidesPanel(
              context,
              point: vm.panelPoint,
              viewModel: TidesViewModel(
                repository: context.read(),
              ),
            ),
          ),
          _BarItem(
            icon: Icons.cloud,
            label: 'Cuaca',
            onTap: () => showWeatherPanel(
              context,
              point: vm.panelPoint,
              viewModel: WeatherViewModel(
                repository: context.read(),
                mapDataRepository: context.read(),
              ),
            ),
          ),
          _BarItem(
            icon: Icons.water,
            label: 'Gelombang',
            onTap: () => showMarinePanel(
              context,
              point: vm.panelPoint,
              viewModel: MarineViewModel(
                repository: context.read(),
              ),
            ),
          ),
          _BarItem(
            icon: Icons.directions_boat,
            label: 'Kapal',
            badge: vm.vessels.isEmpty
                ? null
                : '${vm.vessels.length}',
            onTap: () => showAisPanel(
              context,
              viewModel: AisViewModel(
                repository: context.read(),
              ),
            ),
          ),
          _BarItem(
            icon: Icons.more_horiz,
            label: 'Lainnya',
            onTap: () => showMoreSheet(context),
          ),
          _BarItem(
            icon: Icons.settings,
            label: 'Pengaturan',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 24, color: scheme.primary),
                if (badge != null)
                  Positioned(
                    right: -10,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheme.onError,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
