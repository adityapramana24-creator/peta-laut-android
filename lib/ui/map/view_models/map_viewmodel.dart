import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/app_constants.dart';
import '../../../data/repositories/ais_repository.dart';
import '../../../data/repositories/depth_repository.dart';
import '../../../data/repositories/map_data_repository.dart';
import '../../../data/services/compass_service.dart';
import '../../../data/services/gebco_service.dart';
import '../../../data/services/location_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../domain/models/map_layers.dart';
import '../../../domain/models/vessel.dart';
import '../../../utils/nav_math.dart';
import '../../../utils/result.dart';
import '../../core/widgets/notice_banner.dart';
import '../../navigation/view_models/navigation_viewmodel.dart';

/// ViewModel layar peta: kamera, GPS/posisi manual, mode ikuti,
/// heading-up, lapisan, lookup kedalaman, kapal AIS, hint awal.
///
/// MapController DIBUAT di MapScreen dan dipasang via attachController
/// (pola resmi flutter_map — controller tidak boleh dibuat di VM).
class MapViewModel extends ChangeNotifier {
  MapViewModel({
    required LocationService locationService,
    required CompassService compassService,
    required SettingsService settingsService,
    required AisRepository aisRepository,
    required DepthRepository depthRepository,
    required MapDataRepository mapDataRepository,
    required NoticeController noticeController,
    NavigationViewModel? navigationViewModel,
  })  : _locationService = locationService,
        _compassService = compassService,
        _settingsService = settingsService,
        _aisRepository = aisRepository,
        _depthRepository = depthRepository,
        _mapDataRepository = mapDataRepository,
        _noticeController = noticeController,
        _navigationViewModel = navigationViewModel {
    _settingsService.addListener(_onSettingsChanged);
    _compassService.headingNotifier.addListener(_onHeadingChanged);
    _aisRepository.vesselsStream.listen((vessels) {
      _vessels = vessels;
      notifyListeners();
    });
    _aisRepository.connectionState.listen((state) {
      _aisState = state;
      notifyListeners();
    });
  }

  final LocationService _locationService;
  final CompassService _compassService;
  final SettingsService _settingsService;
  final AisRepository _aisRepository;
  final DepthRepository _depthRepository;
  final MapDataRepository _mapDataRepository;
  final NoticeController _noticeController;

  /// ViewModel navigasi (opsional — dipasang di dependencies):
  /// menerima posisi GPS/manual untuk GoTo, rekam jejak, alarm
  /// jangkar, dan SOG/COG. Satu sumber posisi, tidak ada stream kedua.
  final NavigationViewModel? _navigationViewModel;

  MapController? _mapController;
  bool _initialized = false;
  bool _aisConnected = false;

  // -- Kamera (cermin state peta) --
  LatLng _center = const LatLng(
    AppConstants.defaultLat,
    AppConstants.defaultLon,
  );
  double _zoom = AppConstants.defaultZoom;
  double _rotation = 0;
  LatLngBounds? _visibleBounds;

  // -- Posisi --
  LatLng? _ownPosition;
  double? _ownAccuracyM;
  bool _positionIsManual = false;
  double? _gpsCourseDeg;
  double? _gpsSpeedMs;
  bool _followMode = false;

  // -- Heading --
  bool _headingUp = false;
  double? _lastRotatedHeading;
  DateTime? _lastRotateTime;
  double? _lastNotifiedHeading;

  // -- Lapisan --
  String? _rainTemplate;

  // -- Kedalaman --
  LatLng? _depthPoint;
  DepthResult? _depthResult;
  String? _depthError;
  bool _depthLoading = false;

  // -- AIS --
  Map<int, Vessel> _vessels = {};
  AisConnectionState _aisState = AisConnectionState.notConfigured;
  Vessel? _selectedVessel;
  Timer? _aisBoundsTimer;
  LatLng? _lastAisCenter;
  double? _lastAisZoom;

