import '../../utils/result.dart';
import 'api_client.dart';

/// Hasil lookup kedalaman satu titik (GEBCO GetFeatureInfo).
/// GEBCO mengembalikan elevasi: negatif = di bawah laut (kedalaman),
/// >= 0 = darat. Grid ~450 m, laut/pantai saja (tanpa kedalaman sungai).
class DepthResult {
  const DepthResult({
    required this.latitude,
    required this.longitude,
    required this.elevationM,
  });

  final double latitude;
  final double longitude;
  final double elevationM;

  bool get isLand => elevationM >= 0;

  /// Kedalaman dalam meter (null bila darat).
  double? get depthM => isLand ? null : -elevationM;
}

class GebcoService {
  GebcoService({ApiClient? client}) : _client = client ?? ApiClient();

  static const _base = 'https://wms.gebco.net/mapserv?';

  final ApiClient _client;

  /// GetFeatureInfo satu titik. Parameter terverifikasi live 21 Nov 2026:
  /// WMS 1.1.1, jendela 1° (256x256 px, titik di tengah 128,128).
  /// Jendela 0.1° mengembalikan "Search returned no results".
  Future<Result<DepthResult>> fetchDepth({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(_base).replace(queryParameters: {
      'service': 'WMS',
      'request': 'GetFeatureInfo',
      'version': '1.1.1',
      'layers': 'GEBCO_LATEST_2',
      'query_layers': 'GEBCO_LATEST_2',
      'srs': 'EPSG:4326',
      'bbox':
          '${(longitude - 0.5).toStringAsFixed(6)},${(latitude - 0.5).toStringAsFixed(6)},${(longitude + 0.5).toStringAsFixed(6)},${(latitude + 0.5).toStringAsFixed(6)}',
      'width': '256',
      'height': '256',
      'x': '128',
      'y': '128',
      'info_format': 'text/plain',
      'format': 'image/png',
    });
    final result = await _client.get(
      uri,
      timeout: const Duration(seconds: 30),
    );
    switch (result) {
      case Ok(value: final body):
        final value = parseValueList(body);
        if (value == null) {
          return Result.error(
            Exception('GEBCO tidak mengembalikan kedalaman titik ini.'),
          );
        }
        return Result.ok(DepthResult(
          latitude: latitude,
          longitude: longitude,
          elevationM: value,
        ));
      case Error(error: final error):
        return Result.error(error);
    }
  }

  /// Parse respons text/plain GEBCO: ambil value_list pertama.
  /// Contoh respons:
  ///   Layer 'GEBCO_LATEST_2'
  ///    Feature 0:
  ///    x = '114.80208'
  ///    y = '-4.5020833'
  ///    value_list = '-26'
  static double? parseValueList(String body) {
    final match = RegExp(r"value_list\s*=\s*'(-?\d+(?:\.\d+)?)'")
        .firstMatch(body);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }
}
