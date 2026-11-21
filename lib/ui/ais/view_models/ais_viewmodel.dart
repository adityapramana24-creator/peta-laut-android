import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/repositories/ais_repository.dart';
import '../../../data/services/ais_alert_settings.dart';
import '../../../domain/models/ais_target_status.dart';
import '../../../domain/models/vessel.dart';
import '../../../utils/command.dart';
import '../../../utils/nav_math.dart';
import '../../../utils/result.dart';

/// Satu kapal + jaraknya dari titik acuan (meter).
/// distanceMeters null bila kapal tanpa posisi (diurutkan paling akhir).
class NearbyVessel {
  const NearbyVessel({required this.vessel, required this.distanceMeters});

  final Vessel vessel;
  final double? distanceMeters;
}

/// Urutkan kapal dari yang terdekat dengan titik acuan (haversine).
/// Kapal tanpa posisi di akhir, urut nama. Fungsi murni — ditutup
/// unit test (test/ais_nearby_test.dart).
List<NearbyVessel> sortVesselsByDistance(
  Iterable<Vessel> vessels,
  double refLat,
  double refLon,
) {
  final withPos = <NearbyVessel>[];
  final withoutPos = <Vessel>[];
  for (final vessel in vessels) {
    if (vessel.hasPosition) {
      withPos.add(NearbyVessel(
        vessel: vessel,
        distanceMeters: NavMath.distanceMeters(
          refLat,
          refLon,
          vessel.latitude!,
          vessel.longitude!,
        ),
      ));
    } else {
      withoutPos.add(vessel);
    }
  }
  withPos.sort(
    (a, b) => a.distanceMeters!.compareTo(b.distanceMeters!),
  );
  withoutPos.sort((a, b) => a.displayName.compareTo(b.displayName));
  return [
    ...withPos,
    ...withoutPos.map(
      (v) => NearbyVessel(vessel: v, distanceMeters: null),
    ),
  ];
}

/// ViewModel panel AIS + seksi AIS di Pengaturan (R-18, R-19).
/// Kunci TIDAK PERNAH disimpan di VM ini selain saat diteruskan ke
/// repository (disimpan di secure storage, tidak di-log/ditampilkan).
class AisViewModel extends ChangeNotifier {
  AisViewModel({
    required AisRepository repository,
    AisAlertSettings? alertSettings,
  })  : _repository = repository,
        _alertSettings = alertSettings ?? AisAlertSettings() {
    saveKeyCommand = Command1(_saveKey);
    testCommand = Command1(_testKey);
    saveKeyCommand.addListener(_onSaveChanged);
    testCommand.addListener(_onTestChanged);
    _vessels = _repository.vessels;
    _state = _repository.state;
    _ownShip = _repository.ownShip;
    _repository.vesselsStream.listen((vessels) {
      _vessels = vessels;
      notifyListeners();
    });
    _repository.ownShipStream.listen((vessel) {
      _ownShip = vessel;
      notifyListeners();
    });
    _repository.connectionState.listen((state) {
      _state = state;
      if (state == AisConnectionState.error) {
        _statusMessage =
            _repository.lastError ?? 'Koneksi AIS gagal.';
        _statusIsError = true;
      }
      notifyListeners();
    });
  }

  final AisRepository _repository;
  final AisAlertSettings _alertSettings;

  /// saveKeyCommand membawa (kunci, bbox) — bbox dari MapViewModel.
  late final Command1<bool, (String, (double, double, double, double))>
      saveKeyCommand;
  late final Command1<bool, String> testCommand;

  bool _hasKey = false;
  bool _keyChecked = false;
  Map<int, Vessel> _vessels = {};
  AisConnectionState _state = AisConnectionState.notConfigured;
  // Kapal sendiri dari AIVDO (sumber kapal Offline) — null bila belum ada.
  Vessel? _ownShip;
  String? _statusMessage;
  bool _statusIsError = false;
  double _cpaThresholdNm =
      AisTargetStatusResolver.defaultCpaThresholdNm;
  double _tcpaThresholdMin =
      AisTargetStatusResolver.defaultTcpaThresholdMin;

  bool get hasKey => _hasKey;
  bool get keyChecked => _keyChecked;
  Map<int, Vessel> get vessels => _vessels;
  AisConnectionState get state => _state;

  /// Kapal sendiri dari AIVDO (AIS kapal Offline) — sumber terbaik
  /// untuk CPA (posisi/SOG/COG dari transponder kapal sendiri).
  Vessel? get ownShip => _ownShip;

