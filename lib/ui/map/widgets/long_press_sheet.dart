import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../../map/widgets/depth_sheet.dart';
import '../../navigation/view_models/navigation_viewmodel.dart';
import '../../navigation/widgets/waypoint_dialog.dart';

/// Lembar aksi ketuk-tahan peta: titik yang ditahan bisa dijadikan
/// waypoint, posisi manual, atau titik cek kedalaman.
/// (Satu gesture, tiga akibat yang jelas — tanpa tebakan.)
Future<void> showLongPressSheet(BuildContext context, LatLng point) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => _LongPressSheet(point: point, parentContext: context),
  );
}

class _LongPressSheet extends StatelessWidget {
  const _LongPressSheet({required this.point, required this.parentContext});

  final LatLng point;

  /// Konteks halaman peta (tetap hidup setelah lembar ditutup).
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            '${NavMath.formatDecimal(point.latitude)}, '
            '${NavMath.formatDecimal(point.longitude)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            NavMath.formatLatLonDms(point.latitude, point.longitude),
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.add_location_alt),
            title: const Text('Tambah waypoint di sini'),
            subtitle: const Text('Simpan titik ini dengan nama'),
            onTap: () async {
              Navigator.of(context).pop();
              final name = await showWaypointDialog(
                parentContext,
                point: point,
                title: 'Waypoint baru',
              );
              if (name == null || !parentContext.mounted) return;
              await parentContext.read<NavigationViewModel>().addWaypoint(
                    name: name,
                    latitude: point.latitude,
                    longitude: point.longitude,
                  );
            },
          ),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const Text('Jadikan posisi saya'),
            subtitle: const Text('Posisi manual (bukan GPS)'),
            onTap: () {
              context.read<MapViewModel>().setManualPosition(point);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.water),
            title: const Text('Cek kedalaman di sini'),
            subtitle: const Text('Angka kedalaman GEBCO titik ini'),
            onTap: () {
              Navigator.of(context).pop();
              parentContext.read<MapViewModel>().lookupDepth(point);
              showDepthSheet(parentContext);
            },
          ),
        ],
      ),
    );
  }
}
