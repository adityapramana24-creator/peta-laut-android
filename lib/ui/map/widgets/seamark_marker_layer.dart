import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../data/services/seamark_service.dart';
import '../../../domain/models/seamark.dart';
import '../../core/widgets/notice_banner.dart';
import '../../core/widgets/seamark_marker.dart';
import 'seamark_sheet.dart';

/// Lapisan marker rambu laut (ronde 2, butir 20): marker simbol per
/// kategori dari tag seamark OpenStreetMap (via Overpass API), bisa
/// ditekan untuk lembar detail. Pola mengikuti DepthLabelsOverlay:
/// fetch per bbox terlihat + debounce + fetch ulang hanya bila kamera
/// bergeser jauh.
///
/// Hemat request (user di kapal, koneksi terbatas):
/// - hanya zoom >= 12 (SeamarkService.minZoom);
/// - debounce 1,5 dtk setelah kamera berhenti bergerak;
/// - fetch ulang hanya bila tengah peta bergeser >25% span atau
///   zoom berubah >= 0,5;
/// - cache service TTL 7 hari (area yang pernah dibuka tidak
///   memicu request lagi).
///
/// Pesan jujur (lewat NoticeController satu slot, hanya saat
/// TRANSISI + throttle 60 dtk agar tidak spam tiap geser peta):
/// - bbox kosong -> "Tidak ada data rambu di area ini
///   (OpenStreetMap)" — BUKAN error;
/// - semua endpoint gagal -> "Data rambu tidak bisa dimuat — coba
///   lagi nanti" (data lama tetap tampil, bukan peta kosong).
/// Marker diputar mengikuti rotasi peta agar tanda puncak kardinal
/// (yang menunjuk utara) tetap benar saat peta berputar.
class SeamarkMarkerLayer extends StatefulWidget {
  const SeamarkMarkerLayer({
    super.key,
    required this.service,
    required this.bounds,
    required this.zoom,
    required this.centerLat,
    required this.centerLon,
    required this.rotationDeg,
    required this.enabled,
  });

  final SeamarkService service;
  final LatLngBounds? bounds;
  final double zoom;
  final double centerLat;
  final double centerLon;
  final double rotationDeg;
  final bool enabled;

  @override
  State<SeamarkMarkerLayer> createState() => _SeamarkMarkerLayerState();
}

class _SeamarkMarkerLayerState extends State<SeamarkMarkerLayer> {
  static const _debounce = Duration(milliseconds: 1500);
  static const _noticeThrottle = Duration(seconds: 60);

  List<Seamark> _seamarks = const [];
  Timer? _timer;
  int _generation = 0;
  LatLng? _fetchedCenter;
  double? _fetchedZoom;

  /// Status fetch terakhir — pesan hanya tampil saat TRANSISI
  /// (masuk area kosong / mulai gagal), bukan tiap fetch.
  bool _lastWasEmpty = false;
  bool _lastWasError = false;
  DateTime? _lastNoticeAt;
  String? _lastNoticeMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeSchedule();
    });
  }

  @override
  void didUpdateWidget(SeamarkMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _timer?.cancel();
      if (_seamarks.isNotEmpty) {
        setState(() {
          _seamarks = const [];
        });
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
        widget.zoom < SeamarkService.minZoom) {
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
        widget.zoom < SeamarkService.minZoom) {
      return;
    }
    final generation = ++_generation;
    _fetchedCenter = LatLng(widget.centerLat, widget.centerLon);
    _fetchedZoom = widget.zoom;
    final result = await widget.service.fetchSeamarks(
      south: bounds.southWest.latitude,
      west: bounds.southWest.longitude,
      north: bounds.northEast.latitude,
      east: bounds.northEast.longitude,
    );
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Ok(value: final seamarks):
        final wasEmpty = seamarks.isEmpty;
        if (wasEmpty && !_lastWasEmpty) {
          _maybeNotice(SeamarkService.emptyMessage);
        }
        _lastWasEmpty = wasEmpty;
        _lastWasError = false;
        setState(() {
          _seamarks = seamarks;
        });
      case Error():
        // Data lama dipertahankan (lebih baik daripada peta kosong).
        if (!_lastWasError) {
          _maybeNotice(SeamarkService.loadFailedMessage);
        }
        _lastWasError = true;
    }
  }

  void _maybeNotice(String message) {
    final now = DateTime.now();
    if (message == _lastNoticeMessage &&
        _lastNoticeAt != null &&
        now.difference(_lastNoticeAt!) < _noticeThrottle) {
      return;
    }
    _lastNoticeMessage = message;
    _lastNoticeAt = now;
    if (!mounted) return;
    context.read<NoticeController>().show(message);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled ||
        widget.bounds == null ||
        widget.zoom < SeamarkService.minZoom ||
        _seamarks.isEmpty) {
      return MarkerLayer(markers: const []);
    }
    // Ukuran mengikuti zoom (12 -> 24 px, 16 ke atas -> 32 px).
    final size = (24.0 + (widget.zoom - SeamarkService.minZoom) * 2)
        .clamp(24.0, 32.0);
    return MarkerLayer(
      markers: _seamarks
          .map(
            (seamark) => Marker(
              point: LatLng(seamark.latitude, seamark.longitude),
              width: size,
              height: size,
              child: GestureDetector(
                onTap: () => showSeamarkSheet(context, seamark),
                child: Transform.rotate(
                  // Tanda puncak kardinal menunjuk utara — putar
                  // mengikuti rotasi peta (pola yang sama dengan
                  // marker kapal AIS).
                  angle: widget.rotationDeg * math.pi / 180,
                  child: SeamarkMarker(seamark: seamark, size: size),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
