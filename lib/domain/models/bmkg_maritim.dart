import '../../utils/formatters.dart';

/// Prakiraan maritim resmi BMKG per wilayah perairan
/// (API Data Maritim BMKG — https://maritim.bmkg.go.id/apidoc,
/// endpoint /perairan/{KODE}.json; publik, GET, tanpa auth).
///
/// BENTUK DATA (terverifikasi live 21 Nov 2026, kode M.01/M.09/M.19/
/// M.33): top-level code, name, no_surat, nama_prakirawan,
/// nama_stasiun, alamat_stasiun, telp_stasiun, email_stasiun,
/// issued, valid_from, valid_to (semua waktu "YYYY-MM-DD HH:00 UTC"),
/// forecast_day1 (24 entri per jam) + forecast_day2-4 (per 3 jam,
/// 17 entri s.d. valid_to). Entri jam: time, weather, temp_avg,
/// rh_avg, wind_from, wind_speed, wind_gust, wave_cat, wave_height,
/// current_to, current_speed.
///
/// SATUAN: gelombang meter, angin/gust knot, arus knot, suhu °C,
/// RH %. wind_from dan current_to adalah NAMA arah kompas Bahasa
/// Indonesia ("Tenggara", "Timur Laut", ...) — BUKAN derajat.
/// TIDAK ADA arah/periode gelombang di API ini (hanya wave_height +
/// wave_cat) — UI wajib tidak mengarang keduanya.
///
/// SEMUA waktu disimpan sebagai DateTime UTC ([DateTime.isUtc]
/// true); tampilan mengonversi ke WIB via [IdFormat.toWib] dengan
/// label zona "WIB" yang jelas. Parsing defensif: field tak dikenal
/// diabaikan, field hilang -> null, entri tanpa jam valid dilewati —
/// jangan pernah crash karena respons berubah bentuk.
class BmkgMaritimHour {
  const BmkgMaritimHour({
    required this.timeUtc,
    this.weather,
    this.tempAvgC,
    this.rhAvgPct,
    this.windFrom,
    this.windSpeedKt,
    this.windGustKt,
    this.waveCat,
    this.waveHeightM,
    this.currentTo,
    this.currentSpeedKt,
  });

  /// Jam prakiraan, UTC (dari "YYYY-MM-DD HH:00 UTC").
  final DateTime timeUtc;

  /// Kondisi cuaca Bahasa Indonesia ("Hujan Ringan", "Berawan Tebal").
  final String? weather;

  /// Suhu rata-rata °C.
  final double? tempAvgC;

  /// Kelembapan rata-rata %.
  final double? rhAvgPct;

  /// Angin DARI arah (nama kompas ID, mis. "Tenggara").
  final String? windFrom;

  /// Kecepatan angin knot.
  final double? windSpeedKt;

  /// Hembusan (gust) knot.
  final double? windGustKt;

  /// Kategori gelombang BMKG ("Tenang".."Sangat Ekstrem").
  final String? waveCat;

  /// Tinggi gelombang meter.
  final double? waveHeightM;

  /// Arus MENUJU arah (nama kompas ID, mis. "Barat Daya").
  final String? currentTo;

  /// Kecepatan arus knot.
  final double? currentSpeedKt;

  bool get hasWave => waveHeightM != null;

  /// Jam ini dalam WIB untuk tampilan: DateTime UTC yang komponen
  /// jamnya sudah digeser +7 (lihat [IdFormat.toWib]) — baca
  /// .hour/.day-nya untuk label, jangan bandingkan instannya
  /// dengan DateTime lokal.
  DateTime get timeWib => IdFormat.toWib(timeUtc);

  static double? _num(dynamic v) =>
      v is num ? v.toDouble() : null;

  static String? _str(dynamic v) =>
      v is String && v.isNotEmpty ? v : null;

