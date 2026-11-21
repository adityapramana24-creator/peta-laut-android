import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/app_constants.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/safety_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../domain/models/anchor_mob.dart';
import '../../../domain/models/waypoint.dart';
import '../../../utils/anchor_math.dart';
import '../../../utils/coordinates.dart';
import '../../../utils/nav_math.dart';
import '../../../utils/track_stats.dart';
import '../../core/widgets/notice_banner.dart';

/// ViewModel navigasi (R-10, R-27, R-28): waypoint, rute, GoTo,
/// pengukur jarak, rekam jejak, alarm jangkar, MOB, SOG/COG.
///
/// Posisi GPS masuk lewat [updatePosition] yang dipanggil MapViewModel
/// dari stream-nya (satu sumber posisi — tidak ada stream kedua).
/// Alarm jangkar + rekam jejak aktif selama aplikasi terbuka.
class NavigationViewModel extends ChangeNotifier {
  NavigationViewModel({
    required NavigationRepository repository,
    required SafetyRepository safetyRepository,
    required NoticeController noticeController,
    NotificationService? notificationService,
  })  : _repository = repository,
        _safetyRepository = safetyRepository,
        _noticeController = noticeController,
        _notifications = notificationService ?? NotificationService() {
    _waypointsSub =
        _repository.watchWaypoints().listen((waypoints) {
      _waypoints = waypoints;
      notifyListeners();
    });
    _routesSub = _repository.watchRoutes().listen((routes) {
      _routes = routes;
      notifyListeners();
    });
    _tracksSub = _repository.watchTracks().listen((tracks) {
      _tracks = tracks;
      // Sapuan yatim sekali saat mulai: jejak yang masih "aktif"
      // (endedAt null) dari sesi sebelumnya berarti aplikasi mati
      // saat merekam — tutup dengan waktu sekarang (titik-titiknya
      // tetap tersimpan, tidak hilang).
      if (!_orphanSweepDone) {
        _orphanSweepDone = true;
        unawaited(_closeOrphanTracks(tracks));
      }
      notifyListeners();
    });
    _mobMarks = _safetyRepository.mobMarks;
    _anchor = _safetyRepository.anchor;
  }

  final NavigationRepository _repository;
  final SafetyRepository _safetyRepository;
  final NoticeController _noticeController;
  final NotificationService _notifications;

  StreamSubscription<List<Waypoint>>? _waypointsSub;
  StreamSubscription<List<RoutePlan>>? _routesSub;
  StreamSubscription<List<Track>>? _tracksSub;

  List<Waypoint> _waypoints = [];
  List<RoutePlan> _routes = [];
  List<Track> _tracks = [];

  // -- Posisi sendiri (dari MapViewModel) --
  LatLng? _ownPosition;
  double? _ownSpeedMs;
  double? _ownCourseDeg;
  bool _positionIsManual = false;

  // -- GoTo --
  Waypoint? _gotoTarget;

  // -- Pengukur jarak --
  bool _measureMode = false;
  List<LatLng> _measurePoints = [];

  // -- Rekam jejak --
  Track? _activeTrack;
  List<TrackPoint> _activePoints = [];
  TrackPoint? _lastRecordedPoint;
  bool _orphanSweepDone = false;

  /// Rekam bila: >= 30 detik sejak titik terakhir DAN bergerak >= 25 m
  /// (hemat baterai + hemat penyimpanan).
  static const _recordMinInterval = Duration(seconds: 30);
  static const _recordMinDistanceM = 25.0;

  // -- Alarm jangkar --
  AnchorSettings? _anchor;
  bool _anchorAlarm = false;

  /// Alarm dibisukan lewat tombol "Diamkan" (F-L3): tetap diam
  /// selama kapal di luar radius; dibersihkan saat kapal kembali ke
  /// dalam radius, sehingga alarm bisa berbunyi lagi bila keluar.
  bool _anchorSilenced = false;
  double? _anchorDistanceM;

  // -- MOB --
  List<MobMark> _mobMarks = [];

  // -- Pilihan tampil di peta --
  RoutePlan? _visibleRoute;
  Track? _visibleTrack;

  // -- Getters --

