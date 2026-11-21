import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/windy.dart';
import '../../../utils/map_projection.dart';
import 'wind_legend.dart';

/// Overlay partikel angin animasi di atas peta (paket Windy, R-30).
/// Partikel bergerak mengikuti grid angin (interpolasi bilinear) dan
/// meninggalkan JEJAK (5 segmen) agar bentuk aliran terlihat —
/// gaya Windy: gerakan + arah terbaca dari streak, kecepatan dari
/// warna garis (lihat [WindColorScale]) dan panjang jejak.
/// Kecepatan tampilan diperbesar agar gerakan terlihat — ini
/// visualisasi arah/kekuatan angin, bukan simulasi fisik.
/// IgnorePointer: gesture peta tetap jalan.
///
/// Diagnosis ronde 2 (kenapa dulu "ga keliatan bentuknya"):
/// (1) tiap partikel hanya 1 segmen 1-frame (maks ~2 px pada angin
/// 10 m/s; pada angin tropis 5 km/jam hanya 0,28 px/frame sehingga
/// DISARING aturan <0,5 px dan tidak digambar sama sekali);
/// (2) warna monokrom (putih + biru tua) tanpa skala kecepatan;
/// (3) grid 5x4 / 8° terlalu kasar — seluruh partikel bergerak
/// hampir seragam; (4) di zoom ASEAN grid hanya menutupi 14° tengah.
class WindParticlesOverlay extends StatefulWidget {
  const WindParticlesOverlay({
    super.key,
    required this.grid,
    required this.hourIndex,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.rotationDeg,
  });

  final WindGrid grid;
  final int hourIndex;
  final double centerLat;
  final double centerLon;
  final double zoom;
  final double rotationDeg;

  @override
  State<WindParticlesOverlay> createState() => _WindParticlesOverlayState();
}

class _Particle {
  _Particle({
    required this.lat,
    required this.lon,
    required this.maxAge,
  });

  double lat;
  double lon;
  double speedKmh = 0;
  int age = 0;
  final int maxAge;

  /// Jejak posisi terakhir (lat/lon), kepala di akhir daftar.
  final List<double> trailLat = [];
  final List<double> trailLon = [];
}

class _WindParticlesOverlayState extends State<WindParticlesOverlay> {
  static const _count = 220;
  static const _tick = Duration(milliseconds: 50);

  /// Panjang jejak (titik). 6 titik = 5 segmen: pada langkah minimum
  /// 1,2 px/frame jejak ~6 px; pada 50 km/jam ~29 px.
  static const _trailLength = 6;

  /// Langkah layar minimum per frame (px): angin lemah pun tetap
  /// menunjukkan arah. Di atas ini langkah sebanding kecepatan
  /// (0,35 px per m/s per frame).
  static const _minStepPx = 1.2;
  static const _pxPerMs = 0.35;