  // -- Hint --
  bool _hintDismissed = false;

  DateTime? _lastCameraNotify;

  // -- Getters --

  LatLng get center => _center;
  double get zoom => _zoom;
  double get rotation => _rotation;
  LatLngBounds? get visibleBounds => _visibleBounds;
  LatLng? get ownPosition => _ownPosition;
  double? get ownAccuracyM => _ownAccuracyM;
  bool get positionIsManual => _positionIsManual;
  bool get followMode => _followMode;
  bool get headingUp => _headingUp;
  LayerSettings get layers => _settingsService.layerSettings;
  String? get rainTemplate => _rainTemplate;
  String get gibsTemplate => _mapDataRepository.gibsTemplate;
  LatLng? get depthPoint => _depthPoint;
  DepthResult? get depthResult => _depthResult;
  String? get depthError => _depthError;
  bool get depthLoading => _depthLoading;
  Map<int, Vessel> get vessels => _vessels;
  AisConnectionState get aisState => _aisState;
  Vessel? get selectedVessel => _selectedVessel;

  bool get showFirstUseHint =>
      !_hintDismissed && !_settingsService.firstUseHintShown;

  /// Heading efektif: course GPS saat bergerak (>1 m/s), else kompas.
  double? get effectiveHeading {
    if (_gpsSpeedMs != null &&
        _gpsSpeedMs! > 1.0 &&
        _gpsCourseDeg != null) {
      return _gpsCourseDeg;
    }
    return _compassService.heading;
  }

  /// Titik acuan panel data: posisi sendiri bila ada, else tengah peta.
  LatLng get panelPoint => _ownPosition ?? _center;

  /// Bbox AIS saat ini (untuk sambung ulang setelah kunci disimpan).
  (double, double, double, double) get aisBounds => _boundsForAis();

  // -- Lifecycle --

  void attachController(MapController controller) {
    _mapController = controller;
  }

