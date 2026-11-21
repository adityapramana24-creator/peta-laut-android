import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/marine.dart';
import '../../domain/models/weather_alert.dart';
import '../../domain/models/windy.dart';
import '../../utils/nav_math.dart';
import '../../utils/result.dart';
import '../services/notification_service.dart';
import '../services/wind_grid_service.dart';
import 'marine_repository.dart';
import 'weather_repository.dart';

/// Paket Windy (R-30): prakiraan titik gabungan (Forecast + Marine),
/// grid angin (cache memori 30 menit), model prakiraan, dan
/// peringatan ambang kustom (disimpan SharedPreferences).
class WindyRepository {
  WindyRepository({
    required WeatherRepository weatherRepository,
    required MarineRepository marineRepository,
    required SharedPreferences prefs,
    WindGridService? windGridService,
    NotificationService? notificationService,
  })  : _weather = weatherRepository,
        _marine = marineRepository,
        _prefs = prefs,
        _windGrid = windGridService ?? WindGridService(),
        _notifications = notificationService ?? NotificationService();

  final WeatherRepository _weather;
  final MarineRepository _marine;
  final SharedPreferences _prefs;
  final WindGridService _windGrid;
  final NotificationService _notifications;

  static const _keyModel = 'windy_model';
  static const _keyParticles = 'windy_particles';
  static const _keyAlerts = 'weather_alerts';
  static const _gridTtl = Duration(minutes: 30);

  /// Jeda minimum antar notifikasi satu peringatan (anti-spam).
  static const _alertCooldown = Duration(hours: 6);

  WindGrid? _gridCache;
  DateTime? _gridFetchedAt;
  String? _gridKey;

  // -- Preferensi model + partikel --

  WindyModel get model =>
      WindyModelInfo.fromApiValue(_prefs.getString(_keyModel) ?? 'auto');

  Future<void> setModel(WindyModel model) async {
    await _prefs.setString(_keyModel, model.apiValue);
    // Grid bergantung pada model — cache tidak berlaku lagi.
    _gridCache = null;
  }

  bool get particlesEnabled => _prefs.getBool(_keyParticles) ?? false;

  Future<void> setParticlesEnabled(bool value) async {
    await _prefs.setBool(_keyParticles, value);
  }

  // -- Prakiraan titik gabungan --

