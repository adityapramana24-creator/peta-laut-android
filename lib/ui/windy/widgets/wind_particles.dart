import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/windy.dart';
import '../../../utils/map_projection.dart';

/// Overlay partikel angin animasi di atas peta (paket Windy, R-30).
/// Partikel bergerak mengikuti grid angin (interpolasi bilinear).
/// Kecepatan tampilan diperbesar agar gerakan terlihat — ini
/// visualisasi arah/kekuatan angin, bukan simulasi fisik.
/// IgnorePointer: gesture peta tetap jalan.
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
  })  : prevLat = lat,
        prevLon = lon;

  double lat;
  double lon;
  double prevLat;
  double prevLon;
  double speedKmh = 0;
  int age = 0;
  final int maxAge;
}

class _WindParticlesOverlayState extends State<WindParticlesOverlay> {
  static const _count = 120;
  static const _tick = Duration(milliseconds: 50);

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
        // Komponen gerak udara (arah MENUJU = dari + 180).
        final dirRad = dirFromDeg * math.pi / 180;
        final uMs = -speedMs * math.sin(dirRad); // ke timur
        final vMs = -speedMs * math.cos(dirRad); // ke utara
        // Perbesaran tampilan: angin 10 m/s -> ~2 px/frame.
        final latRad = p.lat * math.pi / 180;
        final pxPerMeter = 256 * math.pow(2, widget.zoom) /
            40075016 /
            math.cos(latRad).clamp(0.2, 1.0);
        final exaggeration = 4 / pxPerMeter;
        final dt = _tick.inMilliseconds / 1000.0;
        final dMetersEast = uMs * dt * exaggeration;
        final dMetersNorth = vMs * dt * exaggeration;
        p.prevLat = p.lat;
        p.prevLon = p.lon;
        p.lat += dMetersNorth / 111320.0;
        p.lon += dMetersEast / (111320.0 * math.cos(latRad));
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
      final (x1, y1) = MapProjection.latLonToScreen(
        latitude: p.prevLat,
        longitude: p.prevLon,
        centerLat: centerLat,
        centerLon: centerLon,
        zoom: zoom,
        rotationDeg: rotationDeg,
        screenWidth: screenSize.width,
        screenHeight: screenSize.height,
      );
      final (x2, y2) = MapProjection.latLonToScreen(
        latitude: p.lat,
        longitude: p.lon,
        centerLat: centerLat,
        centerLon: centerLon,
        zoom: zoom,
        rotationDeg: rotationDeg,
        screenWidth: screenSize.width,
        screenHeight: screenSize.height,
      );
      if ((x2 - x1).abs() < 0.5 && (y2 - y1).abs() < 0.5) continue;
      // Makin kencang makin terang.
      final alpha = (0.25 + p.speedKmh / 60).clamp(0.25, 0.9);
      // Garis putih tebal di bawah (terbaca di basemap gelap),
      // garis biru tua di atas (terbaca di basemap terang).
      canvas.drawLine(
        Offset(x1, y1),
        Offset(x2, y2),
        Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.6)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(x1, y1),
        Offset(x2, y2),
        Paint()
          ..color = const Color(0xFF1A5276).withValues(alpha: alpha)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter oldDelegate) => true;
}
