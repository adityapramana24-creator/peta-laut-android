import 'dart:async';

import '../../config/app_constants.dart';
import '../../domain/models/vessel.dart';
import '../../utils/result.dart';
import '../services/ais_service.dart';
import '../services/nmea_ais_parser.dart';
import '../services/secure_key_service.dart';
import '../services/ship_ais_bluetooth_service.dart';
import '../services/ship_ais_service.dart';

/// Statistik jalur AIS untuk diagnosis di panel: berapa frame masuk,
/// berapa ter-decode, berapa pesan jadi kapal, kapan terakhir.
/// Tanpa ini, "kapal tidak muncul" tidak bisa dibedakan antara
/// "tidak ada kapal di area" vs "stream mati" (pelajaran bug frame
/// biner v1.1 — stream "terhubung" tapi nol pesan ter-parse).
class AisDiagnostics {
  const AisDiagnostics({
    required this.framesReceived,
    required this.framesDecoded,
    required this.framesDropped,
    required this.messagesParsed,
    required this.messagesDropped,
    required this.lastMessageAt,
    required this.lastError,
  });

  final int framesReceived;
  final int framesDecoded;
  final int framesDropped;
  final int messagesParsed;
  final int messagesDropped;
  final DateTime? lastMessageAt;
  final String? lastError;

  /// true bila data kapal pernah mengalir pada sesi ini.
  bool get hasFlowed => messagesParsed > 0;
}

