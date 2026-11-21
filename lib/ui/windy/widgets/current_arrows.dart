import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/windy.dart';
import '../../../utils/map_projection.dart';
import '../../../utils/nav_math.dart';
import 'wind_legend.dart';

/// Overlay panah arus di atas peta (ronde 2, item 4b): satu panah
/// di tiap titik grid arus, menunjuk ke arah arus MENGALIR
/// (konvensi Open-Meteo: ocean_current_direction = arah MENUJU),
/// berwarna menurut kecepatan (lihat [CurrentColorScale]).
/// Panjang panah tetap (kecepatan dibaca dari warna, gaya Windy);
/// titik tanpa data (darat) tidak digambar.
/// IgnorePointer: gesture peta tetap jalan.
class CurrentArrowsOverlay extends StatelessWidget {
  const CurrentArrowsOverlay({
    super.key,
    required this.grid,
    required this.hourIndex,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.rotationDeg,
  });

  final CurrentGrid grid;
  final int hourIndex;
  final double centerLat;
  final double centerLon;
  final double zoom;
  final double rotationDeg;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return CustomPaint(
            size: size,
            painter: _CurrentArrowsPainter(
              grid: grid,
              hourIndex: hourIndex,
              centerLat: centerLat,
              centerLon: centerLon,
              zoom: zoom,
              rotationDeg: rotationDeg,
              screenSize: size,
            ),
          );
        },
      ),
    );
  }
}

class _CurrentArrowsPainter extends CustomPainter {
  const _CurrentArrowsPainter({
    required this.grid,
    required this.hourIndex,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.rotationDeg,
    required this.screenSize,
  });

  final CurrentGrid grid;
  final int hourIndex;
  final double centerLat;
  final double centerLon;
  final double zoom;
  final double rotationDeg;
  final Size screenSize;

  /// Panjang batang panah di layar (px) + kepala panah (px).
  static const double _shaftPx = 16;
  static const double _headPx = 7;

  /// Di bawah ini dianggap tenang: gambar titik, bukan panah
  /// (arah tidak bermakna pada arus ~0).
  static const double _calmKnots = 0.1;

  @override
  void paint(Canvas canvas, Size size) {
    for (final point in grid.points) {
      if (hourIndex < 0 || hourIndex >= point.velocityKmh.length) continue;
      final speedKmh = point.velocityKmh[hourIndex];
      final dirDeg = point.directionDeg[hourIndex];
      if (speedKmh == null || dirDeg == null) continue;

      final (x, y) = MapProjection.latLonToScreen(
        latitude: point.latitude,
        longitude: point.longitude,
        centerLat: centerLat,
        centerLon: centerLon,
        zoom: zoom,
        rotationDeg: rotationDeg,
        screenWidth: screenSize.width,
        screenHeight: screenSize.height,
      );
      // Di luar layar -> lewati.
      if (x < -24 ||
          x > screenSize.width + 24 ||
          y < -24 ||
          y > screenSize.height + 24) {
        continue;
      }

      final knots = NavMath.kmhToKnots(speedKmh);
      final color = CurrentColorScale.colorForKnots(knots);
      final origin = Offset(x, y);

      if (knots < _calmKnots) {
        // Tenang: titik kecil (data ada, arus ~0).
        canvas.drawCircle(
          origin,
          3.5,
          Paint()..color = Colors.white.withValues(alpha: 0.8),
        );
        canvas.drawCircle(
          origin,
          2.0,
          Paint()..color = color,
        );
        continue;
      }

      // Titik kepala: geser sepanjang arah aliran sejauh _shaftPx.
      // Dihitung lewat lat/lon agar rotasi peta + proyeksi otomatis
      // benar (bukan sekadar putar vektor layar).
      final latRad = point.latitude * math.pi / 180;
      final pxPerMeter = 256 * math.pow(2, zoom) /
          40075016 /
          math.cos(latRad).clamp(0.2, 1.0);
      final dMeters = _shaftPx / pxPerMeter;
      final dirRad = dirDeg * math.pi / 180;
      final headLat =
          point.latitude + math.cos(dirRad) * dMeters / 111320.0;
      final headLon = point.longitude +
          math.sin(dirRad) * dMeters / (111320.0 * math.cos(latRad));
      final (hx, hy) = MapProjection.latLonToScreen(
        latitude: headLat,
        longitude: headLon,
        centerLat: centerLat,
        centerLon: centerLon,
        zoom: zoom,
        rotationDeg: rotationDeg,
        screenWidth: screenSize.width,
        screenHeight: screenSize.height,
      );
      final head = Offset(hx, hy);
      final shaft = head - origin;
      final len = shaft.distance;
      if (len < 1) continue;
      final unit = shaft / len;
      // Kepala panah: dua garis 150° dari batang.
      final headAngle = math.pi / 6; // 30° dari sumbu batang
      final left = head -
          Offset(
            unit.dx * math.cos(headAngle) - unit.dy * math.sin(headAngle),
            unit.dx * math.sin(headAngle) + unit.dy * math.cos(headAngle),
          ) *
              _headPx;
      final right = head -
          Offset(
            unit.dx * math.cos(-headAngle) -
                unit.dy * math.sin(-headAngle),
            unit.dx * math.sin(-headAngle) +
                unit.dy * math.cos(-headAngle),
          ) *
              _headPx;

      // Halo putih (terbaca di basemap apa pun), lalu panah warna.
      final halo = Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;
      final pen = Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(origin, head, halo);
      canvas.drawLine(head, left, halo);
      canvas.drawLine(head, right, halo);
      canvas.drawLine(origin, head, pen);
      canvas.drawLine(head, left, pen);
      canvas.drawLine(head, right, pen);
    }
  }

  @override
  bool shouldRepaint(_CurrentArrowsPainter oldDelegate) =>
      oldDelegate.grid != grid ||
      oldDelegate.hourIndex != hourIndex ||
      oldDelegate.centerLat != centerLat ||
      oldDelegate.centerLon != centerLon ||
      oldDelegate.zoom != zoom ||
      oldDelegate.rotationDeg != rotationDeg;
}
