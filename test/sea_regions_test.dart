import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/config/sea_regions.dart';

/// Daftar wilayah laut (R-15, ronde 2): nama + koordinat valid dalam
/// bbox ASEAN (lat -11..29, lon 92..141), tanpa duplikat, dan setiap
/// titik tercatat sudah diverifikasi di laut (verifikasi live
/// Open-Meteo Marine 21 Nov 2026 — lihat komentar sea_regions.dart).
/// Test ini tidak memanggil jaringan: ia mengunci data yang sudah
/// diverifikasi agar regresi (titik bergeser ke darat / wilayah
/// tanpa verifikasi) tertangkap di CI.
void main() {
  group('kSeaRegions', () {
    test('daftar tidak kosong', () {
      expect(kSeaRegions, isNotEmpty);
    });

    test('setiap wilayah punya nama + id + koordinat valid', () {
      for (final region in kSeaRegions) {
        expect(region.id, isNotEmpty, reason: 'id kosong: ${region.name}');
        expect(region.name, isNotEmpty, reason: 'nama kosong: ${region.id}');
        expect(region.latitude.isFinite, isTrue);
        expect(region.longitude.isFinite, isTrue);
        expect(region.latitude, greaterThanOrEqualTo(-11),
            reason: '${region.id} lat di luar ASEAN');
        expect(region.latitude, lessThanOrEqualTo(29),
            reason: '${region.id} lat di luar ASEAN');
        expect(region.longitude, greaterThanOrEqualTo(92),
            reason: '${region.id} lon di luar ASEAN');
        expect(region.longitude, lessThanOrEqualTo(141),
            reason: '${region.id} lon di luar ASEAN');
      }
    });

    test('setiap titik tercatat sudah diverifikasi di laut', () {
      for (final region in kSeaRegions) {
        expect(region.verifiedAtSea, isTrue,
            reason: '${region.id} belum diverifikasi di laut — '
                'verifikasi dulu via Open-Meteo Marine live');
      }
    });

    test('tidak ada id atau nama duplikat', () {
      final ids = kSeaRegions.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      final names = kSeaRegions.map((r) => r.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('kode BMKG: 20 wilayah M.xx + 3 non-BMKG', () {
      final bmkg = kSeaRegions.where((r) => r.bmkgCode != null).toList();
      final nonBmkg = kSeaRegions.where((r) => r.bmkgCode == null).toList();
      expect(bmkg.length, 20);
      expect(nonBmkg.length, 3);
      for (final region in bmkg) {
        expect(region.bmkgCode, matches(RegExp(r'^M\.\d+$')),
            reason: 'kode BMKG tidak valid: ${region.bmkgCode}');
        expect(region.id, region.bmkgCode,
            reason: 'id wilayah BMKG harus sama dengan kodenya');
      }
      expect(
        nonBmkg.map((r) => r.id).toSet(),
        {'SCS', 'GOT', 'ANDA'},
      );
    });
  });

  group('bmkgWaveCategory (skala resmi BMKG, bmkg.go.id/cuaca/maritim)',
      () {
    test('batas bawah inklusif tiap tingkat', () {
      expect(bmkgWaveCategory(0.0), 'Tenang');
      expect(bmkgWaveCategory(0.49), 'Tenang');
      expect(bmkgWaveCategory(0.5), 'Rendah');
      expect(bmkgWaveCategory(1.24), 'Rendah');
      expect(bmkgWaveCategory(1.25), 'Sedang');
      expect(bmkgWaveCategory(2.49), 'Sedang');
      expect(bmkgWaveCategory(2.5), 'Tinggi');
      expect(bmkgWaveCategory(3.99), 'Tinggi');
      expect(bmkgWaveCategory(4.0), 'Sangat Tinggi');
      expect(bmkgWaveCategory(5.99), 'Sangat Tinggi');
      expect(bmkgWaveCategory(6.0), 'Ekstrem');
      expect(bmkgWaveCategory(8.99), 'Ekstrem');
      expect(bmkgWaveCategory(9.0), 'Sangat Ekstrem');
      expect(bmkgWaveCategory(12.0), 'Sangat Ekstrem');
    });
  });
}
