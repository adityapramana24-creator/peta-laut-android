import '../../utils/nav_math.dart';

/// Pelabuhan referensi: koordinat + kode adm4 BMKG.
/// Koordinat 8 pelabuhan pertama + Ambon dari report.md (terverifikasi);
/// 6 lainnya adalah pusat kota (cukup untuk lompat peta + cuaca terdekat).
/// Kode adm4 dari pemetaan adm2→adm4 repo Prakiraan-Cuaca-Indonesia-BMKG
/// (report §10); 15 dari 15 DITES LIVE 21 Nov 2026 ~18:20 WIB
/// (api.bmkg.go.id/publik/prakiraan-cuaca?adm4=...): semua HTTP 200,
/// adm4 respons cocok, kota/provinsi benar, 17–18 jam prakiraan —
/// F-L8 SELESAI, tidak ada kode yang perlu diperbaiki.
class Port {
  const Port({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.adm4,
  });

  final String name;
  final double latitude;
  final double longitude;

  /// Kode kelurahan referensi kota ini untuk API BMKG.
  final String adm4;

  static const List<Port> all = [
    Port(name: 'Banjarmasin', latitude: -3.32, longitude: 114.59, adm4: '63.71.01.1001'),
    Port(name: 'Pontianak', latitude: -0.02, longitude: 109.34, adm4: '61.71.01.1002'),
    Port(name: 'Palembang', latitude: -2.99, longitude: 104.76, adm4: '16.71.01.1001'),
    Port(name: 'Belawan', latitude: 3.78, longitude: 98.68, adm4: '12.71.01.1001'),
    Port(name: 'Balikpapan', latitude: -1.24, longitude: 116.83, adm4: '64.71.01.1001'),
    Port(name: 'Surabaya', latitude: -7.25, longitude: 112.75, adm4: '35.78.01.1001'),
    Port(name: 'Jakarta', latitude: -6.20, longitude: 106.85, adm4: '31.71.01.1001'),
    Port(name: 'Sumbawa', latitude: -8.77, longitude: 117.42, adm4: '52.04.02.2001'),
    Port(name: 'Makassar', latitude: -5.15, longitude: 119.40, adm4: '73.71.01.1001'),
    Port(name: 'Denpasar', latitude: -8.65, longitude: 115.22, adm4: '51.71.01.1001'),
    Port(name: 'Manado', latitude: 1.49, longitude: 124.85, adm4: '71.71.01.1001'),
    Port(name: 'Ambon', latitude: -3.70, longitude: 128.17, adm4: '81.71.01.1006'),
    Port(name: 'Sorong', latitude: -0.88, longitude: 131.25, adm4: '96.71.01.1001'),
    Port(name: 'Jayapura', latitude: -2.53, longitude: 140.72, adm4: '91.71.01.1001'),
    Port(name: 'Kupang', latitude: -10.17, longitude: 123.60, adm4: '53.71.01.1001'),
  ];

  static Port byAdm4(String adm4) =>
      all.firstWhere((p) => p.adm4 == adm4, orElse: () => all.first);

  /// Pelabuhan terdekat dari satu titik (haversine).
  static Port nearest(double latitude, double longitude) {
    Port best = all.first;
    var bestDistance = double.infinity;
    for (final port in all) {
      final d = NavMath.distanceMeters(
        latitude,
        longitude,
        port.latitude,
        port.longitude,
      );
      if (d < bestDistance) {
        bestDistance = d;
        best = port;
      }
    }
    return best;
  }

  double distanceMetersTo(double latitude, double longitude) =>
      NavMath.distanceMeters(latitude, longitude, this.latitude, this.longitude);
}
