import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/ais_target_status.dart';

/// Ambang alarm target berbahaya (CPA/TCPA) — disimpan di
/// SharedPreferences, diubah dari seksi AIS di Pengaturan.
/// Nilai bawaan = AisTargetStatusResolver (satu sumber kebenaran).
class AisAlertSettings {
  static const double defaultCpaThresholdNm =
      AisTargetStatusResolver.defaultCpaThresholdNm;
  static const double defaultTcpaThresholdMin =
      AisTargetStatusResolver.defaultTcpaThresholdMin;
  static const List<double> cpaOptionsNm = [0.25, 0.5, 1.0, 2.0];
  static const List<double> tcpaOptionsMin = [5, 15, 30, 60];

  static const _keyCpa = 'ais_cpa_threshold_nm';
  static const _keyTcpa = 'ais_tcpa_threshold_min';

  /// Muat kedua ambang sekaligus: (cpaNm, tcpaMin).
  Future<(double, double)> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      prefs.getDouble(_keyCpa) ?? defaultCpaThresholdNm,
      prefs.getDouble(_keyTcpa) ?? defaultTcpaThresholdMin,
    );
  }

  Future<void> saveCpaThresholdNm(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCpa, value);
  }

  Future<void> saveTcpaThresholdMin(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTcpa, value);
  }
}
