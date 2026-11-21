import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/weather_alert.dart';

/// Dialog tambah/ubah peringatan cuaca.
/// Mengembalikan peringatan baru/terubah, atau null bila dibatalkan.
/// Minimal satu ambang wajib diisi.
Future<WeatherAlert?> showAlertDialog(
  BuildContext context, {
  WeatherAlert? existing,
}) {
  return showDialog<WeatherAlert>(
    context: context,
    builder: (_) => _AlertDialog(existing: existing),
  );
}

class _AlertDialog extends StatefulWidget {
  const _AlertDialog({this.existing});

  final WeatherAlert? existing;

  @override
  State<_AlertDialog> createState() => _AlertDialogState();
}

class _AlertDialogState extends State<_AlertDialog> {
  late final TextEditingController _name;
  late final TextEditingController _wind;
  late final TextEditingController _wave;
  late final TextEditingController _rain;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _wind = TextEditingController(
      text: e?.windKnots?.toStringAsFixed(0) ?? '',
    );
    _wave = TextEditingController(
      text: e?.waveM?.toStringAsFixed(1) ?? '',
    );
    _rain = TextEditingController(
      text: e?.rainMmPerHour?.toStringAsFixed(1) ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _wind.dispose();
    _wave.dispose();
    _rain.dispose();
    super.dispose();
  }

  double? _parse(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  void _save() {
    final wind = _parse(_wind.text);
    final wave = _parse(_wave.text);
    final rain = _parse(_rain.text);
    if (wind == null && wave == null && rain == null) {
      setState(() {
        _error = 'Isi minimal satu ambang (angin, gelombang, atau hujan).';
      });
      return;
    }
    final name = _name.text.trim().isEmpty
        ? 'Peringatan cuaca'
        : _name.text.trim();
    final existing = widget.existing;
    Navigator.of(context).pop(
      existing == null
          ? WeatherAlert(
              id: 'al_${DateTime.now().microsecondsSinceEpoch}',
              name: name,
              windKnots: wind,
              waveM: wave,
              rainMmPerHour: rain,
            )
          : existing.copyWith(
              name: name,
              windKnots: wind,
              waveM: wave,
              rainMmPerHour: rain,
              clearWind: wind == null,
              clearWave: wave == null,
              clearRain: rain == null,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Peringatan baru'
            : 'Ubah peringatan',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama',
                hintText: 'mis. Angin kencang',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _ThresholdField(
              controller: _wind,
              label: 'Angin di atas (knot)',
              hint: 'mis. 25',
            ),
            const SizedBox(height: 12),
            _ThresholdField(
              controller: _wave,
              label: 'Gelombang di atas (meter)',
              hint: 'mis. 2,5',
            ),
            const SizedBox(height: 12),
            _ThresholdField(
              controller: _rain,
              label: 'Hujan di atas (mm/jam)',
              hint: 'mis. 5',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Kosongkan ambang yang tidak dipakai. Peringatan '
              'dipicu bila prakiraan 24 jam ke depan melewati ambang.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _ThresholdField extends StatelessWidget {
  const _ThresholdField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