  String? get statusMessage => _statusMessage;
  bool get statusIsError => _statusIsError;

  /// Ambang target berbahaya (diubah dari Pengaturan).
  double get cpaThresholdNm => _cpaThresholdNm;
  double get tcpaThresholdMin => _tcpaThresholdMin;

  /// Statistik jalur data untuk diagnosis di panel.
  AisDiagnostics get diagnostics => _repository.diagnostics;

  /// Pesan error terakhir dari service (null bila tidak ada).
  String? get lastError => _repository.lastError;

  /// Daftar kapal terurut nama (yang berposisi dulu).
  List<Vessel> get vesselList {
    final list = _vessels.values.toList();
    list.sort((a, b) {
      if (a.hasPosition != b.hasPosition) {
        return a.hasPosition ? -1 : 1;
      }
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  /// Daftar kapal terurut dari yang terdekat dengan titik acuan
  /// (posisi GPS user, atau tengah peta bila GPS tidak ada).
  List<NearbyVessel> nearbyList(LatLng reference) =>
      sortVesselsByDistance(
        _vessels.values,
        reference.latitude,
        reference.longitude,
      );

  Future<void> init() async {
    _hasKey = await _repository.hasKey();
    final (cpa, tcpa) = await _alertSettings.load();
    _cpaThresholdNm = cpa;
    _tcpaThresholdMin = tcpa;
    _keyChecked = true;
    notifyListeners();
  }

  Future<void> setCpaThreshold(double value) async {
    _cpaThresholdNm = value;
    await _alertSettings.saveCpaThresholdNm(value);
    notifyListeners();
  }

  Future<void> setTcpaThreshold(double value) async {
    _tcpaThresholdMin = value;
    await _alertSettings.saveTcpaThresholdMin(value);
    notifyListeners();
  }

  /// Coba sambung ulang setelah error (tombol "Coba lagi" di panel).
  Future<void> retryConnection(
    (double, double, double, double) bounds,
  ) async {
    _statusMessage = 'Mencoba menyambung ulang…';
    _statusIsError = false;
    notifyListeners();
    await _repository.connectIfConfigured(bounds: bounds);
  }

  /// Putuskan stream AISStream secara manual (tombol "Putuskan").
  /// Kunci tetap tersimpan; sambung lagi lewat retryConnection.
  Future<void> disconnect() async {
    await _repository.disconnect();
    _statusMessage = 'Koneksi AISStream diputuskan.';
    _statusIsError = false;
    notifyListeners();
  }

  Future<Result<bool>> _saveKey(
    (String, (double, double, double, double)) args,
  ) async {
    final (key, bounds) = args;
    if (key.trim().isEmpty) {
      return Result.error(Exception('Kunci masih kosong.'));
    }
    try {
      await _repository.saveKey(key);
      _hasKey = true;
      await _repository.connectIfConfigured(bounds: bounds);
      return const Result.ok(true);
    } catch (e) {
      return Result.error(Exception('Gagal menyimpan kunci: $e'));
    }
  }

  Future<Result<bool>> _testKey(String key) {
    if (key.trim().isEmpty) {
      return Future.value(
        Result.error(Exception('Kunci masih kosong.')),
      );
    }
    return _repository.testConnection(key.trim());
  }

  void _onSaveChanged() {
    final result = saveKeyCommand.result;
    if (result is Ok<bool>) {
      _statusMessage = 'Kunci tersimpan. Menghubungkan ke AISStream…';
      _statusIsError = false;
    } else if (result is Error<bool>) {
      _statusMessage =
          result.error.toString().replaceFirst('Exception: ', '');
      _statusIsError = true;
    }
    notifyListeners();
  }

  void _onTestChanged() {
    final result = testCommand.result;
    if (result is Ok<bool>) {
      _statusMessage = 'Kunci valid — sambungan AISStream berhasil.';
      _statusIsError = false;
    } else if (result is Error<bool>) {
      _statusMessage =
          result.error.toString().replaceFirst('Exception: ', '');
      _statusIsError = true;
    }
    notifyListeners();
  }

  void clearStatus() {
    _statusMessage = null;
    notifyListeners();
  }

  Future<void> deleteKey() async {
    await _repository.deleteKey();
    _hasKey = false;
    _statusMessage = 'Kunci AIS dihapus.';
    _statusIsError = false;
    notifyListeners();
  }

  @override
  void dispose() {
    saveKeyCommand.removeListener(_onSaveChanged);
    testCommand.removeListener(_onTestChanged);
    saveKeyCommand.dispose();
    testCommand.dispose();
    super.dispose();
  }
}
