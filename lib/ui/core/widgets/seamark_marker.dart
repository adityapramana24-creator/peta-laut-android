import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/seamark.dart';

/// Simbol marker rambu laut — penyederhanaan IHO S-52 / OpenSeaMap
/// yang jujur: bentuk + warna per kategori, BUKAN simbol ECDIS penuh.
///
/// - Lateral: lingkaran + tanda puncak (port = merah + silinder,
///   starboard = hijau + kerucut ke atas), IALA-A.
/// - Kardinal: belah ketupat kuning-hitam per kuartal + dua kerucut.
/// - Bahaya terisolasi: hitam + pita merah + dua bola hitam.
/// - Air aman: garis vertikal merah-putih + satu bola merah.
/// - Tujuan khusus: kuning + tanda X.
/// - Lampu: bintang magenta (besar = lampu utama, kecil = lampu kecil).
/// - Tanda darat: segitiga cokelat. Lainnya: belah ketupat abu-abu.
///
/// Tanda puncak kardinal menunjuk utara — parent WAJIB memutar widget
/// mengikuti rotasi peta (seperti marker AIS) agar arahnya tetap benar
/// saat peta berputar (heading-up / gestur rotasi).
class SeamarkMarker extends StatelessWidget {
  const SeamarkMarker({super.key, required this.seamark, this.size = 28});

  final Seamark seamark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SeamarkSymbolPainter(seamark: seamark),
    );
  }
}

class _SeamarkSymbolPainter extends CustomPainter {
  _SeamarkSymbolPainter({required this.seamark});

