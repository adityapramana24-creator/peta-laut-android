import 'package:flutter/material.dart';

/// Konstanta aplikasi: identitas, default peta, timeout, dan URL tile.
/// Stempel versi di sini adalah SATU-SATUNYA sumber versi yang tampil
/// di UI (splash, sudut peta, Pengaturan) — ubah di sini saat rilis baru.
class AppConstants {
  AppConstants._();

  static const String appName = 'Peta Laut';
  static const String packageId = 'id.prasmanan.petalaut';
  static const String credit = 'Buatan Prasmanan';

  /// Stempel versi yang terlihat di UI (R-38).
  static const String versionLabel = 'v1.1 · 21 Nov 2026';
  static const String versionName = '1.1.0';

  static const String safetyWarning =
      'Alat bantu saja. Bukan pengganti navigasi resmi kapal.';

  /// Tampilan awal: Indonesia (pusat ~-2.5, 113, zoom 5).
  static const double defaultLat = -2.5;
  static const double defaultLon = 113.0;
  static const double defaultZoom = 5.0;
  static const double minZoom = 3.0;
  static const double maxZoom = 19.0;

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

  static const String userAgent = 'PetaLaut/1.1 (id.prasmanan.petalaut)';

  /// Tautan prakiraan gelombang BMKG (BMKG tidak punya API gelombang).
  static const String bmkgWaveUrl = 'https://maritim.bmkg.go.id/';
  static const String aisSignupUrl = 'https://aisstream.io/';

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
