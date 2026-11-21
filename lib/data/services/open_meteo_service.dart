import 'dart:convert';

import '../../domain/models/marine.dart';
import '../../utils/result.dart';
import 'api_client.dart';

/// Open-Meteo: tanpa key, tanpa batas keras yang terdokumentasi.
/// Marine (gelombang/swell/arus/SST) + Forecast (angin/hujan/awan/
/// suhu/tekanan; parameter `models` = gfs|icon|ecmwf_ifs).
/// Titik darat pada Marine mengembalikan null semua -> hasData false;
/// UI menampilkan "tidak ada data", BUKAN 0.
class OpenMeteoService {
  OpenMeteoService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  static const _marineVars =
      'wave_height,wave_direction,wave_period,'
      'swell_wave_height,swell_wave_direction,swell_wave_period,'
      'ocean_current_velocity,ocean_current_direction,'
      'sea_surface_temperature';

  static const _forecastVars =
      'temperature_2m,wind_speed_10m,wind_direction_10m,'
      'wind_gusts_10m,precipitation,cloud_cover,pressure_msl';

  Future<Result<MarineForecast>> fetchMarine({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('https://marine-api.open-meteo.com/v1/marine')
        .replace(queryParameters: {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'hourly': _marineVars,
      'forecast_days': '3',
      'timezone': 'Asia/Jakarta',
    });
    final result = await _client.get(uri);
    switch (result) {
      case Ok(value: final body):
        try {
          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic>) {
            return Result.error(
              Exception('Respons Open-Meteo Marine tidak valid.'),
            );
          }
          final forecast = MarineForecast.fromJson(
            decoded,
            latitude: latitude,
            longitude: longitude,
            fetchedAt: DateTime.now(),
          );
          if (forecast.hours.isEmpty) {
            return Result.error(
              Exception('Open-Meteo tidak mengembalikan data gelombang.'),
            );
          }
          return Result.ok(forecast);
        } catch (e) {
          return Result.error(
            Exception('Gagal membaca data gelombang: $e'),
          );
        }
      case Error(error: final error):
        return Result.error(error);
    }
  }

  /// Prakiraan Forecast per jam. `model`: 'auto' | 'gfs' | 'icon' |
  /// 'ecmwf_ifs' — 'auto' tidak mengirim parameter models.
  Future<Result<List<ForecastHour>>> fetchForecast({
    required double latitude,
    required double longitude,
    String model = 'auto',
  }) async {
    final params = <String, String>{
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'hourly': _forecastVars,
      'forecast_days': '3',
      'timezone': 'Asia/Jakarta',
    };
    if (model != 'auto') params['models'] = model;
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast')
        .replace(queryParameters: params);
    final result = await _client.get(uri);
    switch (result) {
      case Ok(value: final body):
        try {
          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic>) {
            return Result.error(
              Exception('Respons Open-Meteo tidak valid.'),
            );
          }
          final hours = PointForecast.parseForecastHourly(decoded);
          if (hours.isEmpty) {
            return Result.error(
              Exception('Open-Meteo tidak mengembalikan prakiraan.'),
            );
          }
          return Result.ok(hours);
        } catch (e) {
          return Result.error(
            Exception('Gagal membaca prakiraan: $e'),
          );
        }
      case Error(error: final error):
        return Result.error(error);
    }
  }
}
