import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/domain/models/weather.dart';

/// Fixture sintetis tapi SESUAI BENTUK respons asli BMKG
/// (top-level lokasi + data[0].cuaca = 3 list slot; field t,
/// weather_desc, wd, wd_deg, ws, hu, tcc, tp, local_datetime).
void main() {
  const bmkgJson = r'''{
    "lokasi": {
      "adm1": "63", "adm2": "63.71", "adm3": "63.71.01", "adm4": "63.71.01.1001",
      "provinsi": "KALIMANTAN SELATAN", "kotkab": "KOTA BANJARMASIN",
      "kecamatan": "BANJARMASIN TENGAH", "desa": "KELAYAN DALAM",
      "lon": 114.59, "lat": -3.32, "type": "Kelurahan"
    },
    "data": [{
      "lokasi": {"lon": 114.59, "lat": -3.32, "timezone": "Asia/Makassar"},
      "cuaca": [
        [
          {"datetime": "2026-11-21T00:00:00", "local_datetime": "2026-11-21T08:00:00",
           "t": 29, "tcc": 75, "tp": 0, "weather": 3, "weather_desc": "Berawan",
           "wd": "Timur", "wd_deg": 90, "ws": 11.1, "hu": 78, "vs": null},
          {"datetime": "2026-11-21T03:00:00", "local_datetime": "2026-11-21T11:00:00",
           "t": 31, "tcc": 90, "tp": 2.5, "weather": 60, "weather_desc": "Hujan Ringan",
           "wd": "Tenggara", "wd_deg": 135, "ws": 18.5, "hu": 85, "vs": null}
        ],
        [
          {"datetime": "2026-11-22T00:00:00", "local_datetime": "2026-11-22T08:00:00",
           "t": 28, "tcc": 20, "tp": 0, "weather": 1, "weather_desc": "Cerah Berawan",
           "wd": "Barat", "wd_deg": 270, "ws": 7.4, "hu": 70, "vs": null}
        ],
        [
          {"datetime": "2026-11-23T00:00:00", "local_datetime": "2026-11-23T08:00:00",
           "t": 27, "tcc": 100, "tp": 12.0, "weather": 63, "weather_desc": "Hujan Sedang",
           "wd": "Barat Laut", "wd_deg": 315, "ws": 22.2, "hu": 92, "vs": null}
        ]
      ]
    }]
  }''';

  test('parse 3 hari + nama lokasi', () {
    final decoded = jsonDecode(bmkgJson) as Map<String, dynamic>;
    final forecast = BmkgForecast.fromJson(
      decoded,
      adm4: '63.71.01.1001',
      fetchedAt: DateTime.utc(2026, 11, 21),
    );
    expect(forecast.days.length, 3);
    expect(forecast.days[0].length, 2);
    expect(forecast.days[1].length, 1);
    expect(forecast.days[2].length, 1);
    expect(forecast.locationName, contains('BANJARMASIN'));
    expect(forecast.adm4, '63.71.01.1001');
  });

  test('field slot + konversi knot', () {
    final decoded = jsonDecode(bmkgJson) as Map<String, dynamic>;
    final forecast = BmkgForecast.fromJson(
      decoded,
      adm4: '63.71.01.1001',
      fetchedAt: DateTime.utc(2026, 11, 21),
    );
    final slot = forecast.days[0][0];
    expect(slot.tempC, 29);
    expect(slot.condition, 'Berawan');
    expect(slot.windFrom, 'Timur');
    expect(slot.windFromDeg, 90);
    expect(slot.windKmh, closeTo(11.1, 0.001));
    // 11.1 km/jam = 6 knot.
    expect(slot.windKnots, closeTo(6, 0.01));
    expect(slot.humidity, 78);
    expect(slot.cloudCover, 75);
    expect(slot.rainMm, 0);
    expect(slot.localTime, DateTime(2026, 11, 21, 8, 0));

    final rainy = forecast.days[0][1];
    expect(rainy.condition, 'Hujan Ringan');
    expect(rainy.rainMm, 2.5);
    // 18.5 km/jam = 10 knot.
    expect(rainy.windKnots, closeTo(10, 0.01));
  });

  test('slot rusak dilewati, sisanya tetap dipakai', () {
    final decoded = jsonDecode(bmkgJson) as Map<String, dynamic>;
    final data = decoded['data'] as List;
    final first = data[0] as Map<String, dynamic>;
    final cuaca = first['cuaca'] as List;
    (cuaca[0] as List).add({'t': 'bukan-angka'});
    final forecast = BmkgForecast.fromJson(
      decoded,
      adm4: '63.71.01.1001',
      fetchedAt: DateTime.utc(2026, 11, 21),
    );
    expect(forecast.days[0].length, 2);
  });

  test('respons tanpa data -> days kosong', () {
    final forecast = BmkgForecast.fromJson(
      {'lokasi': {}},
      adm4: '63.71.01.1001',
      fetchedAt: DateTime.now(),
    );
    expect(forecast.days, isEmpty);
    expect(forecast.current, isNull);
  });

  test('toJson/fromCacheJson round-trip', () {
    final decoded = jsonDecode(bmkgJson) as Map<String, dynamic>;
    final forecast = BmkgForecast.fromJson(
      decoded,
      adm4: '63.71.01.1001',
      fetchedAt: DateTime.utc(2026, 11, 21),
    );
    final restored = BmkgForecast.fromCacheJson(forecast.toJson());
    expect(restored.days.length, 3);
    expect(restored.days[0][1].condition, 'Hujan Ringan');
    expect(restored.days[0][1].windKnots, closeTo(10, 0.01));
  });
}
