import 'dart:convert';

import '../../domain/models/tide.dart';
import '../../utils/formatters.dart';
import '../../utils/result.dart';
import '../local/app_database.dart';
import '../services/tides_service.dart';

/// Pasang surut: cache per lokasi (2 desimal) + hari WIB.
/// Prakiraan model untuk tanggal tetap tidak berubah, jadi cache
/// hari yang sama selalu dianggap segar. Bila fetch gagal dan ada
/// cache, cache dipakai dengan penanda isStale (UI menampilkan
/// "data lama"). Kurva gagal -> interpolasi kosinus antar-ekstremum.
class TidesRepository {
  TidesRepository({required AppDatabase db, TidesService? service})
      : _db = db,
        _service = service ?? TidesService();

  final AppDatabase _db;
  final TidesService _service;

  String _key(double lat, double lon, String dateKey) =>
      'tides|${lat.toStringAsFixed(2)}|${lon.toStringAsFixed(2)}|$dateKey';

  Future<Result<TideForecast>> getTides({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final nowWib = IdFormat.toWib(DateTime.now().toUtc());
    final key = _key(latitude, longitude, IdFormat.dateKey(nowWib));

    if (!forceRefresh) {
      final cached = await _readCache(key);
      if (cached != null) return Result.ok(cached);
    }

    final (startUtc, endUtc) = TidesService.twoDayRangeUtc();
    final results = await Future.wait<Result<dynamic>>([
      _service.fetchExtrema(
        latitude: latitude,
        longitude: longitude,
        startUtc: startUtc,
        endUtc: endUtc,
      ),
      _service.fetchCurve(
        latitude: latitude,
        longitude: longitude,
        startUtc: startUtc,
        endUtc: endUtc,
      ),
    ]);
    final extremaResult = results[0] as Result<TideForecast>;
    final curveResult = results[1] as Result<List<TideCurvePoint>>;

    switch (extremaResult) {
      case Ok(value: final forecast):
        var merged = forecast;
        if (curveResult case Ok(value: final curve)) {
          merged = forecast.copyWith(curve: curve);
        }
        await _writeCache(key, merged);
        return Result.ok(merged);
      case Error(error: final error):
        // Fallback ke cache lama (bila ada) saat fetch gagal.
        final cached = await _readCache(key);
        if (cached != null) {
          return Result.ok(cached.copyWith(isStale: true));
        }
        return Result.error(error);
    }
  }

  Future<TideForecast?> _readCache(String key) async {
    final cached = await _db.getCached(key);
    if (cached == null) return null;
    try {
      final decoded = jsonDecode(cached.payload);
      if (decoded is! Map<String, dynamic>) return null;
      return TideForecast.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, TideForecast forecast) async {
    try {
      await _db.putCached(
        key: key,
        scope: 'tides',
        payload: jsonEncode(forecast.toJson()),
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      // Cache gagal ditulis — data tetap dipakai, bukan error.
    }
  }
}
