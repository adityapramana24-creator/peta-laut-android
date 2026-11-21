import 'dart:math' as math;

/// Matahari terbit/terbenam (algoritma NOAA) + fase bulan.
/// Murni Dart, tanpa API — jalan offline penuh.
///
/// Terverifikasi terhadap nilai publik 21 Nov 2026 (lihat
/// test/sun_moon_test.dart): Jakarta terbit 05:26 WIB (referensi
/// weather.com 05:25), terbenam 17:51 WIB (referensi 17:50/17:51);
/// bulan umur 11,6 hari, iluminasi 89% (referensi 86–89%,
/// Waxing Gibbous); purnama 24 Nov 2026 100%, bulan baru 9 Des 2026 0%.
class SunMoon {
  SunMoon._();

  /// Panjang bulan sinodis (rata-rata), hari.
  static const double synodicMonthDays = 29.530588853;

  /// Bulan baru acuan: 6 Jan 2000 18:14 UTC.
  static final DateTime _referenceNewMoon =
      DateTime.utc(2000, 1, 6, 18, 14);

  /// Zenith resmi matahari terbit/terbenam (refraksi + radius piringan).
  static const double _sunriseZenithDeg = 90.833;

  /// Offset zona waktu (jam) dari bujur — pembulatan ke jam terdekat.
  static int timezoneOffsetHours(double longitude) =>
      (longitude / 15).round();

  /// Label zona dari offset jam (Indonesia: WIB/WITA/WIT).
  static String timezoneLabel(int offsetHours) {
    switch (offsetHours) {
      case 7:
        return 'WIB';
      case 8:
        return 'WITA';
      case 9:
        return 'WIT';
      default:
        return offsetHours >= 0 ? 'UTC+$offsetHours' : 'UTC$offsetHours';
    }
  }

  /// Matahari terbit & terbenam pada satu tanggal di satu titik.
  /// `date` adalah tanggal lokal (tahun/bulan/hari dipakai).
  /// `timezoneOffsetHours` default dihitung dari bujur.
  /// Mengembalikan record (terbit, terbenam) sebagai DateTime "naif"
  /// zona setempat, atau (null, null) bila matahari tidak terbit /
  /// tidak terbenam hari itu (daerah kutub — tidak terjadi di Indonesia).
  static (DateTime?, DateTime?) sunTimes({
    required double latitude,
    required double longitude,
    required DateTime date,
    int? timezoneOffsetHours,
  }) {
    final tz = timezoneOffsetHours ?? SunMoon.timezoneOffsetHours(longitude);
    final jd = _julianDay(date.year, date.month, date.day);
    final t = _julianCentury(jd);
    final decl = _sunDeclination(t);
    final eqTime = _equationOfTime(t);
    final ha = _hourAngle(latitude, decl);
    if (ha == null) return (null, null);

    // Tengah hari solar dalam menit sejak tengah malam (waktu setempat).
    final solarNoonMin = 720 - 4 * longitude - eqTime + tz * 60;
    final rise = _minutesToDateTime(date, solarNoonMin - ha * 4);
    final set = _minutesToDateTime(date, solarNoonMin + ha * 4);
    return (rise, set);
  }

  /// Fase bulan pada satu saat (UTC).
  static MoonPhase moonPhase(DateTime momentUtc) {
    final age = momentUtc
            .toUtc()
            .difference(_referenceNewMoon)
            .inSeconds /
        86400 %
        synodicMonthDays;
    final angle = 2 * math.pi * age / synodicMonthDays;
    final illumination = (1 - math.cos(angle)) / 2;
    final phaseIndex =
        ((age / synodicMonthDays) * 8 + 0.5).floor() % 8;
    return MoonPhase(
      ageDays: age,
      illumination: illumination,
      phaseIndex: phaseIndex,
    );
  }

  static DateTime _minutesToDateTime(DateTime date, double minutes) {
    var total = minutes.round();
    var dayOffset = 0;
    while (total < 0) {
      total += 1440;
      dayOffset -= 1;
    }
    while (total >= 1440) {
      total -= 1440;
      dayOffset += 1;
    }
    final day = DateTime(date.year, date.month, date.day)
        .add(Duration(days: dayOffset));
    return DateTime(day.year, day.month, day.day, total ~/ 60, total % 60);
  }

  // -- Algoritma NOAA (NOAA Solar Calculator) --

  static double _julianDay(int year, int month, int day) {
    var y = year;
    var m = month;
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = y ~/ 100;
    final b = 2 - a + a ~/ 4;
    return (365.25 * (y + 4716)).floor() +
        (30.6001 * (m + 1)).floor() +
        day +
        b -
        1524.5;
  }

