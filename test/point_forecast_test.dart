import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/domain/models/marine.dart';
import 'package:peta_laut/domain/models/windy.dart';
import 'package:peta_laut/data/services/wind_grid_service.dart';

/// Fixture sesuai bentuk respons Open-Meteo Forecast
/// (hourly: time + array per variabel, timezone Asia/Jakarta).
void main() {
  const forecastJson = r'''{
    "latitude": -4.5, "longitude": 114.8,
    "hourly_units": {"time": "iso8601", "wind_speed_10m": "km/h"},
    "hourly": {
      "time": ["2026-11-21T08:00", "2026-11-21T09:00", "2026-11-21T10:00"],
      "temperature_2m": [28.5, 29.0, 30.1],
      "wind_speed_10m": [18.5, 22.2, 36.0],
      "wind_direction_10m": [120, 125, 130],
      "wind_gusts_10m": [25.0, 30.0, 45.0],
      "precipitation": [0.0, 0.2, 1.5],
      "cloud_cover": [40, 55, 80],
      "pressure_msl": [1010.5, 1010.0, 1009.2]
    }
  }''';

  group('PointForecast.parseForecastHourly', () {
    test('parse 3 jam + semua variabel', () {
      final decoded = jsonDecode(forecastJson) as Map<String, dynamic>;
      final hours = PointForecast.parseForecastHourly(decoded);
      expect(hours.length, 3);
      final h = hours[0];
      expect(h.tempC, 28.5);
      expect(h.windKmh, 18.5);
      expect(h.windDirDeg, 120);
      expect(h.gustsKmh, 25.0);
      expect(h.precipitationMm, 0.0);
      expect(h.cloudCoverPct, 40);
      expect(h.pressureHpa, 1010.5);
      // 36 km/jam = 19,4 knot.
      expect(hours[2].windKnots, closeTo(19.44, 0.01));
      expect(hours[2].time, DateTime(2026, 11, 21, 10, 0));
    });

    test('nilai null dipertahankan (bukan 0)', () {
      const withNulls = r'''{"hourly": {
        "time": ["2026-11-21T08:00"],
        "temperature_2m": [null],
        "wind_speed_10m": [null],
        "wind_direction_10m": [null],
        "wind_gusts_10m": [null],
        "precipitation": [null],
        "cloud_cover": [null],
        "pressure_msl": [null]
      }}''';
      final decoded = jsonDecode(withNulls) as Map<String, dynamic>;
      final hours = PointForecast.parseForecastHourly(decoded);
      expect(hours.length, 1);
      expect(hours[0].windKmh, isNull);
      expect(hours[0].windKnots, isNull);
    });

    test('hourly kosong / hilang -> daftar kosong', () {
      expect(PointForecast.parseForecastHourly({}), isEmpty);
      expect(
        PointForecast.parseForecastHourly({'hourly': {}}),
        isEmpty,
      );
      expect(
        PointForecast.parseForecastHourly(
          {'hourly': {'time': []}},
        ),
        isEmpty,
      );
    });

    test('round-trip toJson/fromJson ForecastHour', () {
      final decoded = jsonDecode(forecastJson) as Map<String, dynamic>;
      final hours = PointForecast.parseForecastHourly(decoded);
      final restored =
          ForecastHour.fromJson(hours[1].toJson());
      expect(restored.windKmh, hours[1].windKmh);
      expect(restored.tempC, hours[1].tempC);
      expect(restored.time, hours[1].time);
    });
  });

  group('WindGridService.parseGrid', () {
    String pointJson(double speed, double dir) => '''
      {"latitude": -4.5, "longitude": 114.8, "hourly": {
        "time": ["2026-11-21T08:00", "2026-11-21T09:00"],
        "wind_speed_10m": [$speed, $speed],
        "wind_direction_10m": [$dir, $dir]
      }}''';

    test('parse multi-lokasi 2x2', () {
      final body = '[${pointJson(10, 90)}, ${pointJson(20, 90)}, '
          '${pointJson(30, 90)}, ${pointJson(40, 90)}]';
      final decoded = jsonDecode(body);
      final grid = WindGridService.parseGrid(
        decoded,
        lats: [0.0, 1.0],
        lons: [0.0, 1.0],
        model: 'auto',
      );
      expect(grid, isNotNull);
      expect(grid!.points.length, 4);
      expect(grid.columns, 2);
      expect(grid.rows, 2);
      expect(grid.times.length, 2);
      expect(grid.points[0].windKmh[0], 10);
      expect(grid.points[3].windKmh[0], 40);
    });

    test('bukan list / jumlah tidak cocok -> null', () {
      expect(
        WindGridService.parseGrid(
          {'hourly': {}},
          lats: [0.0],
          lons: [0.0],
          model: 'auto',
        ),
        isNull,
      );
      expect(
        WindGridService.parseGrid(
          [jsonDecode(pointJson(10, 90))],
          lats: [0.0, 1.0],
          lons: [0.0, 1.0],
          model: 'auto',
        ),
        isNull,
      );
    });
  });

  group('WindGrid.windAt', () {
    WindGrid grid2x2() {
      WindGridPoint pt(double lat, double lon, double speed) =>
          WindGridPoint(
            latitude: lat,
            longitude: lon,
            windKmh: [speed],
            windDirDeg: [90.0],
          );
      return WindGrid(
        points: [
          pt(0, 0, 0),
          pt(0, 1, 10),
          pt(1, 0, 20),
          pt(1, 1, 30),
        ],
        columns: 2,
        rows: 2,
        times: [DateTime(2026, 11, 21, 8)],
        model: 'auto',
        fetchedAt: DateTime.now(),
      );
    }

    test('tengah grid = rata-rata bilinear (15 km/jam, 90 derajat)', () {
      final grid = grid2x2();
      final wind = grid.windAt(0.5, 0.5, 0);
      expect(wind, isNotNull);
      final w = wind!;
      expect(w.$1, closeTo(15, 0.001));
      expect(w.$2, closeTo(90, 0.001));
    });

    test('sudut grid = nilai titik itu', () {
      final grid = grid2x2();
      expect(grid.windAt(0, 0, 0)?.$1, closeTo(0, 0.001));
      expect(grid.windAt(1, 1, 0)?.$1, closeTo(30, 0.001));
    });

    test('indeks jam di luar rentang -> null', () {
      final grid = grid2x2();
      expect(grid.windAt(0.5, 0.5, 5), isNull);
      expect(grid.windAt(0.5, 0.5, -1), isNull);
    });

    test('arah dikembalikan sebagai arah DATANG DARI', () {
      // Angin dari utara (0 deg) di semua titik.
      final grid = WindGrid(
        points: [
          const WindGridPoint(
            latitude: 0,
            longitude: 0,
            windKmh: [10.0],
            windDirDeg: [0.0],
          ),
          const WindGridPoint(
            latitude: 0,
            longitude: 1,
            windKmh: [10.0],
            windDirDeg: [0.0],
          ),
          const WindGridPoint(
            latitude: 1,
            longitude: 0,
            windKmh: [10.0],
            windDirDeg: [0.0],
          ),
          const WindGridPoint(
            latitude: 1,
            longitude: 1,
            windKmh: [10.0],
            windDirDeg: [0.0],
          ),
        ],
        columns: 2,
        rows: 2,
        times: [DateTime(2026, 11, 21, 8)],
        model: 'auto',
        fetchedAt: DateTime.now(),
      );
      final wind = grid.windAt(0.5, 0.5, 0);
      expect(wind, isNotNull);
      final w = wind!;
      expect(w.$1, closeTo(10, 0.001));
      expect(w.$2, closeTo(0, 0.001));
    });
  });
}