/// Kapal AIS: peta MMSI -> Vessel, merge PositionReport + ShipStaticData,
/// sapu kedaluwarsa 15 menit tiap 60 detik, stream broadcast untuk UI.
/// Kunci dikelola SecureKeyService (tidak pernah di-log/ditampilkan).
/// RONDE 2: dua sumber merge ke peta yang sama — AISStream internet
/// (AisService) + AIS kapal offline (ShipAisService WiFi / Bluetooth).
/// AIVDO (kapal sendiri) TIDAK masuk peta kapal — dipisah ke stream
/// own-ship agar tidak jadi target CPA terhadap dirinya sendiri.
class AisRepository {
  AisRepository({
    AisService? service,
    SecureKeyService? keyService,
    ShipAisService? shipAisService,
    ShipAisBluetoothService? shipAisBluetoothService,
  })  : _service = service ?? AisService(),
        _keyService = keyService ?? SecureKeyService() {
    _service.messages.listen(_onMessage);
    _service.connectionState.listen((state) {
      _state = state;
      _stateController.add(state);
    });
    // Sumber kapal (Offline): hasil decode NMEA merge ke peta yang sama;
    // own-ship AIVDO dipisah (lihat _onShipMessage / _onOwnShip).
    shipAisService?.resultsStream.listen(_onShipMessage);
    shipAisService?.ownShipStream.listen(_onOwnShip);
    shipAisBluetoothService?.resultsStream.listen(_onShipMessage);
    shipAisBluetoothService?.ownShipStream.listen(_onOwnShip);
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
  // Kapal sendiri dari AIVDO (sumber terbaik untuk CPA — posisi/SOG/COG
  // dari transponder kapal sendiri, lebih baik dari GPS HP).
  Vessel? _ownShip;
  final _ownShipController = StreamController<Vessel>.broadcast();
  Timer? _expiryTimer;
  AisConnectionState _state = AisConnectionState.notConfigured;
  int _messagesParsed = 0;
  int _messagesDropped = 0;
  DateTime? _lastMessageAt;

  Stream<Map<int, Vessel>> get vesselsStream => _vesselsController.stream;
  Stream<AisConnectionState> get connectionState => _stateController.stream;

  /// Kapal sendiri dari AIVDO (null bila sumber kapal belum memberi
  /// posisi own-ship). Dipakai CPA sebagai prioritas di atas GPS.
  Stream<Vessel> get ownShipStream => _ownShipController.stream;
  Vessel? get ownShip => _ownShip;

  AisConnectionState get state => _state;
  Map<int, Vessel> get vessels => Map.unmodifiable(_vessels);
  int get vesselCount => _vessels.length;

  /// Pesan error terakhir dari service (null bila tidak ada).
  String? get lastError => _service.lastError;

  /// true bila server sudah mengonfirmasi langganan aktif.
  bool get subscriptionConfirmed => _service.subscriptionConfirmed;

  AisDiagnostics get diagnostics => AisDiagnostics(
        framesReceived: _service.framesReceived,
        framesDecoded: _service.framesDecoded,
        framesDropped: _service.framesDropped,
        messagesParsed: _messagesParsed,
        messagesDropped: _messagesDropped,
        lastMessageAt: _lastMessageAt,
        lastError: _service.lastError,
      );

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

  /// Putuskan stream secara manual (tombol "Putuskan"). Kunci tetap
  /// tersimpan; daftar kapal dikosongkan karena tidak lagi live.
  /// Sambung lagi lewat connectIfConfigured.
  Future<void> disconnect() async {
    await _service.disconnect();
    _vessels.clear();
    _vesselsController.add(Map.unmodifiable(_vessels));
    _state = AisConnectionState.disconnected;
    _stateController.add(_state);
  }

  void _onMessage(Map<String, dynamic> envelope) {
    final mmsiRaw = (envelope['MetaData'] as Map?)?['MMSI'];
    final mmsi = mmsiRaw is int
        ? mmsiRaw
        : int.tryParse('$mmsiRaw');
    final existing = mmsi == null ? null : _vessels[mmsi];
    final parsed = AisMessageParser.parse(envelope, existing: existing);
    if (parsed == null) {
      _messagesDropped++;
      return;
    }
    _messagesParsed++;
    _lastMessageAt = DateTime.now();
    _vessels[parsed.mmsi] = parsed.updated;
    _vesselsController.add(Map.unmodifiable(_vessels));
  }

  /// Hasil decode NMEA dari AIS kapal (WiFi/Bluetooth) — merge ke peta
  /// yang sama dengan AISStream (last-writer-wins per field; data kapal
  /// lokal segar tiap 2–10 detik). `updated` adalah kapal PARSIAL (hanya
  /// field dari pesan ini) — copyWith mempertahankan nilai lama bila
  /// argumen null, jadi field kosong tidak menimpa data yang ada.
  /// AIVDO (kapal sendiri) TIDAK masuk peta kapal — dipisah ke
  /// stream own-ship (service juga mengirimnya ke resultsStream).
  void _onShipMessage(ShipAisParseResult result) {
    if (result.isOwnShip) {
      _onOwnShip(result.updated);
      return;
    }
    final partial = result.updated;
    final existing = _vessels[result.mmsi];
    final merged = existing?.copyWith(
          name: partial.name,
          latitude: partial.latitude,
          longitude: partial.longitude,
          speedKnots: partial.speedKnots,
          courseDeg: partial.courseDeg,
          headingDeg: partial.headingDeg,
          destination: partial.destination,
          eta: partial.eta,
          lastSeen: partial.lastSeen,
          shipType: partial.shipType,
          navStatus: partial.navStatus,
          rateOfTurn: partial.rateOfTurn,
          lengthM: partial.lengthM,
          beamM: partial.beamM,
          callsign: partial.callsign,
          imoNumber: partial.imoNumber,
        ) ??
        partial;
    _messagesParsed++;
    _lastMessageAt = DateTime.now();
    _vessels[result.mmsi] = merged;
    _vesselsController.add(Map.unmodifiable(_vessels));
  }

  /// Posisi kapal sendiri dari AIVDO — disimpan + disiarkan untuk CPA.
  void _onOwnShip(Vessel vessel) {
    _ownShip = vessel;
    _ownShipController.add(vessel);
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
    await _ownShipController.close();
  }
}
