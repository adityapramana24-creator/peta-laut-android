import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../utils/coordinates.dart';
import '../view_models/map_viewmodel.dart';

/// Dialog ketik koordinat (jalur cadangan posisi manual, R-12).
/// Koma desimal Indonesia diterima ("-3,32, 114,59").
Future<void> showManualPositionDialog(BuildContext context) {
  final controller = TextEditingController();
  String? error;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Tetapkan posisi manual'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ketik lintang, bujur. Koma desimal boleh dipakai.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: '-3,32, 114,59',
                    labelText: 'Lintang, Bujur',
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed =
                      CoordinateInput.parseLatLon(controller.text);
                  if (parsed == null) {
                    setState(() {
                      error =
                          'Format tidak dikenal. Contoh: -3,32, 114,59';
                    });
                    return;
                  }
                  context.read<MapViewModel>().setManualPosition(
                        LatLng(parsed.$1, parsed.$2),
                      );
                  Navigator.of(context).pop();
                },
                child: const Text('Tetapkan'),
              ),
            ],
          );
        },
      );
    },
  ).then((_) => controller.dispose());
}
