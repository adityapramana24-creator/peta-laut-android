import 'dart:convert';

import '../../domain/models/marine.dart';
import '../../domain/models/windy.dart';
import '../../utils/result.dart';
import 'api_client.dart';

/// Grid angin Open-Meteo Forecast untuk partikel angin (paket Windy).
/// SATU request multi-lokasi (koordinat dipisah koma — respons menjadi
/// list, sesuai dokumentasi Open-Meteo). Grid 7 x 5 titik di atas
/// kotak pandang peta, 72 jam (3 hari), variabel angin saja.
/// (Ronde 2: 5x4 -> 7x5 dan rentang 8° -> 14° — grid lama terlalu
/// kasar sehingga partikel bergerak seragam tanpa bentuk aliran.)
///
/// Bila respons multi-lokasi gagal dipahami, jatuh ke request per titik
/// (maks 35, batch 5) — lebih lambat tapi tetap jalan.
class WindGridService {
  WindGridService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  static const int columns = 7;
  static const int rows = 5;

  /// Rentang grid maksimum (derajat) — di atas ini grid dipusatkan
  /// dan dipersempit (partikel di atas area raksasa tidak bermakna).
  /// 14° menutupi seluruh layar pada zoom >= 7; pada tampilan
  /// seluruh ASEAN (zoom ~3,5) partikel hanya menutupi 14° di tengah
  /// — perbesar peta untuk cakupan penuh.
  static const double maxSpanDeg = 14.0;

  Future<Result<WindGrid>> fetchGrid({
    required double south,
    required double west,
    required double north,
    required double east,
    String model = 'auto',
  }) async {
    final span = _clampedSpan(south: south, west: west, north: north, east: east);
    final lats = _linspace(span.$1, span.$3, rows);
    final lons = _linspace(span.$2, span.$4, columns);
    // F-R2: Open-Meteo memasangkan lat/lon PER INDEKS dan
    // mensyaratkan kedua list SAMA JUMLAH — mengirim 5 lat vs 7 lon
    // membuat respons maksimal 5 lokasi / HTTP 400 sehingga jalur
    // satu-request mati. Kirim 35 pasangan (dua list 35 elemen,
    // urutan baris-per-baris yang sama dengan parseGrid).
    final (pairedLats, pairedLons) = pairedCoordinates(lats, lons);

    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast')
        .replace(queryParameters: {
      'latitude': pairedLats.map((v) => v.toStringAsFixed(4)).join(','),
      'longitude': pairedLons.map((v) => v.toStringAsFixed(4)).join(','),
      'hourly': 'wind_speed_10m,wind_direction_10m',
      'forecast_days': '3',
      'timezone': 'Asia/Jakarta',
      if (model != 'auto') 'models': model,
    });

    final result = await _client.get(uri);
    switch (result) {
      case Ok(value: final body):
        try {
          final decoded = jsonDecode(body);
          final grid = parseGrid(
            decoded,
            lats: lats,
            lons: lons,
            model: model,
          );
          if (grid != null) return Result.ok(grid);
        } catch (_) {
          // Jatuh ke per-titik di bawah.
        }
        return _fetchPerPoint(lats: lats, lons: lons, model: model);
      case Error():
        return _fetchPerPoint(lats: lats, lons: lons, model: model);
    }
  }

  Future<Result<WindGrid>> _fetchPerPoint({
    required List<double> lats,
    required List<double> lons,
    required String model,
  }) async {
    final points = <WindGridPoint>[];
    List<DateTime> times = const [];
    for (var batchStart = 0; batchStart < lats.length * lons.length; batchStart += 5) {
      final batch = <Future<WindGridPoint?>>[];
      for (var i = batchStart;
          i < batchStart + 5 && i < lats.length * lons.length;
          i++) {
        final lat = lats[i ~/ lons.length];
        final lon = lons[i % lons.length];
        batch.add(_fetchOnePoint(lat: lat, lon: lon, model: model));
      }
      final results = await Future.wait(batch);
      for (final point in results) {
        if (point != null) points.add(point);
      }
    }
    if (points.isEmpty) {
      return Result.error(
        Exception('Grid angin tidak dapat dimuat. Coba lagi nanti.'),
      );
    }
    // Jam ASLI dari titik pertama yang punya data (F-R2: jam
    // disimpan di tiap titik sejak _fetchOnePoint — jangan pernah
    // mengarang jam dari DateTime.now() di sini).
    for (final p in points) {
      if (p.times.isNotEmpty) {
        times = p.times;
        break;
      }
    }
    return Result.ok(WindGrid(
      points: points,
      columns: columns,
      rows: rows,
      times: times,
      model: model,
      fetchedAt: DateTime.now(),
    ));
  }

