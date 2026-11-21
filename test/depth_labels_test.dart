import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:peta_laut/ui/map/widgets/depth_labels_overlay.dart';

/// Sampling grid label kedalaman (ronde 2, item 5): gerbang zoom,
/// jumlah titik, batas maksimum, spasi minimum (grid GEBCO ~450 m),
/// determinisme. Hitungan dicocokkan dengan mirror Python
/// (lihat laporan pekerja B).
void main() {
  LatLngBounds bounds(
    double sLat,
    double sLon,
    double nLat,
    double nLon,
  ) =>
      LatLngBounds(LatLng(sLat, sLon), LatLng(nLat, nLon));

  test('zoom < 10 -> tanpa titik', () {
    expect(
      DepthLabelSampling.pointsFor(
        bounds: bounds(-5.0, 114.5, -4.0, 115.1),
        zoom: 9.9,
      ),
      isEmpty,
    );
    expect(DepthLabelSampling.shouldShow(9.9), isFalse);
    expect(DepthLabelSampling.shouldShow(10.0), isTrue);
  });

  test('zoom 10, bounds 1,0° x 0,6° -> 24 titik (4 kolom x 6 baris)',
      () {
    final points = DepthLabelSampling.pointsFor(
      bounds: bounds(-5.0, 114.5, -4.0, 115.1),
      zoom: 10,
    );
    expect(points.length, 24);
    for (final p in points) {
      expect(p.latitude, greaterThanOrEqualTo(-5.0));
      expect(p.latitude, lessThanOrEqualTo(-4.0));
      expect(p.longitude, greaterThanOrEqualTo(114.5));
      expect(p.longitude, lessThanOrEqualTo(115.1));
    }
    // Titik pertama = tengah sel barat daya (6 baris, 4 kolom).
    expect(points.first.latitude, closeTo(-5.0 + 1.0 * 0.5 / 6, 0.0001));
    expect(
      points.first.longitude,
      closeTo(114.5 + 0.6 * 0.5 / 4, 0.0001),
    );
  });

  test('zoom 16, bounds 0,02° x 0,02° -> 9 titik (3 x 3)', () {
    final points = DepthLabelSampling.pointsFor(
      bounds: bounds(-4.51, 114.79, -4.49, 114.81),
      zoom: 16,
    );
    expect(points.length, 9);
    // Spasi antar titik sebaris >= 0,6 km (grid GEBCO ~450 m).
    final dLonKm = (points[1].longitude - points[0].longitude).abs() *
        111.32 *
        math.cos(-4.5 * math.pi / 180);
    expect(dLonKm, greaterThanOrEqualTo(0.6));
  });

  test('zoom 12 -> 24 titik, tidak pernah lebih dari 30', () {
    final points = DepthLabelSampling.pointsFor(
      bounds: bounds(-4.6, 114.7, -4.35, 114.837),
      zoom: 12,
    );
    expect(points.length, 24);
    final wide = DepthLabelSampling.pointsFor(
      bounds: bounds(-5.0, 114.0, -3.0, 117.0),
      zoom: 10,
    );
    expect(wide.length, 24);
    expect(wide.length, lessThanOrEqualTo(DepthLabelSampling.maxPoints));
  });

  test('deterministik: bounds + zoom sama -> titik sama', () {
    final a = DepthLabelSampling.pointsFor(
      bounds: bounds(-5.0, 114.5, -4.0, 115.1),
      zoom: 11,
    );
    final b = DepthLabelSampling.pointsFor(
      bounds: bounds(-5.0, 114.5, -4.0, 115.1),
      zoom: 11,
    );
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].latitude, b[i].latitude);
      expect(a[i].longitude, b[i].longitude);
    }
  });

  test('bounds kosong -> tanpa titik', () {
    expect(
      DepthLabelSampling.pointsFor(
        bounds: bounds(-4.0, 114.5, -4.0, 114.5),
        zoom: 12,
      ),
      isEmpty,
    );
  });
}
