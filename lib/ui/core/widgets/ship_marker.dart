import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marker kapal berbentuk siluet kapal tampak atas (R-19).
/// `size` menyesuaikan zoom (diatur MapScreen); rotasi heading
/// dilakukan parent dengan Transform.rotate.
class ShipMarker extends StatelessWidget {
  const ShipMarker({
    super.key,
    this.size = 28,
    this.color = const Color(0xFF1565C0),
    this.selected = false,
  });

  final double size;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.4),
      painter: _ShipPainter(
        color: selected ? Colors.orange.shade700 : color,
      ),
    );
  }
}

class _ShipPainter extends CustomPainter {
  _ShipPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Lambung: haluan runcing di atas, buritan datar di bawah.
    final hull = Path()
      ..moveTo(w * 0.5, 0)
      ..quadraticBezierTo(w * 0.85, h * 0.25, w * 0.9, h * 0.55)
      ..lineTo(w * 0.82, h)
      ..lineTo(w * 0.18, h)
      ..lineTo(w * 0.1, h * 0.55)
      ..quadraticBezierTo(w * 0.15, h * 0.25, w * 0.5, 0)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(hull, paint);

    // Garis tepi putih agar terbaca di atas tile gelap/terang.
    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.05);
    canvas.drawPath(hull, outline);

    // Bangunan atas (superstructure) — kotak terang di tengah.
    final superPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.35, h * 0.42, w * 0.3, h * 0.28),
        Radius.circular(w * 0.05),
      ),
      superPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ShipPainter oldDelegate) =>
      oldDelegate.color != color;
}
