import 'package:flutter/material.dart';

/// Skala warna kecepatan angin gaya Windy: tenang biru muda ->
/// hijau -> kuning -> oranye -> merah -> ungu (kencang).
/// Dipakai partikel angin (warna garis) + legenda (di peta & panel).
/// Interpolasi linear antar titik henti.
class WindColorScale {
  WindColorScale._();

  /// (km/jam, warna). Titik henti dipilih agar angin tropis yang
  /// umum (5–30 km/jam) terbagi ke 4 warna yang mudah dibedakan.
  static const List<(double, Color)> stops = [
    (0, Color(0xFFB8E3F5)), // tenang — biru sangat muda
    (10, Color(0xFF6FC7E8)), // biru muda
    (20, Color(0xFF3AA655)), // hijau
    (30, Color(0xFFF5D90A)), // kuning
    (40, Color(0xFFF59E0B)), // oranye
    (50, Color(0xFFE84B3C)), // merah
    (65, Color(0xFF8E44AD)), // ungu — kencang
  ];

  static Color colorForKmh(double kmh) {
    final v = kmh.clamp(stops.first.$1, stops.last.$1);
    for (var i = 0; i < stops.length - 1; i++) {
      final (s0, c0) = stops[i];
      final (s1, c1) = stops[i + 1];
      if (v >= s0 && v <= s1) {
        final t = s1 == s0 ? 0.0 : (v - s0) / (s1 - s0);
        return Color.lerp(c0, c1, t)!;
      }
    }
    return stops.last.$2;
  }
}

/// Skala warna kecepatan arus (knot): lambat biru -> hijau ->
/// kuning -> oranye -> merah (kencang). Dipakai panah arus + legenda.
class CurrentColorScale {
  CurrentColorScale._();

  /// (knot, warna).
  static const List<(double, Color)> stops = [
    (0.0, Color(0xFF7FB8E8)), // < 0,5 kt — biru muda
    (0.5, Color(0xFF3AA655)), // hijau
    (1.0, Color(0xFFF5D90A)), // kuning
    (2.0, Color(0xFFF59E0B)), // oranye
    (3.0, Color(0xFFE84B3C)), // merah — kencang
  ];

  static Color colorForKnots(double knots) {
    final v = knots.clamp(stops.first.$1, stops.last.$1);
    for (var i = 0; i < stops.length - 1; i++) {
      final (s0, c0) = stops[i];
      final (s1, c1) = stops[i + 1];
      if (v >= s0 && v <= s1) {
        final t = s1 == s0 ? 0.0 : (v - s0) / (s1 - s0);
        return Color.lerp(c0, c1, t)!;
      }
    }
    return stops.last.$2;
  }
}

/// Satu baris legenda skala warna: label + gradien + nilai ujung.
class _ScaleRow extends StatelessWidget {
  const _ScaleRow({
    required this.label,
    required this.stops,
    required this.minLabel,
    required this.maxLabel,
  });

  final String label;
  final List<(double, Color)> stops;
  final String minLabel;
  final String maxLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.onSurface),
        ),
        const SizedBox(width: 6),
        Container(
          width: 72,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: stops.map((s) => s.$2).toList(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$minLabel–$maxLabel',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Legenda skala warna angin (dipakai di panel Windy).
class WindLegend extends StatelessWidget {
  const WindLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScaleRow(
      label: 'Angin',
      stops: WindColorScale.stops,
      minLabel: '0',
      maxLabel: '65+ km/jam',
    );
  }
}

/// Legenda skala warna arus (dipakai di panel Windy).
class CurrentLegend extends StatelessWidget {
  const CurrentLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ScaleRow(
      label: 'Arus',
      stops: CurrentColorScale.stops,
      minLabel: '0',
      maxLabel: '3+ kt',
    );
  }
}

/// Kartu legenda ringkas di atas peta: baris angin bila partikel aktif,
/// baris arus bila panah arus aktif. Sembunyi bila keduanya mati.
class WindCurrentLegendCard extends StatelessWidget {
  const WindCurrentLegendCard({
    super.key,
    required this.showWind,
    required this.showCurrent,
  });

  final bool showWind;
  final bool showCurrent;

  @override
  Widget build(BuildContext context) {
    if (!showWind && !showCurrent) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showWind) const WindLegend(),
          if (showWind && showCurrent) const SizedBox(height: 4),
          if (showCurrent) const CurrentLegend(),
        ],
      ),
    );
  }
}
