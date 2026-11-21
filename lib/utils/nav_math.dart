import 'dart:math' as math;

import 'formatters.dart';

/// Matematika navigasi murni (tanpa dependensi Flutter) — haversine,
/// bearing, titik tujuan, konversi satuan, dan format koordinat.
/// Semua fungsi di sini ditutup unit test (test/nav_math_test.dart).
class NavMath {
  NavMath._();

  static const double earthRadiusM = 6371000.0;
  static const double metersPerNauticalMile = 1852.0;
  static const double kmhPerKnot = 1.852;

  static double toRadians(double degrees) => degrees * math.pi / 180.0;
  static double toDegrees(double radians) => radians * 180.0 / math.pi;

  /// Jarak great-circle (haversine) dalam meter.
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final p1 = toRadians(lat1);
    final p2 = toRadians(lat2);
    final dp = toRadians(lat2 - lat1);
    final dl = toRadians(lon2 - lon1);
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  /// Bearing awal (arah haluan) dari titik 1 ke titik 2, derajat 0..360.
  static double bearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final p1 = toRadians(lat1);
    final p2 = toRadians(lat2);
    final dl = toRadians(lon2 - lon1);
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    return normalizeDegrees(toDegrees(math.atan2(y, x)));
  }

  /// Titik tujuan dari titik awal, bearing (derajat), dan jarak (meter).
  /// Mengembalikan record (latitude, longitude).
  static (double, double) destinationPoint(
    double lat,
    double lon,
    double bearingDeg,
    double distanceM,
  ) {
    final d = distanceM / earthRadiusM;
    final b = toRadians(bearingDeg);
    final p1 = toRadians(lat);
    final l1 = toRadians(lon);
    final p2 = math.asin(math.sin(p1) * math.cos(d) +
        math.cos(p1) * math.sin(d) * math.cos(b));
    final l2 = l1 +
        math.atan2(math.sin(b) * math.sin(d) * math.cos(p1),
            math.cos(d) - math.sin(p1) * math.sin(p2));
    return (toDegrees(p2), normalizeLongitude(toDegrees(l2)));
  }

  /// Normalisasi sudut ke 0..360.
  static double normalizeDegrees(double degrees) {
    var d = degrees % 360.0;
    if (d < 0) d += 360.0;
    return d;
  }

  /// Normalisasi bujur ke -180..180.
  static double normalizeLongitude(double longitude) {
    var l = (longitude + 540.0) % 360.0 - 180.0;
    if (l == -180.0 && longitude > 0) l = 180.0;
    return l;
  }

  static double kmhToKnots(double kmh) => kmh / kmhPerKnot;
  static double knotsToKmh(double knots) => knots * kmhPerKnot;
  static double msToKnots(double ms) => ms * 1.943844;
  static double knotsToMs(double knots) => knots / 1.943844;
  static double metersToNm(double meters) => meters / metersPerNauticalMile;
  static double metersToKm(double meters) => meters / 1000.0;
  static double nmToMeters(double nm) => nm * metersPerNauticalMile;

  /// Estimasi waktu tempuh. null bila kecepatan tidak valid (<= 0).
  static Duration? etaDuration(double distanceM, double speedKnots) {
    if (speedKnots <= 0 || distanceM < 0) return null;
    final seconds = distanceM / (speedKnots * metersPerNauticalMile / 3600.0);
    return Duration(seconds: seconds.round());
  }

  /// Nama mata angin 16 arah dalam Bahasa Indonesia.
  static String compassPoint(double degrees) {
    const points = [
      'Utara',
      'Utara Timur Laut',
      'Timur Laut',
      'Timur Timur Laut',
      'Timur',
      'Timur Tenggara',
      'Tenggara',
      'Selatan Tenggara',
      'Selatan',
      'Selatan Barat Daya',
      'Barat Daya',
      'Barat Barat Daya',
      'Barat',
      'Barat Barat Laut',
      'Barat Laut',
      'Utara Barat Laut',
    ];
    final index =
        ((normalizeDegrees(degrees) + 11.25) / 22.5).floor() % 16;
    return points[index];
  }

  /// Singkatan mata angin 16 arah (U, UTL, TL, ...).
  static String compassPointShort(double degrees) {
    const points = [
      'U',
      'UTL',
      'TL',
      'TTL',
      'T',
      'TTG',
      'TG',
      'STG',
      'S',
      'SBD',
      'BD',
      'BBD',
      'B',
      'BBL',
      'BL',
      'UBL',
    ];
    final index =
        ((normalizeDegrees(degrees) + 11.25) / 22.5).floor() % 16;
    return points[index];
  }

  /// Format satu koordinat ke derajat-menit-detik, mis. 3°19'12"S.
  static String formatDms(double value, {required bool isLatitude}) {
    final hemisphere = isLatitude
        ? (value < 0 ? 'S' : 'U')
        : (value < 0 ? 'B' : 'T');
    final abs = value.abs();
    final deg = abs.floor();
    final minFloat = (abs - deg) * 60;
    final min = minFloat.floor();
    final sec = ((minFloat - min) * 60).round();
    // Bila pembulatan detik jadi 60, geser ke menit (kasus langka).
    if (sec == 60) {
      final min2 = min + 1;
      if (min2 == 60) return "$hemisphere ${deg + 1}°00'00\"";
      return "$hemisphere $deg°${_two(min2)}'00\"";
    }
    return "$hemisphere $deg°${_two(min)}'${_two(sec)}\"";
  }

  /// Format pasangan lat/lon ke DMS dua baris pendek.
  static String formatLatLonDms(double lat, double lon) =>
      '${formatDms(lat, isLatitude: true)}  ${formatDms(lon, isLatitude: false)}';

  /// Format desimal dengan jumlah digit tetap (tanpa pemisah ribuan).
  static String formatDecimal(double value, {int fractionDigits = 5}) =>
      value.toStringAsFixed(fractionDigits);

  /// Format jarak: "< 1 km" dalam meter, "1,2 km" di bawah 1 nm,
  /// "12.3 nm (22.8 km)" di atas 1 nm (nm + km, sesuai R-10).
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    if (meters < metersPerNauticalMile) {
      return '${metersToKm(meters).toStringAsFixed(1)} km';
    }
    return '${metersToNm(meters).toStringAsFixed(1)} nm '
        '(${metersToKm(meters).toStringAsFixed(1)} km)';
  }

  /// Format ETA: "2 jam 15 mnt" / "45 mnt" / "—" bila null.
  static String formatEta(Duration? eta) =>
      eta == null ? '—' : IdFormat.durationShort(eta);

  /// Format durasi: sama dengan formatEta tanpa null.
  static String formatDuration(Duration d) => IdFormat.durationShort(d);

  /// Format tanggal+waktu: "21 Nov, 05.29".
  static String formatDateTime(DateTime dt) => IdFormat.dateTimeShort(dt);

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Satu kaki rute: dari satu titik ke titik berikut.
class RouteLeg {
  const RouteLeg({
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
  });

  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;

  double get distanceM =>
      NavMath.distanceMeters(fromLat, fromLon, toLat, toLon);
  double get bearingDeg =>
      NavMath.bearingDegrees(fromLat, fromLon, toLat, toLon);
  Duration? etaAt(double speedKnots) =>
      NavMath.etaDuration(distanceM, speedKnots);
}

/// Hitungan rute dari daftar titik (lat, lon) berurutan.
/// Dipakai fondasi waypoint/rute (UI lengkap oleh Builder 2).
class RouteMath {
  RouteMath._();

  static List<RouteLeg> legs(List<(double, double)> points) {
    final result = <RouteLeg>[];
    for (var i = 0; i + 1 < points.length; i++) {
      result.add(RouteLeg(
        fromLat: points[i].$1,
        fromLon: points[i].$2,
        toLat: points[i + 1].$1,
        toLon: points[i + 1].$2,
      ));
    }
    return result;
  }

  static double totalDistanceM(List<(double, double)> points) =>
      legs(points).fold(0.0, (sum, leg) => sum + leg.distanceM);

  static Duration? totalEta(
    List<(double, double)> points,
    double speedKnots,
  ) =>
      NavMath.etaDuration(totalDistanceM(points), speedKnots);
}
