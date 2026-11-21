import 'dart:convert';

import '../../domain/models/marine.dart';
import '../../domain/models/weather.dart';
import '../../utils/result.dart';
import '../local/app_database.dart';
import '../services/bmkg_service.dart';
import '../services/open_meteo_service.dart';

/// Cuaca: BMKG per adm4 (TTL 6 jam) + Open-Meteo Forecast per titik
/// (TTL 3 jam, model gfs/icon/ecmwf_ifs). Stale fallback pada keduanya.
class WeatherRepository {
  WeatherRepository({
    required AppDatabase db,
    BmkgService? bmkgService,
    OpenMeteoService? openMeteoService,
  })  : _db = db,
        _bmkg = bmkgService ?? BmkgService(),
        _openMeteo = openMeteoService ?? OpenMeteoService();

  final AppDatabase _db;
  final BmkgService _bmkg;
  final OpenMeteoService _openMeteo;

  static const _bmkgTtl = Duration(hours: 6);
  static const _forecastTtl = Duration(hours: 3);

  Future<Result<BmkgForecast>> getBmkg({
    required String adm4,
    bool forceRefresh = false,
  }) async {
    final key = 'bmkg|$adm4';
    if (!forceRefresh) {
      final cached = await _readBmkgCache(key);
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < _bmkgTtl) {
        return Result.ok(cached);
      }
    }
    final result = await _bmkg.fetchForecast(adm4);
    switch (result) {
      case Ok(value: final forecast):
        await _writeCache(key, 'bmkg', jsonEncode(forecast.toJson()));
        return Result.ok(forecast);
      case Error(error: final error):
        final cached = await _readBmkgCache(key);
        if (cached != null) {
          return Result.ok(cached.copyWith(isStale: true));
        }
        return Result.error(error);
    }
  }

  Future<Result<List<ForecastHour>>> getForecast({
    required double latitude,
    required double longitude,
    String model = 'auto',
    bool forceRefresh = false,
  }) async {
    final key =
        'forecast|${latitude.toStringAsFixed(2)}|${longitude.toStringAsFixed(2)}|$model';
    if (!forceRefresh) {
      final cached = await _readForecastCache(key);
      if (cached != null) return Result.ok(cached.$1);
    }
    final result = await _openMeteo.fetchForecast(
      latitude: latitude,
      longitude: longitude,
      model: model,
    );
    switch (result) {
      case Ok(value: final hours):
        await _writeCache(
          key,
          'forecast',
          jsonEncode({
            'fetchedAt': DateTime.now().toIso8601String(),
            'hours': hours.map((h) => h.toJson()).toList(),
          }),
        );
        return Result.ok(hours);
      case Error(error: final error):
        final cached = await _readForecastCache(key, ignoreTtl: true);
        if (cached != null) return Result.ok(cached.$1);
        return Result.error(error);
    }
  }

  Future<BmkgForecast?> _readBmkgCache(String key) async {
    final cached = await _db.getCached(key);
    if (cached == null) return null;
    try {
      final decoded = jsonDecode(cached.payload);
      if (decoded is! Map<String, dynamic>) return null;
      return BmkgForecast.fromCacheJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Mengembalikan (jam, fetchedAt) atau null.
  Future<(List<ForecastHour>, DateTime)?> _readForecastCache(
    String key, {
    bool ignoreTtl = false,
  }) async {
    final cached = await _db.getCached(key);
    if (cached == null) return null;
    try {
      final decoded = jsonDecode(cached.payload);
      if (decoded is! Map<String, dynamic>) return null;
      final fetchedAt = DateTime.parse(decoded['fetchedAt'] as String);
      if (!ignoreTtl &&
          DateTime.now().difference(fetchedAt) >= _forecastTtl) {
        return null;
      }
      final raw = decoded['hours'];
      if (raw is! List) return null;
      final hours = raw
          .map((h) => ForecastHour.fromJson(h as Map<String, dynamic>))
          .toList();
      return (hours, fetchedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, String scope, String payload) async {
    try {
      await _db.putCached(
        key: key,
        scope: scope,
        payload: payload,
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      // Cache gagal ditulis — data tetap dipakai.
    }
  }
}
