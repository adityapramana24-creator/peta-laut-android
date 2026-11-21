import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/domain/models/waypoint.dart';
import 'package:peta_laut/utils/anchor_math.dart';
import 'package:peta_laut/utils/nav_math.dart';
import 'package:peta_laut/utils/track_stats.dart';

void main() {
  group('RouteMath multi-leg', () {
    // Jakarta -> Surabaya -> Makassar -> Ambon (4 titik, 3 kaki).
    final points = [
      (-6.20, 106.85),
      (-7.25, 112.75),
      (-5.15, 119.40),
      (-3.70, 128.17),
    ];

    test('3 kaki, total = jumlah kaki', () {
      final legs = RouteMath.legs(points);
      expect(legs.length, 3);
      final leg1 = NavMath.distanceMeters(-6.20, 106.85, -7.25, 112.75);
      final leg2 = NavMath.distanceMeters(-7.25, 112.75, -5.15, 119.40);
      final leg3 = NavMath.distanceMeters(-5.15, 119.40, -3.70, 128.17);
      expect(RouteMath.totalDistanceM(points),
          closeTo(leg1 + leg2 + leg3, 0.001));
      expect(legs[0].distanceM, closeTo(leg1, 0.001));
      expect(legs[1].distanceM, closeTo(leg2, 0.001));
      expect(legs[2].distanceM, closeTo(leg3, 0.001));
    });

    test('bearing tiap kaki 0..360', () {
      for (final leg in RouteMath.legs(points)) {
        expect(leg.bearingDeg, greaterThanOrEqualTo(0));
        expect(leg.bearingDeg, lessThan(360));
      }
      // Kaki pertama ke timur-tenggara (~100 derajat).
      expect(RouteMath.legs(points)[0].bearingDeg, closeTo(100.5, 0.5));
    });

    test('ETA total = total jarak / kecepatan', () {
      final total = RouteMath.totalDistanceM(points);
      final eta = RouteMath.totalEta(points, 8);
      expect(eta, isNotNull);
      final expectedSeconds =
          (total / (8 * 1852 / 3600)).round();
      expect(eta!.inSeconds, expectedSeconds);
    });

    test('kasus kosong / satu titik', () {
      expect(RouteMath.legs([]), isEmpty);
      expect(RouteMath.legs([(-6.20, 106.85)]), isEmpty);
      expect(RouteMath.totalDistanceM([]), 0);
      expect(RouteMath.totalDistanceM([(-6.20, 106.85)]), 0);
      expect(RouteMath.totalEta([], 8), Duration.zero);
      expect(RouteMath.totalEta(points, 0), isNull);
    });
  });

  group('TrackStats', () {
    List<TrackPoint> track() => [
          TrackPoint(
            latitude: -6.20,
            longitude: 106.85,
            recordedAt: DateTime.utc(2026, 11, 21, 0, 0),
          ),
          TrackPoint(
            latitude: -7.25,
            longitude: 112.75,
            recordedAt: DateTime.utc(2026, 11, 21, 6, 0),
          ),
          TrackPoint(
            latitude: -7.25,
            longitude: 114.59,
            recordedAt: DateTime.utc(2026, 11, 21, 8, 30),
          ),
        ];

    test('jarak total = jumlah antar titik', () {
      final points = track();
      final leg1 = NavMath.distanceMeters(-6.20, 106.85, -7.25, 112.75);
      final leg2 = NavMath.distanceMeters(-7.25, 112.75, -7.25, 114.59);
      expect(TrackStats.totalDistanceM(points), closeTo(leg1 + leg2, 0.001));
    });

    test('durasi 8,5 jam + kecepatan rata-rata', () {
      final points = track();
      expect(
        TrackStats.duration(points),
        const Duration(hours: 8, minutes: 30),
      );
      final totalNm = NavMath.metersToNm(TrackStats.totalDistanceM(points));
      expect(
        TrackStats.averageSpeedKnots(points),
        closeTo(totalNm / 8.5, 0.01),
      );
    });

    test('kasus kosong / satu titik', () {
      expect(TrackStats.totalDistanceM([]), 0);
      expect(TrackStats.duration([]), isNull);
      expect(
        TrackStats.duration([
          TrackPoint(
            latitude: -6.20,
            longitude: 106.85,
            recordedAt: DateTime.utc(2026, 11, 21),
          ),
        ]),
        isNull,
      );
      expect(TrackStats.averageSpeedKnots([]), isNull);
    });
  });

  group('AnchorWatch', () {
    const anchorLat = -3.32;
    const anchorLon = 114.59;

    test('jarak 40 m ke utara', () {
      final (lat, lon) = NavMath.destinationPoint(
        anchorLat,
        anchorLon,
        0,
        40,
      );
      final d = AnchorWatch.distanceFromAnchorM(
        anchorLat: anchorLat,
        anchorLon: anchorLon,
        latitude: lat,
        longitude: lon,
      );
      expect(d, closeTo(40, 0.1));
    });

    test('di dalam radius 50 m, di luar radius 30 m', () {
      final (lat, lon) = NavMath.destinationPoint(
        anchorLat,
        anchorLon,
        90,
        40,
      );
      expect(
        AnchorWatch.isOutside(
          anchorLat: anchorLat,
          anchorLon: anchorLon,
          latitude: lat,
          longitude: lon,
          radiusM: 50,
        ),
        isFalse,
      );
      expect(
        AnchorWatch.isOutside(
          anchorLat: anchorLat,
          anchorLon: anchorLon,
          latitude: lat,
          longitude: lon,
          radiusM: 30,
        ),
        isTrue,
      );
    });

    test('batas persis radius dianggap aman', () {
      final (lat, lon) = NavMath.destinationPoint(
        anchorLat,
        anchorLon,
        180,
        50,
      );
      // Radius sedikit di atas jarak -> di dalam.
      expect(
        AnchorWatch.isOutside(
          anchorLat: anchorLat,
          anchorLon: anchorLon,
          latitude: lat,
          longitude: lon,
          radiusM: 50.5,
        ),
        isFalse,
      );
    });

    test('arah hanyut = bearing dari jangkar', () {
      final (lat, lon) = NavMath.destinationPoint(
        anchorLat,
        anchorLon,
        45,
        100,
      );
      expect(
        AnchorWatch.driftBearingDeg(
          anchorLat: anchorLat,
          anchorLon: anchorLon,
          latitude: lat,
          longitude: lon,
        ),
        closeTo(45, 0.5),
      );
    });
  });
}
