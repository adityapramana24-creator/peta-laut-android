import 'dart:convert';

import '../../domain/models/marine.dart';
import '../../utils/result.dart';
import '../local/app_database.dart';
import '../services/open_meteo_service.dart';

/// Gelombang Open-Meteo Marine per titik (pembulatan 0.05°, TTL 6 jam).
/// Stale fallback bila fetch gagal.
class MarineRepository {
  MarineRepository({required AppDatabase db, OpenMeteoService? service})
      : _db = db,
        _service = service ?? OpenMeteoService();

  final AppDatabase _db;
  final OpenMeteoService _service;

  static const _ttl = Duration(hours: 6);

  String _key(double lat, double lon) =>
      'marine|${(lat * 20).round() / 20}|${(lon * 20).round() / 20}';

  Future<Result<MarineForecast>> getMarine({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final key = _key(latitude, longitude);
    if (!forceRefresh) {
      final cached = await _readCache(key);
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < _ttl) {
        return Result.ok(cached);
      }
    }
    final result = await _service.fetchMarine(
      latitude: latitude,
      longitude: longitude,
    );
    switch (result) {
      case Ok(value: final forecast):
        await _writeCache(key, forecast);
        return Result.ok(forecast);
      case Error(error: final error):
        final cached = await _readCache(key);
        if (cached != null) {
          return Result.ok(cached.copyWith(isStale: true));
        }
        return Result.error(error);
    }
  }

  Future<MarineForecast?> _readCache(String key) async {
    final cached = await _db.getCached(key);
    if (cached == null) return null;
    try {
      final decoded = jsonDecode(cached.payload);
      if (decoded is! Map<String, dynamic>) return null;
      return MarineForecast.fromCacheJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, MarineForecast forecast) async {
    try {
      await _db.putCached(
        key: key,
        scope: 'marine',
        payload: jsonEncode(forecast.toJson()),
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      // Cache gagal ditulis — data tetap dipakai.
    }
  }
}
