import 'dart:convert';

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