  static double _julianCentury(double julianDay) =>
      (julianDay - 2451545.0) / 36525.0;

  static double _geomMeanLongSun(double t) {
    final l0 = 280.46646 + t * (36000.76983 + t * 0.0003032);
    return l0 % 360;
  }

  static double _geomMeanAnomSun(double t) =>
      357.52911 + t * (35999.05029 - 0.0001537 * t);

  static double _eccentEarthOrbit(double t) =>
      0.016708634 - t * (0.000042037 + 0.0000001267 * t);

  static double _sunEqOfCtr(double t) {
    final m = _geomMeanAnomSun(t);
    final mr = m * math.pi / 180;
    return math.sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        math.sin(2 * mr) * (0.019993 - 0.000101 * t) +
        math.sin(3 * mr) * 0.000289;
  }

  static double _sunTrueLong(double t) =>
      _geomMeanLongSun(t) + _sunEqOfCtr(t);

  static double _sunAppLong(double t) {
    final o = _sunTrueLong(t) -
        0.00569 -
        0.00478 * math.sin((125.04 - 1934.136 * t) * math.pi / 180);
    return o;
  }

  static double _meanObliqEcliptic(double t) {
    return 23 +
        (26 +
                (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) /
                    60) /
            60;
  }

  static double _obliqCorr(double t) {
    return _meanObliqEcliptic(t) +
        0.00256 *
            math.cos((125.04 - 1934.136 * t) * math.pi / 180);
  }

  static double _sunDeclination(double t) {
    final e = _obliqCorr(t) * math.pi / 180;
    final lambda = _sunAppLong(t) * math.pi / 180;
    return math.asin(math.sin(e) * math.sin(lambda)) * 180 / math.pi;
  }

  static double _varY(double t) {
    final e = _obliqCorr(t) * math.pi / 180;
    final tanHalf = math.tan(e / 2);
    return tanHalf * tanHalf;
  }

  /// Equation of time, menit.
  static double _equationOfTime(double t) {
    final l0 = _geomMeanLongSun(t) * math.pi / 180;
    final e = _eccentEarthOrbit(t);
    final m = _geomMeanAnomSun(t) * math.pi / 180;
    final y = _varY(t);
    final eq = y * math.sin(2 * l0) -
        2 * e * math.sin(m) +
        4 * e * y * math.sin(m) * math.cos(2 * l0) -
        0.5 * y * y * math.sin(4 * l0) -
        1.25 * e * e * math.sin(2 * m);
    return eq * 180 / math.pi * 4;
  }

  /// Sudut jam matahari terbit/terbenam, derajat. null bila matahari
  /// tidak terbit / tidak terbenam hari itu.
  static double? _hourAngle(double latitude, double declination) {
    final latR = latitude * math.pi / 180;
    final declR = declination * math.pi / 180;
    final cosH = (math.cos(_sunriseZenithDeg * math.pi / 180) -
            math.sin(latR) * math.sin(declR)) /
        (math.cos(latR) * math.cos(declR));
    if (cosH > 1 || cosH < -1) return null;
    return math.acos(cosH) * 180 / math.pi;
  }
}

/// Fase bulan: umur (hari sejak bulan baru), iluminasi (0..1),
/// dan indeks fase 0..7.
class MoonPhase {
  const MoonPhase({
    required this.ageDays,
    required this.illumination,
    required this.phaseIndex,
  });

  final double ageDays;

  /// Fraksi piringan bulan yang terang (0 = baru, 1 = purnama).
  final double illumination;

  /// 0 baru, 1 sabit awal, 2 perbani awal, 3 benjol awal,
  /// 4 purnama, 5 benjol akhir, 6 perbani akhir, 7 sabit akhir.
  final int phaseIndex;

  static const List<String> phaseNames = [
    'Bulan baru',
    'Sabit awal',
    'Perbani awal',
    'Benjol awal',
    'Purnama',
    'Benjol akhir',
    'Perbani akhir',
    'Sabit akhir',
  ];

  String get name => phaseNames[phaseIndex];

  /// Membesar (waxing): fase 0..3; mengecil (waning): 4..7.
  bool get isWaxing => phaseIndex < 4;

  /// Sudut fase (radian, 0 = baru, π = purnama) — untuk gambar bulan.
  double get phaseAngle =>
      2 * math.pi * ageDays / SunMoon.synodicMonthDays;
}
