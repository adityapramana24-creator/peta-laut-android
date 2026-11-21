import '../config/app_constants.dart';

/// Hasil parse satu koordinat: [value] bila berhasil, [error] (pesan
/// Bahasa Indonesia yang jelas) bila gagal. Salah satu selalu null.
class ParsedCoordinate {
  const ParsedCoordinate.ok(this.value) : error = null;
  const ParsedCoordinate.fail(this.error) : value = null;

  final double? value;
  final String? error;

  bool get isOk => value != null;
}

/// Parsing koordinat yang diketik user (jalur cadangan bila GPS tidak
/// ada + form waypoint ketik, ronde 2).
///
/// Desimal (titik maupun koma desimal Indonesia):
///   "-3.32, 114.59" · "-3,32, 114,59" · "-3.32 114.59"
/// DMS (derajat-menit-detik) satu koordinat:
///   "6°07'24\"S" · "S 6°07'24\"" · "6 07 24 S" · "6°07.5'S" ·
///   "6.1234°S" · "106°49'30\"E"
/// Huruf belahan: N/U = utara, S = selatan, E/T = timur, W/B = barat
/// (huruf Indonesia U/T/B diterima). Bila ada huruf belahan, huruf
/// menentukan tanda (tanda minus di angka diabaikan).
class CoordinateInput {
  CoordinateInput._();

  static final _numberPattern = RegExp(r'-?\d+(?:[.,]\d+)?');

  /// Simbol DMS yang diganti spasi saat tokenisasi.
  static const _dmsSymbols = [
    '°',
    'º',
    "'",
    '"',
    '′',
    '″',
    '’',
    '”',
  ];

  /// Parse pasangan "lintang, bujur" dalam satu teks.
  /// Menerima desimal (dua angka pertama dipakai) dan pasangan DMS
  /// ("6°07'24\"S 106°49'30\"E", "6.12 S, 106.5 E").
  /// Mengembalikan null bila tidak ada dua koordinat valid.
  static (double, double)? parseLatLon(String input) {
    // Ada penanda DMS -> jalur DMS; bila gagal, JANGAN jatuh ke jalur
    // angka (regex angka akan salah membaca 6°07'24" sebagai 6, 07).
    if (_hasDmsMarker(input)) return _parseDmsPair(input);
    final matches = _numberPattern.allMatches(input).toList();
    if (matches.length < 2) return null;
    final lat = _parseNumber(matches[0].group(0)!);
    final lon = _parseNumber(matches[1].group(0)!);
    if (lat == null || lon == null) return null;
    if (lat < -90 || lat > 90) return null;
    if (lon < -180 || lon > 180) return null;
    return (lat, lon);
  }

