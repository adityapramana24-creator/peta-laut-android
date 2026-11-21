import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/waypoint.dart';
import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../view_models/navigation_viewmodel.dart';
import 'manual_waypoint_dialog.dart';
import 'route_builder_sheet.dart';
import 'route_detail_sheet.dart';
import 'track_detail_sheet.dart';

/// Lembar Titik & Rute & Jejak — tiga tab.
/// [initialTab]: 0 = Titik, 1 = Rute, 2 = Jejak.
Future<void> showNavigationSheet(
  BuildContext context, {
  int initialTab = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => NavigationSheet(initialTab: initialTab),
  );
}

class NavigationSheet extends StatelessWidget {
  const NavigationSheet({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.78;
    return SizedBox(
      height: height,
      child: DefaultTabController(
        length: 3,
        initialIndex: initialTab,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.place), text: 'Titik'),
                Tab(icon: Icon(Icons.route), text: 'Rute'),
                Tab(icon: Icon(Icons.timeline), text: 'Jejak'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _WaypointTab(),
                  _RouteTab(),
                  _TrackTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Titik --

class _WaypointTab extends StatelessWidget {
  const _WaypointTab();

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final waypoints = nav.waypoints;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: FilledButton.icon(
            onPressed: () async {
              final result = await showManualWaypointDialog(context);
              if (result == null || !context.mounted) return;
              await context.read<NavigationViewModel>().addWaypoint(
                    name: result.name,
                    latitude: result.latitude,
                    longitude: result.longitude,
                  );
            },
            icon: const Icon(Icons.keyboard),
            label: const Text('+ Tambah waypoint ketik'),
          ),
        ),
        Expanded(
          child: waypoints.isEmpty
              ? const _EmptyState(
                  icon: Icons.add_location_alt,
                  title: 'Belum ada titik',
                  body: 'Ketuk tombol di atas untuk mengetik nama + '
                      'koordinat (desimal atau DMS), atau ketuk-tahan '
                      'peta lalu pilih "Tambah waypoint di sini".',
                )
              : ListView.builder(
                  itemCount: waypoints.length,
                  itemBuilder: (context, index) {
                    final wp = waypoints[index];
                    return _WaypointTile(waypoint: wp, number: index + 1);
                  },
                ),
        ),
      ],
    );
  }
}

class _WaypointTile extends StatelessWidget {
  const _WaypointTile({required this.waypoint, required this.number});

  final Waypoint waypoint;
  final int number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    waypoint.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${NavMath.formatDecimal(waypoint.latitude)}, '
                    '${NavMath.formatDecimal(waypoint.longitude)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    NavMath.formatLatLonDms(
                      waypoint.latitude,
                      waypoint.longitude,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 2,
              children: [
                _ActionButton(
                  icon: Icons.visibility,
                  label: 'Lihat',
                  onPressed: () {
                    context.read<MapViewModel>().moveTo(
                          LatLng(waypoint.latitude, waypoint.longitude),
                          zoom: 13,
                        );
                    Navigator.of(context).pop();
                  },
                ),
                _ActionButton(
                  icon: Icons.route,
                  label: 'Rute',
                  onPressed: () => showRouteBuilderSheet(
                    context,
                    initialSelectedIds: [waypoint.id],
                  ),
                ),
                _ActionButton(
                  icon: Icons.navigation,
                  label: 'Ke sini',
                  onPressed: () {
                    context.read<NavigationViewModel>().setGoto(waypoint);
                    Navigator.of(context).pop();
                  },
                ),
                _ActionButton(
                  icon: Icons.edit,
                  label: 'Ubah',
                  onPressed: () async {
                    final result = await showManualWaypointDialog(
                      context,
                      existing: waypoint,
                    );
                    if (result == null || !context.mounted) return;
                    await context
                        .read<NavigationViewModel>()
                        .updateWaypoint(
                          id: waypoint.id,
                          name: result.name,
                          latitude: result.latitude,
                          longitude: result.longitude,
                        );
                  },
                ),
                _ActionButton(
                  icon: Icons.delete,
                  label: 'Hapus',
                  color: scheme.error,
                  onPressed: () async {
                    final ok = await _confirmDelete(
                      context,
                      'Hapus titik "${waypoint.name}"?',
                    );
                    if (ok && context.mounted) {
                      await context
                          .read<NavigationViewModel>()
                          .deleteWaypoint(waypoint.id);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Rute --

class _RouteTab extends StatelessWidget {
  const _RouteTab();

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final routes = nav.routes;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: FilledButton.icon(
            onPressed: nav.waypoints.length < 2
                ? null
                : () => showRouteBuilderSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Buat rute baru'),
          ),
        ),
        if (nav.waypoints.length < 2)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Butuh minimal 2 titik untuk membuat rute. Tambahkan '
              'waypoint dulu dari tab Titik (ketik koordinat) atau '
              'dari peta (ketuk-tahan).',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: routes.isEmpty
              ? const _EmptyState(
                  icon: Icons.route,
                  title: 'Belum ada rute',
                  body: 'Rute adalah urutan waypoint: jarak, bearing, '
                      'dan ETA dihitung otomatis.',
                )
              : ListView.builder(
                  itemCount: routes.length,
                  itemBuilder: (context, index) {
                    final route = routes[index];
                    return _RouteTile(route: route);
                  },
                ),
        ),
      ],
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.route});

  final RoutePlan route;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final wps = nav.routeWaypoints(route);
    final points =
        wps.map((w) => (w.latitude, w.longitude)).toList();
    final totalM = RouteMath.totalDistanceM(points);
    final eta = RouteMath.totalEta(points, route.speedKnots);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.route),
        title: Text(route.name),
        subtitle: Text(
          '${wps.length} titik aktif · '
          '${NavMath.formatDistance(totalM)} · '
          '${NavMath.formatEta(eta)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showRouteDetailSheet(context, route),
      ),
    );
  }
}

// ---------------------------------------------------------------- Jejak --

class _TrackTab extends StatelessWidget {
  const _TrackTab();

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final tracks = nav.tracks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              if (nav.isRecording)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  nav.isRecording
                      ? 'Merekam jejak — ${nav.activePoints.length} titik'
                      : 'Perekaman jejak mati',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (nav.isRecording) {
                    nav.stopRecording();
                  } else {
                    nav.startRecording();
                  }
                },
                icon: Icon(
                  nav.isRecording ? Icons.stop : Icons.fiber_manual_record,
                ),
                label: Text(nav.isRecording ? 'Berhenti' : 'Mulai rekam'),
                style: nav.isRecording
                    ? FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.error,
                      )
                    : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Posisi dicatat tiap 30 detik bila sudah bergerak 25 m '
            '(hemat baterai). Jejak tersimpan di HP ini.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: tracks.isEmpty
              ? const _EmptyState(
                  icon: Icons.timeline,
                  title: 'Belum ada jejak',
                  body: 'Tekan "Mulai rekam" sebelum berlayar; jejak '
                      'muncul di sini setelah perekaman dihentikan.',
                )
              : ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final active = nav.activeTrack?.id == track.id;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: Icon(
                          active ? Icons.fiber_manual_record : Icons.timeline,
                          color: active ? Colors.red : null,
                        ),
                        title: Text(track.name),
                        subtitle: Text(
                          '${NavMath.formatDateTime(track.startedAt)}'
                          '${active ? ' · sedang direkam' : ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showTrackDetailSheet(context, track),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- bersama --

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: color),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hapus?'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  return result ?? false;
}
