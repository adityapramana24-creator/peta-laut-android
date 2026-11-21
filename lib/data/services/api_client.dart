import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_constants.dart';
import '../../utils/result.dart';

/// Klien HTTP bersama: satu http.Client, timeout, dan pesan error
/// Bahasa Indonesia. Semua service jaringan memakai ini.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Result<String>> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = AppConstants.apiTimeout,
  }) async {
    try {
      final response = await _client
          .get(uri, headers: _withUserAgent(headers))
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return Result.ok(response.body);
      }
      return Result.error(Exception(
        'Server menjawab ${response.statusCode} untuk ${uri.host}.',
      ));
    } on TimeoutException {
      return Result.error(Exception(
        'Waktu habis — koneksi lambat. Coba lagi nanti.',
      ));
    } catch (e) {
      return Result.error(Exception('Tidak dapat terhubung: $e'));
    }
  }

  Future<Result<String>> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration timeout = AppConstants.apiTimeout,
  }) async {
    try {
      final merged = _withUserAgent(headers);
      merged['Content-Type'] = 'application/json';
      final response = await _client
          .post(uri, headers: merged, body: jsonEncode(body))
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return Result.ok(response.body);
      }
      return Result.error(Exception(
        'Server menjawab ${response.statusCode} untuk ${uri.host}.',
      ));
    } on TimeoutException {
      return Result.error(Exception(
        'Waktu habis — server lambat. Coba lagi nanti.',
      ));
    } catch (e) {
      return Result.error(Exception('Tidak dapat terhubung: $e'));
    }
  }

  Map<String, String> _withUserAgent(Map<String, String>? headers) {
    final merged = <String, String>{'User-Agent': AppConstants.userAgent};
    if (headers != null) merged.addAll(headers);
    return merged;
  }

  void close() => _client.close();
}
