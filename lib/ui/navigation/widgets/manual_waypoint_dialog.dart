import 'package:flutter/material.dart';

import '../../../domain/models/waypoint.dart';
import '../../../utils/coordinates.dart';
import '../../../utils/nav_math.dart';

/// Hasil form waypoint ketik: nama + koordinat desimal.
typedef ManualWaypointResult = ({
  String name,
  double latitude,
  double longitude,
});

/// Dialog tambah/ubah waypoint dengan koordinat KETIK (ronde 2).
/// Nama + lintang + bujur diketik user; tiap field menerima desimal
/// ("-6,1234" / "-6.1234") maupun DMS ("6°07'24\"S", "S 6°07'24\"").
/// Mengembalikan hasil bila disimpan, null bila dibatalkan.
/// [existing] diisi saat mengubah waypoint yang sudah ada — field
/// terisi nilai lama (koordinat tampil desimal).
Future<ManualWaypointResult?> showManualWaypointDialog(
  BuildContext context, {
  Waypoint? existing,
}) {
  final nameController = TextEditingController(text: existing?.name ?? '');
  final latController = TextEditingController(
    text: existing == null
        ? ''
        : NavMath.formatDecimal(existing.latitude),
  );
  final lonController = TextEditingController(
    text: existing == null
        ? ''
        : NavMath.formatDecimal(existing.longitude),
  );
  String? latError;
  String? lonError;
  String? generalError;
  return showDialog<ManualWaypointResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              existing == null ? 'Tambah waypoint ketik' : 'Ubah waypoint',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Desimal: -6,1234 atau -6.1234. DMS: 6°07\'24"S. '
                    'Huruf: U/S untuk lintang, T/B untuk bujur.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama titik',
                      hintText: 'mis. Karang Berbahaya',
                      helperText: 'Boleh kosong — nama otomatis "Titik N".',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: latController,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Lintang',
                      hintText: '-6,1234 atau 6°07\'24"S',
                      errorText: latError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lonController,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Bujur',
                      hintText: '106,825 atau 106°49\'30"E',
                      errorText: lonError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (generalError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      generalError!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  final lat = CoordinateInput.parseCoordinate(
                    latController.text,
                    isLatitude: true,
                  );
                  final lon = CoordinateInput.parseCoordinate(
                    lonController.text,
                    isLatitude: false,
                  );
                  setState(() {
                    latError = lat.error;
                    lonError = lon.error;
                    generalError = null;
                  });
                  if (!lat.isOk || !lon.isOk) return;
                  if (!CoordinateInput.isInAsean(
                    lat.value!,
                    lon.value!,
                  )) {
                    setState(() {
                      generalError =
                          'Di luar kawasan ASEAN — waypoint hanya bisa '
                          'dibuat di dalam ASEAN (lintang -11 sampai 29, '
                          'bujur 92 sampai 141).';
                    });
                    return;
                  }
                  Navigator.of(context).pop((
                    name: nameController.text.trim(),
                    latitude: lat.value!,
                    longitude: lon.value!,
                  ));
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      );
    },
  ).then((value) {
    nameController.dispose();
    latController.dispose();
    lonController.dispose();
    return value;
  });
}
