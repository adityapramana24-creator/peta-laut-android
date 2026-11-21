import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/data/services/current_grid_service.dart';
import 'package:peta_laut/domain/models/windy.dart';

/// Grid arus Open-Meteo Marine (ronde 2, item 4b): parse respons
/// multi-lokasi + interpolasi bilinear currentAt.
/// Konvensi arah: ocean_current_direction = arah MENUJU
/// (0° = ke utara, 90° = ke timur) — kebalikan konvensi angin.
void main() {
  group('CurrentGridService.parseGrid', () {
    String pointJson(double speed, double dir) => '''
      {"latitude": -4.5, "longitude": 114.8, "hourly": {
        "time": ["2026-11-21T08:00", "2026-11-21T09:00"],
        "ocean_current_velocity": [$speed, $speed],
        "ocean_current_direction": [$dir, $dir]
      }}''';

    test('parse multi-lokasi 2x2', () {
      final body = '[${pointJson(1.0, 90)}, ${pointJson(2.0, 90)}, '
          '${pointJson(3.0, 90)}, ${pointJson(4.0, 90)}]';
      final decoded = jsonDecode(body);
      final grid = CurrentGridService.parseGrid(
        decoded,
        lats: [0.0, 1.0],
        lons: [0.0, 1.0],
      );
      expect(grid, isNotNull);
      expect(grid!.points.length, 4);
      expect(grid.columns, 2);
      expect(grid.rows, 2);
      expect(grid.times.length, 2);
      expect(grid.points[0].velocityKmh[0], 1.0);
      expect(grid.points[3].velocityKmh[0], 4.0);
      expect(grid.points[2].directionDeg[0], 90);
      expect(grid.south, 0.0);
      expect(grid.east, 1.0);
    });

    test('bukan list / jumlah tidak cocok -> null', () {
      expect(
        CurrentGridService.parseGrid(
          {'hourly': {}},
          lats: [0.0],
          lons: [0.0],
        ),
        isNull,
      );
      expect(
        CurrentGridService.parseGrid(
          [jsonDecode(pointJson(1.0, 90))],
          lats: [0.0, 1.0],
          lons: [0.0, 1.0],
        ),
        isNull,
      );
    });

    test('titik darat (semua null) tetap jadi titik grid', () {
      const landPoint = '''
        {"latitude": -3.32, "longitude": 114.59, "hourly": {
          "time": ["2026-11-21T08:00"],
          "ocean_current_velocity": [null],
          "ocean_current_direction": [null]
        }}''';
      final body = '[$landPoint, $landPoint, $landPoint, $landPoint]';
      final grid = CurrentGridService.parseGrid(
        jsonDecode(body),
        lats: [0.0, 1.0],
        lons: [0.0, 1.0],
      );
      expect(grid, isNotNull);
      expect(grid!.points[0].velocityKmh[0], isNull);
      // Tanpa data sama sekali -> currentAt null (bukan 0).
      expect(grid.currentAt(0.5, 0.5, 0), isNull);
    });

    test('F-R2: tiap titik menyimpan jam ASLI respons (bukan karangan)', () {
      final body = '[${pointJson(1.0, 90)}, ${pointJson(2.0, 90)}, '
          '${pointJson(3.0, 90)}, ${pointJson(4.0, 90)}]';
      final grid = CurrentGridService.parseGrid(
        jsonDecode(body),
        lats: [0.0, 1.0],
        lons: [0.0, 1.0],
      );
      expect(grid, isNotNull);
      expect(grid!.times, [
        DateTime(2026, 11, 21, 8),
        DateTime(2026, 11, 21, 9),
      ]);
      for (final p in grid.points) {
        expect(p.times, grid.times);
      }
    });
  });

  group('CurrentGrid.currentAt', () {
    CurrentGrid grid2x2() {
      CurrentGridPoint pt(double lat, double lon, double speed) =>
          CurrentGridPoint(
            latitude: lat,
            longitude: lon,
            velocityKmh: [speed],
            directionDeg: [90.0],
          );
      return CurrentGrid(
        points: [
          pt(0, 0, 0),
          pt(0, 1, 1),
          pt(1, 0, 2),
          pt(1, 1, 3),
        ],
        columns: 2,
        rows: 2,
        times: [DateTime(2026, 11, 21, 8)],
        fetchedAt: DateTime.now(),
      );
    }

    test('tengah grid = rata-rata bilinear (1,5 km/jam, 90 derajat)', () {
      final grid = grid2x2();
      final current = grid.currentAt(0.5, 0.5, 0);
      expect(current, isNotNull);
      final c = current!;
      expect(c.$1, closeTo(1.5, 0.001));
      expect(c.$2, closeTo(90, 0.001));
    });

    test('sudut grid = nilai titik itu', () {
      final grid = grid2x2();
      expect(grid.currentAt(1, 1, 0)?.$1, closeTo(3, 0.001));
      expect(grid.currentAt(1, 1, 0)?.$2, closeTo(90, 0.001));
      // Kecepatan 0 -> arah 0 (penjaga kecepatan < 0,05).
      expect(grid.currentAt(0, 0, 0)?.$1, closeTo(0, 0.001));
      expect(grid.currentAt(0, 0, 0)?.$2, closeTo(0, 0.001));
    });

    test('arah dikembalikan sebagai arah MENUJU', () {
      // Arus ke utara (0 deg) di semua titik.
      final grid = CurrentGrid(
        points: [
          for (final (lat, lon) in [(0.0, 0.0), (0.0, 1.0),
                (1.0, 0.0), (1.0, 1.0)])
            CurrentGridPoint(
              latitude: lat,
              longitude: lon,
              velocityKmh: [2.0],
              directionDeg: [0.0],
            ),
        ],
        columns: 2,
        rows: 2,
        times: [DateTime(2026, 11, 21, 8)],
        fetchedAt: DateTime.now(),
      );
      final current = grid.currentAt(0.5, 0.5, 0);
      expect(current, isNotNull);
      expect(current!.$1, closeTo(2, 0.001));
      expect(current.$2, closeTo(0, 0.001));
    });

    test('arus ke tenggara (135) dipertahankan', () {
      final grid = CurrentGrid(
        points: [
          for (final (lat, lon) in [(0.0, 0.0), (0.0, 1.0),
                (1.0, 0.0), (1.0, 1.0)])
            CurrentGridPoint(
              latitude: lat,
              longitude: lon,
              velocityKmh: [2.0],
              directionDeg: [135.0],
            ),
        ],
        columns: 2,
        rows: 2,
        times: [DateTime(2026, 11, 21, 8)],
        fetchedAt: DateTime.now(),
      );
      final current = grid.currentAt(0.5, 0.5, 0);
      expect(current, isNotNull);
      expect(current!.$1, closeTo(2, 0.001));
      expect(current.$2, closeTo(135, 0.001));
    });

    test('indeks jam di luar rentang -> null', () {
      final grid = grid2x2();
      expect(grid.currentAt(0.5, 0.5, 5), isNull);
      expect(grid.currentAt(0.5, 0.5, -1), isNull);
    });

    test('sudut tanpa data -> jatuh ke titik terdekat', () {
      final grid = CurrentGrid(
        points: [
          const CurrentGridPoint(
            latitude: 0,
            longitude: 0,
            velocityKmh: [null],
            directionDeg: [null],
          ),
          const CurrentGridPoint(
            latitude: 0,
            longitude: 1,
            velocityKmh: [null],
            directionDeg: [null],
          ),
          const CurrentGridPoint(
            latitude: 1,
            longitude: 0,
            velocityKmh: [null],
            directionDeg: [null],
          ),
          const CurrentGridPoint(
            latitude: 1,
            longitude: 1,
            velocityKmh: [2.0],
            directionDeg: [90.0],
          ),
        ],
        columns: 2,
        rows: 2,
        times: [DateTime(2026, 11, 21, 8)],
        fetchedAt: DateTime.now(),
      );
      final current = grid.currentAt(0.5, 0.5, 0);
      expect(current, isNotNull);
      expect(current!.$1, closeTo(2, 0.001));
      expect(current.$2, closeTo(90, 0.001));
    });
  });
}
