import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/data/services/gebco_service.dart';

/// Fixture = respons GetFeatureInfo ASLI yang ditangkap live
/// 21 Nov 2026 (titik -4.5, 114.8, jendela 1 derajat, 256x256).
void main() {
  const gfiResponse = '''
Layer 'GEBCO_LATEST_2'
 Feature 0:
 x = '114.80208'
 y = '-4.5020833'
 value_list = '-26'
''';

  test('parse value_list negatif -> kedalaman 26 m', () {
    final value = GebcoService.parseValueList(gfiResponse);
    expect(value, -26);
    final depth = DepthResult(
      latitude: -4.5,
      longitude: 114.8,
      elevationM: value!,
    );
    expect(depth.isLand, isFalse);
    expect(depth.depthM, 26);
  });

  test('nilai desimal negatif', () {
    final value = GebcoService.parseValueList(
      "value_list = '-123.45'",
    );
    expect(value, closeTo(-123.45, 0.001));
  });

  test('nilai >= 0 -> darat, depthM null', () {
    final land = DepthResult(
      latitude: -3.32,
      longitude: 114.59,
      elevationM: 12.0,
    );
    expect(land.isLand, isTrue);
    expect(land.depthM, isNull);
    final zero = DepthResult(
      latitude: 0,
      longitude: 0,
      elevationM: 0,
    );
    expect(zero.isLand, isTrue);
  });

  test('"Search returned no results" -> null', () {
    const noResult = '''
GetFeatureInfo results:

  Search returned no results.
''';
    expect(GebcoService.parseValueList(noResult), isNull);
    expect(GebcoService.parseValueList(''), isNull);
  });
}
