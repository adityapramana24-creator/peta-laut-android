/// Wilayah laut untuk ramalan gelombang per wilayah (R-15, ronde 2).
///
/// SUMBER NAMA + KODE: pembagian wilayah perairan resmi BMKG, seri
/// nasional "Indonesia" (M.01–M.42) dari endpoint meta publik BMKG:
/// https://maritim.bmkg.go.id/marine2026-data/meta/area_province.json
/// (dibaca 21 Nov 2026; halaman web yang sama tampil di
/// https://www.bmkg.go.id/cuaca/maritim — "Indonesia: 42 Perairan").
/// Nama dipakai VERBATIM dari BMKG (termasuk ejaan "Arafuru").
/// Tiga wilayah di luar pembagian BMKG (Laut Cina Selatan, Teluk
/// Thailand, Laut Andaman) ditandai `bmkgCode: null` — ditambahkan
/// karena user menyebut Laut Cina Selatan dan cakupan app adalah ASEAN.
///
/// TITIK REPRESENTATIF: satu koordinat tengah wilayah per item. BUKAN
/// rata-rata wilayah — ramalan yang ditampilkan adalah ramalan
/// Open-Meteo Marine DI TITIK ITU, dan UI wajib menulis itu eksplisit.
/// Titik dipilih di laut terbuka (tengah selat/laut, jauh dari garis
/// pantai dan pulau) lalu DIVERIFIKASI HIDUP 21 Nov 2026 18:07 WIB:
/// satu panggilan Open-Meteo Marine (marine-api.open-meteo.com, hourly
/// wave_height, 1 hari) untuk ke-23 titik — ke-23 titik mengembalikan
/// 24/24 nilai wave_height non-null (titik darat mengembalikan null
/// semua). Dua titik digeser dari tebakan awal sebelum verifikasi:
/// Laut Bali digeser ke utara (-7,6) agar jauh dari pantai utara Bali
/// (Singaraja -8,1); Laut Seram digeser ke timur (-2,0; 131,5) agar
/// tidak jatuh di Pulau Seram. Bila satu titik gagal verifikasi,
/// wilayah itu dikeluarkan dari daftar (tidak terjadi 21 Nov 2026).
/// Field [SeaRegion.verifiedAtSea] mencatat hasil verifikasi itu agar
/// bisa diasert di test; wilayah baru WAJIB diverifikasi dulu dengan
/// cara yang sama sebelum `verifiedAtSea: true`.
///
/// KATEGORI GELOMBANG: skala resmi BMKG, [bmkgWaveCategory].

/// Satu wilayah laut + titik representatif tengah wilayahnya.
class SeaRegion {
  const SeaRegion({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.verifiedAtSea,
    this.bmkgCode,
  });

  /// ID stabil: kode BMKG (M.xx) untuk wilayah BMKG, kode singkat
  /// untuk wilayah non-BMKG (SCS/GOT/ANDA).
  final String id;

  /// Nama wilayah — verbatim BMKG untuk wilayah berkode M.xx.
  final String name;

  /// Titik representatif tengah wilayah (laut terbuka).
  final double latitude;
  final double longitude;

  /// Kode wilayah BMKG (M.xx), atau null bila di luar pembagian BMKG.
  final String? bmkgCode;

  /// True bila titik sudah diverifikasi berada di laut lewat panggilan
  /// Open-Meteo Marine live (lihat komentar file). Jangan set true
  /// tanpa verifikasi.
  final bool verifiedAtSea;
}

