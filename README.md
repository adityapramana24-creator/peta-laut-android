# Peta Laut — Aplikasi Android (Flutter)

Chart laut pribadi untuk perairan Indonesia: peta interaktif, GPS,
pasang surut, cuaca BMKG, gelombang, kedalaman GEBCO, kapal AIS,
waypoint/rute, jejak, alarm jangkar, MOB, paket Windy, dan peta
offline. Semua sumber data gratis; tanpa iklan, tanpa akun.

- **Nama app:** Peta Laut · **applicationId:** `id.prasmanan.petalaut`
- **Versi:** 1.1.0+2 · **Stempel UI:** v1.1 · 21 Nov 2026
- **Bahasa UI:** Indonesia · **Target:** Android 7.0+ (minSdk 24)

> **Keselamatan:** aplikasi ini alat bantu saja — bukan pengganti
> navigasi resmi kapal. Banner peringatan tampil permanen di atas peta.

## Build (via GitHub Actions — tidak ada SDK lokal)

Project ini ditulis tangan tanpa Flutter/Dart SDK di VM pengembang;
**CI adalah compiler-nya.** Workflow ada di
`.github/workflows/build-apk.yml`:

1. Push ke `main`/`master` (atau tag `v*`, atau manual via
   **Actions → Build APK → Run workflow**).
2. CI menjalankan: `flutter pub get` → `dart run build_runner build`
   (codegen Drift) → `flutter analyze` → `flutter test` →
   `flutter build apk --release`.
3. APK tersedia sebagai artifact **peta-laut-apk**; untuk tag `v*`
   APK juga diterbitkan sebagai GitHub Release.

**Asumsi lokasi workflow:** isi direktori `app/` di-push sebagai
**root repo**. Bila repo menyimpan `app/` sebagai subdirektori,
pindahkan workflow ke `.github/workflows/` di root repo dan tambahkan
`defaults.run.working-directory: app` (lihat komentar di workflow).

**Build lokal (bila punya Flutter SDK):**

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --release
```

**Penandatanganan:** release saat ini memakai kunci debug (pola
template standar) agar APK sideload langsung bisa diinstal. Sebelum
pengajuan Play Store, buat keystore release sendiri dan isi
`signingConfigs.release` di `android/app/build.gradle`.

## Struktur project

```
app/
├── lib/
│   ├── main.dart                  # entry: cache tile, prefs, DB, splash→peta
│   ├── config/                    # konstanta, tema Material 3, wiring provider
│   ├── domain/models/             # model murni: port, tide, weather, marine,
│   │                              #   vessel, waypoint, map_layers, windy,
│   │                              #   weather_alert, offline_area, anchor_mob
│   ├── data/
│   │   ├── services/              # api_client, tides, bmkg, open_meteo, gebco,
│   │   │                          #   ais (WebSocket), rainviewer, gibs,
│   │   │                          #   location, compass, secure_key, settings,
│   │   │                          #   wind_grid, offline_tile, notification
│   │   ├── local/app_database.dart# Drift (SQLite): cache payload + waypoint/
│   │   │                          #   rute/track
│   │   └── repositories/          # tides, weather, marine, depth, ais,
│   │                              #   map_data, navigation, windy, offline,
│   │                              #   safety
│   ├── ui/
│   │   ├── core/widgets/          # notice, safety banner, version stamp,
│   │   │                          #   compass dial, ship/own-ship marker, footer
│   │   ├── splash/                # splash screen logo kapten
│   │   ├── map/                   # MapScreen + MapViewModel + depth/layers/
│   │   │                          #   manual-position / long-press / gebco-legend /
│   │   │                          #   saved-area tile provider
│   │   ├── tides|weather|marine|ais/  # panel + view-model masing-masing
│   │   ├── navigation/            # waypoint/rute/jejak, anchor+MOB,
│   │   │                          #   matahari/bulan, pelabuhan
│   │   ├── windy/                 # partikel angin, timeline, meteogram,
│   │   │                          #   alert, cuaca rute
│   │   ├── offline/               # panel peta offline / wilayah tersimpan
│   │   ├── more/                  # menu "Lainnya"
│   │   └── settings/              # layar Pengaturan (AIS paling atas)
│   └── utils/                     # result, command, nav_math, coordinates,
│                                  #   formatters (tanpa package intl),
│                                  #   sun_moon, track_stats, anchor_math,
│                                  #   tile_math, map_projection
├── test/                          # unit test: nav_math, tides, bmkg, marine,
│                                  #   ais, coordinates, gebco, sun_moon,
│                                  #   navigation_math, point_forecast,
│                                  #   tile_map
├── assets/images/peta-laut-logo.webp
└── android/                       # manifest, Gradle (AGP 8.6.0, Kotlin 2.1.0,
                                   #   Gradle 8.7), MainActivity, launcher icon,
                                   #   ic_notification (ikon notifikasi)
