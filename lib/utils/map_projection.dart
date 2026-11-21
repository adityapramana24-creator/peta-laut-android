import 'dart:math' as math;

/// Proyeksi Web Mercator (EPSG:3857) lat/lon <-> titik layar.
/// Dipakai overlay partikel angin (butuh konversi tiap frame tanpa
/// bergantung pada API kamera flutter_map).
///
/// Rotasi peta (derajat, searah jarum jam, positif) diperhitungkan:
/// titik di timur tengah peta muncul di selatan tengah layar bila
/// rotasi 90°.
class MapProjection {
  MapProjection._();

  static const double tileSize = 256.0;

  /// Koordinat dunia (piksel) pada zoom z.
  static (double, double) project(double latitude, double longitude, double zoom) {
    final scale = tileSize * math.pow(2, zoom).toDouble();
    final x = (longitude + 180.0) / 360.0 * scale;
    final sinLat = math.sin(latitude * math.pi / 180);
    final y =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
            scale;
    return (x, y);
  }

  /// Invers project: piksel dunia -> (lat, lon).
  static (double, double) unproject(double wx, double wy, double zoom) {
    final scale = tileSize * math.pow(2, zoom).toDouble();
    final lon = wx / scale * 360.0 - 180.0;
    final n = math.pi * (1 - 2 * wy / scale);
    // sinh(n) = (e^n - e^-n) / 2 — dart:math tidak punya sinh.
    final sinhN = (math.exp(n) - math.exp(-n)) / 2;
    final lat = math.atan(sinhN) * 180 / math.pi;
    return (lat, lon);
  }

  /// lat/lon -> titik layar (piksel dari pojok kiri atas).
  static (double, double) latLonToScreen({
    required double latitude,
    required double longitude,
    required double centerLat,
    required double centerLon,
    required double zoom,
    required double rotationDeg,
    required double screenWidth,
    required double screenHeight,
  }) {
    final (wx, wy) = project(latitude, longitude, zoom);
    final (cx, cy) = project(centerLat, centerLon, zoom);
    final dx = wx - cx;
    final dy = wy - cy;
    // Rotasi searah jarum jam di koordinat layar (y ke bawah).
    final r = rotationDeg * math.pi / 180;
    final cosR = math.cos(r);
    final sinR = math.sin(r);
    final rx = dx * cosR - dy * sinR;
    final ry = dx * sinR + dy * cosR;
    return (screenWidth / 2 + rx, screenHeight / 2 + ry);
  }

  /// Titik layar -> lat/lon (invers latLonToScreen).
  static (double, double) screenToLatLon({
    required double screenX,
    required double screenY,
    required double centerLat,
    required double centerLon,
    required double zoom,
    required double rotationDeg,
    required double screenWidth,
    required double screenHeight,
  }) {
    final r = rotationDeg * math.pi / 180;
    final cosR = math.cos(r);
    final sinR = math.sin(r);
    final rx = screenX - screenWidth / 2;
    final ry = screenY - screenHeight / 2;
    // Invers rotasi.
    final dx = rx * cosR + ry * sinR;
    final dy = -rx * sinR + ry * cosR;
    final (cx, cy) = project(centerLat, centerLon, zoom);
    return unproject(cx + dx, cy + dy, zoom);
  }
}