  /// Parse SATU koordinat (lintang bila [isLatitude], else bujur).
  /// Otomatis mengenali desimal dan DMS. Gagal -> [ParsedCoordinate]
  /// dengan [ParsedCoordinate.error] berisi alasan Bahasa Indonesia.
  static ParsedCoordinate parseCoordinate(
    String input, {
    required bool isLatitude,
  }) {
    // Buang pemisah pasangan yang tertinggal di ujung (", " / ";").
    var rest = input
        .trim()
        .replaceAll(RegExp(r'^[,;]+'), '')
        .replaceAll(RegExp(r'[,;]+$'), '')
        .trim();
    if (rest.isEmpty) {
      return const ParsedCoordinate.fail('Koordinat kosong.');
    }

    // 1. Huruf belahan: akhir dulu ("...24\"S"), lalu awal ("S 6°...").
    String? hemi;
    final last = rest[rest.length - 1];
    if (_isHemisphereLetter(last)) {
      hemi = last.toUpperCase();
      rest = rest.substring(0, rest.length - 1).trim();
    } else {
      final first = rest[0];
      if (_isHemisphereLetter(first)) {
        final second = rest.length > 1 ? rest[1] : '';
        if (second == ' ' ||
            second == '°' ||
            second == '-' ||
            second == '+' ||
            _isDigit(second)) {
          hemi = first.toUpperCase();
          rest = rest.substring(1).trim();
        }
      }
    }

    // 2. Huruf harus sesuai sumbu.
    if (hemi != null) {
      final okLat = hemi == 'N' || hemi == 'S' || hemi == 'U';
      final okLon =
          hemi == 'E' || hemi == 'W' || hemi == 'T' || hemi == 'B';
      if (isLatitude && !okLat) {
        return ParsedCoordinate.fail(
          'Huruf $hemi untuk bujur, bukan lintang. '
          'Pakai U (utara) atau S (selatan).',
        );
      }
      if (!isLatitude && !okLon) {
        return ParsedCoordinate.fail(
          'Huruf $hemi untuk lintang, bukan bujur. '
          'Pakai T (timur) atau B (barat).',
        );
      }
    }

    // 3. Ganti simbol DMS dengan spasi, pecah menjadi token angka.
    var cleaned = rest;
    for (final sym in _dmsSymbols) {
      cleaned = cleaned.replaceAll(sym, ' ');
    }
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return const ParsedCoordinate.fail('Tidak ada angka yang bisa dibaca.');
    }
    if (tokens.length > 3) {
      return const ParsedCoordinate.fail(
        'Terlalu banyak angka — isi satu koordinat saja '
        '(derajat, atau derajat menit detik).',
      );
    }
    final numbers = <double>[];
    for (final token in tokens) {
      final n = _parseNumber(token);
      if (n == null) {
        return ParsedCoordinate.fail(
          '"$token" bukan angka. Contoh: -6,1234 atau 6°07\'24"S.',
        );
      }
      numbers.add(n);
    }

    // 4. Hitung nilai desimal.
    final negativeFromHemi =
        hemi == 'S' || hemi == 'B' || hemi == 'W';
    double value;
    if (numbers.length == 1) {
      value = numbers[0];
      if (hemi != null) {
        value = value.abs() * (negativeFromHemi ? -1 : 1);
      }
    } else {
      final deg = numbers[0];
      final min = numbers[1];
      final sec = numbers.length == 3 ? numbers[2] : 0.0;
      if (min < 0 || sec < 0) {
        return const ParsedCoordinate.fail(
          'Menit/detik tidak boleh negatif.',
        );
      }
      if (min >= 60) {
        return const ParsedCoordinate.fail('Menit harus 0–59.');
      }
      if (sec >= 60) {
        return const ParsedCoordinate.fail('Detik harus 0–59.');
      }
      final magnitude = deg.abs() + min / 60 + sec / 3600;
      final sign = hemi != null
          ? (negativeFromHemi ? -1.0 : 1.0)
          : (deg < 0 ? -1.0 : 1.0);
      value = magnitude * sign;
    }

