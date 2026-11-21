import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../utils/nav_math.dart';

/// Dialog tambah/ubah waypoint: nama + koordinat (desimal + DMS).
/// Mengembalikan nama yang dimasukkan, atau null bila dibatalkan.
Future<String?> showWaypointDialog(
  BuildContext context, {
  required LatLng point,
  String? initialName,
  required String title,
}) {
  final controller = TextEditingController(text: initialName ?? '');
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${NavMath.formatDecimal(point.latitude)}, '
              '${NavMath.formatDecimal(point.longitude)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              NavMath.formatLatLonDms(point.latitude, point.longitude),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama titik',
                hintText: 'mis. Karang Berbahaya',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) =>
                  Navigator.of(dialogContext).pop(controller.text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Simpan'),
          ),
        ],
      );
    },
  ).then((value) {
    controller.dispose();
    return value;
  });
}
