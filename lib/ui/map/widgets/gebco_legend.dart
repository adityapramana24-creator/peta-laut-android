import 'package:flutter/material.dart';

/// Legenda warna lapisan kedalaman GEBCO + catatan jujur:
/// grid ~450 m (kasar), sungai tanpa data, dan sorot area dangkal
/// per ambang TIDAK tersedia (GEBCO tidak bisa diwarnai per ambang
/// dengan andal — ketuk titik laut untuk angka kedalaman).
class GebcoLegend extends StatelessWidget {
  const GebcoLegend({super.key});

  static const _swatches = [
    ('> 4.000 m', Color(0xFF0B1E4B)),
    ('2.000–4.000 m', Color(0xFF144A8A)),
    ('200–2.000 m', Color(0xFF2E7FC4)),
    ('0–200 m', Color(0xFF8FC3E8)),
    ('Darat', Color(0xFF7BA05B)),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Legenda kedalaman (GEBCO)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: _swatches.map((s) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: s.$2,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 4),
                Text(s.$1, style: const TextStyle(fontSize: 12)),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Grid ~450 m — kasar, bukan sounding chart. Sungai tidak '
          'ada data kedalaman. Sorot area dangkal per ambang tidak '
          'tersedia: ketuk titik laut untuk angka kedalamannya.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
