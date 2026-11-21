import 'dart:convert';

import '../../domain/models/tide.dart';
import '../../utils/result.dart';
import 'api_client.dart';

/// Pasang surut via hamandmore MCP (JSON-RPC 2.0, stateless, tanpa init).
/// Respons lambat (~21 dtk komputasi model) — timeout 75 dtk.
/// lat/lon WAJIB double (koordinat integer ditolak server — pelajaran
/// web v2). Header Accept WAJIB menyertakan text/event-stream.
class TidesService {
  TidesService({ApiClient? client}) : _client = client ?? ApiClient();

  static const _endpoint = 'https://hamandmore.net/api/harmonics/mcp';
  static const _accept = 'application/json, text/event-stream';

  final ApiClient _client;

  Future<Result<Map<String, dynamic>>> _callTool(
    String tool,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _client.postJson(
      Uri.parse(_endpoint),
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': tool,
          'arguments': arguments,
        },
      },
      headers: {'Accept': _accept},
      timeout: const Duration(seconds: 75),
    );
    switch (result) {
      case Ok(value: final body):
        try {
          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic>) {
            return Result.error(Exception('Respons pasang surut tidak valid.'));
          }
          if (decoded['error'] != null) {
            final message =
                (decoded['error'] as Map?)?['message'] ?? 'kesalahan server';
            return Result.error(Exception('Pasang surut gagal: $message'));
          }
          final payload = TideForecast.extractPayload(decoded);
          if (payload == null) {
            return Result.error(
              Exception('Respons pasang surut tidak berisi data.'),
            );
          }
          return Result.ok(payload);
        } catch (e) {
          return Result.error(Exception('Gagal membaca pasang surut: $e'));
        }
      case Error(error: final error):
        return Result.error(error);
    }
  }

  /// Ekstremum 2 hari (hari ini + besok, WIB) untuk satu titik.
  /// Mengembalikan TideForecast dengan kurva kosong — kurva diisi
  /// repository dari fetchCurve (atau interpolasi bila kurva gagal).
  Future<Result<TideForecast>> fetchExtrema({
    required double latitude,
    required double longitude,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final result = await _callTool('tides_extrema', {
      'latitude': latitude,
      'longitude': longitude,
      'start_time': _iso(startUtc),
      'end_time': _iso(endUtc),
    });
    switch (result) {
      case Ok(value: final payload):
        final forecast = TideForecast.fromExtremaPayload(
          payload: payload,
          latitude: latitude,
          longitude: longitude,
          fetchedAt: DateTime.now(),
        );
        if (forecast.extrema.isEmpty) {
          return Result.error(
            Exception('Tidak ada data pasang surut untuk titik ini.'),
          );
        }
        return Result.ok(forecast);
      case Error(error: final error):
        return Result.error(error);
    }
  }

  /// Rangkaian tinggi pasang surut (kurva) untuk satu rentang.
  Future<Result<List<TideCurvePoint>>> fetchCurve({
    required double latitude,
    required double longitude,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final result = await _callTool('tides_array', {
      'latitude': latitude,
      'longitude': longitude,
      'start_time': _iso(startUtc),
      'end_time': _iso(endUtc),
    });
    switch (result) {
      case Ok(value: final payload):
        final points = TideForecast.parseArrayPayload(
          payload: payload,
          startUtc: startUtc,
          endUtc: endUtc,
        );
        if (points.isEmpty) {
          return Result.error(
            Exception('Kurva pasang surut kosong.'),
          );
        }
        return Result.ok(points);
      case Error(error: final error):
        return Result.error(error);
    }
  }

  /// Rentang 2 hari penuh (hari ini + besok, WIB) dalam UTC.
  static (DateTime, DateTime) twoDayRangeUtc() {
    final nowWib = DateTime.now().toUtc().add(const Duration(hours: 7));
    final startWib =
        DateTime(nowWib.year, nowWib.month, nowWib.day, 0, 0, 0);
    final endWib = startWib.add(const Duration(days: 2));
    return (
      startWib.subtract(const Duration(hours: 7)),
      endWib.subtract(const Duration(hours: 7)),
    );
  }

  static String _iso(DateTime dt) => dt.toUtc().toIso8601String();
}
