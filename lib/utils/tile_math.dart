import 'dart:math' as math;

/// Matematika tile Slippy Map (OSM/Esri/OpenTopoMap) — murni, tanpa
/// dependensi Flutter. Dipakai fitur "Simpan area ini" (offline).
///
/// Terverifikasi: Banjarmasin (-3.32, 114.59) zoom 12 -> x=3351, y=2085
/// (sama persis dengan bukti riset report.md §3).
class TileMath {
  TileMath._();

  /// Tile (x, y) yang memuat satu titik pada zoom z.
  static (int, int) latLonToTile(double latitude, double longitude, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    final max = (n - 1).toInt();
    var x = ((longitude + 180.0) / 360.0 * n).floor();
    final latRad = latitude * math.pi / 180;
    // asinh(tan φ) = ln(tan φ + sec φ) — dart:math tidak punya asinh.
    final merc = math.log(math.tan(latRad) + 1 / math.cos(latRad));
    var y = ((1.0 - merc / math.pi) / 2.0 * n).floor();
    x = x.clamp(0, max);
    y = y.clamp(0, max);
    return (x, y);
  }

  /// Rentang tile yang menutupi satu kotak batas pada zoom z.
  /// Bujur barat > timur (melewati antimeridian) tidak didukung —
  /// Indonesia (95°–141°T) tidak pernah melewatinya.
  static TileRange rangeForBounds({
    required double south,
    required double west,
    required double north,
    required double east,
    required int zoom,
  }) {
    final s = south < north ? south : north;
    final n = south < north ? north : south;
    final w = west < east ? west : east;
    final e = west < east ? east : west;
    final (xMin, yMin) = latLonToTile(n, w, zoom);
    final (xMax, yMax) = latLonToTile(s, e, zoom);
    return TileRange(
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
      zoom: zoom,
    );
  }

  /// Isi placeholder {z}/{x}/{y} pada template URL tile.
  /// Berfungsi untuk urutan {z}/{x}/{y} (OSM) maupun {z}/{y}/{x} (Esri).
  static String tileUrl(String template, int z, int x, int y) =>
      template
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');
}

/// Rentang tile persegi (inklusif) pada satu zoom.
class TileRange {
  const TileRange({
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.zoom,
  });

  final int xMin;
  final int yMin;
  final int xMax;
  final int yMax;
  final int zoom;

  int get width => xMax - xMin + 1;
  int get height => yMax - yMin + 1;
  int get count => width * height;

  /// Semua koordinat tile (x, y) dalam rentang, baris per baris.
  Iterable<(int, int)> get tiles sync* {
    for (var y = yMin; y <= yMax; y++) {
      for (var x = xMin; x <= xMax; x++) {
        yield (x, y);
      }
    }
  }
}