  Future<WindGridPoint?> _fetchOnePoint({
    required double lat,
    required double lon,
    required String model,
  }) async {
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast')
        .replace(queryParameters: {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': 'wind_speed_10m,wind_direction_10m',
      'forecast_days': '3',
      'timezone': 'Asia/Jakarta',
      if (model != 'auto') 'models': model,
    });
    final result = await _client.get(uri);
    if (result is! Ok<String>) return null;
    try {
      final decoded = jsonDecode(result.value);
      if (decoded is! Map<String, dynamic>) return null;
      final hours = PointForecast.parseForecastHourly(decoded);
      if (hours.isEmpty) return null;
      return WindGridPoint(
        latitude: lat,
        longitude: lon,
        windKmh: hours.map((h) => h.windKmh).toList(),
        windDirDeg: hours.map((h) => h.windDirDeg).toList(),
        times: hours.map((h) => h.time).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse respons multi-lokasi Open-Meteo (list) menjadi WindGrid.
  /// `lats`/`lons` adalah urutan koordinat yang diminta (baris-per-baris:
  /// lintang selatan -> utara, dalam tiap baris bujur barat -> timur).
  /// Mengembalikan null bila respons tidak dapat dipahami.
  static WindGrid? parseGrid(
    dynamic decoded, {
    required List<double> lats,
    required List<double> lons,
    required String model,
  }) {
    if (decoded is! List) return null;
    if (decoded.length != lats.length * lons.length) return null;
    final points = <WindGridPoint>[];
    List<DateTime> times = const [];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map<String, dynamic>) return null;
      final hours = PointForecast.parseForecastHourly(item);
      if (hours.isEmpty) return null;
      if (i == 0) times = hours.map((h) => h.time).toList();
      points.add(WindGridPoint(
        latitude: lats[i ~/ lons.length],
        longitude: lons[i % lons.length],
        windKmh: hours.map((h) => h.windKmh).toList(),
        windDirDeg: hours.map((h) => h.windDirDeg).toList(),
        times: hours.map((h) => h.time).toList(),
      ));
    }
    return WindGrid(
      points: points,
      columns: lons.length,
      rows: lats.length,
      times: times,
      model: model,
      fetchedAt: DateTime.now(),
    );
  }

  /// Pasangan lat/lon baris-per-baris untuk request multi-lokasi
  /// Open-Meteo: dua list sama panjang (rows x columns), indeks i
  /// = titik (lats[i ~/ columns], lons[i % columns]) — urutan yang
  /// sama persis dengan yang diharapkan [parseGrid]. Dipakai juga
  /// oleh [CurrentGridService] agar kedua grid berimpit.
  /// (F-R2: tanpa pasangan ini, list 5 lat vs 7 lon membuat
  /// Open-Meteo mengembalikan maksimal 5 lokasi.)
  static (List<double>, List<double>) pairedCoordinates(
    List<double> lats,
    List<double> lons,
  ) {
    final pairedLats = <double>[];
    final pairedLons = <double>[];
    for (final lat in lats) {
      for (final lon in lons) {
        pairedLats.add(lat);
        pairedLons.add(lon);
      }
    }
    return (pairedLats, pairedLons);
  }

  /// Persempit kotak ke rentang maksimum, berpusat di tengah kotak.
  static (double, double, double, double) _clampedSpan({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    final centerLat = (south + north) / 2;
    final centerLon = (west + east) / 2;
    final latSpan = (north - south).abs();
    final lonSpan = (east - west).abs();
    final halfLat = (latSpan > maxSpanDeg ? maxSpanDeg : latSpan) / 2;
    final halfLon = (lonSpan > maxSpanDeg ? maxSpanDeg : lonSpan) / 2;
    return (
      (centerLat - halfLat).clamp(-90.0, 90.0),
      (centerLon - halfLon).clamp(-180.0, 180.0),
      (centerLat + halfLat).clamp(-90.0, 90.0),
      (centerLon + halfLon).clamp(-180.0, 180.0),
    );
  }

  static List<double> _linspace(double start, double end, int count) {
    if (count <= 1) return [start];
    final step = (end - start) / (count - 1);
    return List.generate(count, (i) => start + step * i);
  }
}
