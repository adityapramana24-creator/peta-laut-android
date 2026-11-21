import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_constants.dart';
import '../../domain/models/map_layers.dart';

/// Pengaturan persisten (SharedPreferences) + ChangeNotifier agar
/// tema/lapisan bereaksi langsung saat diubah.
/// Injeksi via konstruktor (dibuat di main() setelah prefs siap).
class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _keyThemeMode = 'theme_mode';
  static const _keyBasemap = 'basemap';
  static const _keyShowGebco = 'show_gebco';
  static const _keyShowSeamark = 'show_seamark';
  static const _keyShowRain = 'show_rain';
  static const _keyShowGibs = 'show_gibs';
  static const _keyShowAis = 'show_ais';
  static const _keyShowDepthLabels = 'show_depth_labels';
  static const _keyFirstUseHintShown = 'first_use_hint_shown';
  static const _keyCruiseSpeedKnots = 'cruise_speed_knots';

  ThemeMode get themeMode {
    final raw = _prefs.getString(_keyThemeMode);
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final raw = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(_keyThemeMode, raw);
    notifyListeners();
  }

  LayerSettings get layerSettings {
    final basemapRaw = _prefs.getString(_keyBasemap);
    BasemapKind basemap = BasemapKind.standard;
    if (basemapRaw != null) {
      basemap = BasemapKind.values.firstWhere(
        (b) => b.name == basemapRaw,
        orElse: () => BasemapKind.standard,
      );
    }
    return LayerSettings(
      basemap: basemap,
      showGebco: _prefs.getBool(_keyShowGebco) ?? true,
      showSeamark: _prefs.getBool(_keyShowSeamark) ?? true,
      showRain: _prefs.getBool(_keyShowRain) ?? false,
      showGibs: _prefs.getBool(_keyShowGibs) ?? false,
      showAis: _prefs.getBool(_keyShowAis) ?? true,
      showDepthLabels: _prefs.getBool(_keyShowDepthLabels) ?? true,
    );
  }

  Future<void> setLayerSettings(LayerSettings settings) async {
    await _prefs.setString(_keyBasemap, settings.basemap.name);
    await _prefs.setBool(_keyShowGebco, settings.showGebco);
    await _prefs.setBool(_keyShowSeamark, settings.showSeamark);
    await _prefs.setBool(_keyShowRain, settings.showRain);
    await _prefs.setBool(_keyShowGibs, settings.showGibs);
    await _prefs.setBool(_keyShowAis, settings.showAis);
    await _prefs.setBool(_keyShowDepthLabels, settings.showDepthLabels);
    notifyListeners();
  }

  bool get firstUseHintShown =>
      _prefs.getBool(_keyFirstUseHintShown) ?? false;

  Future<void> setFirstUseHintShown() async {
    await _prefs.setBool(_keyFirstUseHintShown, true);
  }

  /// Kecepatan jelajah (knot) untuk ETA rute — kecepatan terakhir
  /// yang dipakai user saat menyimpan/mengubah rute. Default 8 knot
  /// (AppConstants.defaultSpeedKnots); dijepit 1–50 knot.
  double get cruiseSpeedKnots {
    final v = _prefs.getDouble(_keyCruiseSpeedKnots);
    if (v == null) return AppConstants.defaultSpeedKnots;
    return v.clamp(1.0, 50.0).toDouble();
  }

  Future<void> setCruiseSpeedKnots(double knots) async {
    await _prefs.setDouble(
      _keyCruiseSpeedKnots,
      knots.clamp(1.0, 50.0).toDouble(),
    );
    notifyListeners();
  }
}
