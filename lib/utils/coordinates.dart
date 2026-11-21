/// Parsing koordinat yang diketik user (jalur cadangan bila GPS tidak ada).
///
/// Menerima desimal titik maupun koma desimal Indonesia:
///   "-3.32, 114.59" · "-3,32, 114,59" · "-3.32 114.59" · "-3,32; 114,59"
/// Dua angka pertama yang ditemukan dipakai sebagai (lintang, bujur).
/// Mengembalikan null bila tidak ada dua angka valid dalam rentang.
class CoordinateInput {
  CoordinateInput._();

  static final _numberPattern = RegExp(r'-?\d+(?:[.,]\d+)?');

  static (double, double)? parseLatLon(String input) {
    final matches = _numberPattern.allMatches(input).toList();
    if (matches.length < 2) return null;
    final lat = _parseNumber(matches[0].group(0)!);
    final lon = _parseNumber(matches[1].group(0)!);
    if (lat == null || lon == null) return null;
    if (lat < -90 || lat > 90) return null;
    if (lon < -180 || lon > 180) return null;
    return (lat, lon);
  }

  static double? _parseNumber(String raw) {
    // Koma desimal Indonesia -> titik. Satu angka hanya punya satu
    // pemisah desimal karena pola regex di atas.
    return double.tryParse(raw.replaceAll(',', '.'));
  }
}
