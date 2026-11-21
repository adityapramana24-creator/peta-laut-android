import 'dart:convert';

import '../../utils/result.dart';
import 'api_client.dart';

/// Radar hujan RainViewer (gratis, tanpa key).
/// https://api.rainviewer.com/public/weather-maps.json ->
/// radar.past[terakhir].path + host = template tile.
/// Bila gagal, lapisan radar cukup disembunyikan (bukan error fatal).
class RainViewerService {
  RainViewerService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<Result<String>> fetchLatestTileTemplate() async {
    final result = await _client.get(
      Uri.parse('https://api.rainviewer.com/public/weather-maps.json'),
    );
    switch (result) {
      case Ok(value: final body):
        try {
          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic>) {
            return Result.error(Exception('Respons RainViewer tidak valid.'));
          }
          final template = parseTileTemplate(decoded);
          if (template == null) {
            return Result.error(
              Exception('RainViewer tidak mengembalikan frame radar.'),
            );
          }
          return Result.ok(template);
        } catch (e) {
          return Result.error(Exception('Gagal membaca RainViewer: $e'));
        }
      case Error(error: final error):
        return Result.error(error);
    }
  }

  /// Parse respons weather-maps.json -> template tile radar terbaru.
  static String? parseTileTemplate(Map<String, dynamic> json) {
    final host = json['host'];
    final radar = json['radar'];
    if (host is! String || radar is! Map<String, dynamic>) return null;
    final past = radar['past'];
    if (past is! List || past.isEmpty) return null;
    final last = past.last;
    if (last is! Map<String, dynamic>) return null;
    final path = last['path'];
    if (path is! String) return null;
    // F-R3: format resmi RainViewer (rainviewer.com/api):
    // {path}/{size}/{z}/{x}/{y}/{color}/{options}.png — "256"
    // HARUS sebelum z/x/y. Susunan lama ({z}/{x}/{y}/256/...)
    // membuat semua tile radar 404 diam-diam.
    return '$host$path/256/{z}/{x}/{y}/2/1_1.png';
  }
}
