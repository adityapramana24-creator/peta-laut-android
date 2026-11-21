import 'dart:convert';

import '../../domain/models/weather.dart';
import '../../utils/result.dart';
import 'api_client.dart';

/// Cuaca BMKG: GET publik tanpa key, batas 60 req/menit/IP.
/// Atribusi "Sumber: BMKG" WAJIB tampil di UI (syarat layanan).
/// Respons: 3 hari ke depan, per 3 jam, update 2x/hari.
class BmkgService {
  BmkgService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<Result<BmkgForecast>> fetchForecast(String adm4) async {
    final uri = Uri.parse(
      'https://api.bmkg.go.id/publik/prakiraan-cuaca',
    ).replace(queryParameters: {'adm4': adm4});
    final result = await _client.get(uri);
    switch (result) {
      case Ok(value: final body):
        try {
          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic>) {
            return Result.error(
              Exception('Respons BMKG tidak valid.'),
            );
          }
          final forecast = BmkgForecast.fromJson(
            decoded,
            adm4: adm4,
            fetchedAt: DateTime.now(),
          );
          if (forecast.days.isEmpty) {
            return Result.error(
              Exception('BMKG tidak mengembalikan prakiraan.'),
            );
          }
          return Result.ok(forecast);
        } catch (e) {
          return Result.error(Exception('Gagal membaca data BMKG: $e'));
        }
      case Error(error: final error):
        return Result.error(error);
    }
  }
}
