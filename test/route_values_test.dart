import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/utils/nav_math.dart';

/// Nilai absolut jarak/bearing/ETA rute — DIVERIFIKASI dengan
/// perhitungan haversine/bearing independen (Python, R = 6371000 m),
/// bukan dari kode Dart itu sendiri. Rute: Jakarta -> Surabaya ->
/// Makassar -> Ambon.
void main() {
  group('RouteMath nilai absolut (terverifikasi Python)', () {
    // Jakarta -> Surabaya -> Makassar -> Ambon (4 titik, 3 kaki).
    final points = [
      (-6.20, 106.85),
      (-7.25, 112.75),
      (-5.15, 119.40),
      (-3.70, 128.17),
    ];

    test('jarak tiap kaki', () {
      final legs = RouteMath.legs(points);
      expect(legs.length, 3);
      expect(legs[0].distanceM, closeTo(661901.47, 1.0));
      expect(legs[1].distanceM, closeTo(771271.73, 1.0));
      expect(legs[2].distanceM, closeTo(985519.01, 1.0));
    });

    test('bearing tiap kaki', () {
      final legs = RouteMath.legs(points);
      expect(legs[0].bearingDeg, closeTo(100.4964, 0.01));
      expect(legs[1].bearingDeg, closeTo(72.7567, 0.01));
      expect(legs[2].bearingDeg, closeTo(80.9416, 0.01));
    });

    test('jarak total meter + mil laut', () {
      expect(
        RouteMath.totalDistanceM(points),
        closeTo(2418692.21, 1.0),
      );
      expect(
        NavMath.metersToNm(RouteMath.totalDistanceM(points)),
        closeTo(1305.989, 0.001),
      );
    });

    test('ETA total 8 knot = 587695 detik (163 jam 14 mnt)', () {
      expect(
        RouteMath.totalEta(points, 8),
        const Duration(seconds: 587695),
      );
      expect(
        NavMath.formatEta(RouteMath.totalEta(points, 8)),
        '163 jam 14 mnt',
      );
    });

    test('ETA total 12 knot = 391797 detik', () {
      expect(
        RouteMath.totalEta(points, 12),
        const Duration(seconds: 391797),
      );
    });

    test('ETA tiap kaki 8 knot', () {
      final legs = RouteMath.legs(points);
      expect(legs[0].etaAt(8), const Duration(seconds: 160829));
      expect(legs[1].etaAt(8), const Duration(seconds: 187404));
      expect(legs[2].etaAt(8), const Duration(seconds: 239462));
    });

    test('ETA 10 mil laut pada 8 knot = 4500 detik', () {
      expect(
        NavMath.etaDuration(18520, 8),
        const Duration(seconds: 4500),
      );
    });

    test('kecepatan tidak valid -> ETA null', () {
      expect(NavMath.etaDuration(18520, 0), isNull);
      expect(NavMath.etaDuration(18520, -3), isNull);
      expect(RouteMath.totalEta(points, 0), isNull);
    });

    test('format jarak total', () {
      expect(
        NavMath.formatDistance(RouteMath.totalDistanceM(points)),
        '1306.0 nm (2418.7 km)',
      );
    });
  });
}
