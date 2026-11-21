import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/domain/models/marine.dart';

/// Fixture sesuai bentuk respons Open-Meteo Marine
/// (hourly: time + array per variabel, timezone Asia/Jakarta).
void main() {
  const marineJson = r'''{
    "latitude": -4.5, "longitude": 114.8,
    "hourly_units": {"time": "iso8601", "wave_height": "m"},
    "hourly": {
      "time": ["2026-11-21T08:00", "2026-11-21T09:00", "2026-11-21T10:00"],
      "wave_height": [1.2, 1.4, 1.1],
      "wave_direction": [120, 125, 130],
      "wave_period": [6.5, 7.0, 6.0],
      "swell_wave_height": [0.8, 0.9, 0.7],
      "swell_wave_direction": [140, 145, 150],
      "swell_wave_period": [9.0, 9.5, 8.5],
      "ocean_current_velocity": [0.9, 1.1, 0.8],
      "ocean_current_direction": [200, 210, 190],
      "sea_surface_temperature": [29.1, 29.2, 29.0]
    }
  }''';

  const landJson = r'''{
    "latitude": -3.32, "longitude": 114.59,
    "hourly": {
      "time": ["2026-11-21T08:00", "2026-11-21T09:00"],
      "wave_height": [null, null],
      "wave_direction": [null, null],
      "wave_period": [null, null],
      "swell_wave_height": [null, null],
      "swell_wave_direction": [null, null],
      "swell_wave_period": [null, null],
      "ocean_current_velocity": [null, null],
      "ocean_current_direction": [null, null],
      "sea_surface_temperature": [null, null]
    }
  }''';

  test('parse laut: 3 jam + semua variabel', () {
    final decoded = jsonDecode(marineJson) as Map<String, dynamic>;
    final forecast = MarineForecast.fromJson(
      decoded,
      latitude: -4.5,
      longitude: 114.8,
      fetchedAt: DateTime.utc(2026, 11, 21),
    );
    expect(forecast.hours.length, 3);
    expect(forecast.hasData, isTrue);
    final h = forecast.hours[0];
    expect(h.waveHeightM, 1.2);
    expect(h.waveDirectionDeg, 120);
    expect(h.wavePeriodS, 6.5);
    expect(h.swellHeightM, 0.8);
    expect(h.swellPeriodS, 9.0);
    // 0.9 km/jam = 0.49 knot.
    expect(h.currentKnots, closeTo(0.49, 0.01));
    expect(h.seaTempC, 29.1);
    expect(h.time, DateTime(2026, 11, 21, 8, 0));
  });

  test('titik darat: semua null -> hasData false (bukan 0)', () {
    final decoded = jsonDecode(landJson) as Map<String, dynamic>;
    final forecast = MarineForecast.fromJson(
      decoded,
      latitude: -3.32,
      longitude: 114.59,
      fetchedAt: DateTime.utc(2026, 11, 21),
    );
    expect(forecast.hours.length, 2);
    expect(forecast.hasData, isFalse);
    expect(forecast.hours[0].waveHeightM, isNull);
    expect(forecast.hours[0].seaTempC, isNull);
  });

  test('every3Hours mengambil tiap jam ke-3', () {
    final decoded = jsonDecode(marineJson) as Map<String, dynamic>;
    final forecast = MarineForecast.fromJson(
      decoded,
      latitude: -4.5,
      longitude: 114.8,
      fetchedAt: DateTime.utc(2026, 11, 21),
    );
    // 3 jam -> indeks 0 saja.
    expect(forecast.every3Hours.length, 1);
    expect(forecast.every3Hours[0].waveHeightM, 1.2);
  });

  test('toJson/fromCacheJson round-trip', () {
    final decoded = jsonDecode(marineJson) as Map<String, dynamic>;
    final forecast = MarineForecast.fromJson(
      decoded,
      latitude: -4.5,
      longitude: 114.8,
      fetchedAt: DateTime.utc(2026, 11, 21),
    );
    final restored = MarineForecast.fromCacheJson(forecast.toJson());
    expect(restored.hours.length, 3);
    expect(restored.hours[1].waveHeightM, 1.4);
    expect(restored.hasData, isTrue);
  });

  test('parseForecastHourly (Open-Meteo Forecast)', () {
    const forecastJson = r'''{
      "hourly": {
        "time": ["2026-11-21T08:00", "2026-11-21T09:00"],
        "temperature_2m": [29.0, 30.0],
        "wind_speed_10m": [18.5, 22.2],
        "wind_direction_10m": [90, 100],
        "wind_gusts_10m": [25.0, 30.0],
        "precipitation": [0.0, 1.2],
        "cloud_cover": [40, 60],
        "pressure_msl": [1010.5, 1009.0]
      }
    }''';
    final decoded = jsonDecode(forecastJson) as Map<String, dynamic>;
    final hours = PointForecast.parseForecastHourly(decoded);
    expect(hours.length, 2);
    expect(hours[0].tempC, 29.0);
    expect(hours[0].windKnots, closeTo(10, 0.01));
    expect(hours[1].precipitationMm, 1.2);
    expect(hours[1].pressureHpa, 1009.0);
  });
}