  final _random = math.Random();
  final _particles = <_Particle>[];
  Timer? _timer;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) => _step());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _seed() {
    _particles.clear();
    for (var i = 0; i < _count; i++) {
      _particles.add(_randomParticle());
    }
  }

  _Particle _randomParticle() {
    final (lat1, lon1) = MapProjection.screenToLatLon(
      screenX: 0,
      screenY: 0,
      centerLat: widget.centerLat,
      centerLon: widget.centerLon,
      zoom: widget.zoom,
      rotationDeg: widget.rotationDeg,
      screenWidth: _size.width,
      screenHeight: _size.height,
    );
    final (lat2, lon2) = MapProjection.screenToLatLon(
      screenX: _size.width,
      screenY: _size.height,
      centerLat: widget.centerLat,
      centerLon: widget.centerLon,
      zoom: widget.zoom,
      rotationDeg: widget.rotationDeg,
      screenWidth: _size.width,
      screenHeight: _size.height,
    );
    var minLat = math.min(lat1, lat2);
    var maxLat = math.max(lat1, lat2);
    var minLon = math.min(lon1, lon2);
    var maxLon = math.max(lon1, lon2);
    // Batasi ke dalam grid angin (irisan dengan area tampil): di luar
    // grid tidak ada data — partikel di sana akan menampilkan angin
    // tepi yang menyesatkan.
    final grid = widget.grid;
    minLat = math.max(minLat, grid.south);
    maxLat = math.min(maxLat, grid.north);
    minLon = math.max(minLon, grid.west);
    maxLon = math.min(maxLon, grid.east);
    if (maxLat <= minLat || maxLon <= minLon) {
      // Layar tidak beririsan dengan grid — pakai tengah grid.
      minLat = maxLat = (grid.south + grid.north) / 2;
      minLon = maxLon = (grid.west + grid.east) / 2;
    }
    return _Particle(
      lat: minLat + _random.nextDouble() * (maxLat - minLat),
      lon: minLon + _random.nextDouble() * (maxLon - minLon),
      maxAge: 40 + _random.nextInt(80),
    );
  }

  void _step() {
    if (_size.isEmpty || !mounted) return;
    if (_particles.isEmpty) _seed();
    final grid = widget.grid;
    final hourIndex = widget.hourIndex;
    for (var i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      p.age++;
      // Keluar grid -> respawn (di luar grid tidak ada data angin).
      final outsideGrid = p.lat < grid.south ||
          p.lat > grid.north ||
          p.lon < grid.west ||
          p.lon > grid.east;
      final wind = outsideGrid ? null : grid.windAt(p.lat, p.lon, hourIndex);
      var respawn = wind == null || p.age > p.maxAge;
      if (!respawn) {
        final speedKmh = wind.$1;
        final dirFromDeg = wind.$2;
        p.speedKmh = speedKmh;
        final speedMs = speedKmh / 3.6;
        if (speedMs > 0.05) {
          // Komponen gerak udara (arah MENUJU = dari + 180).
          final dirRad = dirFromDeg * math.pi / 180;
          final uMs = -speedMs * math.sin(dirRad); // ke timur
          final vMs = -speedMs * math.cos(dirRad); // ke utara
          // Langkah layar: minimal 1,2 px/frame (arah tetap terbaca
          // pada angin lemah), selebihnya sebanding kecepatan.
          // Dikonversi ke meter lewat pxPerMeter agar langkah layar
          // konsisten di semua zoom.
          final latRad = p.lat * math.pi / 180;
          final pxPerMeter = 256 * math.pow(2, widget.zoom) /
              40075016 /
              math.cos(latRad).clamp(0.2, 1.0);
          final stepPx = math.max(_minStepPx, speedMs * _pxPerMs);
          final stepMeters = stepPx / pxPerMeter;
          final dMetersEast = uMs / speedMs * stepMeters;
          final dMetersNorth = vMs / speedMs * stepMeters;
          p.lat += dMetersNorth / 111320.0;
          p.lon += dMetersEast / (111320.0 * math.cos(latRad));
        }
        // Perpanjang jejak dengan posisi terbaru.
        p.trailLat.add(p.lat);
        p.trailLon.add(p.lon);
        while (p.trailLat.length > _trailLength) {
          p.trailLat.removeAt(0);
          p.trailLon.removeAt(0);
        }
        // Keluar layar -> respawn.
        final (x, y) = MapProjection.latLonToScreen(
          latitude: p.lat,
          longitude: p.lon,
          centerLat: widget.centerLat,
          centerLon: widget.centerLon,
          zoom: widget.zoom,
          rotationDeg: widget.rotationDeg,
          screenWidth: _size.width,
          screenHeight: _size.height,
        );
        if (x < -20 ||
            x > _size.width + 20 ||
            y < -20 ||
            y > _size.height + 20) {
          respawn = true;
        }
      }
      if (respawn) {
        _particles[i] = _randomParticle();
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _size) {
            _size = size;
            _particles.clear();
          }
          return CustomPaint(
            size: size,
            painter: _ParticlesPainter(
              particles: _particles,
              centerLat: widget.centerLat,
              centerLon: widget.centerLon,
              zoom: widget.zoom,
              rotationDeg: widget.rotationDeg,
              screenSize: size,
            ),
          );
        },
      ),
    );
  }
}

class _ParticlesPainter extends CustomPainter {
  const _ParticlesPainter({
    required this.particles,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.rotationDeg,
    required this.screenSize,
  });

  final List<_Particle> particles;
  final double centerLat;
  final double centerLon;
  final double zoom;
  final double rotationDeg;
  final Size screenSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.trailLat.length < 2) continue;
      // Proyeksikan seluruh jejak ke layar sekali jalan.
      final points = <Offset>[];
      for (var i = 0; i < p.trailLat.length; i++) {
        final (x, y) = MapProjection.latLonToScreen(
          latitude: p.trailLat[i],
          longitude: p.trailLon[i],
          centerLat: centerLat,
          centerLon: centerLon,
          zoom: zoom,
          rotationDeg: rotationDeg,
          screenWidth: screenSize.width,
          screenHeight: screenSize.height,
        );
        points.add(Offset(x, y));
      }
      final color = WindColorScale.colorForKmh(p.speedKmh);
      final segments = points.length - 1;
      // Dua pass: halo putih di bawah (terbaca di basemap gelap
      // maupun terang), garis warna di atas (kecepatan terbaca).
      for (var pass = 0; pass < 2; pass++) {
        final isHalo = pass == 0;
        for (var i = 0; i < segments; i++) {
          final a = points[i];
          final b = points[i + 1];
          if ((b.dx - a.dx).abs() < 0.5 &&
              (b.dy - a.dy).abs() < 0.5) {
            continue;
          }
          // Ekor memudar, kepala paling terang.
          final fade = (i + 1) / segments;
          final alpha = isHalo ? 0.35 * fade : 0.9 * (0.35 + 0.65 * fade);
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = (isHalo ? Colors.white : color)
                  .withValues(alpha: alpha)
              ..strokeWidth = isHalo ? 4.0 : 2.2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter oldDelegate) => true;
}
