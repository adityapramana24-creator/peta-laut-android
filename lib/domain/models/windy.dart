import 'dart:math' as math;

/// Model prakiraan Open-Meteo (paket Windy, R-30).
enum WindyModel { auto, gfs, icon, ecmwfIfs }

extension WindyModelInfo on WindyModel {
  /// Nilai parameter `models` Open-Meteo ('auto' = tidak dikirim).
  String get apiValue {
    switch (this) {
      case WindyModel.auto:
        return 'auto';
      case WindyModel.gfs:
        return 'gfs';
      case WindyModel.icon:
        return 'icon';
      case WindyModel.ecmwfIfs:
        return 'ecmwf_ifs';
    }
  }

  String get label {
    switch (this) {
      case WindyModel.auto:
        return 'Otomatis';
      case WindyModel.gfs:
        return 'GFS (AS)';
      case WindyModel.icon:
        return 'ICON (Jerman)';
      case WindyModel.ecmwfIfs:
        return 'ECMWF IFS (Eropa)';
    }
  }

  static WindyModel fromApiValue(String value) {
    switch (value) {
      case 'gfs':
        return WindyModel.gfs;
      case 'icon':
        return WindyModel.icon;
      case 'ecmwf_ifs':
        return WindyModel.ecmwfIfs;
      default:
        return WindyModel.auto;
    }
  }
}

/// Satu titik grid angin: posisi + deret angin per jam (72 jam).
class WindGridPoint {
  const WindGridPoint({
    required this.latitude,
    required this.longitude,
    required this.windKmh,
    required this.windDirDeg,
  });

  final double latitude;
  final double longitude;

  /// Kecepatan angin (km/jam) per jam; null = tidak ada data jam itu.
  final List<double?> windKmh;

  /// Arah angin DATANG DARI (derajat) per jam.
  final List<double?> windDirDeg;
}

/// Grid angin 5 x 4 titik dari Open-Meteo (satu request multi-lokasi).
/// Titik tersusun baris-per-baris: lintang selatan -> utara,
/// dalam tiap baris bujur barat -> timur.
class WindGrid {
  const WindGrid({
    required this.points,
    required this.columns,
    required this.rows,
    required this.times,
    required this.model,
    required this.fetchedAt,
  });

  final List<WindGridPoint> points;

  /// Jumlah kolom (bujur) dan baris (lintang) grid.
  final int columns;
  final int rows;

  /// Jam prakiraan (72 jam, Asia/Jakarta).
  final List<DateTime> times;

  final String model;
  final DateTime fetchedAt;

  double get south => points.map((p) => p.latitude).reduce(math.min);
  double get north => points.map((p) => p.latitude).reduce(math.max);
  double get west => points.map((p) => p.longitude).reduce(math.min);
  double get east => points.map((p) => p.longitude).reduce(math.max);

  /// Angin (kecepatan km/jam, arah derajat) di satu titik + indeks jam.
  /// Interpolasi bilinear komponen u/v; jatuh ke titik terdekat bila
  /// ada sudut grid yang datanya kosong. null bila tidak ada data sama
  /// sekali pada jam itu.
  (double, double)? windAt(double latitude, double longitude, int hourIndex) {
    if (points.isEmpty || times.isEmpty) return null;
    if (hourIndex < 0 || hourIndex >= times.length) return null;
    if (points.length != columns * rows) return _nearestWind(latitude, longitude, hourIndex);

    final latSpan = north - south;
    final lonSpan = east - west;
    if (latSpan <= 0 || lonSpan <= 0) {
      return _nearestWind(latitude, longitude, hourIndex);
    }
    final fx = ((longitude - west) / lonSpan * (columns - 1))
        .clamp(0.0, (columns - 1).toDouble());
    final fy = ((latitude - south) / latSpan * (rows - 1))
        .clamp(0.0, (rows - 1).toDouble());
    final x0 = fx.floor().clamp(0, columns - 1);
    final y0 = fy.floor().clamp(0, rows - 1);
    final x1 = (x0 + 1).clamp(0, columns - 1);
    final y1 = (y0 + 1).clamp(0, rows - 1);
    final tx = fx - x0;
    final ty = fy - y0;

    (double, double)? uvAt(int col, int row) {
      final point = points[row * columns + col];
      final speed = _at(point.windKmh, hourIndex);
      final dir = _at(point.windDirDeg, hourIndex);
      if (speed == null || dir == null) return null;
      // Arah angin DATANG DARI: komponen gerak udara berlawanan.
      final r = (dir + 180) * math.pi / 180;
      return (speed * math.sin(r), -speed * math.cos(r));
    }

    final uv00 = uvAt(x0, y0);
    final uv10 = uvAt(x1, y0);
    final uv01 = uvAt(x0, y1);
    final uv11 = uvAt(x1, y1);
    if (uv00 == null || uv10 == null || uv01 == null || uv11 == null) {
      return _nearestWind(latitude, longitude, hourIndex);
    }
    final u = _bilinear(uv00.$1, uv10.$1, uv01.$1, uv11.$1, tx, ty);
    final v = _bilinear(uv00.$2, uv10.$2, uv01.$2, uv11.$2, tx, ty);
    final speed = math.sqrt(u * u + v * v);
    if (speed < 0.05) return (0, 0);
    // Kembalikan arah DATANG DARI (konvensi Open-Meteo).
    final dirTo = (math.atan2(u, -v) * 180 / math.pi + 360) % 360;
    final dirFrom = (dirTo + 180) % 360;
    return (speed, dirFrom);
  }

  (double, double)? _nearestWind(double latitude, double longitude, int hourIndex) {
    WindGridPoint? best;
    var bestD = double.infinity;
    for (final p in points) {
      final speed = _at(p.windKmh, hourIndex);
      final dir = _at(p.windDirDeg, hourIndex);
      if (speed == null || dir == null) continue;
      final d = (p.latitude - latitude) * (p.latitude - latitude) +
          (p.longitude - longitude) * (p.longitude - longitude);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    if (best == null) return null;
    return (best.windKmh[hourIndex]!, best.windDirDeg[hourIndex]!);
  }

  static double? _at(List<double?> list, int i) =>
      i < list.length ? list[i] : null;

  static double _bilinear(
    double v00,
    double v10,
    double v01,
    double v11,
    double tx,
    double ty,
  ) {
    final a = v00 * (1 - tx) + v10 * tx;
    final b = v01 * (1 - tx) + v11 * tx;
    return a * (1 - ty) + b * ty;
  }
}

/// Cuaca di satu titik rute pada jam ETA-nya.
class RouteWeatherPoint {
  const RouteWeatherPoint({
    required this.waypointName,
    required this.eta,
    this.windKnots,
    this.windDirDeg,
    this.gustsKnots,
    this.waveHeightM,
    this.rainMm,
    this.tempC,
  });

  final String waypointName;
  final DateTime eta;
  final double? windKnots;
  final double? windDirDeg;
  final double? gustsKnots;
  final double? waveHeightM;
  final double? rainMm;
  final double? tempC;

  bool get hasData =>
      windKnots != null ||
      waveHeightM != null ||
      rainMm != null ||
      tempC != null;
}
