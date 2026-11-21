import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/offline_area.dart';
import '../../utils/tile_math.dart';
import '../services/offline_tile_service.dart';

/// Wilayah peta tersimpan (offline, R-32/R-33): metadata area di
/// SharedPreferences (JSON) + file tile via OfflineTileService.
/// Juga: cek status online (DNS lookup singkat) untuk banner offline.
class OfflineRepository {
  OfflineRepository({
    required SharedPreferences prefs,
    OfflineTileService? tileService,
  })  : _prefs = prefs,
        _tileService = tileService ?? OfflineTileService();

  final SharedPreferences _prefs;
  final OfflineTileService _tileService;

  static const _keyAreas = 'saved_areas';

  List<SavedArea> get areas {
    final raw = _prefs.getString(_keyAreas);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedArea.fromJson)
          .where((a) => a.id.isNotEmpty)
          .toList();
      list.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _persistAreas(List<SavedArea> areas) async {
    await _prefs.setString(
      _keyAreas,
      jsonEncode(areas.map((a) => a.toJson()).toList()),
    );
  }

  /// Unduh tile area yang tampil di layar (zoom saat ini saja).
  /// Stream kemajuan; metadata ditulis setelah unduh selesai.
  /// Mengembalikan area yang tersimpan (null bila 0 tile berhasil).
  Stream<SaveProgress> saveArea({
    required String id,
    required String name,
    required double centerLat,
    required double centerLon,
    required TileRange range,
    required String basemap,
    required String urlTemplate,
  }) async* {
    SaveProgress? last;
    await for (final progress in _tileService.downloadArea(
      areaId: id,
      basemap: basemap,
      range: range,
      urlTemplate: urlTemplate,
    )) {
      last = progress;
      yield progress;
    }
    final finalProgress = last;
    if (finalProgress == null) return;
    final saved = finalProgress.done - finalProgress.failed;
    if (saved <= 0) {
      // Tidak ada satu pun tile berhasil — jangan catat area palsu.
      await _tileService.deleteAreaFiles(id);
      return;
    }
    final size = await _tileService.areaSizeBytes(id);
    final area = SavedArea(
      id: id,
      name: name,
      centerLat: centerLat,
      centerLon: centerLon,
      zoom: range.zoom,
      basemap: basemap,
      tileCount: saved,
      sizeBytes: size,
      savedAt: DateTime.now(),
      failedTiles: finalProgress.failed,
    );
    final list = areas.where((a) => a.id != id).toList()..add(area);
    await _persistAreas(list);
  }

  /// Hapus satu area (metadata + file tile).
  Future<void> deleteArea(String id) async {
    await _tileService.deleteAreaFiles(id);
    final list = areas.where((a) => a.id != id).toList();
    await _persistAreas(list);
  }

  /// Jalur file tile tersimpan untuk basemap + koordinat tile tertentu.
  /// Dicari di semua area (biasanya sedikit). null bila tidak ada.
  /// Dipakai SavedAreaTileProvider (sinkron per render — file check
  /// memakai existsSync agar tidak ada await di jalur render).
  String? localTilePath({
    required String basemap,
    required int z,
    required int x,
    required int y,
  }) {
    final baseDir = _cachedBaseDir;
    if (baseDir == null) return null;
    final ext = OfflineTileService.extensionForBasemap(basemap);
    for (final area in areas) {
      if (area.basemap != basemap || area.zoom != z) continue;
      final path =
          '$baseDir/${area.id}/$basemap/$z/$x/$y.$ext';
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  String? _cachedBaseDir;

  /// Direktori dasar area offline — diisi sekali saat aplikasi mulai
  /// (dipanggil dari MapScreen.initState agar localTilePath sinkron).
  Future<void> warmUpBaseDir() async {
    if (_cachedBaseDir != null) return;
    // Memakai tileFilePath satu kali untuk memicu pembuatan direktori
    // tidaklah cukup; hitung langsung dari path_provider.
    try {
      final docs = await _tileService.areasDirPath();
      _cachedBaseDir = docs;
    } catch (_) {
      _cachedBaseDir = null;
    }
  }

  /// Cek online: DNS lookup singkat ke host tile. true = online.
  Future<bool> checkOnline() async {
    try {
      final result = await InternetAddress.lookup('tile.openstreetmap.de')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
