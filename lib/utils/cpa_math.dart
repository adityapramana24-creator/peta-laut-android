import 'dart:math' as math;

import 'nav_math.dart';

/// Keadaan kapal sendiri untuk hitungan CPA/TCPA.
/// SOG/COG dari GPS (NavigationViewModel.sogKnots/cogDeg); null bila GPS
/// tidak memberi gerak (diam / posisi manual) — CPA TIDAK dihitung
/// dalam kondisi itu, jangan dipalsukan dengan asumsi diam.
class OwnShipState {
  const OwnShipState({
    required this.latitude,
    required this.longitude,
    this.sogKnots,
    this.cogDeg,
  });

  final double latitude;
  final double longitude;
  final double? sogKnots;
  final double? cogDeg;

  /// CPA hanya bermakna bila gerak sendiri diketahui.
  bool get hasMotion => sogKnots != null && cogDeg != null;
}

/// Hasil hitungan CPA/TCPA terhadap satu target.
/// `cpaNm` = jarak pada titik terdekat; bila `tcpaMinutes` negatif,
/// titik terdekat sudah lewat (kapal MENJAUH) dan `cpaNm` adalah jarak
/// pada titik terdekat DI MASA LALU — UI wajib menampilkan "menjauh"
/// + jarak saat ini, bukan CPA lalu sebagai ancaman.
class CpaResult {
  const CpaResult({
    required this.cpaNm,
    required this.tcpaMinutes,
    required this.closing,
    required this.currentDistanceNm,
  });

  final double cpaNm;

  /// Menit sampai titik terdekat; null bila kecepatan relatif ~0
  /// (paralel / sama-sama diam — jarak praktis tidak berubah).
  final double? tcpaMinutes;

  /// true bila TCPA > 0 (jarak sedang mengecil).
  final bool closing;

  final double currentDistanceNm;
}

/// CPA/TCPA (Closest Point of Approach / Time to CPA) — hitungan murni.
/// Pendekatan planar equirectangular di sekitar posisi sendiri; akurat
/// untuk jarak < ~50 nm. Kedua kapal diasumsikan lurus + kecepatan
/// tetap (asumsi standar ARPA/ECDIS — bukan ramalan bila kapal
/// berbelok; CPA dihitung ulang tiap laporan posisi baru).
/// Terverifikasi terhadap implementasi referensi Python independen
/// (test/ais_cpa_test.dart — 7 skenario).
class CpaMath {
  CpaMath._();

  static const double earthRadiusNm = 3440.065;

  /// Hitung CPA/TCPA. null bila target tanpa posisi/SOG/COG, atau
  /// kapal sendiri tanpa gerak GPS.
  static CpaResult? compute({
    required OwnShipState own,
    required double targetLat,
    required double targetLon,
    required double? targetSogKnots,
    required double? targetCogDeg,
  }) {
    if (!own.hasMotion || targetSogKnots == null || targetCogDeg == null) {
      return null;
    }
    final dLat = NavMath.toRadians(targetLat - own.latitude);
    final dLon = NavMath.toRadians(targetLon - own.longitude);
    final meanLat = NavMath.toRadians((own.latitude + targetLat) / 2.0);
    // Posisi relatif target (nm): timur, utara.
    final rx = dLon * math.cos(meanLat) * earthRadiusNm;
    final ry = dLat * earthRadiusNm;
    final ownCog = NavMath.toRadians(own.cogDeg!);
    final tgtCog = NavMath.toRadians(targetCogDeg);
    // Kecepatan relatif (kt): timur = sog*sin(cog),
    // utara = sog*cos(cog).
    final vx = targetSogKnots * math.sin(tgtCog) -
        own.sogKnots! * math.sin(ownCog);
    final vy = targetSogKnots * math.cos(tgtCog) -
        own.sogKnots! * math.cos(ownCog);
    final current = math.sqrt(rx * rx + ry * ry);
    final v2 = vx * vx + vy * vy;
    if (v2 < 1e-9) {
      return CpaResult(
        cpaNm: current,
        tcpaMinutes: null,
        closing: false,
        currentDistanceNm: current,
      );
    }
    final tcpaHours = -(rx * vx + ry * vy) / v2;
    final cx = rx + vx * tcpaHours;
    final cy = ry + vy * tcpaHours;
    return CpaResult(
      cpaNm: math.sqrt(cx * cx + cy * cy),
      tcpaMinutes: tcpaHours * 60.0,
      closing: tcpaHours > 0,
      currentDistanceNm: current,
    );
  }

  /// Format TCPA untuk UI: "12 mnt" / "1 jam 5 mnt" / "—" / "menjauh".
  static String formatTcpa(double? tcpaMinutes) {
    if (tcpaMinutes == null) return '—';
    if (tcpaMinutes < 0) return 'menjauh';
    if (tcpaMinutes < 1) return '< 1 mnt';
    if (tcpaMinutes < 60) return '${tcpaMinutes.round()} mnt';
    final hours = (tcpaMinutes / 60).floor();
    final mins = (tcpaMinutes % 60).round();
    return '$hours jam $mins mnt';
  }
}