  Future<Result<PointForecast>> getPointForecast({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final model = this.model.apiValue;
    final forecastResult = await _weather.getForecast(
      latitude: latitude,
      longitude: longitude,
      model: model,
      forceRefresh: forceRefresh,
    );
    final marineResult = await _marine.getMarine(
      latitude: latitude,
      longitude: longitude,
      forceRefresh: forceRefresh,
    );
    final forecastHours = switch (forecastResult) {
      Ok(value: final hours) => hours,
      Error() => <ForecastHour>[],
    };
    final marineHours = switch (marineResult) {
      Ok(value: final forecast) => forecast.hours,
      Error() => <MarineHour>[],
    };
    if (forecastHours.isEmpty && marineHours.isEmpty) {
      final error = switch (forecastResult) {
        Error(error: final e) => e,
        _ => Exception('Prakiraan titik tidak tersedia.'),
      };
      return Result.error(error);
    }
    return Result.ok(PointForecast(
      latitude: latitude,
      longitude: longitude,
      forecast: forecastHours,
      marine: marineHours,
      model: model,
      fetchedAt: DateTime.now(),
    ));
  }

  // -- Grid angin --

  Future<Result<WindGrid>> getWindGrid({
    required double south,
    required double west,
    required double north,
    required double east,
    bool forceRefresh = false,
  }) async {
    final key =
        '${south.toStringAsFixed(1)}|${west.toStringAsFixed(1)}|'
        '${north.toStringAsFixed(1)}|${east.toStringAsFixed(1)}|'
        '${model.apiValue}';
    if (!forceRefresh &&
        _gridCache != null &&
        _gridKey == key &&
        _gridFetchedAt != null &&
        DateTime.now().difference(_gridFetchedAt!) < _gridTtl) {
      return Result.ok(_gridCache!);
    }
    final result = await _windGrid.fetchGrid(
      south: south,
      west: west,
      north: north,
      east: east,
      model: model.apiValue,
    );
    switch (result) {
      case Ok(value: final grid):
        _gridCache = grid;
        _gridKey = key;
        _gridFetchedAt = DateTime.now();
        return Result.ok(grid);
      case Error(error: final error):
        if (_gridCache != null) return Result.ok(_gridCache!);
        return Result.error(error);
    }
  }

  // -- Peringatan ambang --

  /// Minta izin notifikasi (diteruskan ke NotificationService).
  Future<void> requestNotificationPermission() =>
      _notifications.requestPermission();

  List<WeatherAlert> get alerts {
    final raw = _prefs.getString(_keyAlerts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(WeatherAlert.fromJson)
          .where((a) => a.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAlerts(List<WeatherAlert> alerts) async {
    await _prefs.setString(
      _keyAlerts,
      jsonEncode(alerts.map((a) => a.toJson()).toList()),
    );
  }

  /// Evaluasi semua peringatan aktif terhadap prakiraan titik
  /// (24 jam ke depan). Peringatan yang terlampaui + melewati masa
  /// jeda 6 jam -> notifikasi lokal dikirim + lastTriggeredAt
  /// diperbarui. Mengembalikan peringatan yang memicu.
  Future<List<WeatherAlert>> evaluateAlerts(
    PointForecast forecast,
  ) async {
    final now = DateTime.now();
    final horizon = now.add(const Duration(hours: 24));
    final triggered = <WeatherAlert>[];
    var changed = false;
    final current = alerts;
    for (var i = 0; i < current.length; i++) {
      final alert = current[i];
      if (!alert.enabled || !alert.hasAnyThreshold) continue;
      if (alert.lastTriggeredAt != null &&
          now.difference(alert.lastTriggeredAt!) < _alertCooldown) {
        continue;
      }
      final hit = _alertHit(alert, forecast, now, horizon);
      if (hit == null) continue;
      triggered.add(alert);
      current[i] = alert.copyWith(lastTriggeredAt: now);
      changed = true;
      await _notifications.showWeatherAlert(
        id: alert.id.hashCode & 0x7fffffff,
        title: 'Peringatan cuaca: ${alert.name}',
        body: hit,
      );
    }
    if (changed) await saveAlerts(current);
    return triggered;
  }

  /// Pesan pemicu (null bila tidak terlampaui).
  String? _alertHit(
    WeatherAlert alert,
    PointForecast forecast,
    DateTime now,
    DateTime horizon,
  ) {
    final hits = <String>[];
    for (final hour in forecast.forecast) {
      if (hour.time.isBefore(now) || hour.time.isAfter(horizon)) continue;
      if (alert.windKnots != null && hour.windKnots != null) {
        if (hour.windKnots! > alert.windKnots!) {
          hits.add(
            'angin ${hour.windKnots!.toStringAsFixed(0)} kt '
            '(ambang ${alert.windKnots!.toStringAsFixed(0)} kt)',
          );
          break;
        }
      }
      if (alert.rainMmPerHour != null && hour.precipitationMm != null) {
        if (hour.precipitationMm! > alert.rainMmPerHour!) {
          hits.add(
            'hujan ${hour.precipitationMm!.toStringAsFixed(1)} mm/jam '
            '(ambang ${alert.rainMmPerHour!.toStringAsFixed(1)} mm/jam)',
          );
          break;
        }
      }
    }
    if (alert.waveM != null) {
      for (final hour in forecast.marine) {
        if (hour.time.isBefore(now) || hour.time.isAfter(horizon)) continue;
        if (hour.waveHeightM != null && hour.waveHeightM! > alert.waveM!) {
          hits.add(
            'gelombang ${hour.waveHeightM!.toStringAsFixed(1)} m '
            '(ambang ${alert.waveM!.toStringAsFixed(1)} m)',
          );
          break;
        }
      }
    }
    if (hits.isEmpty) return null;
    return 'Terlampaui dalam 24 jam ke depan: ${hits.join(', ')}.';
  }

  /// Cuaca di sepanjang rute: prakiraan di tiap waypoint pada jam ETA.
  /// `etas` sejajar dengan `points` (nama + koordinat + ETA).
  Future<List<RouteWeatherPoint>> routeWeather(
    List<({String name, double lat, double lon, DateTime eta})> points,
  ) async {
    final result = <RouteWeatherPoint>[];
    for (final point in points) {
      final forecast = await getPointForecast(
        latitude: point.lat,
        longitude: point.lon,
      );
      switch (forecast) {
        case Ok(value: final pf):
          result.add(_weatherAtEta(pf, point.name, point.eta));
        case Error():
          result.add(RouteWeatherPoint(
            waypointName: point.name,
            eta: point.eta,
          ));
      }
    }
    return result;
  }

  RouteWeatherPoint _weatherAtEta(
    PointForecast pf,
    String name,
    DateTime eta,
  ) {
    ForecastHour? bestForecast;
    var bestDiff = Duration(days: 99);
    for (final h in pf.forecast) {
      final diff = h.time.difference(eta).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestForecast = h;
      }
    }
    MarineHour? bestMarine;
    bestDiff = Duration(days: 99);
    for (final h in pf.marine) {
      final diff = h.time.difference(eta).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestMarine = h;
      }
    }
    return RouteWeatherPoint(
      waypointName: name,
      eta: eta,
      windKnots: bestForecast?.windKnots,
      windDirDeg: bestForecast?.windDirDeg,
      gustsKnots: bestForecast?.gustsKmh == null
          ? null
          : NavMath.kmhToKnots(bestForecast!.gustsKmh!),
      waveHeightM: bestMarine?.waveHeightM,
      rainMm: bestForecast?.precipitationMm,
      tempC: bestForecast?.tempC,
    );
  }
}