/// Daftar wilayah laut, urut barat → timur (lalu 3 wilayah non-BMKG).
const List<SeaRegion> kSeaRegions = [
  SeaRegion(
    id: 'M.01',
    name: 'Selat Malaka bagian utara',
    latitude: 5.5,
    longitude: 98.8,
    bmkgCode: 'M.01',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.02',
    name: 'Selat Malaka bagian tengah',
    latitude: 3.0,
    longitude: 100.3,
    bmkgCode: 'M.02',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.16',
    name: 'Laut Natuna Utara',
    latitude: 5.0,
    longitude: 109.0,
    bmkgCode: 'M.16',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.17',
    name: 'Selat Karimata bagian utara',
    latitude: -1.0,
    longitude: 108.7,
    bmkgCode: 'M.17',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.18',
    name: 'Selat Karimata bagian selatan',
    latitude: -2.8,
    longitude: 109.3,
    bmkgCode: 'M.18',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.19',
    name: 'Laut Jawa bagian barat',
    latitude: -5.3,
    longitude: 108.5,
    bmkgCode: 'M.19',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.20',
    name: 'Laut Jawa bagian tengah',
    latitude: -5.5,
    longitude: 111.5,
    bmkgCode: 'M.20',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.21',
    name: 'Laut Jawa bagian timur',
    latitude: -5.8,
    longitude: 114.5,
    bmkgCode: 'M.21',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.22',
    name: 'Selat Makassar bagian utara',
    latitude: 0.5,
    longitude: 118.8,
    bmkgCode: 'M.22',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.23',
    name: 'Selat Makassar bagian tengah',
    latitude: -1.5,
    longitude: 118.2,
    bmkgCode: 'M.23',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.24',
    name: 'Selat Makassar bagian selatan',
    latitude: -4.0,
    longitude: 118.0,
    bmkgCode: 'M.24',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.25',
    name: 'Laut Bali',
    latitude: -7.6,
    longitude: 115.0,
    bmkgCode: 'M.25',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.27',
    name: 'Laut Flores',
    latitude: -8.0,
    longitude: 120.0,
    bmkgCode: 'M.27',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.29',
    name: 'Laut Banda',
    latitude: -5.5,
    longitude: 127.0,
    bmkgCode: 'M.29',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.30',
    name: 'Laut Seram',
    latitude: -2.0,
    longitude: 131.5,
    bmkgCode: 'M.30',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.35',
    name: 'Laut Sulawesi bagian barat',
    latitude: 2.5,
    longitude: 121.0,
    bmkgCode: 'M.35',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.38',
    name: 'Laut Maluku',
    latitude: 0.5,
    longitude: 126.0,
    bmkgCode: 'M.38',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.09',
    name: 'Samudra Hindia selatan Jawa Barat',
    latitude: -8.8,
    longitude: 107.0,
    bmkgCode: 'M.09',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.12',
    name: 'Samudra Hindia selatan Jawa Timur',
    latitude: -9.5,
    longitude: 113.0,
    bmkgCode: 'M.12',
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'M.33',
    name: 'Laut Arafuru bagian tengah',
    latitude: -8.5,
    longitude: 133.5,
    bmkgCode: 'M.33',
    verifiedAtSea: true,
  ),
  // Di luar pembagian wilayah BMKG (bmkgCode null) — cakupan ASEAN.
  SeaRegion(
    id: 'SCS',
    name: 'Laut Cina Selatan',
    latitude: 12.0,
    longitude: 114.0,
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'GOT',
    name: 'Teluk Thailand',
    latitude: 9.0,
    longitude: 101.0,
    verifiedAtSea: true,
  ),
  SeaRegion(
    id: 'ANDA',
    name: 'Laut Andaman',
    latitude: 8.0,
    longitude: 96.0,
    verifiedAtSea: true,
  ),
];

/// Halaman resmi BMKG "Cuaca Maritim" — daftar prakiraan per wilayah
/// perairan Indonesia (server-rendered; terverifikasi live 21 Nov 2026
/// 18:07 WIB). Dipakai sebagai tautan "prakiraan resmi BMKG per
/// wilayah" di panel Gelombang. BUKAN tautan per wilayah tunggal —
/// BMKG tidak menyediakan URL per wilayah yang bisa diverifikasi
/// (situs maritim.bmkg.go.id adalah SPA); user memilih wilayah di
/// halaman ini.
const String kBmkgMaritimUrl = 'https://www.bmkg.go.id/cuaca/maritim';

/// Kategori tinggi gelombang resmi BMKG (skala 7 tingkat, dari
/// https://www.bmkg.go.id/cuaca/maritim — dicek 21 Nov 2026):
/// 0–0,5 m Tenang; 0,5–1,25 m Rendah; 1,25–2,5 m Sedang; 2,5–4 m
/// Tinggi; 4–6 m Sangat Tinggi; 6–9 m Ekstrem; >9 m Sangat Ekstrem.
/// Catatan: sebagian halaman BMKG (mis. stamar-merak.bmkg.go.id)
/// menggabung ≥6 m sebagai "Ekstrem" saja; skala 7 tingkat di atas
/// adalah yang tampil di halaman maritim utama BMKG.
/// Batas bawah inklusif: tepat 0,5 → Rendah, tepat 2,5 → Tinggi, dst.
String bmkgWaveCategory(double heightM) {
  if (heightM < 0.5) return 'Tenang';
  if (heightM < 1.25) return 'Rendah';
  if (heightM < 2.5) return 'Sedang';
  if (heightM < 4) return 'Tinggi';
  if (heightM < 6) return 'Sangat Tinggi';
  if (heightM < 9) return 'Ekstrem';
  return 'Sangat Ekstrem';
}