  /// Dipanggil sekali dari MapScreen.initState.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _compassService.start();
    // Bila izin sudah diberikan sebelumnya, stream GPS langsung jalan.
    if (await _locationService.hasPermission) {
      _startPositionStream();
    }
  }

  /// Dipanggil dari onMapReady: AIS sambung dengan bbox terlihat.
  Future<void> onMapReady() async {
    if (_aisConnected) return;
    _aisConnected = true;
    final bounds = _boundsForAis();
    await _aisRepository.connectIfConfigured(bounds: bounds);
    _lastAisCenter = _center;
    _lastAisZoom = _zoom;
  }

  // -- Kamera --

  void onCameraChanged(MapCamera camera, bool hasGesture) {
    final rotationChanged = (camera.rotation - _rotation).abs() > 1.0;
    final zoomChanged = (camera.zoom - _zoom).abs() > 0.25;
    _center = camera.center;
    _zoom = camera.zoom;
    _rotation = camera.rotation;
    _visibleBounds = camera.visibleBounds;
    if (hasGesture && _followMode) {
      _followMode = false;
    }
    // Throttle rebuild: rotasi/zoom berubah signifikan, atau 500 ms.
    final now = DateTime.now();
    final due = _lastCameraNotify == null ||
        now.difference(_lastCameraNotify!) >=
            const Duration(milliseconds: 500);
    if (rotationChanged || zoomChanged || due) {
      _lastCameraNotify = now;
      notifyListeners();
    }
    _maybeUpdateAisBounds();
  }

  void _maybeUpdateAisBounds() {
    if (!_aisConnected) return;
    final lastCenter = _lastAisCenter;
    final lastZoom = _lastAisZoom;
    final centerMoved = lastCenter == null ||
        NavMath.distanceMeters(
              lastCenter.latitude,
              lastCenter.longitude,
              _center.latitude,
              _center.longitude,
            ) >
            30000; // ~0.3 derajat
    final zoomMoved =
        lastZoom == null || (_zoom - lastZoom).abs() > 1.0;
    if (!centerMoved && !zoomMoved) return;
    _aisBoundsTimer?.cancel();
    _aisBoundsTimer = Timer(const Duration(seconds: 1), () {
      _aisRepository.updateBounds(_boundsForAis());
      _lastAisCenter = _center;
      _lastAisZoom = _zoom;
    });
  }

  (double, double, double, double) _boundsForAis() {
    final bounds = _visibleBounds;
    if (bounds == null) {
      return (
        _center.latitude - 20,
        _center.longitude - 20,
        _center.latitude + 20,
        _center.longitude + 20,
      );
    }
    return (
      bounds.southWest.latitude,
      bounds.southWest.longitude,
      bounds.northEast.latitude,
      bounds.northEast.longitude,
    );
  }

  // -- Posisi --

  Future<void> locateMe() async {
    final granted = await _locationService.requestPermission();
    if (!granted) {
      _noticeController.show(
        'Izin lokasi ditolak. Pakai posisi manual: tahan peta, atau ketik koordinat.',
      );
      return;
    }
    final result = await _locationService.getCurrentPosition();
    switch (result) {
      case Ok(value: final position):
        _applyPosition(position);
        _positionIsManual = false;
        _followMode = true;
        _mapController?.move(_ownPosition!, _zoom < 10 ? 12 : _zoom);
        _startPositionStream();
        notifyListeners();
      case Error(error: final error):
        _noticeController.show(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _startPositionStream() {
    _locationService.listenToPositionStream((position) {
      final moved = _ownPosition == null ||
          NavMath.distanceMeters(
                _ownPosition!.latitude,
                _ownPosition!.longitude,
                position.latitude,
                position.longitude,
              ) >
              5;
      _applyPosition(position);
      _positionIsManual = false;
      if (_followMode && moved) {
        _mapController?.move(_ownPosition!, _zoom);
      }
      notifyListeners();
    });
  }

  void _applyPosition(Position position) {
    _ownPosition = LatLng(position.latitude, position.longitude);
    _ownAccuracyM = position.accuracy;
    // geolocator: heading/speed negatif = tidak tersedia.
    _gpsCourseDeg =
        (position.heading >= 0 && position.heading <= 360)
            ? position.heading
            : null;
    _gpsSpeedMs = position.speed >= 0 ? position.speed : null;
    _navigationViewModel?.updatePosition(position);
    if (_headingUp) _maybeRotateMap();
  }

  /// Posisi manual: long-press peta / ketik koordinat (R-12).
  void setManualPosition(LatLng point) {
    _ownPosition = point;
    _ownAccuracyM = null;
    _positionIsManual = true;
    _followMode = false;
    _gpsCourseDeg = null;
    _gpsSpeedMs = null;
    _navigationViewModel?.setManualPosition(point);
    _mapController?.move(point, _zoom);
    _noticeController.show('Posisi manual ditetapkan.');
    notifyListeners();
  }

  /// Pindah kamera ke satu titik (mis. dari lembar detail kapal).
  void moveTo(LatLng point, {double? zoom}) {
    _followMode = false;
    _mapController?.move(point, zoom ?? _zoom);
    notifyListeners();
  }

  void toggleFollow() {
    if (_ownPosition == null) {
      locateMe();
      return;
    }
    _followMode = !_followMode;
    if (_followMode) {
      _mapController?.move(_ownPosition!, _zoom);
    }
    notifyListeners();
  }

  // -- Heading / rotasi --

  void toggleHeadingUp() {
    _headingUp = !_headingUp;
    if (_headingUp) {
      final heading = effectiveHeading;
      if (heading != null) {
        _mapController?.rotate(heading);
        _lastRotatedHeading = heading;
        _lastRotateTime = DateTime.now();
      } else {
        _noticeController.show(
          'Heading belum tersedia — bergeraklah agar GPS membaca arah.',
        );
      }
    } else {
      _mapController?.rotate(0);
    }
    notifyListeners();
  }

  void _onHeadingChanged() {
    // Sensor kompas bisa melaporkan puluhan kali per detik — rebuild
    // hanya bila heading efektif berubah > 2 derajat.
    final heading = effectiveHeading;
    if (heading == null) return;
    if (_lastNotifiedHeading != null &&
        (heading - _lastNotifiedHeading!).abs() <= 2.0) {
      return;
    }
    _lastNotifiedHeading = heading;
    if (_headingUp) _maybeRotateMap();
    notifyListeners();
  }

  /// Rotasi peta di-throttle: perubahan >2 derajat dan >=100 ms.
  void _maybeRotateMap() {
    final heading = effectiveHeading;
    final controller = _mapController;
    if (heading == null || controller == null) return;
    final now = DateTime.now();
    if (_lastRotateTime != null &&
        now.difference(_lastRotateTime!) <
            const Duration(milliseconds: 100)) {
      return;
    }
    if (_lastRotatedHeading != null &&
        (heading - _lastRotatedHeading!).abs() <= 2.0) {
      return;
    }
    controller.rotate(heading);
    _lastRotatedHeading = heading;
    _lastRotateTime = now;
  }

  // -- Lapisan --

  Future<void> setBasemap(BasemapKind basemap) async {
    await _settingsService
        .setLayerSettings(layers.copyWith(basemap: basemap));
  }

  Future<void> toggleGebco(bool value) async {
    await _settingsService
        .setLayerSettings(layers.copyWith(showGebco: value));
  }

  Future<void> toggleSeamark(bool value) async {
    await _settingsService
        .setLayerSettings(layers.copyWith(showSeamark: value));
  }

  Future<void> toggleRain(bool value) async {
    await _settingsService
        .setLayerSettings(layers.copyWith(showRain: value));
    if (value) await refreshRainTemplate();
  }

  Future<void> toggleGibs(bool value) async {
    await _settingsService
        .setLayerSettings(layers.copyWith(showGibs: value));
  }

  Future<void> toggleAis(bool value) async {
    await _settingsService
        .setLayerSettings(layers.copyWith(showAis: value));
  }

  Future<void> refreshRainTemplate() async {
    final result = await _mapDataRepository.getRainTemplate();
    switch (result) {
      case Ok(value: final template):
        _rainTemplate = template;
        notifyListeners();
      case Error():
        _noticeController.show('Radar hujan tidak tersedia saat ini.');
    }
  }

  // -- Kedalaman --

  Future<void> lookupDepth(LatLng point) async {
    _depthPoint = point;
    _depthResult = null;
    _depthError = null;
    _depthLoading = true;
    notifyListeners();
    final result = await _depthRepository.getDepth(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    // Abaikan hasil bila user sudah mengetuk titik lain.
    if (_depthPoint != point) return;
    switch (result) {
      case Ok(value: final depth):
        _depthResult = depth;
      case Error(error: final error):
        _depthError = error.toString().replaceFirst('Exception: ', '');
    }
    _depthLoading = false;
    notifyListeners();
  }

  void clearDepth() {
    _depthPoint = null;
    _depthResult = null;
    _depthError = null;
    _depthLoading = false;
    notifyListeners();
  }

  // -- AIS --

  void selectVessel(Vessel? vessel) {
    _selectedVessel = vessel;
    notifyListeners();
  }

  // -- Hint --

  Future<void> dismissFirstUseHint() async {
    _hintDismissed = true;
    await _settingsService.setFirstUseHintShown();
    notifyListeners();
  }

  void _onSettingsChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _aisBoundsTimer?.cancel();
    _settingsService.removeListener(_onSettingsChanged);
    _compassService.headingNotifier.removeListener(_onHeadingChanged);
    _locationService.stopPositionStream();
    super.dispose();
  }
}
