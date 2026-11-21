import 'nav_math.dart';

/// Logika alarm jangkar (murni, ditutup unit test):
/// jarak dari titik jangkar, di dalam / di luar radius, arah hanyut.
class AnchorWatch {
  AnchorWatch._();

  /// Jarak posisi saat ini dari titik jangkar (meter).
  static double distanceFromAnchorM({
    required double anchorLat,
    required double anchorLon,
    required double latitude,
    required double longitude,
  }) =>
      NavMath.distanceMeters(anchorLat, anchorLon, latitude, longitude);

  /// true bila posisi di luar radius jangkar (alarm berbunyi).
  /// Batas persis (= radius) dianggap masih aman.
  static bool isOutside({
    required double anchorLat,
    required double anchorLon,
    required double latitude,
    required double longitude,
    required double radiusM,
  }) =>
      distanceFromAnchorM(
        anchorLat: anchorLat,
        anchorLon: anchorLon,
        latitude: latitude,
        longitude: longitude,
      ) >
      radiusM;

  /// Bearing dari titik jangkar ke posisi saat ini (arah hanyut).
  static double driftBearingDeg({
    required double anchorLat,
    required double anchorLon,
    required double latitude,
    required double longitude,
  }) =>
      NavMath.bearingDegrees(anchorLat, anchorLon, latitude, longitude);
}