  /// null bila jam tidak bisa diparse — pemanggil melewati entri ini.
  static BmkgMaritimHour? tryFromJson(Map<String, dynamic> json) {
    final time = parseBmkgUtcTime(json['time'] as String?);
    if (time == null) return null;
    return BmkgMaritimHour(
      timeUtc: time,
      weather: _str(json['weather']),
      tempAvgC: _num(json['temp_avg']),
      rhAvgPct: _num(json['rh_avg']),
      windFrom: _str(json['wind_from']),
      windSpeedKt: _num(json['wind_speed']),
      windGustKt: _num(json['wind_gust']),
      waveCat: _str(json['wave_cat']),
      waveHeightM: _num(json['wave_height']),
      currentTo: _str(json['current_to']),
      currentSpeedKt: _num(json['current_speed']),
    );
  }

  Map<String, dynamic> toJson() => {
        'time': timeUtc.toIso8601String(),
        'weather': weather,
        'temp_avg': tempAvgC,
        'rh_avg': rhAvgPct,
        'wind_from': windFrom,
        'wind_speed': windSpeedKt,
        'wind_gust': windGustKt,
        'wave_cat': waveCat,
        'wave_height': waveHeightM,
        'current_to': currentTo,
        'current_speed': currentSpeedKt,
      };

  /// Cache memakai ISO 8601 ("...Z") — diparse via [DateTime.parse],
  /// bukan format BMKG "YYYY-MM-DD HH:00 UTC".
  factory BmkgMaritimHour.fromCacheJson(Map<String, dynamic> json) {
    final parsed = DateTime.parse(json['time'] as String);
    return BmkgMaritimHour(
      timeUtc: parsed.toUtc(),
      weather: _str(json['weather']),
      tempAvgC: _num(json['temp_avg']),
      rhAvgPct: _num(json['rh_avg']),
      windFrom: _str(json['wind_from']),
      windSpeedKt: _num(json['wind_speed']),
      windGustKt: _num(json['wind_gust']),
      waveCat: _str(json['wave_cat']),
      waveHeightM: _num(json['wave_height']),
      currentTo: _str(json['current_to']),
      currentSpeedKt: _num(json['current_speed']),
    );
  }
}

/// Prakiraan BMKG satu wilayah perairan (kode M.xx).
class BmkgMaritimForecast {
  const BmkgMaritimForecast({
    required this.code,
    required this.name,
    required this.issuedUtc,
    required this.validFromUtc,
    required this.validToUtc,
    required this.day1,
    required this.day2to4,
    required this.fetchedAt,
    this.isStale = false,
  });

  /// Kode wilayah BMKG (M.xx).
  final String code;

  /// Nama wilayah verbatim BMKG.
  final String name;

  /// Waktu terbit prakiraan (UTC). null bila field hilang.
  final DateTime? issuedUtc;

  /// Awal masa berlaku (UTC). null bila field hilang.
  final DateTime? validFromUtc;

  /// Akhir masa berlaku (UTC). null bila field hilang.
  final DateTime? validToUtc;

  /// Hari pertama: per jam (24 entri).
  final List<BmkgMaritimHour> day1;

  /// Hari ke-2 s.d. ke-4: per 3 jam.
  final List<BmkgMaritimHour> day2to4;

  /// Kapan data ini diambil dari server (jam lokal perangkat).
  final DateTime fetchedAt;

  /// True bila data ini dari cache karena fetch gagal (offline).
  final bool isStale;

  BmkgMaritimForecast copyWith({bool? isStale}) {
    return BmkgMaritimForecast(
      code: code,
      name: name,
      issuedUtc: issuedUtc,
      validFromUtc: validFromUtc,
      validToUtc: validToUtc,
      day1: day1,
      day2to4: day2to4,
      fetchedAt: fetchedAt,
      isStale: isStale ?? this.isStale,
    );
  }

  /// Semua jam, urut waktu (day1 lalu day2-4).
  List<BmkgMaritimHour> get allHours => [...day1, ...day2to4];

  /// false bila kedua daftar kosong — service menolak respons ini.
  bool get hasData => day1.isNotEmpty || day2to4.isNotEmpty;

