import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/domain/models/ais_target_status.dart';
import 'package:peta_laut/domain/models/vessel.dart';
import 'package:peta_laut/utils/cpa_math.dart';

/// CPA/TCPA — 7 skenario. Nilai harapan dihitung dengan implementasi
/// referensi Python independen (proyeksi equirectangular yang sama,
/// R = 3440,065 nm). Toleransi 0,05 nm / 0,1 menit menutup selisih
/// float, bukan selisih rumus.
void main() {
  const own = OwnShipState(
    latitude: 0,
    longitude: 0,
    sogKnots: 10,
    cogDeg: 0,
  );

  CpaResult? cpa({
    required OwnShipState o,
    required double lat,
    required double lon,
    required double sog,
    required double cog,
  }) =>
      CpaMath.compute(
        own: o,
        targetLat: lat,
        targetLon: lon,
        targetSogKnots: sog,
        targetCogDeg: cog,
      );

  test('1 head-on: CPA 0, TCPA 30 mnt', () {
    final r = cpa(o: own, lat: 10 / 60, lon: 0, sog: 10, cog: 180)!;
    expect(r.cpaNm, closeTo(0.0, 0.05));
    expect(r.tcpaMinutes, closeTo(30.02, 0.1));
    expect(r.closing, isTrue);
  });

  test('2 berpotongan: CPA 7,08 nm, TCPA 30 mnt', () {
    const ownEast = OwnShipState(
      latitude: 0,
      longitude: 0,
      sogKnots: 10,
      cogDeg: 90,
    );
    final r = cpa(o: ownEast, lat: 0, lon: 10 / 60, sog: 10, cog: 180)!;
    expect(r.cpaNm, closeTo(7.08, 0.05));
    expect(r.tcpaMinutes, closeTo(30.02, 0.1));
    expect(r.closing, isTrue);
  });

  test('3 menjauh: TCPA negatif, closing false', () {
    final r = cpa(o: own, lat: 10 / 60, lon: 0, sog: 20, cog: 0)!;
    expect(r.tcpaMinutes, closeTo(-60.04, 0.1));
    expect(r.closing, isFalse);
  });

  test('4 menyalip: CPA 0, TCPA 30 mnt', () {
    const ownFast = OwnShipState(
      latitude: 0,
      longitude: 0,
      sogKnots: 20,
      cogDeg: 0,
    );
    final r = cpa(o: ownFast, lat: 5 / 60, lon: 0, sog: 10, cog: 0)!;
    expect(r.cpaNm, closeTo(0.0, 0.05));
    expect(r.tcpaMinutes, closeTo(30.02, 0.1));
    expect(r.closing, isTrue);
  });

  test('5 target diam 3 nm Timur Laut: CPA 2,12 nm, TCPA 10,6 mnt', () {
    const ownEast = OwnShipState(
      latitude: 0,
      longitude: 0,
      sogKnots: 12,
      cogDeg: 90,
    );
    final r = cpa(
      o: ownEast,
      lat: 2.12132 / 60,
      lon: 2.12132 / 60,
      sog: 0,
      cog: 0,
    )!;
    expect(r.cpaNm, closeTo(2.12, 0.05));
    expect(r.tcpaMinutes, closeTo(10.61, 0.1));
    expect(r.closing, isTrue);
  });

  test('6 paralel kecepatan sama: TCPA null, jarak stabil', () {
    final r = cpa(o: own, lat: 5 / 60, lon: 3 / 60, sog: 10, cog: 0)!;
    expect(r.tcpaMinutes, isNull);
    expect(r.closing, isFalse);
    expect(r.cpaNm, closeTo(5.83, 0.05));
  });

  test('7 berpotongan dengan offset: CPA 5,66 nm, TCPA 36 mnt', () {
    const ownEast = OwnShipState(
      latitude: 0,
      longitude: 0,
      sogKnots: 10,
      cogDeg: 90,
    );
    final r = cpa(o: ownEast, lat: 2 / 60, lon: 10 / 60, sog: 10, cog: 180)!;
    expect(r.cpaNm, closeTo(5.66, 0.05));
    expect(r.tcpaMinutes, closeTo(36.02, 0.1));
    expect(r.closing, isTrue);
  });

  test('tanpa gerak GPS sendiri / tanpa SOG-COG target -> null', () {
    const noMotion = OwnShipState(latitude: 0, longitude: 0);
    expect(
      CpaMath.compute(
        own: noMotion,
        targetLat: 0.1,
        targetLon: 0,
        targetSogKnots: 10,
        targetCogDeg: 180,
      ),
      isNull,
    );
    expect(
      CpaMath.compute(
        own: own,
        targetLat: 0.1,
        targetLon: 0,
        targetSogKnots: null,
        targetCogDeg: 180,
      ),
      isNull,
    );
    expect(
      CpaMath.compute(
        own: own,
        targetLat: 0.1,
        targetLon: 0,
        targetSogKnots: 10,
        targetCogDeg: null,
      ),
      isNull,
    );
  });

  test('isDangerous: ambang CPA 0,5 nm + TCPA 15 mnt', () {
    final headOn = cpa(o: own, lat: 10 / 60, lon: 0, sog: 10, cog: 180)!;
    // CPA 0 tapi TCPA 30 mnt > 15 -> belum berbahaya.
    expect(
      AisTargetStatusResolver.isDangerous(
        headOn,
        cpaThresholdNm: 0.5,
        tcpaThresholdMin: 15,
      ),
      isFalse,
    );
    // Dengan ambang TCPA 45 mnt -> berbahaya.
    expect(
      AisTargetStatusResolver.isDangerous(
        headOn,
        cpaThresholdNm: 0.5,
        tcpaThresholdMin: 45,
      ),
      isTrue,
    );
    // Sudah di dalam lingkaran ambang -> berbahaya apa pun TCPA.
    const inside = CpaResult(
      cpaNm: 0.3,
      tcpaMinutes: null,
      closing: false,
      currentDistanceNm: 0.3,
    );
    expect(
      AisTargetStatusResolver.isDangerous(
        inside,
        cpaThresholdNm: 0.5,
        tcpaThresholdMin: 15,
      ),
      isTrue,
    );
  });

  test('formatTcpa', () {
    expect(CpaMath.formatTcpa(12.4), '12 mnt');
    expect(CpaMath.formatTcpa(75), '1 jam 15 mnt');
    expect(CpaMath.formatTcpa(null), '—');
    expect(CpaMath.formatTcpa(-5), 'menjauh');
    expect(CpaMath.formatTcpa(0.5), '< 1 mnt');
  });

  test('resolve: hilang > berbahaya > aktif > tidur', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final stale = Vessel(
      mmsi: 1,
      latitude: 0.01,
      longitude: 0,
      speedKnots: 10,
      courseDeg: 180,
      lastSeen: now.subtract(const Duration(minutes: 6)),
    );
    // Basi 6 menit -> hilang, meski posisinya mengancam.
    expect(
      AisTargetStatusResolver.resolve(vessel: stale, own: own, now: now),
      AisTargetStatus.lost,
    );
    final close = Vessel(
      mmsi: 2,
      latitude: 0.4 / 60,
      longitude: 0,
      speedKnots: 10,
      courseDeg: 180,
      lastSeen: now,
    );
    // 0,4 nm di depan, head-on -> berbahaya.
    expect(
      AisTargetStatusResolver.resolve(vessel: close, own: own, now: now),
      AisTargetStatus.dangerous,
    );
    final far = Vessel(
      mmsi: 3,
      latitude: 1,
      longitude: 1,
      speedKnots: 5,
      courseDeg: 90,
      lastSeen: now,
    );
    expect(
      AisTargetStatusResolver.resolve(
        vessel: far,
        own: own,
        selectedMmsi: 3,
        now: now,
      ),
      AisTargetStatus.activated,
    );
    expect(
      AisTargetStatusResolver.resolve(vessel: far, own: own, now: now),
      AisTargetStatus.sleeping,
    );
  });
}