  List<Waypoint> get waypoints => _waypoints;
  List<RoutePlan> get routes => _routes;
  List<Track> get tracks => _tracks;
  LatLng? get ownPosition => _ownPosition;
  bool get positionIsManual => _positionIsManual;
  Waypoint? get gotoTarget => _gotoTarget;
  bool get measureMode => _measureMode;
  List<LatLng> get measurePoints => _measurePoints;
  bool get isRecording => _activeTrack != null;
  Track? get activeTrack => _activeTrack;
  List<TrackPoint> get activePoints => _activePoints;
  AnchorSettings? get anchor => _anchor;
  bool get anchorArmed => _anchor?.armed ?? false;
  bool get anchorAlarm => _anchorAlarm;
  bool get anchorSilenced => _anchorSilenced;
  double? get anchorDistanceM => _anchorDistanceM;
  List<MobMark> get mobMarks => _mobMarks;
  RoutePlan? get visibleRoute => _visibleRoute;
  Track? get visibleTrack => _visibleTrack;

  /// SOG (knot) dari GPS; null bila GPS tidak memberi kecepatan.
  double? get sogKnots =>
      _ownSpeedMs == null ? null : NavMath.msToKnots(_ownSpeedMs!);

  /// COG (derajat) dari GPS; null bila tidak bergerak / tidak ada.
  double? get cogDeg => _ownCourseDeg;

  /// Jarak ke target GoTo (meter).
  double? get gotoDistanceM {
    final target = _gotoTarget;
    final own = _ownPosition;
    if (target == null || own == null) return null;
    return NavMath.distanceMeters(
      own.latitude,
      own.longitude,
      target.latitude,
      target.longitude,
    );
  }

  /// Bearing ke target GoTo (derajat).
  double? get gotoBearingDeg {
    final target = _gotoTarget;
    final own = _ownPosition;
    if (target == null || own == null) return null;
    return NavMath.bearingDegrees(
      own.latitude,
      own.longitude,
      target.latitude,
      target.longitude,
    );
  }

  /// ETA ke target GoTo: memakai SOG saat ini bila bergerak
  /// (> 0,5 knot), else kecepatan rencana 8 knot.
  Duration? get gotoEta {
    final distance = gotoDistanceM;
    if (distance == null) return null;
    final speed = (sogKnots != null && sogKnots! > 0.5)
        ? sogKnots!
        : AppConstants.defaultSpeedKnots;
    return NavMath.etaDuration(distance, speed);
  }

  /// Total jarak garis ukur (meter).
  double get measureTotalM {
    var total = 0.0;
    for (var i = 0; i + 1 < _measurePoints.length; i++) {
      total += NavMath.distanceMeters(
        _measurePoints[i].latitude,
        _measurePoints[i].longitude,
        _measurePoints[i + 1].latitude,
        _measurePoints[i + 1].longitude,
      );
    }
    return total;
  }

  /// Waypoint dalam satu rute (urut, yang masih ada).
  List<Waypoint> routeWaypoints(RoutePlan route) {
    final byId = {for (final w in _waypoints) w.id: w};
    return route.waypointIds
        .map((id) => byId[id])
        .whereType<Waypoint>()
        .toList();
  }

  // -- Posisi (dipanggil MapViewModel) --

  void updatePosition(Position position) {
    _ownPosition = LatLng(position.latitude, position.longitude);
    _ownSpeedMs = position.speed >= 0 ? position.speed : null;
    _ownCourseDeg =
        (position.heading >= 0 && position.heading <= 360)
            ? position.heading
            : null;
    _positionIsManual = false;
    _maybeRecordTrackPoint(position);
    _checkAnchor();
    notifyListeners();
  }

  /// Posisi manual (dari MapViewModel.setManualPosition): tidak ada
  /// SOG/COG, tapi GoTo + alarm jangkar tetap memakai titik ini.
  void setManualPosition(LatLng point) {
    _ownPosition = point;
    _ownSpeedMs = null;
    _ownCourseDeg = null;
    _positionIsManual = true;
    _checkAnchor();
    notifyListeners();
  }

  // -- Waypoint --

