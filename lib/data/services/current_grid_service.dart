import 'dart:convert';

import '../../domain/models/marine.dart';
import '../../domain/models/windy.dart';
import '../../utils/result.dart';
import 'api_client.dart';
import 'wind_grid_service.dart';

/// Grid arus Open-Meteo Marine untuk panah arus di peta (ronde 2,
/// item 4b). Pola yang sama persis dengan [WindGridService]: SATU
/// request multi-lokasi (koordinat dipisah koma — respons menjadi
/// list; Marine mendukung multi-lokasi seperti Forecast, sesuai
/// dokumentasi Open-Meteo), grid 7 x 5 titik yang SAMA dengan grid
/// angin (kolom/baris/rentang diambil dari [WindGridService] agar
/// panah arus segaris dengan partikel angin), 72 jam (3 hari),
/// variabel arus saja.
///
/// Konvensi arah: `ocean_current_direction` adalah arah MENUJU
/// (0° = ke utara, 90° = ke timur) — kebalikan konvensi angin.
///
/// Bila respons multi-lokasi gagal dipahami, jatuh ke request per titik
/// (maks 35, batch 5) — lebih lambat tapi tetap jalan.
class CurrentGridService {
  CurrentGridService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// Grid yang sama dengan grid angin (titik-titiknya berimpit).
  static int get columns => WindGridService.columns;
  static int get rows => WindGridService.rows;
  static double get maxSpanDeg => WindGridService.maxSpanDeg;

  Future<Result<CurrentGrid>> fetchGrid({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    final span =
        _clampedSpan(south: south, west: west, north: north, east: east);
    final lats = _linspace(span.$1, span.$3, rows);
    final lons = _linspace(span.$2, span.$4, columns);
    // F-R2: seperti grid angin — kirim 35 pasangan lat,lon
    // (dua list 35 elemen), bukan 5 lat vs 7 lon.
    final (pairedLats, pairedLons) =
        WindGridService.pairedCoordinates(lats, lons);

    final uri =
        Uri.parse('https://marine-api.open-meteo.com/v1/marine')
            .replace(queryParameters: {
      'latitude': pairedLats.map((v) => v.toStringAsFixed(4)).join(','),
      'longitude': pairedLons.map((v) => v.toStringAsFixed(4)).join(','),
      'hourly': 'ocean_current_velocity,ocean_current_direction',
      'forecast_days': '3',
      'timezone': 'Asia/Jakarta',
    });

    final result = await _client.get(uri);
    switch (result) {
      case Ok(value: final body):
        try {
          final decoded = jsonDecode(body);
          final grid = parseGrid(decoded, lats: lats, lons: lons);
          if (grid != null) return Result.ok(grid);
        } catch (_) {
          // Jatuh ke per-titik di bawah.
        }
        return _fetchPerPoint(lats: lats, lons: lons);
      case Error():
        return _fetchPerPoint(lats: lats, lons: lons);
    }
  }

  Future<Result<CurrentGrid>> _fetchPerPoint({
    required List<double> lats,
    required List<double> lons,
  }) async {
    final points = <CurrentGridPoint>[];
    List<DateTime> times = const [];
    for (var batchStart = 0;
        batchStart < lats.length * lons.length;
        batchStart += 5) {
      final batch = <Future<CurrentGridPoint?>>[];
      for (var i = batchStart;
          i < batchStart + 5 && i < lats.length * lons.length;
          i++) {
        final lat = lats[i ~/ lons.length];
        final lon = lons[i % lons.length];
        batch.add(_fetchOnePoint(lat: lat, lon: lon));
      }
      final results = await Future.wait(batch);
      for (final point in results) {
        if (point != null) points.add(point);
      }
    }
    if (points.isEmpty) {
      return Result.error(
        Exception('Grid arus tidak dapat dimuat. Coba lagi nanti.'),
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
    return Result.ok(CurrentGrid(
      points: points,
      columns: columns,
      rows: rows,
      times: times,
      fetchedAt: DateTime.now(),
    ));
  }

  Future<CurrentGridPoint?> _fetchOnePoint({
    required double lat,
    required double lon,
  }) async {
    final uri =
        Uri.parse('https://marine-api.open-meteo.com/v1/marine')
            .replace(queryParameters: {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': 'ocean_current_velocity,ocean_current_direction',
      'forecast_days': '3',
      'timezone': 'Asia/Jakarta',
    });
    final result = await _client.get(uri);
    if (result is! Ok<String>) return null;
    try {
      final decoded = jsonDecode(result.value);
      if (decoded is! Map<String, dynamic>) return null;
      final hours = _parseMarineHours(decoded);
      if (hours.isEmpty) return null;
      return CurrentGridPoint(
        latitude: lat,
        longitude: lon,
        velocityKmh: hours.map((h) => h.currentVelocityKmh).toList(),
        directionDeg: hours.map((h) => h.currentDirectionDeg).toList(),
        times: hours.map((h) => h.time).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse respons multi-lokasi Open-Meteo Marine (list) menjadi
  /// CurrentGrid. `lats`/`lons` adalah urutan koordinat yang diminta
  /// (baris-per-baris: lintang selatan -> utara, dalam tiap baris
  /// bujur barat -> timur). Mengembalikan null bila respons tidak
  /// dapat dipahami.
  static CurrentGrid? parseGrid(
    dynamic decoded, {
    required List<double> lats,
    required List<double> lons,
  }) {
    if (decoded is! List) return null;
    if (decoded.length != lats.length * lons.length) return null;
    final points = <CurrentGridPoint>[];
    List<DateTime> times = const [];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map<String, dynamic>) return null;
      final hours = _parseMarineHours(item);
      if (hours.isEmpty) return null;
      if (i == 0) times = hours.map((h) => h.time).toList();
      points.add(CurrentGridPoint(
        latitude: lats[i ~/ lons.length],
        longitude: lons[i % lons.length],
        velocityKmh: hours.map((h) => h.currentVelocityKmh).toList(),
        directionDeg: hours.map((h) => h.currentDirectionDeg).toList(),
        times: hours.map((h) => h.time).toList(),
      ));
    }
    return CurrentGrid(
      points: points,
      columns: lons.length,
      rows: lats.length,
      times: times,
      fetchedAt: DateTime.now(),
    );
  }

  /// Jam Marine per lokasi (dipakai ulang dari parser MarineForecast
  /// yang sudah ada — variabel arus sudah tercakup di sana).
  /// Catatan F-R2: `_timesFromPoint` lama (jam karangan dari
  /// "sekarang") DIHAPUS — jam kini disimpan di tiap titik.
  static List<MarineHour> _parseMarineHours(Map<String, dynamic> json) {
    final forecast = MarineForecast.fromJson(
      json,
      latitude: 0,
      longitude: 0,
      fetchedAt: DateTime.now(),
    );
    return forecast.hours;
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
