import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marker posisi kapal sendiri: panah navigasi berputar mengikuti
/// heading (rotasi dilakukan parent dengan Transform.rotate).
/// Bila heading tidak diketahui, parent memakai [neutral]: lingkaran
/// tanpa arah (F-L11) — panah ke utara saat diam menyesatkan.
class OwnShipMarker extends StatelessWidget {
  const OwnShipMarker({
    super.key,
    this.size = 40,
    this.manual = false,
    this.neutral = false,
  });

  final double size;

  /// true bila posisi berasal dari input manual (bukan GPS) —
  /// ditampilkan dengan warna berbeda.
  final bool manual;

  /// true bila heading tidak diketahui — lingkaran tanpa arah.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(size, size),
      painter: _ArrowPainter(
        color: manual ? Colors.orange.shade700 : scheme.primary,
        neutral: neutral,
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.color, this.neutral = false});

  final Color color;
  final bool neutral;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    if (neutral) {
      // Lingkaran tanpa arah: isi warna + tepi putih + titik tengah.
      final center = Offset(w * 0.5, h * 0.5);
      final radius = math.min(w, h) * 0.3;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, w * 0.04),
      );
      canvas.drawCircle(
        center,
        math.max(2.0, w * 0.06),
        Paint()..color = Colors.white,
      );
      return;
    }

    // Panah navigasi: ujung di atas, ekor bercabang.
    final arrow = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.92, h * 0.78)
      ..lineTo(w * 0.5, h * 0.58)
      ..lineTo(w * 0.08, h * 0.78)
      ..close();

    canvas.drawPath(
      arrow,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.04),
    );

    // Titik tengah putih.
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.52),
      math.max(2.0, w * 0.06),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.neutral != neutral;
}
