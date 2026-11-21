import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/repositories/depth_repository.dart';
import '../../../data/services/gebco_service.dart';
import '../../../utils/map_projection.dart';

/// Logika sampling grid label kedalaman (fungsi murni — dites).
class DepthLabelSampling {
  DepthLabelSampling._();

  /// Label hanya tampil pada zoom ini ke atas: di bawah zoom 10 satu
  /// layar mencakup >60 km sehingga angka per titik tidak bermakna
  /// dan request-nya sia-sia.
  static const double minZoom = 10.0;

  /// Maksimum titik per tampilan (hemat request + layar tidak penuh).
  static const int maxPoints = 30;

  /// Target titik per tampilan pada zoom wajar.
  static const int targetPoints = 24;

  /// Jarak minimum antar titik sampling (km): grid GEBCO ~450 m —
  /// sampling lebih rapat dari itu hanya mengulang nilai yang sama.
  static const double minSpacingKm = 0.6;

  static bool shouldShow(double zoom) => zoom >= minZoom;

  /// Titik sampling di dalam [bounds]: grid adaptif — jumlah kolom/
  /// baris menyesuaikan rasio aspek tampilan agar spasi antar titik
  /// sedekat mungkin persegi (dalam km), dibatasi [maxPoints] dan
  /// [minSpacingKm]. Titik di tengah sel (bukan tepi) agar label
  /// tidak terpotong tepi layar. [] bila zoom < [minZoom].
  static List<LatLng> pointsFor({
    required LatLngBounds bounds,
    required double zoom,
  }) {
    if (zoom < minZoom) return const [];
    final latSpan =
        (bounds.northEast.latitude - bounds.southWest.latitude).abs();
    final lonSpan =
        (bounds.northEast.longitude - bounds.southWest.longitude).abs();
    if (latSpan <= 0 || lonSpan <= 0) return const [];
    final centerLat =
        (bounds.northEast.latitude + bounds.southWest.latitude) / 2;
    final latKm = latSpan * 110.57;
    final lonKm =
        lonSpan * 111.32 * math.cos(centerLat * math.pi / 180);

    var cols = (math.sqrt(targetPoints * lonKm / latKm))
        .round()
        .clamp(3, 8);
    var rows = (targetPoints / cols).round().clamp(2, 6);
    // Jangan sampling lebih rapat dari grid data. Titik di tengah
    // sel -> spasi antar titik = span/jumlah, jadi batasnya
    // floor(spanKm / 0,6) (minimum 2x2 dipertahankan).
    cols = math
        .min(cols, (lonKm / minSpacingKm).floor())
        .clamp(2, 8);
    rows = math
        .min(rows, (latKm / minSpacingKm).floor())
        .clamp(2, 6);
    while (cols * rows > maxPoints) {
      if (cols >= rows) {
        cols--;
      } else {
        rows--;
      }
    }
    final points = <LatLng>[];
    for (var r = 0; r < rows; r++) {
      final lat =
          bounds.southWest.latitude + latSpan * (r + 0.5) / rows;
      for (var c = 0; c < cols; c++) {
        final lon =
            bounds.southWest.longitude + lonSpan * (c + 0.5) / cols;
        points.add(LatLng(lat, lon));
      }
    }
    return points;
  }
}

/// Overlay angka kedalaman langsung di peta (ronde 2, item 5):
/// label angka meter gaya sounding chart di titik-titik sampling
/// grid GEBCO. JUJUR: nilai model grid ~450 m, BUKAN sounding
/// survei; titik darat / gagal fetch tidak berlabel (bukan angka 0).
///
/// Hemat request (user di kapal, koneksi terbatas):
/// - hanya zoom >= 10, maks 30 titik per tampilan;
/// - debounce 600 ms setelah kamera berhenti bergerak;
/// - fetch ulang hanya bila tengah peta bergeser >25% span atau
///   zoom berubah >= 0,5;
/// - cache memori per sesi + cache repository 30 hari per titik,
///   jadi area yang pernah dibuka tidak memicu request lagi.
/// IgnorePointer: gesture peta tetap jalan.
class DepthLabelsOverlay extends StatefulWidget {
  const DepthLabelsOverlay({
    super.key,
    required this.repository,
    required this.bounds,
    required this.zoom,
    required this.centerLat,
    required this.centerLon,
    required this.rotationDeg,
    required this.enabled,
  });

  final DepthRepository repository;
  final LatLngBounds? bounds;
  final double zoom;
  final double centerLat;
  final double centerLon;
  final double rotationDeg;
  final bool enabled;

  @override
  State<DepthLabelsOverlay> createState() => _DepthLabelsOverlayState();
}

class _DepthLabelsOverlayState extends State<DepthLabelsOverlay> {
  static const _debounce = Duration(milliseconds: 600);