  final Seamark seamark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    switch (seamark.kind) {
      case SeamarkKind.lateral:
        _drawLateral(canvas, s);
      case SeamarkKind.cardinal:
        _drawCardinal(canvas, s);
      case SeamarkKind.isolatedDanger:
        _drawIsolatedDanger(canvas, s);
      case SeamarkKind.safeWater:
        _drawSafeWater(canvas, s);
      case SeamarkKind.specialPurpose:
        _drawSpecialPurpose(canvas, s);
      case SeamarkKind.lightMajor:
        _drawLight(canvas, s, major: true);
      case SeamarkKind.lightMinor:
        _drawLight(canvas, s, major: false);
      case SeamarkKind.landmark:
        _drawLandmark(canvas, s);
      case SeamarkKind.other:
        _drawOther(canvas, s);
    }
  }

  Paint _fill(Color color) =>
      Paint()..color = color..style = PaintingStyle.fill;

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;

  /// Bentuk berisi + halo putih agar terbaca di atas tile apa pun.
  void _drawShape(Canvas canvas, Path path, Color fill) {
    canvas.drawPath(path, _stroke(Colors.white, 2.0));
    canvas.drawPath(path, _fill(fill));
  }

  Path _triangle(Offset a, Offset b, Offset c) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..close();

  Path _diamond(Offset center, double r) => Path()
    ..moveTo(center.dx, center.dy - r)
    ..lineTo(center.dx + r, center.dy)
    ..lineTo(center.dx, center.dy + r)
    ..lineTo(center.dx - r, center.dy)
    ..close();

  Path _starPath(Offset center, double outerR, double innerR, int points) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outerR : innerR;
      final angle = (i * math.pi / points) - math.pi / 2;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  /// Warna dari tag `seamark:*:colour` (token pertama); abu-abu bila
  /// tidak dikenal / tidak ada tag.
  Color _tagColour() {
    final colours = seamark.colours;
    if (colours.isEmpty) return Colors.grey.shade600;
    switch (colours.first) {
      case 'red':
        return Colors.red.shade700;
      case 'green':
        return Colors.green.shade700;
      case 'yellow':
        return Colors.yellow.shade700;
      case 'white':
        return Colors.grey.shade300;
      case 'black':
        return Colors.black87;
      case 'orange':
        return Colors.orange.shade700;
      case 'blue':
        return Colors.blue.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  void _drawLateral(Canvas canvas, double size) {
    final cx = size / 2;
    final bodyCy = size * 0.60;
    final r = size * 0.30;
    final side = seamark.lateralSide;
    final color = switch (side) {
      LateralSide.port => Colors.red.shade700,
      LateralSide.starboard => Colors.green.shade700,
      LateralSide.unknown => _tagColour(),
    };
    if (side == LateralSide.port) {
      // Tanda puncak silinder (can).
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, size * 0.16),
          width: size * 0.26,
          height: size * 0.18,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, _stroke(Colors.white, 2.0));
      canvas.drawRRect(rect, _fill(color));
    } else if (side == LateralSide.starboard) {
      // Tanda puncak kerucut ke atas.
      final cone = _triangle(
        Offset(cx, size * 0.04),
        Offset(cx - size * 0.13, size * 0.28),
        Offset(cx + size * 0.13, size * 0.28),
      );
      _drawShape(canvas, cone, color);
    }
    final body = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, bodyCy), radius: r));
    _drawShape(canvas, body, color);
  }

  void _drawCardinal(Canvas canvas, double size) {
    final cx = size / 2;
    final bodyCy = size * 0.60;
    final r = size * 0.30;
    final q = seamark.cardinalQuadrant;
    final black = Colors.black87;
    final yellow = Colors.yellow.shade600;
    final top = Offset(cx, bodyCy - r);
    final right = Offset(cx + r, bodyCy);
    final bottom = Offset(cx, bodyCy + r);
    final left = Offset(cx - r, bodyCy);
    final diamond = _diamond(Offset(cx, bodyCy), r);
    // Dasar: kuning, kecuali barat (hitam, sisinya kuning).
    _drawShape(canvas, diamond, q == CardinalQuadrant.west ? black : yellow);
    switch (q) {
      case CardinalQuadrant.north:
        canvas.drawPath(_triangle(top, right, left), _fill(black));
      case CardinalQuadrant.south:
        canvas.drawPath(_triangle(bottom, right, left), _fill(black));
      case CardinalQuadrant.east:
        canvas.drawPath(_triangle(left, top, bottom), _fill(black));
        canvas.drawPath(_triangle(right, top, bottom), _fill(black));
      case CardinalQuadrant.west:
        canvas.drawPath(_triangle(left, top, bottom), _fill(yellow));
        canvas.drawPath(_triangle(right, top, bottom), _fill(yellow));
      case CardinalQuadrant.unknown:
        canvas.drawPath(_triangle(right, top, bottom), _fill(black));
    }
    canvas.drawPath(diamond, _stroke(Colors.white, 1.5));
    _drawCardinalTopmark(canvas, size, q);
  }

  /// Tanda puncak kardinal: dua kerucut — utara: keduanya ke atas;
  /// selatan: keduanya ke bawah; timur: menghadap keluar (pangkal
  /// bertemu); barat: menghadap ke dalam (ujung bertemu).
  void _drawCardinalTopmark(
    Canvas canvas,
    double size,
    CardinalQuadrant q,
  ) {
    if (q == CardinalQuadrant.unknown) return;
    final cx = size / 2;
    final hw = size * 0.11;
    final black = _fill(Colors.black87);
    Path cone(double apexY, double baseY) => _triangle(
          Offset(cx, apexY),
          Offset(cx - hw, baseY),
          Offset(cx + hw, baseY),
        );
    final y0 = size * 0.03;
    final y1 = size * 0.14;
    final y2 = size * 0.25;
    switch (q) {
      case CardinalQuadrant.north:
        canvas.drawPath(cone(y0, y1), black);
        canvas.drawPath(cone(y1, y2), black);
      case CardinalQuadrant.south:
        canvas.drawPath(cone(y1, y0), black);
        canvas.drawPath(cone(y2, y1), black);
      case CardinalQuadrant.east:
        canvas.drawPath(cone(y0, y1), black);
        canvas.drawPath(cone(y2, y1), black);
      case CardinalQuadrant.west:
        canvas.drawPath(cone(y1, y0), black);
        canvas.drawPath(cone(y1, y2), black);
      case CardinalQuadrant.unknown:
        break;
    }
  }

  void _drawIsolatedDanger(Canvas canvas, double size) {
    final cx = size / 2;
    final bodyCy = size * 0.60;
    final r = size * 0.30;
    final center = Offset(cx, bodyCy);
    // Tanda puncak: dua bola hitam bertumpuk.
    for (final y in [size * 0.10, size * 0.22]) {
      canvas.drawCircle(Offset(cx, y), size * 0.07, _fill(Colors.black87));
    }
    // Badan hitam + pita merah mendatar.
    canvas.drawCircle(center, r, _fill(Colors.black87));
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx - r, bodyCy - r * 0.32, r * 2, r * 0.64),
      _fill(Colors.red.shade700),
    );
    canvas.restore();
    canvas.drawCircle(center, r, _stroke(Colors.white, 1.5));
  }

  void _drawSafeWater(Canvas canvas, double size) {
    final cx = size / 2;
    final bodyCy = size * 0.60;
    final r = size * 0.30;
    final center = Offset(cx, bodyCy);
    // Tanda puncak: satu bola merah.
    canvas.drawCircle(
      Offset(cx, size * 0.16),
      size * 0.08,
      _fill(Colors.red.shade700),
    );
    // Badan: garis vertikal merah-putih (4 lajur).
    canvas.drawCircle(center, r, _fill(Colors.white));
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
    );
    final red = _fill(Colors.red.shade700);
    canvas.drawRect(Rect.fromLTWH(cx - r, bodyCy - r, r / 2, r * 2), red);
    canvas.drawRect(Rect.fromLTWH(cx, bodyCy - r, r / 2, r * 2), red);
    canvas.restore();
    // Garis tepi abu-abu (putih tidak terlihat di badan putih).
    canvas.drawCircle(center, r, _stroke(Colors.grey.shade700, 1.5));
  }

  void _drawSpecialPurpose(Canvas canvas, double size) {
    final cx = size / 2;
    final bodyCy = size * 0.60;
    final r = size * 0.30;
    final center = Offset(cx, bodyCy);
    // Tanda puncak: X kuning.
    final xPaint = Paint()
      ..color = Colors.yellow.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.06
      ..strokeCap = StrokeCap.round;
    final t = size * 0.09;
    final cy = size * 0.15;
    canvas.drawLine(Offset(cx - t, cy - t), Offset(cx + t, cy + t), xPaint);
    canvas.drawLine(Offset(cx + t, cy - t), Offset(cx - t, cy + t), xPaint);
    final body = Path()
      ..addOval(Rect.fromCircle(center: center, radius: r));
    _drawShape(canvas, body, Colors.yellow.shade600);
  }

  void _drawLight(Canvas canvas, double size, {required bool major}) {
    // Bintang magenta ala IHO (lampu utama: 8 ujung, lebih besar;
    // lampu kecil: 4 ujung).
    final star = _starPath(
      Offset(size / 2, size / 2),
      size * (major ? 0.36 : 0.30),
      size * (major ? 0.16 : 0.13),
      major ? 8 : 4,
    );
    _drawShape(canvas, star, const Color(0xFFC2185B));
  }

  void _drawLandmark(Canvas canvas, double size) {
    final cx = size / 2;
    final tri = _triangle(
      Offset(cx, size * 0.10),
      Offset(cx - size * 0.30, size * 0.80),
      Offset(cx + size * 0.30, size * 0.80),
    );
    _drawShape(canvas, tri, Colors.brown.shade600);
  }

  void _drawOther(Canvas canvas, double size) {
    final diamond = _diamond(Offset(size / 2, size / 2), size * 0.30);
    _drawShape(canvas, diamond, Colors.grey.shade600);
  }

  @override
  bool shouldRepaint(covariant _SeamarkSymbolPainter oldDelegate) =>
      oldDelegate.seamark.id != seamark.id ||
      oldDelegate.seamark.kind != seamark.kind;
}
