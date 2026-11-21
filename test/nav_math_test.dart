import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/utils/nav_math.dart';

/// Nilai ekspektasi dihitung dengan Python (haversine independen)
/// pada 21 Nov 2026 — bukan tebakan:
/// Jakarta (-6.20, 106.85) -> Surabaya (-7.25, 112.75):
/// jarak 661901.5 m (357.4 mil laut), bearing 100.5 derajat.
void main() {
  group('distanceMeters', () {
    test('Jakarta -> Surabaya ~661.9 km', () {
      final d = NavMath.distanceMeters(-6.20, 106.85, -7.25, 112.75);
      expect(d, closeTo(661901.5, 50));
      expect(NavMath.metersToNm(d), closeTo(357.4, 0.1));
    });

    test('titik sama -> 0', () {
      expect(NavMath.distanceMeters(-3.32, 114.59, -3.32, 114.59), 0);
    });

    test('simetris', () {
      final a = NavMath.distanceMeters(-6.20, 106.85, -7.25, 112.75);
      final b = NavMath.distanceMeters(-7.25, 112.75, -6.20, 106.85);
      expect(a, closeTo(b, 0.001));
    });
  });

  group('bearingDegrees', () {
    test('Jakarta -> Surabaya ~100.5 derajat', () {
      final b = NavMath.bearingDegrees(-6.20, 106.85, -7.25, 112.75);
      expect(b, closeTo(100.5, 0.1));
    });

    test('tepat ke timur -> 90', () {
      expect(NavMath.bearingDegrees(0, 0, 0, 1), closeTo(90, 0.001));
    });

    test('tepat ke utara -> 0', () {
      expect(NavMath.bearingDegrees(0, 0, 1, 0), closeTo(0, 0.001));
    });

    test('hasil selalu 0..360', () {
      final b = NavMath.bearingDegrees(-7.25, 112.75, -6.20, 106.85);
      expect(b, greaterThanOrEqualTo(0));
      expect(b, lessThan(360));
    });
  });

  group('destinationPoint', () {
    test('Jakarta, haluan 100, 100 mil laut', () {
      final (lat, lon) = NavMath.destinationPoint(
        -6.20,
        106.85,
        100,
        100 * 1852,
      );
      expect(lat, closeTo(-6.4866, 0.001));
      expect(lon, closeTo(108.5008, 0.001));
    });

    test('bolak-balik konsisten', () {
      final (lat, lon) = NavMath.destinationPoint(
        -3.32,
        114.59,
        45,
        50000,
      );
      final back =
          NavMath.distanceMeters(-3.32, 114.59, lat, lon);
      expect(back, closeTo(50000, 1));
    });
  });

  group('konversi satuan', () {
    test('knot <-> km/jam', () {
      expect(NavMath.kmhToKnots(18.52), closeTo(10, 0.001));
      expect(NavMath.knotsToKmh(10), closeTo(18.52, 0.001));
    });

    test('m/s -> knot', () {
      expect(NavMath.msToKnots(1), closeTo(1.943844, 0.0001));
    });

    test('meter <-> mil laut', () {
      expect(NavMath.metersToNm(1852), 1);
      expect(NavMath.nmToMeters(2), 3704);
    });
  });

  group('etaDuration', () {
    test('100 mil laut @ 8 knot = 12.5 jam', () {
      final eta = NavMath.etaDuration(100 * 1852, 8);
      expect(eta, const Duration(seconds: 45000));
    });

    test('10 mil laut @ 8 knot = 75 menit', () {
      final eta = NavMath.etaDuration(10 * 1852, 8);
      expect(eta, const Duration(minutes: 75));
    });

    test('kecepatan 0 -> null', () {
      expect(NavMath.etaDuration(1000, 0), isNull);
      expect(NavMath.etaDuration(1000, -5), isNull);
    });
  });

  group('compassPoint', () {
    test('arah mata angin', () {
      expect(NavMath.compassPoint(0), 'Utara');
      expect(NavMath.compassPoint(45), 'Timur Laut');
      expect(NavMath.compassPoint(90), 'Timur');
      expect(NavMath.compassPoint(180), 'Selatan');
      expect(NavMath.compassPoint(270), 'Barat');
      // 100.5 derajat paling dekat ke Timur (90) daripada TTG (112.5).
      expect(NavMath.compassPoint(100.5), 'Timur');
      expect(NavMath.compassPoint(112.5), 'Timur Tenggara');
    });

    test('singkatan', () {
      expect(NavMath.compassPointShort(0), 'U');
      expect(NavMath.compassPointShort(90), 'T');
      expect(NavMath.compassPointShort(225), 'BD');
    });
  });

  group('formatDms', () {
    test('Banjarmasin', () {
      expect(
        NavMath.formatDms(-3.32, isLatitude: true),
        "S 3°19'12\"",
      );
      expect(
        NavMath.formatDms(114.59, isLatitude: false),
        "T 114°35'24\"",
      );
    });
  });

  group('normalizeDegrees', () {
    test('negatif dan > 360', () {
      expect(NavMath.normalizeDegrees(-10), 350);
      expect(NavMath.normalizeDegrees(370), 10);
      expect(NavMath.normalizeDegrees(360), 0);
    });
  });

  group('RouteMath', () {
    test('total jarak 2 kaki', () {
      final points = [
        (-6.20, 106.85),
        (-7.25, 112.75),
        (-7.25, 114.59),
      ];
      final total = RouteMath.totalDistanceM(points);
      final leg1 = NavMath.distanceMeters(-6.20, 106.85, -7.25, 112.75);
      final leg2 = NavMath.distanceMeters(-7.25, 112.75, -7.25, 114.59);
      expect(total, closeTo(leg1 + leg2, 0.001));
      expect(RouteMath.legs(points).length, 2);
    });

    test('ETA total', () {
      final eta = RouteMath.totalEta([(-6.20, 106.85), (-7.25, 112.75)], 8);
      expect(eta, isNotNull);
      expect(eta!.inHours, 44); // 357.4 nm / 8 kt = 44.7 jam
    });
  });
}