    // 5. Validasi rentang.
    final max = isLatitude ? 90.0 : 180.0;
    final label = isLatitude ? 'Lintang' : 'Bujur';
    if (value < -max || value > max) {
      return ParsedCoordinate.fail(
        '$label harus -${max.toStringAsFixed(0)} sampai '
        '${max.toStringAsFixed(0)}.',
      );
    }
    return ParsedCoordinate.ok(value);
  }

  /// Parse DMS saja (ketat): gagal bila tidak ada penanda DMS
  /// (simbol ° ' " atau huruf belahan). Desimal polos ditolak.
  static ParsedCoordinate parseDms(
    String input, {
    required bool isLatitude,
  }) {
    if (!_hasDmsMarker(input)) {
      return const ParsedCoordinate.fail(
        'Bukan format DMS — perlu simbol ° \' " atau huruf belahan '
        '(U/S untuk lintang, T/B untuk bujur).',
      );
    }
    return parseCoordinate(input, isLatitude: isLatitude);
  }

  /// Cek titik di dalam bbox ASEAN (lintang -11..29, bujur 92..141).
  static bool isInAsean(double latitude, double longitude) =>
      latitude >= AppConstants.aseanSouth &&
      latitude <= AppConstants.aseanNorth &&
      longitude >= AppConstants.aseanWest &&
      longitude <= AppConstants.aseanEast;

  /// Pasangan DMS dalam satu teks: coba potong di setiap pemisah
  /// (spasi/koma/titik-koma) dan di sekitar huruf belahan, dari kiri
  /// ke kanan; potongan pertama yang membuat kedua belah pihak valid
  /// dipakai. Menangani gaya akhiran ("6°07'24\"S 106°49'30\"E"),
  /// gaya awalan ("S 6°07'24\" E 106°49'30\""), satu huruf saja,
  /// dan tanpa pemisah ("6°07'24\"S106°49'30\"E"). Tanpa pemisah
  /// dan tanpa huruf, token genap dibagi dua (derajat / DM / DMS).
  /// Gaya yang tidak bisa dipotong dengan benar ditolak (null).
  static (double, double)? _parseDmsPair(String input) {
    final cuts = <int>{};
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (c == ' ' || c == ',' || c == ';' || c == '\t') {
        cuts.add(i);
      }
      if (!_isHemisphereLetter(c)) continue;
      final prev = i > 0 ? input[i - 1] : '';
      final next = i + 1 < input.length ? input[i + 1] : '';
      // Huruf di dalam kata (mis. 'n' pada "lon") bukan belahan.
      if (_isAsciiLetter(prev) || _isAsciiLetter(next)) continue;
      cuts.add(i);
      cuts.add(i + 1);
    }
    final ordered = cuts.toList()..sort();
    for (final cut in ordered) {
      if (cut <= 0 || cut >= input.length) continue;
      final lat =
          parseCoordinate(input.substring(0, cut), isLatitude: true);
      if (!lat.isOk) continue;
      final lon =
          parseCoordinate(input.substring(cut), isLatitude: false);
      if (lon.isOk) return (lat.value!, lon.value!);
    }
    // Tanpa pemisah/huruf: bagi token genap (derajat / DM / DMS
    // per sumbu).
    var cleaned = input;
    for (final sym in _dmsSymbols) {
      cleaned = cleaned.replaceAll(sym, ' ');
    }
    final tokens = cleaned
        .split(RegExp(r'[\s,;]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length != 2 && tokens.length != 4 && tokens.length != 6) {
      return null;
    }
    final half = tokens.length ~/ 2;
    final lat = parseCoordinate(
      tokens.sublist(0, half).join(' '),
      isLatitude: true,
    );
    final lon = parseCoordinate(
      tokens.sublist(half).join(' '),
      isLatitude: false,
    );
    if (lat.isOk && lon.isOk) return (lat.value!, lon.value!);
    return null;
  }

  static bool _hasDmsMarker(String input) {
    for (final sym in _dmsSymbols) {
      if (input.contains(sym)) return true;
    }
    for (var i = 0; i < input.length; i++) {
      if (!_isHemisphereLetter(input[i])) continue;
      final prev = i > 0 ? input[i - 1] : '';
      final next = i + 1 < input.length ? input[i + 1] : '';
      if (!_isAsciiLetter(prev) && !_isAsciiLetter(next)) return true;
    }
    return false;
  }

  static bool _isHemisphereLetter(String c) =>
      c.length == 1 && 'NSUEWTBnsuewtb'.contains(c);

  static bool _isAsciiLetter(String c) =>
      c.length == 1 &&
      ((c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
          (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122));

  static bool _isDigit(String c) =>
      c.length == 1 &&
      c.codeUnitAt(0) >= 48 &&
      c.codeUnitAt(0) <= 57;

  static double? _parseNumber(String raw) {
    // Koma desimal Indonesia -> titik. Satu angka hanya punya satu
    // pemisah desimal karena pola regex di atas.
    return double.tryParse(raw.replaceAll(',', '.'));
  }
}
