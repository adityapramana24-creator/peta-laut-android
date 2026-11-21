import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/port.dart';
import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../view_models/navigation_viewmodel.dart';

/// Daftar 15 pelabuhan: ketuk untuk lompat ke pelabuhan itu.
/// Menampilkan jarak dari posisi sendiri bila tersedia.
Future<void> showPortsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const PortsSheet(),
  );
}

class PortsSheet extends StatelessWidget {
  const PortsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final own = nav.ownPosition;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Pelabuhan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Ketuk pelabuhan untuk lompat ke lokasinya.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: Port.all.length,
              itemBuilder: (context, index) {
                final port = Port.all[index];
                final distance = own == null
                    ? null
                    : NavMath.distanceMeters(
                        own.latitude,
                        own.longitude,
                        port.latitude,
                        port.longitude,
                      );
                return ListTile(
                  leading: const Icon(Icons.sailing),
                  title: Text(port.name),
                  subtitle: Text(
                    '${NavMath.formatDecimal(port.latitude)}, '
                    '${NavMath.formatDecimal(port.longitude)}'
                    '${distance == null ? '' : ' · ${NavMath.formatDistance(distance)} dari saya'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.read<MapViewModel>().moveTo(
                          LatLng(port.latitude, port.longitude),
                          zoom: 11,
                        );
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
