import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/domain/models/vessel.dart';
import 'package:peta_laut/ui/ais/view_models/ais_viewmodel.dart';
import 'package:peta_laut/utils/nav_math.dart';

/// "Kapal di dekatku": jarak haversine + urutan terdekat.
/// Nilai referensi dihitung independen dengan Python (haversine,
/// R = 6371000 m — rumus yang sama dengan NavMath).
void main() {
  test('haversine: Jakarta -> Singapura = 894924 m (483,22 nm)', () {
    final meters = NavMath.distanceMeters(-6.2, 106.8, 1.29, 103.85);
    expect(meters, closeTo(894923.6, 1.0));
    expect(NavMath.metersToNm(meters), closeTo(483.22, 0.01));
  });

  test('haversine: 1 menit lintang = 1853,25 m', () {
    expect(NavMath.distanceMeters(0, 0, 1 / 60, 0), closeTo(1853.25, 0.5));
  });

  test('haversine: (0,0) -> (0.1,0.1) = 15725 m', () {
    expect(NavMath.distanceMeters(0, 0, 0.1, 0.1), closeTo(15725.33, 1.0));
  });

  test('haversine: titik sama = 0', () {
    expect(NavMath.distanceMeters(-6.2, 106.8, -6.2, 106.8), 0.0);
  });

  test('format jarak: m / km / nm + km', () {
    expect(NavMath.formatDistance(500), '500 m');
    expect(NavMath.formatDistance(1500), '1.5 km');
    expect(NavMath.formatDistance(5556), '3.0 nm (5.6 km)');
  });

  test('urut dari yang terdekat; tanpa posisi paling akhir', () {
    const refLat = -6.2;
    const refLon = 106.8;
    final vessels = [
      const Vessel(mmsi: 2, latitude: 1.29, longitude: 103.85), // SG ~483 nm
      const Vessel(mmsi: 3), // tanpa posisi
      const Vessel(mmsi: 1, latitude: -6.2, longitude: 106.9), // ~11,1 km
      const Vessel(mmsi: 4, latitude: -5.93, longitude: 106.0), // Merak ~50 nm
    ];
    final sorted = sortVesselsByDistance(vessels, refLat, refLon);
    expect(
      sorted.map((e) => e.vessel.mmsi).toList(),
      [1, 4, 2, 3],
    );
    expect(sorted[0].distanceMeters, closeTo(11054.5, 1.0));
    expect(sorted[1].distanceMeters, closeTo(93413.9, 1.0));
    expect(sorted[2].distanceMeters, closeTo(894923.6, 1.0));
    expect(sorted[3].distanceMeters, isNull);
  });

  test('kapal tanpa posisi diurutkan nama di akhir', () {
    final vessels = [
      const Vessel(mmsi: 1, name: 'ZULU'),
      const Vessel(mmsi: 2, name: 'ALPHA'),
      const Vessel(mmsi: 3, latitude: 0, longitude: 0),
    ];
    final sorted = sortVesselsByDistance(vessels, 0, 0);
    expect(
      sorted.map((e) => e.vessel.mmsi).toList(),
      [3, 2, 1],
    );
  });
}