  /// Simpan waypoint baru. Menolak koordinat di luar rentang atau
  /// di luar kawasan ASEAN (laporan B §e-3) dengan pesan jelas dan
  /// mengembalikan null — tidak ada yang tersimpan. Berhasil ->
  /// waypoint yang tersimpan (dipakai pembangun rute untuk langsung
  /// memasukkan titik ketik ke rute).
  Future<Waypoint?> addWaypoint({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final error = _validateWaypointCoords(latitude, longitude);
    if (error != null) {
      _noticeController.show(error);
      return null;
    }
    final waypoint = Waypoint(
      id: 'wp_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Titik ${_waypoints.length + 1}' : name.trim(),
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now(),
    );
    await _repository.saveWaypoint(waypoint);
    _noticeController.show('Titik "${waypoint.name}" tersimpan.');
    return waypoint;
  }

  /// Ubah nama + koordinat waypoint yang sudah ada (dari form ketik).
  /// Validasi sama dengan [addWaypoint]; false bila ditolak / tidak
  /// ditemukan.
  Future<bool> updateWaypoint({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final error = _validateWaypointCoords(latitude, longitude);
    if (error != null) {
      _noticeController.show(error);
      return false;
    }
    Waypoint? existing;
    for (final w in _waypoints) {
      if (w.id == id) {
        existing = w;
        break;
      }
    }
    if (existing == null) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _noticeController.show('Nama titik tidak boleh kosong.');
      return false;
    }
    await _repository.saveWaypoint(existing.copyWith(
      name: trimmed,
      latitude: latitude,
      longitude: longitude,
    ));
    _noticeController.show('Titik "$trimmed" diperbarui.');
    return true;
  }

  /// Validasi koordinat waypoint: rentang global lalu bbox ASEAN.
  /// Null = valid; else pesan Bahasa Indonesia untuk ditampilkan.
  String? _validateWaypointCoords(double latitude, double longitude) {
    if (latitude < -90 || latitude > 90) {
      return 'Lintang harus -90 sampai 90.';
    }
    if (longitude < -180 || longitude > 180) {
      return 'Bujur harus -180 sampai 180.';
    }
    if (!CoordinateInput.isInAsean(latitude, longitude)) {
      return 'Di luar kawasan ASEAN — waypoint hanya bisa dibuat di '
          'dalam ASEAN (lintang -11 sampai 29, bujur 92 sampai 141).';
    }
    return null;
  }

  Future<void> renameWaypoint(String id, String name) async {
    Waypoint? existing;
    for (final w in _waypoints) {
      if (w.id == id) {
        existing = w;
        break;
      }
    }
    if (existing == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _repository.saveWaypoint(existing.copyWith(name: trimmed));
    _noticeController.show('Nama titik diubah menjadi "$trimmed".');
  }

  Future<void> deleteWaypoint(String id) async {
    await _repository.deleteWaypoint(id);
    if (_gotoTarget?.id == id) _gotoTarget = null;
    if (_visibleRoute != null &&
        _visibleRoute!.waypointIds.contains(id)) {
      _visibleRoute = null;
    }
    _noticeController.show('Titik dihapus.');
    notifyListeners();
  }

  // -- Rute --

  Future<void> saveRoute(RoutePlan route) async {
    await _repository.saveRoute(route);
    // Rute langsung tergambar di peta (garis + titik) begitu
    // disimpan — tanpa ketukan "Tampilkan di peta" lagi (ronde 2).
    _visibleRoute = route;
    _visibleTrack = null;
    _noticeController.show('Rute "${route.name}" tersimpan.');
    notifyListeners();
  }

  Future<void> deleteRoute(String id) async {
    await _repository.deleteRoute(id);
    if (_visibleRoute?.id == id) _visibleRoute = null;
    _noticeController.show('Rute dihapus.');
    notifyListeners();
  }

  void showRouteOnMap(RoutePlan? route) {
    _visibleRoute = route;
    if (route != null) _visibleTrack = null;
    notifyListeners();
  }

  // -- GoTo --

  void setGoto(Waypoint? target) {
    _gotoTarget = target;
    if (target != null) {
      _noticeController.show('Navigasi ke "${target.name}".');
    }
    notifyListeners();
  }

  void cancelGoto() {
    _gotoTarget = null;
    notifyListeners();
  }

  // -- Pengukur jarak --

  void setMeasureMode(bool enabled) {
    _measureMode = enabled;
    if (!enabled) _measurePoints = [];
    notifyListeners();
  }

  void addMeasurePoint(LatLng point) {
    _measurePoints = [..._measurePoints, point];
    notifyListeners();
  }

  void undoMeasurePoint() {
    if (_measurePoints.isEmpty) return;
    _measurePoints = _measurePoints.sublist(0, _measurePoints.length - 1);
    notifyListeners();
  }

  void clearMeasurePoints() {
    _measurePoints = [];
    notifyListeners();
  }

  // -- Rekam jejak --

  Future<void> startRecording() async {
    if (_activeTrack != null) return;
    if (_ownPosition == null) {
      _noticeController.show(
        'Posisi belum tersedia — nyalakan GPS dulu sebelum merekam.',
      );
      return;
    }
    if (_positionIsManual) {
      // Posisi manual tidak bergerak mengikuti kapal — jejak yang
      // direkam akan diam di satu titik. Tolak dengan jelas.
      _noticeController.show(
        'Perekaman butuh GPS aktif — posisi manual tidak bisa direkam. '
        'Tekan tombol Posisi saya untuk menyalakan GPS.',
      );
      return;
    }
    final track = Track(
      id: 'tr_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Jejak ${_tracks.length + 1}',
      startedAt: DateTime.now(),
    );
    await _repository.saveTrack(track);
    _activeTrack = track;
    _activePoints = [];
    _lastRecordedPoint = null;
    // Titik pertama langsung dicatat.
    final first = TrackPoint(
      latitude: _ownPosition!.latitude,
      longitude: _ownPosition!.longitude,
      recordedAt: DateTime.now(),
      speedKnots: sogKnots,
    );
    await _repository.addTrackPoint(track.id, first);
    _activePoints = [first];
    _lastRecordedPoint = first;
    _noticeController.show('Merekam jejak dimulai.');
    notifyListeners();
  }

  Future<void> stopRecording() async {
    final track = _activeTrack;
    if (track == null) return;
    final finished = Track(
      id: track.id,
      name: track.name,
      startedAt: track.startedAt,
      endedAt: DateTime.now(),
      points: _activePoints,
    );
    await _repository.saveTrack(finished);
    _activeTrack = null;
    _activePoints = [];
    _lastRecordedPoint = null;
    final distanceNm =
        NavMath.metersToNm(TrackStats.totalDistanceM(finished.points));
    _noticeController.show(
      'Jejak tersimpan (${distanceNm.toStringAsFixed(1)} mil laut).',
    );
    notifyListeners();
  }

  void _maybeRecordTrackPoint(Position position) {
    final track = _activeTrack;
    if (track == null) return;
    final now = DateTime.now();
    final last = _lastRecordedPoint;
    if (last != null) {
      final dt = now.difference(last.recordedAt);
      final moved = NavMath.distanceMeters(
        last.latitude,
        last.longitude,
        position.latitude,
        position.longitude,
      );
      if (dt < _recordMinInterval || moved < _recordMinDistanceM) return;
    }
    final point = TrackPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      recordedAt: now,
      speedKnots: sogKnots,
    );
    _lastRecordedPoint = point;
    _activePoints = [..._activePoints, point];
    // Tulis ke DB tanpa await (tidak boleh menghambat update posisi).
    unawaited(_repository.addTrackPoint(track.id, point));
  }

  Future<void> _closeOrphanTracks(List<Track> tracks) async {
    for (final track in tracks) {
      if (track.endedAt == null) {
        await _repository.saveTrack(Track(
          id: track.id,
          name: track.name,
          startedAt: track.startedAt,
          endedAt: DateTime.now(),
        ));
      }
    }
  }

  Future<Track?> loadTrack(String id) =>
      _repository.getTrackWithPoints(id);

  Future<void> deleteTrack(String id) async {
    await _repository.deleteTrack(id);
    if (_visibleTrack?.id == id) _visibleTrack = null;
    _noticeController.show('Jejak dihapus.');
    notifyListeners();
  }

  void showTrackOnMap(Track? track) {
    _visibleTrack = track;
    if (track != null) _visibleRoute = null;
    notifyListeners();
  }

  // -- Alarm jangkar --

  Future<void> setAnchor({
    required double latitude,
    required double longitude,
    required double radiusM,
  }) async {
    _anchor = AnchorSettings(
      latitude: latitude,
      longitude: longitude,
      radiusM: radiusM,
      armed: true,
      setAt: DateTime.now(),
    );
    _anchorAlarm = false;
    _anchorSilenced = false;
    _anchorDistanceM = 0;
    await _safetyRepository.saveAnchor(_anchor!);
    unawaited(_notifications.requestPermission());
    _noticeController.show(
      'Alarm jangkar aktif (radius ${radiusM.toStringAsFixed(0)} m).',
    );
    notifyListeners();
  }

  Future<void> disarmAnchor() async {
    if (_anchor == null) return;
    _anchor = _anchor!.copyWith(armed: false);
    _anchorAlarm = false;
    _anchorSilenced = false;
    _anchorDistanceM = null;
    await _safetyRepository.saveAnchor(_anchor!);
    _noticeController.show('Alarm jangkar dimatikan.');
    notifyListeners();
  }

  Future<void> clearAnchor() async {
    _anchor = null;
    _anchorAlarm = false;
    _anchorSilenced = false;
    _anchorDistanceM = null;
    await _safetyRepository.clearAnchor();
    notifyListeners();
  }

  void _checkAnchor() {
    final anchor = _anchor;
    final own = _ownPosition;
    if (anchor == null || !anchor.armed || own == null) return;
    final distance = AnchorWatch.distanceFromAnchorM(
      anchorLat: anchor.latitude,
      anchorLon: anchor.longitude,
      latitude: own.latitude,
      longitude: own.longitude,
    );
    _anchorDistanceM = distance;
    final outside = distance > anchor.radiusM;
    if (outside && !_anchorAlarm && !_anchorSilenced) {
      _anchorAlarm = true;
      _noticeController.show(
        'Alarm jangkar! Kapal ${distance.toStringAsFixed(0)} m dari titik jangkar.',
      );
      unawaited(_notifications.showAnchorAlarm(
        body: 'Kapal ${distance.toStringAsFixed(0)} m dari titik jangkar '
            '(radius ${anchor.radiusM.toStringAsFixed(0)} m).',
      ));
    } else if (!outside && (_anchorAlarm || _anchorSilenced)) {
      // Kembali ke dalam radius: alarm berhenti DAN bisu dibersihkan,
      // sehingga alarm bisa berbunyi lagi bila keluar (F-L3).
      _anchorAlarm = false;
      _anchorSilenced = false;
      _noticeController.show('Kapal kembali ke dalam radius jangkar.');
    }
  }

  /// Diamkan bunyi alarm (tetap bersenjata): diam selama kapal di
  /// luar radius; bunyi lagi bila kapal kembali ke dalam radius lalu
  /// keluar lagi (F-L3).
  void silenceAnchorAlarm() {
    _anchorAlarm = false;
    _anchorSilenced = true;
    notifyListeners();
  }

  // -- MOB --

  Future<void> addMobMark(LatLng point) async {
    final mark = MobMark(
      id: 'mob_${DateTime.now().microsecondsSinceEpoch}',
      latitude: point.latitude,
      longitude: point.longitude,
      recordedAt: DateTime.now(),
    );
    await _safetyRepository.addMobMark(mark);
    _mobMarks = _safetyRepository.mobMarks;
    _noticeController.show('Tanda MOB dicatat di peta.');
    notifyListeners();
  }

  Future<void> deleteMobMark(String id) async {
    await _safetyRepository.deleteMobMark(id);
    _mobMarks = _safetyRepository.mobMarks;
    notifyListeners();
  }

  @override
  void dispose() {
    _waypointsSub?.cancel();
    _routesSub?.cancel();
    _tracksSub?.cancel();
    super.dispose();
  }
}
