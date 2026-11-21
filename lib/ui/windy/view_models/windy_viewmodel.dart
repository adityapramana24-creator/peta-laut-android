import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/repositories/windy_repository.dart';
import '../../../data/services/current_grid_service.dart';
import '../../../domain/models/marine.dart';
import '../../../domain/models/weather_alert.dart';
import '../../../domain/models/windy.dart';
import '../../../utils/result.dart';
import '../../../utils/wib_clock.dart';
import '../../core/widgets/notice_banner.dart';

/// ViewModel paket Windy (R-29/R-30): partikel angin, panah arus,
/// timeline, pilih model, prakiraan titik + meteogram, peringatan
/// ambang, cuaca di sepanjang rute.
class WindyViewModel extends ChangeNotifier {
  WindyViewModel({
    required WindyRepository repository,
    required NoticeController noticeController,
    CurrentGridService? currentGridService,
  })  : _repository = repository,
        _noticeController = noticeController,
        _currentGridService = currentGridService ?? CurrentGridService() {
    _model = _repository.model;
    _particlesEnabled = _repository.particlesEnabled;
    _currentsEnabled = _repository.currentsEnabled;
    _alerts = _repository.alerts;
    // Jam default = jam berjalan WIB (indeks dari awal hari ini —
    // jam grid adalah wall-clock WIB, lihat WibClock).
    _hourIndex = WibClock.now().hour;
    _alertTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _refreshAlertsAtOwnPosition(),
    );
  }

  final WindyRepository _repository;
  final NoticeController _noticeController;
  final CurrentGridService _currentGridService;

  WindyModel _model = WindyModel.auto;
  bool _particlesEnabled = false;
  WindGrid? _grid;
  bool _gridLoading = false;
  String? _gridError;
  // Panah arus (ronde 2, item 4b): saklar tersimpan di
  // WindyRepository (kunci _keyCurrents), cermin particlesEnabled.
  bool _currentsEnabled = false;
  CurrentGrid? _currentGrid;
  bool _currentGridLoading = false;
  String? _currentGridError;
  String? _currentGridKey;
  DateTime? _currentGridFetchedAt;
  static const _currentGridTtl = Duration(minutes: 30);
  int _hourIndex = 0;
  bool _playing = false;
  Timer? _playTimer;
  Timer? _alertTimer;

  PointForecast? _pointForecast;
  LatLng? _forecastPoint;
  bool _forecastLoading = false;
  String? _forecastError;
  bool _pickMode = false;

  /// Peringatan ambang cuaca (R-30, F-L5): dimuat dari repository
  /// di konstruktor, disimpan kembali ke repository di tiap
  /// perubahan (add/update/delete/toggle + setelah evaluasi yang
  /// memperbarui lastTriggeredAt). Timer 15 menit mengevaluasi
  /// ulang daftar ini terhadap prakiraan segar di posisi kapal.
  List<WeatherAlert> _alerts = [];

  /// Penyedia posisi kapal sendiri untuk timer peringatan (F-L5):
  /// dipasang MapScreen dari MapViewModel (`() => vm.ownPosition`).
  /// Null = posisi tidak diketahui -> timer jatuh ke evaluasi
  /// prakiraan lama.
  LatLng? Function()? ownPositionProvider;

  WindyModel get model => _model;
  bool get particlesEnabled => _particlesEnabled;
  WindGrid? get grid => _grid;
  bool get gridLoading => _gridLoading;
  String? get gridError => _gridError;
  bool get currentsEnabled => _currentsEnabled;
  CurrentGrid? get currentGrid => _currentGrid;
  bool get currentGridLoading => _currentGridLoading;
  String? get currentGridError => _currentGridError;
  int get hourIndex => _hourIndex;
  bool get playing => _playing;
  PointForecast? get pointForecast => _pointForecast;
  LatLng? get forecastPoint => _forecastPoint;
  bool get forecastLoading => _forecastLoading;
  String? get forecastError => _forecastError;
  bool get pickMode => _pickMode;
  List<WeatherAlert> get alerts => _alerts;

  /// Jumlah jam timeline (72 jam = 3 hari).
  int get timelineHours => _grid?.times.length ?? 72;

  /// Label jam timeline yang dipilih (WIB).
  DateTime? get selectedTime {
    final grid = _grid;
    if (grid != null &&
        _hourIndex >= 0 &&
        _hourIndex < grid.times.length) {
      return grid.times[_hourIndex];
    }
    final now = WibClock.now();
    return DateTime(now.year, now.month, now.day, now.hour)
        .add(Duration(hours: _hourIndex - now.hour));
  }

  // -- Model + partikel --

  Future<void> setModel(WindyModel model) async {
    if (_model == model) return;
    _model = model;
    await _repository.setModel(model);
    _grid = null;
    _pointForecast = null;
    notifyListeners();
    _noticeController.show('Model prakiraan: ${model.label}.');
    // Muat ulang prakiraan titik yang sama dengan model baru
    // (bila sebelumnya sudah ada titik) — meteogram tidak hilang
    // begitu saja saat model diganti.
    final point = _forecastPoint;
    if (point != null) {
      unawaited(loadPointForecast(point));
    }
  }

  Future<void> setParticlesEnabled(
    bool enabled, {
    LatLngBounds? bounds,
  }) async {
    _particlesEnabled = enabled;
    await _repository.setParticlesEnabled(enabled);
    notifyListeners();
    if (enabled && bounds != null) {
      await loadGrid(bounds);
    }
  }

  Future<void> loadGrid(LatLngBounds bounds, {bool forceRefresh = false}) async {
    if (_gridLoading) return;
    _gridLoading = true;
    _gridError = null;
    notifyListeners();
    final result = await _repository.getWindGrid(
      south: bounds.southWest.latitude,
      west: bounds.southWest.longitude,
      north: bounds.northEast.latitude,
      east: bounds.northEast.longitude,
      forceRefresh: forceRefresh,
    );
    switch (result) {
      case Ok(value: final grid):
        _grid = grid;
        _gridError = null;
        // Jam default: jam berjalan WIB relatif terhadap awal grid.
        // Jam grid adalah wall-clock WIB (F-R2: jam asli respons,
        // F-L4: WibClock agar benar juga di perangkat WITA/WIT).
        final now = WibClock.now();
        var idx = 0;
        for (var i = 0; i < grid.times.length; i++) {
          if (!grid.times[i].isAfter(now)) idx = i;
        }
        _hourIndex = idx;
      case Error(error: final error):
        _gridError = error.toString().replaceFirst('Exception: ', '');
        _noticeController.show('Grid angin gagal dimuat.');
    }
    _gridLoading = false;
    notifyListeners();
  }

  // -- Panah arus --

  Future<void> setCurrentsEnabled(
    bool enabled, {
    LatLngBounds? bounds,
  }) async {
    _currentsEnabled = enabled;
    await _repository.setCurrentsEnabled(enabled);
    notifyListeners();
    if (enabled && bounds != null) {
      await loadCurrentGrid(bounds);
    }
  }

  Future<void> loadCurrentGrid(
    LatLngBounds bounds, {
    bool forceRefresh = false,
  }) async {
    if (_currentGridLoading) return;
    // Cache memori 30 menit per area (pola yang sama dengan grid
    // angin di repository) — grid arus tidak bergantung pada model
    // angin (Marine API tidak punya parameter model).
    final key =
        '${bounds.southWest.latitude.toStringAsFixed(1)}|'
        '${bounds.southWest.longitude.toStringAsFixed(1)}|'
        '${bounds.northEast.latitude.toStringAsFixed(1)}|'
        '${bounds.northEast.longitude.toStringAsFixed(1)}';
    if (!forceRefresh &&
        _currentGrid != null &&
        _currentGridKey == key &&
        _currentGridFetchedAt != null &&
        DateTime.now().difference(_currentGridFetchedAt!) <
            _currentGridTtl) {
      return;
    }
    _currentGridLoading = true;
    _currentGridError = null;
    notifyListeners();
    final result = await _currentGridService.fetchGrid(
      south: bounds.southWest.latitude,
      west: bounds.southWest.longitude,
      north: bounds.northEast.latitude,
      east: bounds.northEast.longitude,
    );
    switch (result) {
      case Ok(value: final grid):
        _currentGrid = grid;
        _currentGridKey = key;
        _currentGridFetchedAt = DateTime.now();
        _currentGridError = null;
      case Error(error: final error):
        _currentGridError = error.toString().replaceFirst('Exception: ', '');
        _noticeController.show('Grid arus gagal dimuat.');
    }
    _currentGridLoading = false;
    notifyListeners();
  }

  // -- Timeline --

  void setHourIndex(int index) {
    final max = timelineHours - 1;
    _hourIndex = index.clamp(0, max);
    notifyListeners();
  }

  void togglePlay() {
    _playing = !_playing;
    _playTimer?.cancel();
    if (_playing) {
      _playTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final next = _hourIndex + 1;
        if (next >= timelineHours) {
          _playing = false;
          _playTimer?.cancel();
        } else {
          _hourIndex = next;
        }
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void stopPlaying() {
    _playing = false;
    _playTimer?.cancel();
    notifyListeners();
  }

  // -- Prakiraan titik --

  void setPickMode(bool enabled) {
    _pickMode = enabled;
    notifyListeners();
  }

  Future<void> loadPointForecast(LatLng point) async {
    _forecastPoint = point;
    _forecastLoading = true;
    _forecastError = null;
    _pickMode = false;
    notifyListeners();
    final result = await _repository.getPointForecast(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    switch (result) {
      case Ok(value: final forecast):
        _pointForecast = forecast;
        _forecastError = null;
        await _evaluateAlertsIfReady();
      case Error(error: final error):
        _forecastError = error.toString().replaceFirst('Exception: ', '');
    }
    _forecastLoading = false;
    notifyListeners();
  }

  Future<void> refreshPointForecast() async {
    if (_forecastPoint != null) {
      await loadPointForecast(_forecastPoint!);
    }
  }

  // -- Peringatan ambang --

  Future<void> addAlert(WeatherAlert alert) async {
    _alerts = [..._alerts, alert];
    await _repository.saveAlerts(_alerts);
    notifyListeners();
    _noticeController.show('Peringatan "${alert.name}" aktif.');
    unawaited(_repository.requestNotificationPermission());
    await _evaluateAlertsIfReady();
  }

  Future<void> updateAlert(WeatherAlert alert) async {
    _alerts = _alerts.map((a) => a.id == alert.id ? alert : a).toList();
    await _repository.saveAlerts(_alerts);
    notifyListeners();
  }

  Future<void> deleteAlert(String id) async {
    _alerts = _alerts.where((a) => a.id != id).toList();
    await _repository.saveAlerts(_alerts);
    notifyListeners();
  }

  Future<void> toggleAlert(String id, bool enabled) async {
    _alerts = _alerts
        .map((a) => a.id == id ? a.copyWith(enabled: enabled) : a)
        .toList();
    await _repository.saveAlerts(_alerts);
    notifyListeners();
  }

  /// Timer 15 menit (F-L5): evaluasi ulang peringatan terhadap
  /// prakiraan SEGAR DI POSISI KAPAL SAAT INI — bukan prakiraan
  /// titik terakhir yang basi (user berlayar menjauh, alert tetap
  /// mengawasi titik lama). Prakiraan tampil (_pointForecast /
  /// _forecastPoint — pilihan user untuk meteogram) TIDAK diubah:
  /// evaluasi memakai salinan segar dari repository (cache repo
  /// membuat pemanggilan tiap 15 menit ini murah). Bila posisi
  /// sendiri tidak diketahui / muat gagal, jatuh ke evaluasi
  /// prakiraan lama.
  Future<void> _refreshAlertsAtOwnPosition() async {
    if (_alerts.where((a) => a.enabled).isEmpty) return;
    final own = ownPositionProvider?.call();
    if (own == null || _forecastLoading) {
      await _evaluateAlertsIfReady();
      return;
    }
    final result = await _repository.getPointForecast(
      latitude: own.latitude,
      longitude: own.longitude,
    );
    switch (result) {
      case Ok(value: final forecast):
        final triggered = await _repository.evaluateAlerts(forecast);
        if (triggered.isNotEmpty) {
          _alerts = _repository.alerts;
          _noticeController.show(
            'Peringatan cuaca: ${triggered.map((a) => a.name).join(', ')}.',
          );
          notifyListeners();
        }
      case Error():
        await _evaluateAlertsIfReady();
    }
  }

  Future<void> _evaluateAlertsIfReady() async {
    final forecast = _pointForecast;
    if (forecast == null) return;
    if (_alerts.where((a) => a.enabled).isEmpty) return;
    final triggered = await _repository.evaluateAlerts(forecast);
    if (triggered.isNotEmpty) {
      _alerts = _repository.alerts;
      _noticeController.show(
        'Peringatan cuaca: ${triggered.map((a) => a.name).join(', ')}.',
      );
      notifyListeners();
    }
  }

  /// Evaluasi peringatan terhadap prakiraan di satu titik (dipakai
  /// tombol "Periksa sekarang" — memuat prakiraan dulu bila perlu).
  Future<void> evaluateNow(LatLng point) async {
    if (_pointForecast == null) {
      await loadPointForecast(point);
    } else {
      await _evaluateAlertsIfReady();
    }
  }

  // -- Cuaca di sepanjang rute --

  Future<Result<List<RouteWeatherPoint>>> routeWeather(
    List<({String name, double lat, double lon, DateTime eta})> points,
  ) async {
    try {
      final result = await _repository.routeWeather(points);
      return Result.ok(result);
    } catch (e) {
      return Result.error(Exception('Gagal memuat cuaca rute: $e'));
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _alertTimer?.cancel();
    super.dispose();
  }
}
