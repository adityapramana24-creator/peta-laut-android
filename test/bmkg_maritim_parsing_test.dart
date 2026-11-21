import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/config/sea_regions.dart';
import 'package:peta_laut/domain/models/bmkg_maritim.dart';
import 'package:peta_laut/ui/marine/widgets/bmkg_wave_style.dart';
import 'package:peta_laut/utils/formatters.dart';

/// Fixture NYATA: respons /perairan/M.01.json ("Selat Malaka bagian
/// utara") diambil live via browser 21 Nov 2026 ~18:55 WIB.
/// Header lengkap + 2 entri forecast_day1 + 1 entri forecast_day2-4,
/// disalin PERSIS (nilai, urutan field, ejaan). Respons penuh punya
/// 24 entri day1 + 17 entri day2-4; fixture memotong daftarnya saja.
void main() {
  const m01Json = r'''{
    "code": "M.01", "name": "Selat Malaka bagian utara",
    "no_surat": "B/ME.01.02/METOS/20/DMM/XI/2026",
    "nama_prakirawan": "Restu Wardani", "nama_stasiun": "",
    "alamat_stasiun": "Jl. Angkasa 1 No.2, Kemayoran, Jakarta 10720",
    "telp_stasiun": "Telp : 021-6546318 Fax. 021-6546314 / 6546315",
    "email_stasiun": "kontak.maritim@bmkg.go.id",
    "issued": "2026-11-20 12:00 UTC",
    "valid_from": "2026-11-21 00:00 UTC",
    "valid_to": "2026-11-24 00:00 UTC",
    "forecast_day1": [
      {"time": "2026-11-21 00:00 UTC", "weather": "Hujan Ringan",
       "temp_avg": 28, "rh_avg": 81, "wind_from": "Tenggara",
       "wind_speed": 14, "wind_gust": 29, "wave_cat": "Sedang",
       "wave_height": 2.0, "current_to": "Barat Daya",
       "current_speed": 1.22},
      {"time": "2026-11-21 01:00 UTC", "weather": "Hujan Ringan",
       "temp_avg": 28, "rh_avg": 82, "wind_from": "Tenggara",
       "wind_speed": 14, "wind_gust": 29, "wave_cat": "Sedang",
       "wave_height": 2.3, "current_to": "Barat Daya",
       "current_speed": 1.23}
    ],
    "forecast_day2-4": [
      {"time": "2026-11-22 00:00 UTC", "weather": "Hujan Petir",
       "temp_avg": 27, "rh_avg": 84, "wind_from": "Timur",
       "wind_speed": 10, "wind_gust": 24, "wave_cat": "Sedang",
       "wave_height": 2.3, "current_to": "Selatan",
       "current_speed": 1.21}
    ]
  }''';

  BmkgMaritimForecast parseFixture() {
    final decoded = jsonDecode(m01Json) as Map<String, dynamic>;
    return BmkgMaritimForecast.fromJson(
      decoded,
      fetchedAt: DateTime.utc(2026, 11, 21, 12),
    );
  }

  test('parse header + jumlah entri', () {
    final forecast = parseFixture();
    expect(forecast.code, 'M.01');
    expect(forecast.name, 'Selat Malaka bagian utara');
    expect(forecast.issuedUtc, DateTime.utc(2026, 11, 20, 12));
    expect(forecast.validFromUtc, DateTime.utc(2026, 11, 21));
    expect(forecast.validToUtc, DateTime.utc(2026, 11, 24));
    expect(forecast.issuedUtc!.isUtc, isTrue);
    expect(forecast.day1.length, 2);
    expect(forecast.day2to4.length, 1);
    expect(forecast.hasData, isTrue);
  });

  test('field entri jam (angin/arus knot, arah nama kompas ID)', () {
    final forecast = parseFixture();
    final h0 = forecast.day1[0];
    expect(h0.timeUtc, DateTime.utc(2026, 11, 21));
    expect(h0.timeUtc.isUtc, isTrue);
    expect(h0.weather, 'Hujan Ringan');
    expect(h0.tempAvgC, 28);
    expect(h0.rhAvgPct, 81);
    // wind_from / current_to adalah NAMA kompas, bukan derajat.
    expect(h0.windFrom, 'Tenggara');
    expect(h0.windSpeedKt, 14);
    expect(h0.windGustKt, 29);
    expect(h0.waveCat, 'Sedang');
    expect(h0.waveHeightM, 2.0);
    expect(h0.currentTo, 'Barat Daya');
    expect(h0.currentSpeedKt, closeTo(1.22, 0.001));

    final h1 = forecast.day1[1];
    expect(h1.timeUtc, DateTime.utc(2026, 11, 21, 1));
    expect(h1.waveHeightM, 2.3);
    expect(h1.rhAvgPct, 82);

    final d2 = forecast.day2to4[0];
    expect(d2.timeUtc, DateTime.utc(2026, 11, 22));
    expect(d2.weather, 'Hujan Petir');
    expect(d2.windFrom, 'Timur');
    expect(d2.currentTo, 'Selatan');
    expect(d2.currentSpeedKt, closeTo(1.21, 0.001));
  });

  test('waktu UTC -> WIB (+7 jam, label zona di UI)', () {
    final forecast = parseFixture();
    // 00:00 UTC = 07:00 WIB. toWib mengembalikan DateTime UTC yang
    // komponen wall-clock-nya sudah WIB — bandingkan dengan UTC
    // (bukan DateTime lokal, yang bergantung zona perangkat).
    expect(forecast.day1[0].timeWib, DateTime.utc(2026, 11, 21, 7));
    expect(forecast.day1[1].timeWib, DateTime.utc(2026, 11, 21, 8));
    expect(forecast.day2to4[0].timeWib, DateTime.utc(2026, 11, 22, 7));
    expect(forecast.day1[0].timeWib.hour, 7);
    // Stempel terbit: 20 Nov 12:00 UTC = 19:00 WIB.
    expect(
      IdFormat.toWib(forecast.issuedUtc!),
      DateTime.utc(2026, 11, 20, 19),
    );
    expect(
      IdFormat.toWib(forecast.validToUtc!),
      DateTime.utc(2026, 11, 24, 7),
    );
  });

  test('jendela berlaku: valid / sebelum / lewat (batas inklusif)', () {
    final forecast = parseFixture();
    // Di dalam jendela: berlaku.
    expect(forecast.isValidAt(DateTime.utc(2026, 11, 22, 12)), isTrue);
    expect(forecast.isExpiredAt(DateTime.utc(2026, 11, 22, 12)), isFalse);
    // Tepat di valid_from / valid_to: masih berlaku.
    expect(forecast.isValidAt(DateTime.utc(2026, 11, 21)), isTrue);
    expect(forecast.isValidAt(DateTime.utc(2026, 11, 24)), isTrue);
    expect(forecast.isExpiredAt(DateTime.utc(2026, 11, 24)), isFalse);
    // Sebelum valid_from: belum berlaku, bukan kedaluwarsa.
    expect(forecast.isValidAt(DateTime.utc(2026, 11, 20, 23)), isFalse);
    expect(forecast.isExpiredAt(DateTime.utc(2026, 11, 20, 23)), isFalse);
    // Setelah valid_to: kedaluwarsa.
    expect(forecast.isValidAt(DateTime.utc(2026, 11, 24, 0, 1)), isFalse);
    expect(forecast.isExpiredAt(DateTime.utc(2026, 11, 24, 0, 1)), isTrue);
  });

  test('tanpa valid_to: tidak bisa dinyatakan kedaluwarsa', () {
    final decoded = jsonDecode(m01Json) as Map<String, dynamic>;
    decoded.remove('valid_to');
    decoded.remove('valid_from');
    final forecast = BmkgMaritimForecast.fromJson(
      decoded,
      fetchedAt: DateTime.utc(2026, 11, 21, 12),
    );
    expect(forecast.validToUtc, isNull);
    expect(
      forecast.isExpiredAt(DateTime.utc(2027, 1, 1)),
      isFalse,
    );
  });

  test('currentAt memilih jam terdekat', () {
    final forecast = parseFixture();
    expect(
      forecast.currentAt(DateTime.utc(2026, 11, 21, 0, 20)),
      forecast.day1[0],
    );
    expect(
      forecast.currentAt(DateTime.utc(2026, 11, 21, 0, 40)),
      forecast.day1[1],
    );
    expect(
      forecast.currentAt(DateTime.utc(2026, 11, 22, 1)),
      forecast.day2to4[0],
    );
  });

  test('kategori BMKG -> warna: 7 tingkat berbeda, tak dikenal abu-abu',
      () {
    const categories = [
      'Tenang',
      'Rendah',
      'Sedang',
      'Tinggi',
      'Sangat Tinggi',
      'Ekstrem',
      'Sangat Ekstrem',
    ];
    final colors =
        categories.map(bmkgWaveCategoryColor).toList();
    expect(colors.toSet().length, 7);
    expect(colors, everyElement(isNot(Colors.grey)));
    expect(
      bmkgWaveCategoryColor('Tenang'),
      const Color(0xFF2E7D32),
    );
    expect(
      bmkgWaveCategoryColor('Sangat Ekstrem'),
      const Color(0xFF4A148C),
    );
    expect(bmkgWaveCategoryColor('Tidak Ada'), Colors.grey);
    expect(bmkgWaveCategoryColor(null), Colors.grey);
  });

  test('wave_cat API konsisten dengan skala bmkgWaveCategory', () {
    final forecast = parseFixture();
    for (final h in forecast.allHours) {
      expect(
        bmkgWaveCategory(h.waveHeightM!),
        h.waveCat,
        reason: '${h.waveHeightM} m harus ${h.waveCat}',
      );
    }
  });

  test('toJson/fromCacheJson round-trip', () {
    final forecast = parseFixture();
    final restored =
        BmkgMaritimForecast.fromCacheJson(forecast.toJson());
    expect(restored.code, 'M.01');
    expect(restored.name, 'Selat Malaka bagian utara');
    expect(restored.issuedUtc, DateTime.utc(2026, 11, 20, 12));
    expect(restored.validToUtc, DateTime.utc(2026, 11, 24));
    expect(restored.day1.length, 2);
    expect(restored.day1[1].waveHeightM, 2.3);
    expect(restored.day1[1].windGustKt, 29);
    expect(restored.day2to4[0].currentTo, 'Selatan');
    expect(restored.day2to4[0].timeUtc.isUtc, isTrue);
    expect(restored.fetchedAt, DateTime.utc(2026, 11, 21, 12));
  });

  test('defensif: entri rusak dilewati, field hilang -> null', () {
    final decoded = jsonDecode(m01Json) as Map<String, dynamic>;
    final day1 = decoded['forecast_day1'] as List;
    // Entri tanpa jam valid dilewati.
    day1.add({'weather': 'Cerah'});
    day1.add({'time': 'bukan-waktu', 'wave_height': 5.0});
    // Tipe field salah -> null, bukan crash.
    day1.add({
      'time': '2026-11-21 02:00 UTC',
      'wave_height': 'tinggi',
      'wind_speed': 'kencang',
    });
    // Field tak dikenal diabaikan.
    decoded['field_baru_tak_dikenal'] = {'a': 1};
    final forecast = BmkgMaritimForecast.fromJson(
      decoded,
      fetchedAt: DateTime.utc(2026, 11, 21, 12),
    );
    expect(forecast.day1.length, 3);
    expect(forecast.day1[2].waveHeightM, isNull);
    expect(forecast.day1[2].windSpeedKt, isNull);
    expect(forecast.day1[2].timeUtc, DateTime.utc(2026, 11, 21, 2));
  });

  test('respons tanpa prakiraan -> hasData false', () {
    final forecast = BmkgMaritimForecast.fromJson(
      {'code': 'M.01', 'name': 'Selat Malaka bagian utara'},
      fetchedAt: DateTime.now(),
    );
    expect(forecast.hasData, isFalse);
    expect(forecast.current, isNull);
  });

  test('parseBmkgUtcTime: format + batas', () {
    expect(
      parseBmkgUtcTime('2026-11-21 00:00 UTC'),
      DateTime.utc(2026, 11, 21),
    );
    expect(
      parseBmkgUtcTime('2026-11-20 12:00:30 UTC'),
      DateTime.utc(2026, 11, 20, 12, 0, 30),
    );
    expect(parseBmkgUtcTime(null), isNull);
    expect(parseBmkgUtcTime('bukan-waktu'), isNull);
    expect(parseBmkgUtcTime('2026-13-01 00:00 UTC'), isNull);
    expect(parseBmkgUtcTime('2026-11-21 25:00 UTC'), isNull);
  });
}
