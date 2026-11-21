import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/config/app_constants.dart';
import 'package:peta_laut/domain/models/port.dart';
import 'package:peta_laut/utils/map_projection.dart';

/// Bbox ASEAN (ronde 2, item 6): lat -11..29, lon 92..141.
/// Titik ekstrem dari pengetahuan umum (Batanes 21,1°N, Hkakabo Razi
/// 28,3°N, pantai Rakhine 92,2°E, perbatasan Papua 141°E, P. Rote
/// -11,0°S) — bila satu titik ekstrem ternyata di luar bbox, bbox
/// harus diperlebar, bukan tesnya yang diubah.
void main() {
  bool inside(double lat, double lon) =>
      lat >= AppConstants.aseanSouth &&
      lat <= AppConstants.aseanNorth &&
      lon >= AppConstants.aseanWest &&
      lon <= AppConstants.aseanEast;

  test('15 pelabuhan lompat-cepat semuanya di dalam ASEAN', () {
    expect(Port.all.length, 15);
    for (final port in Port.all) {
      expect(
        inside(port.latitude, port.longitude),
        isTrue,
        reason: '${port.name} (${port.latitude}, ${port.longitude}) '
            'di luar bbox ASEAN',
      );
    }
  });

  test('titik ekstrem 11 negara ASEAN di dalam bbox', () {
    const extremes = <(String, double, double)>[
      ('Indonesia selatan (P. Rote)', -10.98, 122.9),
      ('Indonesia timur (perbatasan Papua)', -8.0, 141.0),
      ('Indonesia barat (P. Rondo)', 6.08, 95.11),
      ('Indonesia utara (P. Miangas)', 5.57, 126.58),
      ('Myanmar utara (Hkakabo Razi)', 28.33, 97.47),
      ('Myanmar barat (Rakhine)', 19.0, 92.2),
      ('Myanmar timur', 21.0, 101.17),
      ('Filipina utara (Batanes)', 21.12, 121.95),
      ('Filipina selatan (Sibutu)', 4.7, 119.5),
      ('Filipina timur', 7.3, 126.6),
      ('Filipina barat (Palawan)', 9.5, 117.1),
      ('Vietnam utara (Lung Cu)', 23.39, 105.32),
      ('Vietnam selatan (Ca Mau)', 8.6, 104.9),
      ('Thailand utara (Mae Sai)', 20.46, 99.88),
      ('Thailand selatan', 5.6, 101.0),
      ('Laos utara', 22.5, 101.8),
      ('Laos selatan', 13.9, 107.6),
      ('Kamboja utara', 14.7, 107.6),
      ('Kamboja selatan', 10.4, 104.3),
      ('Malaysia Sabah utara (Kudat)', 7.4, 116.7),
      ('Malaysia Sarawak barat', 1.6, 109.6),
      ('Malaysia selatan (Johor)', 1.2, 103.6),
      ('Singapura', 1.35, 103.82),
      ('Brunei', 4.9, 114.9),
      ('Timor-Leste barat (Oecusse)', -9.2, 124.4),
      ('Timor-Leste timur', -8.4, 127.3),
    ];
    for (final (name, lat, lon) in extremes) {
      expect(
        inside(lat, lon),
        isTrue,
        reason: '$name ($lat, $lon) di luar bbox ASEAN',
      );
    }
  });

  test('pusat ASEAN = titik tengah bbox', () {
    expect(
      AppConstants.aseanCenterLat,
      closeTo(
        (AppConstants.aseanSouth + AppConstants.aseanNorth) / 2,
        0.001,
      ),
    );
    expect(
      AppConstants.aseanCenterLon,
      closeTo(
        (AppConstants.aseanWest + AppConstants.aseanEast) / 2,
        0.001,
      ),
    );
    expect(AppConstants.aseanCenterLat, 9.0);
    expect(AppConstants.aseanCenterLon, 116.5);
  });

  test('zoom fit bbox 49° pada layar HP 400 px = 3,52', () {
    // Span bujur terlihat = 360 * lebarPx / (256 * 2^z).
    final fitZoom =
        math.log2(360 * 400 / (256 * (AppConstants.aseanEast - AppConstants.aseanWest)));
    expect(fitZoom, closeTo(3.52, 0.01));
    // Zoom minimum harus DI BAWAH zoom fit agar bingkai awal
    // (CameraFit.bounds) selalu tercapai pada layar HP.
    expect(AppConstants.aseanMinZoom, lessThan(fitZoom));
    // Zoom awal berada di dekat zoom fit.
    expect(
      AppConstants.aseanInitialZoom,
      closeTo(fitZoom, 0.05),
    );
  });

  test('proyeksi: layar 400 px pada zoom 3,5 memuat 49° bujur', () {
    final (cx, cy) = MapProjection.project(
      AppConstants.aseanCenterLat,
      AppConstants.aseanCenterLon,
      3.5,
    );
    final (_, lonWest) = MapProjection.unproject(cx - 200, cy, 3.5);
    final (_, lonEast) = MapProjection.unproject(cx + 200, cy, 3.5);
    final span = lonEast - lonWest;
    expect(span, closeTo(49.72, 0.1));
    expect(span, greaterThanOrEqualTo(49.0));
  });

  test('proyeksi: span lintang -11..29 muat di layar 700 px', () {
    final (_, ySouth) = MapProjection.project(-11.0, 116.5, 3.5);
    final (_, yNorth) = MapProjection.project(29.0, 116.5, 3.5);
    final spanPx = (ySouth - yNorth).abs();
    expect(spanPx, closeTo(333, 5));
    expect(spanPx, lessThan(700));
  });
}
