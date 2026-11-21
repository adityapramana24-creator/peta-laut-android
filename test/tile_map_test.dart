import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/utils/map_projection.dart';
import 'package:peta_laut/utils/tile_math.dart';

void main() {
  group('TileMath.latLonToTile', () {
    test('Banjarmasin z12 = (3351, 2085) — bukti report.md §3', () {
      expect(TileMath.latLonToTile(-3.32, 114.59, 12), (3351, 2085));
    });

    test('Jakarta z12 = (3263, 2118), z10 = (815, 529)', () {
      expect(TileMath.latLonToTile(-6.20, 106.85, 12), (3263, 2118));
      expect(TileMath.latLonToTile(-6.20, 106.85, 10), (815, 529));
    });

    test('Surabaya z12 = (3330, 2130)', () {
      expect(TileMath.latLonToTile(-7.25, 112.75, 12), (3330, 2130));
    });
  });

  group('TileMath.rangeForBounds', () {
    test('kotak Banjarmasin z12 = 36 tile', () {
      final range = TileMath.rangeForBounds(
        south: -3.5,
        west: 114.4,
        north: -3.0,
        east: 114.8,
        zoom: 12,
      );
      expect(range.xMin, 3349);
      expect(range.xMax, 3354);
      expect(range.yMin, 2082);
      expect(range.yMax, 2087);
      expect(range.count, 36);
      expect(range.tiles.length, 36);
    });

    test('batas terbalik tetap benar', () {
      final range = TileMath.rangeForBounds(
        south: -3.0,
        west: 114.8,
        north: -3.5,
        east: 114.4,
        zoom: 12,
      );
      expect(range.count, 36);
    });
  });

  group('TileMath.tileUrl', () {
    test('template OSM {z}/{x}/{y}', () {
      expect(
        TileMath.tileUrl('https://tile.openstreetmap.de/{z}/{x}/{y}.png', 12, 3351, 2085),
        'https://tile.openstreetmap.de/12/3351/2085.png',
      );
    });

    test('template Esri {z}/{y}/{x} — urutan dipertahankan', () {
      expect(
        TileMath.tileUrl(
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          12,
          3351,
          2085,
        ),
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/12/2085/3351',
      );
    });
  });

  group('MapProjection', () {
    test('tengah peta -> tengah layar', () {
      final (x, y) = MapProjection.latLonToScreen(
        latitude: -3.32,
        longitude: 114.59,
        centerLat: -3.32,
        centerLon: 114.59,
        zoom: 10,
        rotationDeg: 0,
        screenWidth: 400,
        screenHeight: 800,
      );
      expect(x, closeTo(200, 0.001));
      expect(y, closeTo(400, 0.001));
    });

    test('titik timur tengah muncul di kanan (rotasi 0)', () {
      final (x, y) = MapProjection.latLonToScreen(
        latitude: -3.32,
        longitude: 115.59,
        centerLat: -3.32,
        centerLon: 114.59,
        zoom: 10,
        rotationDeg: 0,
        screenWidth: 400,
        screenHeight: 800,
      );
      expect(x, greaterThan(200));
      expect(y, closeTo(400, 0.001));
    });

    test('rotasi 90: titik timur muncul di bawah tengah', () {
      final (x, y) = MapProjection.latLonToScreen(
        latitude: -3.32,
        longitude: 115.59,
        centerLat: -3.32,
        centerLon: 114.59,
        zoom: 10,
        rotationDeg: 90,
        screenWidth: 400,
        screenHeight: 800,
      );
      expect(x, closeTo(200, 0.001));
      expect(y, greaterThan(400));
    });

    test('round-trip layar -> lat/lon -> layar', () {
      const args = (
        centerLat: -3.32,
        centerLon: 114.59,
        zoom: 12.0,
        rotationDeg: 30.0,
        screenWidth: 400.0,
        screenHeight: 800.0,
      );
      final (lat, lon) = MapProjection.screenToLatLon(
        screenX: 300,
        screenY: 200,
        centerLat: args.centerLat,
        centerLon: args.centerLon,
        zoom: args.zoom,
        rotationDeg: args.rotationDeg,
        screenWidth: args.screenWidth,
        screenHeight: args.screenHeight,
      );
      final (x, y) = MapProjection.latLonToScreen(
        latitude: lat,
        longitude: lon,
        centerLat: args.centerLat,
        centerLon: args.centerLon,
        zoom: args.zoom,
        rotationDeg: args.rotationDeg,
        screenWidth: args.screenWidth,
        screenHeight: args.screenHeight,
      );
      expect(x, closeTo(300, 0.001));
      expect(y, closeTo(200, 0.001));
    });

    test('project/unproject round-trip', () {
      final (wx, wy) = MapProjection.project(-3.32, 114.59, 12);
      final (lat, lon) = MapProjection.unproject(wx, wy, 12);
      expect(lat, closeTo(-3.32, 0.000001));
      expect(lon, closeTo(114.59, 0.000001));
    });
  });
}
