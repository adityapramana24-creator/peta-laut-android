/// Format tanggal/waktu Bahasa Indonesia TANPA package intl
/// (menghindari inisialisasi data locale; cukup untuk kebutuhan app).
/// Semua waktu tampil dalam WIB (UTC+7) — zona waktu acuan aplikasi.
class IdFormat {
  IdFormat._();

  static const List<String> monthShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static const List<String> dayNames = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  /// Konversi waktu UTC ke WIB (DateTime "naif" zona WIB).
  static DateTime toWib(DateTime utc) =>
      utc.toUtc().add(const Duration(hours: 7));

  /// Konversi waktu WIB (naif) kembali ke UTC.
  static DateTime wibToUtc(DateTime wib) =>
      DateTime.utc(wib.year, wib.month, wib.day, wib.hour, wib.minute,
              wib.second)
          .subtract(const Duration(hours: 7));

  /// "05:29"
  static String timeHm(DateTime dt) =>
      '${_two(dt.hour)}:${_two(dt.minute)}';

  /// "21 Nov"
  static String dateShort(DateTime dt) =>
      '${dt.day} ${monthShort[dt.month - 1]}';

  /// "21 Nov, 05.29"
  static String dateTimeShort(DateTime dt) =>
      '${dateShort(dt)}, ${timeHm(dt)}';

  /// "Sabtu, 21 Nov 2026"
  static String dayDateLong(DateTime dt) =>
      '${dayNames[dt.weekday - 1]}, ${dt.day} ${monthShort[dt.month - 1]} ${dt.year}';

  /// "2j 15m" / "45m" / "3h 05m" — durasi singkat.
  static String durationShort(Duration d) {
    if (d.inMinutes < 1) return '<1 mnt';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m mnt';
    if (m == 0) return '$h jam';
    return '$h jam $m mnt';
  }

  /// "2026-11-21" — kunci cache per hari.
  static String dateKey(DateTime dt) =>
      '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}
