import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../utils/result.dart';
import '../local/app_database.dart';
import '../services/gebco_service.dart';

/// Kedalaman GEBCO per titik (pembulatan 0.01° ~1 km, TTL 30 hari —
/// batimetri praktis tidak berubah). Stale fallback bila fetch gagal.
class DepthRepository {
  DepthRepository({required AppDatabase db, GebcoService? service})
      : _db = db,
        _service = service ?? GebcoService();

  final AppDatabase _db;
  final GebcoService _service;

  static const _ttl = Duration(days: 30);

  String _key(double lat, double lon) =>
      'depth|${lat.toStringAsFixed(2)}|${lon.toStringAsFixed(2)}';

  /// Kunci label per titik (dipakai overlay label kedalaman):
  /// dibulatkan 0,0001° (~11 m) agar satu titik selalu memetakan
  /// ke satu entri label.
  static String labelKey(double lat, double lon) =>
      '${lat.toStringAsFixed(4)}|${lon.toStringAsFixed(4)}';

  /// Kedalaman banyak titik sekaligus (label kedalaman di peta).
  /// GetFeatureInfo GEBCO hanya melayani satu titik per request —
  /// tidak ada endpoint batch — jadi strategi hematnya: request
  /// paralel terbatas (`concurrency`, default 4) + cache 30 hari
  /// per titik (lihat [getDepth]) sehingga area yang pernah dibuka
  /// tidak memicu request lagi. Titik yang gagal -> null (labelnya
  /// dilewati, bukan angka 0).
  ///
  /// `onBatch` (F-L10): dipanggil tiap satu batch selesai agar
  /// pemanggil bisa menampilkan label SECARA PROGRESIF per batch
  /// (tanpa ini, area baru kosong ~10 detik sampai SEMUA titik
  /// selesai). Nilai kembalian tetap berisi semua hasil.
  Future<Map<String, DepthResult?>> getDepths(
    List<LatLng> points, {
    int concurrency = 4,
    void Function(Map<String, DepthResult?> batch)? onBatch,
  }) async {
    final results = <String, DepthResult?>{};
    final batchSize = concurrency < 1 ? 1 : concurrency;
    for (var i = 0; i < points.length; i += batchSize) {
      final chunk = points.sublist(
        i,
        math.min(i + batchSize, points.length),
      );
      final fetched = await Future.wait(chunk.map(
        (p) => getDepth(latitude: p.latitude, longitude: p.longitude),
      ));
      final batch = <String, DepthResult?>{};
      for (var j = 0; j < chunk.length; j++) {
        final p = chunk[j];
        batch[labelKey(p.latitude, p.longitude)] = switch (fetched[j]) {
          Ok(value: final depth) => depth,
          Error() => null,
        };
      }
      results.addAll(batch);
      onBatch?.call(batch);
    }
    return results;
  }

  Future<Result<DepthResult>> getDepth({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final key = _key(latitude, longitude);
    if (!forceRefresh) {
      final cached = await _readCache(key, latitude, longitude);
      if (cached != null) return Result.ok(cached);
    }
    final result = await _service.fetchDepth(
      latitude: latitude,
      longitude: longitude,
    );
    switch (result) {
      case Ok(value: final depth):
        await _writeCache(key, depth);
        return Result.ok(depth);
      case Error(error: final error):
        final cached =
            await _readCache(key, latitude, longitude, ignoreTtl: true);
        if (cached != null) return Result.ok(cached);
        return Result.error(error);
    }
  }

  Future<DepthResult?> _readCache(
    String key,
    double latitude,
    double longitude, {
    bool ignoreTtl = false,
  }) async {
    final cached = await _db.getCached(key);
    if (cached == null) return null;
    if (!ignoreTtl &&
        DateTime.now().difference(cached.fetchedAt) >= _ttl) {
      return null;
    }
    try {
      final decoded = jsonDecode(cached.payload);
      if (decoded is! Map<String, dynamic>) return null;
      final elevation = decoded['elevationM'];
      if (elevation is! num) return null;
      return DepthResult(
        latitude: latitude,
        longitude: longitude,
        elevationM: elevation.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, DepthResult depth) async {
    try {
      await _db.putCached(
        key: key,
        scope: 'depth',
        payload: jsonEncode({'elevationM': depth.elevationM}),
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      // Cache gagal ditulis — data tetap dipakai.
    }
  }
}
