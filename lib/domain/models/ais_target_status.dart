import '../../utils/cpa_math.dart';
import 'vessel.dart';

/// Status target AIS mengikuti bahasa ECDIS (IMO SN.1/Circ.243
/// "Guidelines for the Presentation of Navigation-Related Symbols"
/// + IEC 62288) — bentuk simbol tiap status digambar di
/// ui/core/widgets/ship_marker.dart.
///
/// Pemetaan ke data AISStream:
/// - sleeping: bawaan (belum dipilih) — simbol kecil, tanpa vektor.
/// - activated: dipilih pengguna (diketuk) — vektor + garis haluan.
/// - dangerous: CPA/TCPA di dalam ambang — merah, tebal.
/// - lost: tidak ada laporan > 5 menit (belum disapu pada 15 menit).
/// Target hilang DIDAHULUKAN atas berbahaya: CPA dari posisi basi
/// tidak bisa dipercaya, jadi tidak diklaim berbahaya.
enum AisTargetStatus {
  sleeping,
  activated,
  dangerous,
  lost,
}

/// Penentu status target + CPA — fungsi murni, tanpa dependensi UI.
class AisTargetStatusResolver {
  AisTargetStatusResolver._();

  /// Target dianggap hilang bila tidak ada laporan selama ini.
  /// (Laporan Kelas A saat berlayar tiap 2–10 detik, saat jangkar
  /// tiap 3 menit — jeda 5 menit berarti sudah di luar jangkauan
  /// stasiun darat. Penyapuan total tetap 15 menit.)
  static const Duration lostAfter = Duration(minutes: 5);

  /// Ambang bawaan target berbahaya (bisa diubah di Pengaturan):
  /// CPA < 0,5 nm + TCPA < 15 menit. Tidak ada satu angka standar
  /// IMO — ECDIS memakai CPA/TCPA limit yang diatur operator;
  /// 0,5 nm / 15 menit adalah ambang praktis pelaut di perairan ramai.
  static const double defaultCpaThresholdNm = 0.5;
  static const double defaultTcpaThresholdMin = 15.0;

  /// CPA/TCPA satu target terhadap kapal sendiri. null bila tidak
  /// bisa dihitung (target tanpa posisi/SOG/COG, atau kapal sendiri
  /// tanpa gerak GPS).
  static CpaResult? cpaFor({
    required Vessel vessel,
    required OwnShipState own,
  }) {
    if (!vessel.hasPosition) return null;
    return CpaMath.compute(
      own: own,
      targetLat: vessel.latitude!,
      targetLon: vessel.longitude!,
      targetSogKnots: vessel.speedKnots,
      targetCogDeg: vessel.courseDeg,
    );
  }

  /// Berbahaya bila (a) sudah di dalam lingkaran ambang CPA, atau
  /// (b) mendekat dengan CPA di bawah ambang dan TCPA di bawah ambang.
  static bool isDangerous(
    CpaResult cpa, {
    required double cpaThresholdNm,
    required double tcpaThresholdMin,
  }) {
    if (cpa.currentDistanceNm < cpaThresholdNm) return true;
    if (!cpa.closing || cpa.tcpaMinutes == null) return false;
    return cpa.cpaNm < cpaThresholdNm &&
        cpa.tcpaMinutes! < tcpaThresholdMin;
  }

  static AisTargetStatus resolve({
    required Vessel vessel,
    int? selectedMmsi,
    OwnShipState? own,
    double cpaThresholdNm = defaultCpaThresholdNm,
    double tcpaThresholdMin = defaultTcpaThresholdMin,
    DateTime? now,
  }) {
    final seen = vessel.lastSeen;
    if (seen != null &&
        (now ?? DateTime.now()).difference(seen) > lostAfter) {
      return AisTargetStatus.lost;
    }
    if (own != null) {
      final cpa = cpaFor(vessel: vessel, own: own);
      if (cpa != null &&
          isDangerous(
            cpa,
            cpaThresholdNm: cpaThresholdNm,
            tcpaThresholdMin: tcpaThresholdMin,
          )) {
        return AisTargetStatus.dangerous;
      }
    }
    if (selectedMmsi != null && vessel.mmsi == selectedMmsi) {
      return AisTargetStatus.activated;
    }
    return AisTargetStatus.sleeping;
  }

  /// Target berbahaya terdekat (untuk peringatan satu-slot di peta).
  /// null bila tidak ada target berbahaya.
  static Vessel? nearestDangerous(
    Iterable<Vessel> vessels, {
    required OwnShipState own,
    double cpaThresholdNm = defaultCpaThresholdNm,
    double tcpaThresholdMin = defaultTcpaThresholdMin,
  }) {
    Vessel? nearest;
    double? nearestDist;
    for (final vessel in vessels) {
      final cpa = cpaFor(vessel: vessel, own: own);
      if (cpa == null ||
          !isDangerous(
            cpa,
            cpaThresholdNm: cpaThresholdNm,
            tcpaThresholdMin: tcpaThresholdMin,
          )) {
        continue;
      }
      if (nearestDist == null ||
          cpa.currentDistanceNm < nearestDist) {
        nearest = vessel;
        nearestDist = cpa.currentDistanceNm;
      }
    }
    return nearest;
  }
}
