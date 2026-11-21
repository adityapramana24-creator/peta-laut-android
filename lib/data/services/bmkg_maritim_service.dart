import 'dart:convert';

import '../../domain/models/bmkg_maritim.dart';
import '../../utils/result.dart';
import 'api_client.dart';

/// Prakiraan maritim BMKG: GET publik tanpa key, tanpa auth.
/// Dokumentasi: https://maritim.bmkg.go.id/apidoc
/// Base: https://maritim.bmkg.go.id/marine2026-data/
/// Endpoint: /perairan/{KODE}.json (KODE = M.xx dari sea_regions).
/// Atribusi "Sumber: BMKG" WAJIB tampil di UI (syarat layanan).
///
/// CATATAN JARINGAN: host maritim.bmkg.go.id mengembalikan 403 dari
/// command-line VM (IP egress bersama diblokir) — verifikasi live
/// dilakukan via browser, bukan curl. Di HP user (IP seluler sendiri)
/// endpoint ini diharapkan dapat diakses normal; bila tetap gagal,
/// repository jatuh ke cache + UI memakai fallback Open-Meteo.
class BmkgMaritimService {
  BmkgMaritimService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  static const String baseUrl =
      'https://maritim.bmkg.go.id/marine2026-data';

  /// Timeout eksplisit 30 detik (lebih pendek dari default ApiClient
  /// 45 dtk — respons prakiraan wilayah kecil; di koneksi kapal yang
  /// lambat, 30 dtk cukup sebelum fallback cache dipakai).
  static const Duration timeout = Duration(seconds: 30);

  Future<Result<BmkgMaritimForecast>> fetchForecast(String code) async {
    final uri = Uri.parse('$baseUrl/perairan/$code.json');
    final result = await _client.get(uri, timeout: timeout);
    switch (result) {
      case Ok(value: final body):
        try {
          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic>) {
            return Result.error(
              Exception('Respons BMKG maritim tidak valid.'),
            );
          }
          final forecast = BmkgMaritimForecast.fromJson(
            decoded,
            codeFallback: code,
            fetchedAt: DateTime.now(),
          );
          if (!forecast.hasData) {
            return Result.error(
              Exception(
                'BMKG tidak mengembalikan prakiraan untuk $code.',
              ),
            );
          }
          return Result.ok(forecast);
        } catch (e) {
          return Result.error(
            Exception('Gagal membaca data BMKG maritim: $e'),
          );
        }
      case Error(error: final error):
        return Result.error(error);
    }
  }
}