```

Arsitektur: **feature-first + MVVM resmi Flutter**
(View / ViewModel / Repository / Service + `Result`/`Command`),
state dengan Provider + ChangeNotifier, Material 3
(`ColorScheme.fromSeed`, terang + gelap sejak awal). Navigasi polos
(`Navigator`) — cukup untuk peta + pengaturan + bottom sheet.

## Status fitur (per SPEC R-item — penomoran BENAR)

Spesifikasi otoritatif: `../SPEC-MAIN-CHAT.md` (R-01..R-38).
Penomoran di bawah ini mengikuti SPEC langsung; tabel README v1.0
memakai nomor R yang SALAH dan sudah diperbaiki di sini.
Detail bukti per item: `../CHECKLIST-VERIFICATION.md`.

| R-item | Fitur | Status |
| ------ | ----- | ------ |
| R-01 | Aplikasi seperti Navionics (pribadi, data gratis) | ✅ |
| R-02 | Cakupan Kalimantan/Sumatra/Jawa s.d. Sumbawa | ✅ |
| R-03 | Peta laut, GPS, rute/waypoint, pasang, kedalaman | ✅ |
| R-04 | Offline didukung | ✅ |
| R-05 | Kedalaman (Google Maps tidak punya → GEBCO) | ✅ |
| R-06 | Cakupan seluruh Indonesia | ✅ |
| R-07 | Android + iOS | ⚠️ Android ✅ · iOS bukan deliverable program ini (butuh Apple $99/thn + keputusan user) |
| R-08 | Peta laut interaktif (bukan gambar statis) | ✅ |
| R-09 | GPS tampil + cadangan manual (tahan peta / ketik) | ✅ |
| R-10 | Waypoint + rute (jarak, bearing, ETA; koordinat tampil) | ✅ |
| R-11 | Pengalih basemap Standar/Satelit/Laut/Topo | ✅ |
| R-12 | Marker posisi berputar sesuai arah (gyro/GPS) | ✅ |
| R-13 | 5 fitur unggulan: ombak, cuaca, pasang, AIS, kedalaman | ✅ |
| R-14 | Ombak + cuaca BMKG tersambung | ✅ |
| R-15 | Gelombang 2 sumber (BMKG tautan + Open-Meteo Marine) | ✅ |
| R-16 | Pasang surut hari ini + besok + kurva | ✅ |
| R-17 | AIS kapal | ✅ |
| R-18 | Kolom input kunci AIS jelas terlihat + simpan + status | ✅ |
| R-19 | Fitur inti dipertahankan (tidak dihapus) | ✅ |
| R-20 | Tombol/notif tidak mengganggu; kompas tidak error | ✅ |
| R-21 | Notifikasi singkat, hilang sendiri ~5 dtk, satu slot | ✅ |
| R-22 | Tombol + panel kecil/ringkas | ✅ |
| R-23 | Peta diutamakan | ✅ |
| R-24 | Marker AIS bentuk kapal, skala ikut zoom, putar ikut heading | ✅ |
| R-25 | Semua fitur ≤ 2–3 ketukan, label jelas, tanpa istilah teknis | ✅ |
| R-26 | Kualitas di atas kecepatan | ✅ |
| R-27 | Track ON/OFF + indikator merekam, tersimpan lokal | ✅ |
| R-28 | Fitur navigasi lain (jangkar, MOB, ukur, SOG/COG, matahari/bulan, sorot dangkal*, malam, angin, GoTo) | ✅ |
| R-29 | Fitur ala Windy | ✅ |
| R-30 | Semua fitur Windy (Tier 1+2; Tier 3 siklon = ronde berikut) | ✅ |
| R-31 | Arus + swell + SST | ✅ |
| R-32 | Indikator unduhan jelas (badge + tanggal + panel Wilayah Tersimpan) | ✅ |
| R-33 | Auto-simpan + progress bar persen (tile tampil saja) | ✅ |
| R-34 | Splash + kredit "Buatan Prasmanan" | ✅ |
| R-35 | Logo kapten berjenggot galak (dikunci user) | ✅ |
| R-36 | Cek total ulang semua fitur dari nol | ✅ |
| R-37 | Loop perbaikan sampai NOL kelemahan | ✅ (4 putaran, putaran ke-4 nol temuan) |
| R-38 | Fitur benar-benar ada + terhubung + stempel versi di UI | ✅ (verifikasi kode; uji perangkat menunggu CI) |

\* Sorot area dangkal: implementasi JUJUR — GEBCO tidak bisa diwarnai
per ambang dengan andal, jadi TIDAK dibuat lapisan palsu; sebagai
gantinya ketuk-titik kedalaman + legenda GEBCO + peringatan grid
~450 m (lihat `CHECKLIST-VERIFICATION.md` R-28).

## Data & cache

| Data | Sumber | Cache |
| ---- | ------ | ----- |
| Pasang surut | hamandmore MCP (model harmonik) | per lokasi+hari |
| Cuaca | BMKG (adm4) + Open-Meteo Forecast | 6 jam / 3 jam |
| Gelombang | Open-Meteo Marine | 6 jam |
| Kedalaman | GEBCO GetFeatureInfo | 30 hari |
| Radar hujan | RainViewer | memori 10 mnt |
| Citra satelit | NASA GIBS (kemarin UTC) | — |
| Kapal | AISStream WebSocket (kunci user) | — (live) |
| Tile peta | OSM.de / Esri / OpenTopoMap | flutter_map built-in, maks 500 MB |
| Grid angin | Open-Meteo Forecast (multi-lokasi) | memori 30 mnt |
| Prakiraan titik | Open-Meteo Forecast + Marine | cache repo 3–6 jam |
| Wilayah offline | Tile file per area (visible tiles saja) | `<docs>/offline_areas/<id>/…` |

Semua API tanpa kunci, kecuali AISStream: kunci dimasukkan user di
runtime (panel AIS / Pengaturan), disimpan di
`flutter_secure_storage` (Keystore Android), tidak pernah di-log atau
ditampilkan kembali. **Tidak ada secret di kode.**

**Matahari/bulan dihitung lokal** (algoritma NOAA + umur bulan dari
bulan baru referensi 2000-01-06) — tanpa API baru. Divalidasi
terhadap nilai yang diketahui: Jakarta 21 Nov 2026 terbit 05:26 /
terbenam 17:51 (±3 mnt dari referensi 05:25/17:50–17:51), fase bulan
86–89% (referensi 86–89%) — lihat `test/sun_moon_test.dart`.

**Peta offline (dua lapis):**
1. **Auto-simpan (built-in flutter_map):** tile yang dilihat
   otomatis di-cache (maks 500 MB). Dokumentasi resmi tidak menjamin
   ketahanan tile — jangan diandalkan sebagai satu-satunya peta
   offline.
2. **Wilayah Tersimpan (eksplisit):** tombol "Simpan area ini"
   mengunduh tile yang tampil di layar pada zoom saat ini (maks 400
   tile, maks 2 unduhan bersamaan, User-Agent PetaLaut) ke file
   lokal, ditampilkan lewat `SavedAreaTileProvider` (lapisan di atas
   basemap, hanya bila basemap sama). Panel Wilayah Tersimpan
   menampilkan tanggal, jumlah tile, ukuran, dan hapus per area.
   Tanpa unduh massal / prefetch multi-zoom (kebijakan tile OSM).

## Risiko yang diketahui (untuk koordinator)

1. **Codegen Drift di CI** — `app_database.g.dart` dibuat oleh
   `build_runner` di CI; kesalahan definisi tabel baru terlihat di
   sana. File `.g.dart` sengaja di-`.gitignore`.
2. **`BuiltInMapCachingProvider.destroy(deleteCache:)`** — nama
   parameter dari dokumentasi resmi (bukan dari source); bila CI
   gagal di baris ini, hapus argumen / sesuaikan dengan dartdoc.
3. **`flutter_compass` 0.8.1** (Nov 2024) — plugin lama, diisolasi di
   `CompassService`; bila gagal di device, heading jatuh ke course
   GPS. Bila CI gagal resolve, ganti dengan pembacaan sensor manual.
4. **Versi package yang belum diverifikasi satu-per-satu di pub.dev:**
   provider, http, web_socket_channel, shared_preferences,
   path_provider, path, latlong2, url_launcher, build_runner,
   drift_dev — semuanya package mapan dengan versi yang dipakai luas;
   risiko rendah, tapi bila `pub get` gagal resolve, turunkan/naikkan
   satu minor.
5. **Template Android** diadaptasi dari contoh `compass_app`
   (flutter/samples) — AGP 8.6.0 / Kotlin 2.1.0 / Gradle 8.7.
   Bila Flutter stable terbaru menuntut AGP lebih baru, CI akan
   memberi tahu lewat error Gradle.
6. **Belum ada uji jalan di perangkat** — semua kode ditulis tangan
   tanpa Flutter/Dart SDK; verifikasi di VM terbatas pada cek
   statis (`../check_dart.py`, `../check_imports.py`: 106 file Dart
   lolos) + validasi Python atas rumus matahari/bulan dan tile math.
   Bukti jalan di perangkat hanya bisa didapat setelah CI berhasil
   build + APK diuji di HP.
7. **`flutter_local_notifications` ^19.4.2** (baru, Builder 2) —
   API inti (`initialize`, `show`, `AndroidNotificationDetails`)
   diverifikasi dari pub.dev; desugaring diaktifkan di
   `android/app/build.gradle` (minSdk 24 < 26). Semua kegagalan
   notifikasi ditelan (fallback: banner/notifikasi in-app).
8. **`SavedAreaTileProvider.getImage` (Builder 2)** — override
   `getImage` (bukan `getImageWithCancelLoadingSupport`) sesuai
   kontrak `TileProvider` flutter_map 8.x; diverifikasi dari
   dokumentasi pub.dev, bukan dari source.
9. **Alarm jangkar + alert cuaca bekerja selama aplikasi terbuka
   saja** — tanpa foreground service (sengaja: risiko tanpa uji
   perangkat). Batasan ini dinyatakan di UI (catatan di panel
   jangkar + alert).
