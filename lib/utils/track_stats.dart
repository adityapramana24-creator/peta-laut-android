import '../domain/models/waypoint.dart';
import 'nav_math.dart';

/// Statistik jejak (track): jarak total, durasi, kecepatan rata-rata.
/// Murni — ditutup unit test (test/navigation_math_test.dart).
class TrackStats {
  TrackStats._();

  /// Jarak total jejak (meter) — jumlah jarak antar titik berurutan.
  static double totalDistanceM(List<TrackPoint> points) {
    var total = 0.0;
    for (var i = 0; i + 1 < points.length; i++) {
      total += NavMath.distanceMeters(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
    }
    return total;
  }

  /// Durasi jejak (titik pertama -> terakhir). null bila < 2 titik.
  static Duration? duration(List<TrackPoint> points) {
    if (points.length < 2) return null;
    final d = points.last.recordedAt.difference(points.first.recordedAt);
    return d.isNegative ? Duration.zero : d;
  }

  /// Kecepatan rata-rata (knot). null bila durasi tidak valid.
  static double? averageSpeedKnots(List<TrackPoint> points) {
    final d = duration(points);
    if (d == null || d.inSeconds <= 0) return null;
    final nm = NavMath.metersToNm(totalDistanceM(points));
    return nm / (d.inSeconds / 3600.0);
  }
}
