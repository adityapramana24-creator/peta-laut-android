import 'dart:async';

import '../../config/app_constants.dart';
import '../../domain/models/vessel.dart';
import '../../utils/result.dart';
import '../services/ais_service.dart';
import '../services/secure_key_service.dart';

/// Kapal AIS: peta MMSI -> Vessel, merge PositionReport + ShipStaticData,
/// sapu kedaluwarsa 15 menit tiap 60 detik, stream broadcast untuk UI.
/// Kunci dikelola SecureKeyService (tidak pernah di-log/ditampilkan).
class AisRepository {
  AisRepository({
    AisService? service,
    SecureKeyService? keyService,
  })  : _service = service ?? AisService(),
        _keyService = keyService ?? SecureKeyService() {
    _service.messages.listen(_onMessage);
    _service.connectionState.listen((state) {
      _state = state;
      _stateController.add(state);
    });
    _expiryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _sweepExpired();
    });
  }

  final AisService _service;
  final SecureKeyService _keyService;

  final Map<int, Vessel> _vessels = {};
  final _vesselsController =
      StreamController<Map<int, Vessel>>.broadcast();
  final _stateController =
      StreamController<AisConnectionState>.broadcast();
  Timer? _expiryTimer;
  AisConnectionState _state = AisConnectionState.notConfigured;

  Stream<Map<int, Vessel>> get vesselsStream => _vesselsController.stream;
  Stream<AisConnectionState> get connectionState => _stateController.stream;
  AisConnectionState get state => _state;
  Map<int, Vessel> get vessels => Map.unmodifiable(_vessels);
  int get vesselCount => _vessels.length;

  Future<bool> hasKey() => _keyService.hasAisKey();

  Future<void> saveKey(String key) async {
    await _keyService.saveAisKey(key);
  }

  Future<void> deleteKey() async {
    await _service.disconnect();
    await _keyService.deleteAisKey();
    _vessels.clear();
    _vesselsController.add(Map.unmodifiable(_vessels));
    _state = AisConnectionState.notConfigured;
    _stateController.add(_state);
  }

  /// Uji kunci dengan koneksi singkat (20 dtk).
  Future<Result<bool>> testConnection(String key) =>
      _service.testConnection(key);

  /// Sambung bila kunci sudah tersimpan (dipanggil saat app mulai
  /// dan setelah kunci disimpan).
  Future<void> connectIfConfigured({
    required (double, double, double, double) bounds,
  }) async {
    final key = await _keyService.readAisKey();
    if (key == null || key.trim().isEmpty) {
      _state = AisConnectionState.notConfigured;
      _stateController.add(_state);
      return;
    }
    await _service.connect(key, bounds: bounds);
  }

  void updateBounds((double, double, double, double) bounds) {
    _service.updateBounds(bounds);
  }

  Future<void> disconnect() => _service.disconnect();

  void _onMessage(Map<String, dynamic> envelope) {
    final mmsiRaw = (envelope['MetaData'] as Map?)?['MMSI'];
    final mmsi = mmsiRaw is int
        ? mmsiRaw
        : int.tryParse('$mmsiRaw');
    final existing = mmsi == null ? null : _vessels[mmsi];
    final parsed = AisMessageParser.parse(envelope, existing: existing);
    if (parsed == null) return;
    _vessels[parsed.mmsi] = parsed.updated;
    _vesselsController.add(Map.unmodifiable(_vessels));
  }

  void _sweepExpired() {
    final now = DateTime.now();
    var removed = false;
    _vessels.removeWhere((_, vessel) {
      final lastSeen = vessel.lastSeen;
      if (lastSeen == null) return false;
      final expired =
          now.difference(lastSeen) > AppConstants.vesselExpiry;
      if (expired) removed = true;
      return expired;
    });
    if (removed) {
      _vesselsController.add(Map.unmodifiable(_vessels));
    }
  }

  Future<void> dispose() async {
    _expiryTimer?.cancel();
    await _service.dispose();
    await _vesselsController.close();
    await _stateController.close();
  }
}