  /// Cache label per sesi: kunci [DepthRepository.labelKey].
  final _labels = <String, DepthResult?>{};
  Timer? _timer;
  int _generation = 0;
  LatLng? _fetchedCenter;
  double? _fetchedZoom;

  @override
  void initState() {
    super.initState();
    // Jadwalkan fetch pertama setelah frame pertama.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeSchedule();
    });
  }

  @override
  void didUpdateWidget(DepthLabelsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _timer?.cancel();
      if (_labels.isNotEmpty) {
        _labels.clear();
        _fetchedCenter = null;
        _fetchedZoom = null;
      }
      return;
    }
    _maybeSchedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _maybeSchedule() {
    final bounds = widget.bounds;
    if (!widget.enabled ||
        bounds == null ||
        !DepthLabelSampling.shouldShow(widget.zoom)) {
      return;
    }
    final center = LatLng(widget.centerLat, widget.centerLon);
    final fetchedCenter = _fetchedCenter;
    final fetchedZoom = _fetchedZoom;
    if (fetchedCenter != null && fetchedZoom != null) {
      final latSpan =
          (bounds.northEast.latitude - bounds.southWest.latitude).abs();
      final lonSpan =
          (bounds.northEast.longitude - bounds.southWest.longitude).abs();
      final movedLat = (center.latitude - fetchedCenter.latitude).abs();
      final movedLon =
          (center.longitude - fetchedCenter.longitude).abs();
      final zoomMoved = (widget.zoom - fetchedZoom).abs() >= 0.5;
      final centerMoved =
          movedLat > latSpan * 0.25 || movedLon > lonSpan * 0.25;
      if (!zoomMoved && !centerMoved) return;
    }
    _timer?.cancel();
    _timer = Timer(_debounce, _fetch);
  }

  Future<void> _fetch() async {
    final bounds = widget.bounds;
    if (!widget.enabled ||
        bounds == null ||
        !DepthLabelSampling.shouldShow(widget.zoom)) {
      return;
    }
    final generation = ++_generation;
    final points = DepthLabelSampling.pointsFor(
      bounds: bounds,
      zoom: widget.zoom,
    );
    _fetchedCenter = LatLng(widget.centerLat, widget.centerLon);
    _fetchedZoom = widget.zoom;
    final missing = points
        .where((p) => !_labels.containsKey(
              DepthRepository.labelKey(p.latitude, p.longitude),
            ))
        .toList();
    if (missing.isEmpty) return;
    // F-L10: tampilkan progresif per batch (4 titik) — label
    // pertama muncul setelah batch pertama, bukan setelah semua
    // ≤30 titik selesai (~10 dtk di cache dingin). Penjaga
    // generasi/mounted yang sama dengan setState akhir.
    final results = await widget.repository.getDepths(
      missing,
      onBatch: (batch) {
        if (!mounted || generation != _generation) return;
        _labels.addAll(batch);
        setState(() {});
      },
    );
    if (!mounted || generation != _generation) return;
    _labels.addAll(results);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled ||
        widget.bounds == null ||
        !DepthLabelSampling.shouldShow(widget.zoom)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return CustomPaint(
            size: size,
            painter: _DepthLabelsPainter(
              labels: _labels,
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

class _DepthLabelsPainter extends CustomPainter {
  const _DepthLabelsPainter({
    required this.labels,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.rotationDeg,
    required this.screenSize,
  });

  final Map<String, DepthResult?> labels;
  final double centerLat;
  final double centerLon;
  final double zoom;
  final double rotationDeg;
  final Size screenSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in labels.entries) {
      final depth = entry.value;
      final depthM = depth?.depthM;
      // Darat (depthM null) atau gagal fetch (null) -> tanpa label.
      if (depth == null || depthM == null) continue;
      final (x, y) = MapProjection.latLonToScreen(
        latitude: depth.latitude,
        longitude: depth.longitude,
        centerLat: centerLat,
        centerLon: centerLon,
        zoom: zoom,
        rotationDeg: rotationDeg,
        screenWidth: screenSize.width,
        screenHeight: screenSize.height,
      );
      if (x < -30 ||
          x > screenSize.width + 30 ||
          y < -30 ||
          y > screenSize.height + 30) {
        continue;
      }
      // Angka meter gaya sounding chart: kecil, pil semi-transparan
      // agar terbaca tapi tidak menutupi peta.
      final textPainter = TextPainter(
        text: TextSpan(
          text: depthM.toStringAsFixed(0),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const padX = 4.0;
      const padY = 2.0;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, y),
          width: textPainter.width + padX * 2,
          height: textPainter.height + padY * 2,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
      textPainter.paint(
        canvas,
        Offset(
          x - textPainter.width / 2,
          y - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_DepthLabelsPainter oldDelegate) => true;
}
