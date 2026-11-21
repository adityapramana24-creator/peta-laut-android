/// Jam "sekarang" dalam zona WIB sebagai wall-clock (F-L4, perbaikan
/// terisolasi paket Windy).
///
/// Open-Meteo diminta dengan `timezone=Asia/Jakarta`, jadi JAM
/// prakiraan adalah wall-clock WIB — dan `DateTime.parse` atas
/// "2026-11-21T08:00" menghasilkan DateTime lokal-naif jam 08:00.
/// Membandingkan jam-jam itu dengan `DateTime.now()` (jam lokal
/// perangkat) BENAR hanya bila perangkat di WIB; di WITA/WIT
/// pemilihan slot "saat ini" bergeser 1–2 jam.
///
/// [now] mengembalikan jam-berjalan WIB sebagai DateTime lokal-naif
/// (komponen UTC + 7 jam) sehingga perbandingan wall-clock vs
/// wall-clock konsisten di zona mana pun perangkat berada.
///
/// BATAS: normalisasi ini hanya dipakai di titik pemilihan slot
/// "saat ini" paket Windy (grid angin/arus + evaluasi peringatan).
/// Panel Gelombang/Cuaca dan garis "sekarang" meteogram masih
/// memakai `DateTime.now()` langsung — refactor zona-waktu
/// app-wide (F-L4 penuh) ditunda ke ronde berikut.
class WibClock {
  WibClock._();

  /// Jam-berjalan WIB sebagai wall-clock lokal-naif.
  static DateTime now() {
    final utc = DateTime.now().toUtc();
    return DateTime(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    ).add(const Duration(hours: 7));
  }
}