  /// Jam terdekat dengan [nowUtc] (UTC). null bila tidak ada jam.
  BmkgMaritimHour? currentAt(DateTime nowUtc) {
    final hours = allHours;
    if (hours.isEmpty) return null;
    BmkgMaritimHour best = hours.first;
    var bestDiff = best.timeUtc.difference(nowUtc).abs();
    for (final h in hours) {
      final diff = h.timeUtc.difference(nowUtc).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = h;
      }
    }
    return best;
  }

  /// Jam terdekat dengan sekarang.
  BmkgMaritimHour? get current =>
      currentAt(DateTime.now().toUtc());

  /// True bila [nowUtc] sudah melewati valid_to. Tanpa valid_to,
  /// tidak bisa dinyatakan kedaluwarsa (jujur: unknown, bukan basi).
  bool isExpiredAt(DateTime nowUtc) =>
      validToUtc != null && nowUtc.isAfter(validToUtc!);

  bool get isExpired => isExpiredAt(DateTime.now().toUtc());

  /// True bila [nowUtc] berada dalam [validFromUtc]..[validToUtc].
  /// Batas yang hilang dianggap tidak membatasi.
  bool isValidAt(DateTime nowUtc) {
    if (validFromUtc != null && nowUtc.isBefore(validFromUtc!)) {
      return false;
    }
    return !isExpiredAt(nowUtc);
  }

  bool get isValidNow => isValidAt(DateTime.now().toUtc());

  static List<BmkgMaritimHour> _parseHours(dynamic raw) {
    final hours = <BmkgMaritimHour>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          final hour = BmkgMaritimHour.tryFromJson(item);
          if (hour != null) hours.add(hour);
        }
      }
    }
    return hours;
  }

  factory BmkgMaritimForecast.fromJson(
    Map<String, dynamic> json, {
    String? codeFallback,
    required DateTime fetchedAt,
  }) {
    final code = json['code'];
    return BmkgMaritimForecast(
      code: code is String && code.isNotEmpty
          ? code
          : (codeFallback ?? ''),
      name: json['name'] is String ? json['name'] as String : '',
      issuedUtc: parseBmkgUtcTime(json['issued'] as String?),
      validFromUtc: parseBmkgUtcTime(json['valid_from'] as String?),
      validToUtc: parseBmkgUtcTime(json['valid_to'] as String?),
      day1: _parseHours(json['forecast_day1']),
      day2to4: _parseHours(json['forecast_day2-4']),
      fetchedAt: fetchedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'issued': issuedUtc?.toIso8601String(),
        'valid_from': validFromUtc?.toIso8601String(),
        'valid_to': validToUtc?.toIso8601String(),
        'forecast_day1': day1.map((h) => h.toJson()).toList(),
        'forecast_day2-4': day2to4.map((h) => h.toJson()).toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory BmkgMaritimForecast.fromCacheJson(Map<String, dynamic> json) {
    DateTime? parseIso(dynamic v) {
      if (v is! String) return null;
      return DateTime.tryParse(v)?.toUtc();
    }

    List<BmkgMaritimHour> parseCached(dynamic raw) {
      final hours = <BmkgMaritimHour>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            try {
              hours.add(BmkgMaritimHour.fromCacheJson(item));
            } catch (_) {
              // Entri cache rusak dilewati, sisanya tetap dipakai.
            }
          }
        }
      }
      return hours;
    }

    return BmkgMaritimForecast(
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      issuedUtc: parseIso(json['issued']),
      validFromUtc: parseIso(json['valid_from']),
      validToUtc: parseIso(json['valid_to']),
      day1: parseCached(json['forecast_day1']),
      day2to4: parseCached(json['forecast_day2-4']),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    );
  }
}

/// Parse waktu BMKG "YYYY-MM-DD HH:00 UTC" (detik opsional) menjadi
/// DateTime UTC. null bila format tidak dikenali / komponen di luar
/// rentang — pemanggil memperlakukannya sebagai field hilang, bukan
/// crash. Sengaja regex, bukan DateTime.parse: format BMKG memakai
/// spasi + sufiks " UTC" yang bukan ISO 8601.
DateTime? parseBmkgUtcTime(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.endsWith('UTC')) s = s.substring(0, s.length - 3).trim();
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$',
  ).firstMatch(s);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6) ?? '0');
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  return DateTime.utc(year, month, day, hour, minute, second);
}
