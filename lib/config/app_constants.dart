import 'package:flutter/material.dart';

/// Konstanta aplikasi: identitas, default peta, timeout, dan URL tile.
/// Stempel versi di sini adalah SATU-SATUNYA sumber versi yang tampil
/// di UI (splash, sudut peta, Pengaturan) — ubah di sini saat rilis baru.
class AppConstants {
  AppConstants._();

  static const String appName = 'Peta Laut';
  static const String packageId = 'id.prasmanan.petalaut';
  /// Kredit pembuat — satu istilah di seluruh aplikasi (S-13):
  /// "Developed by Prasmanan" (dipakai splash + Pengaturan).
  static const String credit = 'Developed by Prasmanan';

  /// Stempel versi yang terlihat di UI (R-38).
  static const String versionLabel = 'v1.2 · 21 Nov 2026';
  static const String versionName = '1.2.0';

  static const String safetyWarning =
      'Alat bantu saja. Bukan pengganti navigasi resmi kapal.';

  /// Tampilan awal: Indonesia (pusat ~-2.5, 113, zoom 5).
  static const double defaultLat = -2.5;
  static const double defaultLon = 113.0;
  static const double defaultZoom = 5.0;
  static const double minZoom = 3.0;
  static const double maxZoom = 19.0;

  /// Batas kawasan ASEAN (ronde 2, item 6): peta hanya menampilkan
  /// perairan ASEAN. Bbox lat -11..29, lon 92..141 — terverifikasi
  /// memuat titik ekstrem semua 11 negara ASEAN + 15 pelabuhan
  /// (lihat test/asean_bounds_test.dart): Filipina utara (Batanes
  /// 21,1°N), Myanmar utara (28,3°N) & barat (92,2°E), Indonesia
  /// selatan (P. Rote -11,0°S) & timur (141°E).
  static const double aseanSouth = -11.0;
  static const double aseanNorth = 29.0;
  static const double aseanWest = 92.0;
  static const double aseanEast = 141.0;

  /// Pusat bbox ASEAN + zoom awal (dipakai bersama initialCameraFit
  /// di MapScreen — fit yang menentukan bingkai pertama persis).
  static const double aseanCenterLat = 9.0;
  static const double aseanCenterLon = 116.5;
  static const double aseanInitialZoom = 3.5;

  /// Zoom minimum saat peta dibatasi ASEAN: 3,25 — di bawah zoom fit
  /// bbox pada layar HP (3,37–3,63 untuk lebar 360–430 px, lihat
  /// test/asean_bounds_test.dart) agar bingkai awal selalu memuat
  /// seluruh ASEAN, tapi cukup tinggi agar di zoom terendah pun
  /// kamera tetap berpusat di ASEAN (CameraConstraint.contain).
  /// RONDE 2 (S-14, P0): konstanta ini TERTINGGAL saat B menulis
  /// komentarnya — map_screen + test sudah memakainya. Tanpa baris
  /// ini CI analyze gagal ("getter isn't defined").
  static const double aseanMinZoom = 3.25;

  static const double defaultSpeedKnots = 8.0;

  /// Pasang surut lambat (~21 dtk, komputasi model) — batas 75 dtk.
  static const Duration tidesTimeout = Duration(seconds: 75);
  static const Duration apiTimeout = Duration(seconds: 45);
  static const Duration depthTimeout = Duration(seconds: 30);

  /// Kapal AIS dianggap hilang bila tidak terlihat selama ini.
  static const Duration vesselExpiry = Duration(minutes: 15);

  /// Cache tile: maks 500 MB (default flutter_map 1 GB).
  /// Kesegaran tile mengikuti header HTTP server (perilaku default
  /// flutter_map — memenuhi syarat kebanyakan server tile, termasuk
  /// kebijakan cache OSM). overrideFreshAge sengaja TIDAK dipakai:
  /// tipenya tidak terverifikasi di dokumentasi.
  static const int tileCacheMaxBytes = 500 * 1024 * 1024;

  static const String userAgent = 'PetaLaut/1.2 (id.prasmanan.petalaut)';

  /// Tautan peringatan gelombang tinggi BMKG — halaman resmi yang
  /// langsung menampilkan prakiraan/peringatan gelombang per provinsi
  /// (server-rendered, ringan untuk koneksi kapal).
  /// Terverifikasi live 21 Nov 2026: berisi Peringatan Gelombang Tinggi
  /// per provinsi (tinggi meter + kondisi sinoptik).
  /// Homepage maritim.bmkg.go.id adalah SPA berat-JS ("Memuat data...")
  /// sehingga di koneksi lambat tampak kosong — jangan pakai sebagai
  /// tautan gelombang. (Ronde 2, item 3.)
  static const String bmkgWaveUrl =
      'https://www.bmkg.go.id/peringatan-dini/gelombang-tinggi';
  static const String aisSignupUrl = 'https://aisstream.io/';

  /// Halaman resmi Berita Pelaut Indonesia (BPI) Pushidrosal —
  /// unduhan PDF koreksi mingguan Peta Laut Indonesia (narasi
  /// koreksi, bukan dataset — tautan ini yang dipakai lembar detail
  /// rambu sebagai "Cek BPI terbaru").
  /// Terverifikasi live 21 Nov 2026: berisi tautan edisi terbaru
  /// (Minggu ke-43 Tahun 2026) + tabel arsip edisi.
  static const String bpiUrl = 'https://www.pushidrosal.id/layanan/bpi';

  // -- URL tile (semua terverifikasi live, lihat report.md) --
  static const String osmDeTemplate =
      'https://tile.openstreetmap.de/{z}/{x}/{y}.png';
  static const String seamarkTemplate =
      'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png';
  static const String esriSatelliteTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const String esriOceanTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Ocean/World_Ocean_Base/MapServer/tile/{z}/{y}/{x}';
  static const String topoTemplate =
      'https://tile.opentopomap.org/{z}/{x}/{y}.png';
  static const String gebcoWmsBase = 'https://wms.gebco.net/mapserv?';

  static const Color seedColor = Color(0xFF0B3D66);
  static const Color splashBackground = Color(0xFF0A2239);
  static const Color goldAccent = Color(0xFFD4A017);
}
