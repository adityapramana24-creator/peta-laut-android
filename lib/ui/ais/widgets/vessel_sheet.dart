import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/vessel.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';

/// Lembar detail satu kapal (dari marker peta / daftar panel AIS).
Future<void> showVesselSheet(BuildContext context, Vessel vessel) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => VesselSheet(vessel: vessel),
  );
}

class VesselSheet extends StatelessWidget {
  const VesselSheet({super.key, required this.vessel});

  final Vessel vessel;

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
          Row(
            children: [
              Icon(Icons.directions_boat, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  vessel.displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tutup',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Row(label: 'MMSI', value: '${vessel.mmsi}'),
          if (vessel.hasPosition) ...[
            _Row(
              label: 'Posisi',
              value:
                  '${NavMath.formatDecimal(vessel.latitude!, fractionDigits: 5)}, '
                  '${NavMath.formatDecimal(vessel.longitude!, fractionDigits: 5)}',
            ),
            _Row(
              label: '',
              value: NavMath.formatLatLonDms(
                vessel.latitude!,
                vessel.longitude!,
              ),
            ),
          ],
          if (vessel.speedKnots != null)
            _Row(
              label: 'Kecepatan',
              value: '${vessel.speedKnots!.toStringAsFixed(1)} knot',
            ),
          if (vessel.courseDeg != null)
            _Row(
              label: 'Haluan (COG)',
              value:
                  '${vessel.courseDeg!.toStringAsFixed(0)}° '
                  '(${NavMath.compassPoint(vessel.courseDeg!)})',
            ),
          if (vessel.headingDeg != null)
            _Row(
              label: 'Arah hadap',
              value: '${vessel.headingDeg!.toStringAsFixed(0)}°',
            ),
          if (vessel.destination != null)
            _Row(label: 'Tujuan', value: vessel.destination!),
          if (vessel.eta != null)
            _Row(label: 'ETA', value: vessel.eta!),
          if (vessel.lastSeen != null)
            _Row(
              label: 'Terakhir terlihat',
              value:
                  '${IdFormat.dateTimeShort(IdFormat.toWib(vessel.lastSeen!.toUtc()))} WIB',
            ),
          const SizedBox(height: 12),
          if (vessel.hasPosition)
            FilledButton.icon(
              icon: const Icon(Icons.center_focus_strong, size: 18),
              label: const Text('Tampilkan di peta'),
              onPressed: () {
                Navigator.of(context).pop();
                context.read<MapViewModel>().moveTo(
                      LatLng(vessel.latitude!, vessel.longitude!),
                      zoom: 12,
                    );
              },
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
