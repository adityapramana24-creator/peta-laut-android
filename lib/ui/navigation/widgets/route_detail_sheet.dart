import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/settings_service.dart';
import '../../../domain/models/waypoint.dart';
import '../../../utils/nav_math.dart';
import '../../windy/widgets/route_weather_sheet.dart';
import '../view_models/navigation_viewmodel.dart';
import 'route_builder_sheet.dart';

/// Detail rute: daftar kaki (dari -> ke, bearing, jarak, ETA),
/// total, dan aksi (tampilkan di peta / ubah rute / ubah kecepatan /
/// cuaca di rute / navigasi / hapus).
Future<void> showRouteDetailSheet(BuildContext context, RoutePlan route) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => RouteDetailSheet(route: route, parentContext: context),
  );
}

class RouteDetailSheet extends StatelessWidget {
  const RouteDetailSheet({
    super.key,
    required this.route,
    required this.parentContext,
  });

  final RoutePlan route;

  /// Konteks halaman peta (tetap hidup setelah lembar ditutup).
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    // Ambil rute segar dari daftar (kecepatan/waypoint bisa berubah
    // lewat tombol di lembar ini — objek konstruktor bisa basi).
    var route = this.route;
    for (final r in nav.routes) {
      if (r.id == this.route.id) {
        route = r;
        break;
      }
    }
    final wps = nav.routeWaypoints(route);
    final points = wps.map((w) => (w.latitude, w.longitude)).toList();
    final legs = RouteMath.legs(points);
    final totalM = RouteMath.totalDistanceM(points);
    final eta = RouteMath.totalEta(points, route.speedKnots);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              route.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              '${wps.length} titik · ${NavMath.formatDistance(totalM)} · '
              'ETA ${NavMath.formatEta(eta)} '
              '(${route.speedKnots.toStringAsFixed(0)} knot)',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: legs.isEmpty
                  ? const Center(
                      child: Text('Rute ini hanya punya satu titik.'),
                    )
                  : ListView.builder(
                      itemCount: legs.length,
                      itemBuilder: (context, index) {
                        final leg = legs[index];
                        final legEta =
                            NavMath.etaDuration(leg.distanceM, route.speedKnots);
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          title: Text(
                            '${wps[index].name} → ${wps[index + 1].name}',
                          ),
                          subtitle: Text(
                            'Arah ${leg.bearingDeg.toStringAsFixed(0)}° · '
                            '${NavMath.formatDistance(leg.distanceM)} · '
                            '${NavMath.formatEta(legEta)}',
                          ),
                        );
                      },
                    ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    nav.showRouteOnMap(route);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('Tampilkan di peta'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showRouteBuilderSheet(
                      parentContext,
                      existingRoute: route,
                    );
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Ubah rute'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final speed = await showSpeedEditDialog(
                      context,
                      initialKnots: route.speedKnots,
                    );
                    if (speed == null || !context.mounted) return;
                    await context
                        .read<NavigationViewModel>()
                        .saveRoute(
                          route.copyWith(speedKnots: speed),
                        );
                    if (context.mounted) {
                      await context
                          .read<SettingsService>()
                          .setCruiseSpeedKnots(speed);
                    }
                  },
                  icon: const Icon(Icons.speed),
                  label: const Text('Ubah kecepatan'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showRouteWeatherSheet(parentContext, initialRoute: route);
                  },
                  icon: const Icon(Icons.cloud),
                  label: const Text('Cuaca di rute'),
                ),
                OutlinedButton.icon(
                  onPressed: wps.isEmpty
                      ? null
                      : () {
                          nav.setGoto(wps.first);
                          Navigator.of(context).pop();
                        },
                  icon: const Icon(Icons.navigation),
                  label: const Text('Navigasi ke titik pertama'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await _confirmDelete(
                      context,
                      'Hapus rute "${route.name}"?',
                    );
                    if (ok && context.mounted) {
                      await nav.deleteRoute(route.id);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                  icon: Icon(Icons.delete, color: scheme.error),
                  label: Text(
                    'Hapus rute',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
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
