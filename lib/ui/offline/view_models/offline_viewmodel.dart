import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/repositories/offline_repository.dart';
import '../../../data/services/offline_tile_service.dart';
import '../../../domain/models/offline_area.dart';
import '../../../utils/tile_math.dart';
import '../../core/widgets/notice_banner.dart';

/// ViewModel offline (R-32/R-33): wilayah tersimpan, simpan area
/// yang tampil, status online/offline.
class OfflineViewModel extends ChangeNotifier {
  OfflineViewModel({
    required OfflineRepository repository,
    required NoticeController noticeController,
  })  : _repository = repository,
        _noticeController = noticeController {
    _areas = _repository.areas;
  }

  final OfflineRepository _repository;
  final NoticeController _noticeController;

  List<SavedArea> _areas = [];
  bool _isOnline = true;
  bool _checkingOnline = false;
  bool _saving = false;
  SaveProgress? _saveProgress;
  String? _saveError;
  Timer? _onlineTimer;
  bool _pollingStarted = false;

  List<SavedArea> get areas => _areas;
  bool get isOnline => _isOnline;
  bool get checkingOnline => _checkingOnline;
  bool get saving => _saving;
  SaveProgress? get saveProgress => _saveProgress;
  String? get saveError => _saveError;

  /// Badge status area saat ini: tersimpan / belum (untuk panel offline).
  bool isAreaSaved({
    required double centerLat,
    required double centerLon,
    required int zoom,
    required String basemap,
  }) {
    for (final area in _areas) {
      if (area.zoom != zoom || area.basemap != basemap) continue;
      // Pusat dalam ~0.05 derajat dianggap area yang sama.
      if ((area.centerLat - centerLat).abs() < 0.05 &&
          (area.centerLon - centerLon).abs() < 0.05) {
        return true;
      }
    }
    return false;
  }

  /// Mulai polling status online tiap 30 detik (dari MapScreen).
  void startOnlinePolling() {
    if (_pollingStarted) return;
    _pollingStarted = true;
    unawaited(checkOnline());
    _onlineTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(checkOnline()),
    );
  }

  Future<void> checkOnline() async {
    if (_checkingOnline) return;
    _checkingOnline = true;
    final online = await _repository.checkOnline();
    final changed = online != _isOnline;
    _isOnline = online;
    _checkingOnline = false;
    if (changed) {
      _noticeController.show(
        online ? 'Kembali online.' : 'Offline — peta tersimpan tetap bisa dilihat.',
      );
    }
    notifyListeners();
  }

  void refreshAreas() {
    _areas = _repository.areas;
    notifyListeners();
  }

  /// Simpan area yang tampil di layar (zoom saat ini saja).
  /// Menolak bila tile melebihi batas (400) — user harus zoom-in dulu.
  Future<void> saveCurrentArea({
    required LatLngBounds bounds,
    required double zoom,
    required String basemap,
    required String urlTemplate,
    required String name,
  }) async {
    if (_saving) return;
    final z = zoom.round().clamp(3, 19);
    final range = TileMath.rangeForBounds(
      south: bounds.southWest.latitude,
      west: bounds.southWest.longitude,
      north: bounds.northEast.latitude,
      east: bounds.northEast.longitude,
      zoom: z,
    );
    if (range.count > OfflineTileService.maxTilesPerArea) {
      _saveError =
          'Area terlalu luas (${range.count} tile, maks ${OfflineTileService.maxTilesPerArea}). '
          'Perbesar peta (zoom in) lalu coba lagi.';
      notifyListeners();
      return;
    }
    if (!_isOnline) {
      _saveError =
          'Tidak ada internet — area tidak dapat diunduh sekarang.';
      notifyListeners();
      return;
    }
    _saving = true;
    _saveError = null;
    _saveProgress = const SaveProgress(done: 0, total: 0, failed: 0, bytes: 0);
    notifyListeners();
    final id = 'area_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await for (final progress in _repository.saveArea(
        id: id,
        name: name,
        centerLat: (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
        centerLon:
            (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
        range: range,
        basemap: basemap,
        urlTemplate: urlTemplate,
      )) {
        _saveProgress = progress;
        notifyListeners();
      }
    } catch (e) {
      _saveError = 'Gagal menyimpan area: $e';
    }
    _saving = false;
    refreshAreas();
    final saved = _areas.where((a) => a.id == id).toList();
    if (saved.isNotEmpty) {
      final area = saved.first;
      _noticeController.show(
        'Area "${area.name}" tersimpan (${area.tileCount} tile, ${area.sizeLabel}).',
      );
    } else if (_saveError == null) {
      _saveError = 'Tidak ada tile yang berhasil diunduh. Coba lagi nanti.';
    }
    notifyListeners();
  }

  Future<void> deleteArea(String id) async {
    await _repository.deleteArea(id);
    refreshAreas();
    _noticeController.show('Wilayah tersimpan dihapus.');
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    super.dispose();
  }
}
