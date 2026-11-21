import 'dart:async';
import 'dart:typed_data';

import '../../domain/models/vessel.dart';
import '../../utils/result.dart';
import 'nmea_ais_parser.dart';
import 'ship_ais_service.dart';

/// Perangkat Bluetooth yang dikenal (hasil pindai / sudah dipasangkan).
class ShipAisBluetoothDevice {
  const ShipAisBluetoothDevice({required this.address, this.name});

  /// Alamat MAC Bluetooth (mis. `00:1A:2B:3C:4D:5E`).
  final String address;
  final String? name;

  String get displayName {
    final n = name?.trim();
    if (n == null || n.isEmpty) return address;
    return '$n ($address)';
  }

  @override
  bool operator ==(Object other) =>
      other is ShipAisBluetoothDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// Transport Bluetooth SPP abstrak — jembatan ke plugin Bluetooth.
///
/// Dipisah agar [ShipAisBluetoothService] bisa compile dan diuji
/// TANPA package Bluetooth apa pun. Implementasi konkret ada di
/// `bluetooth_spp_transport.dart` (memakai package
/// `flutter_bluetooth_serial_plus` — file itu TERGATE: butuh entri
/// pubspec + izin AndroidManifest dari koordinator, lihat
/// SHIP-AIS-HARDWARE.md §Bluetooth).
abstract class ShipAisBluetoothTransport {
  /// Stream byte mentah dari perangkat yang tersambung.
  Stream<Uint8List> get input;

  bool get isConnected;

  /// Sambung ke perangkat (alamat MAC). Melempar bila izin
  /// ditolak atau perangkat tidak merespons.
  Future<void> connect(String address);

  /// Putuskan sambungan (bila ada).
  Future<void> disconnect();

  /// Perangkat yang sudah dipasangkan (bonded) di HP.
  Future<List<ShipAisBluetoothDevice>> bondedDevices();

  /// Pindai perangkat Bluetooth Classic di sekitar.
  /// Stream selesai sendiri bila pindai berakhir.
  Stream<ShipAisBluetoothDevice> startDiscovery();

  /// Hentikan pindai yang sedang berjalan.
  Future<void> cancelDiscovery();
}

/// Klien AIS kapal lewat Bluetooth Serial (SPP) — jalur cadangan
/// jarak pendek (±10 m) untuk multiplexer/bridge Bluetooth
/// (mis. bridge HC-05 ke output NMEA 0183 unit AIS, atau
/// dAISy 2+ + modul HC-05).
///
/// API ini mencerminkan [ShipAisService] (WiFi): stream hasil,
/// stream own-ship AIVDO, statistik, dan auto-reconnect yang
/// DEFAULT MATI. Bedanya: sambungan ditujukan ke alamat MAC
/// perangkat, bukan host:port.
///
/// Service ini dibuat HANYA bila transport tersedia — panel
/// menyembunyikan seksi Bluetooth bila service-nya null (tanpa
/// tombol mati).
class ShipAisBluetoothService {
  ShipAisBluetoothService({
    required ShipAisBluetoothTransport transport,
    NmeaAisParser? parser,
  })  : _transport = transport,
        _parser = parser ?? NmeaAisParser();

  final ShipAisBluetoothTransport _transport;
  final NmeaAisParser _parser;

  ShipAisConnectionState _state = ShipAisConnectionState.disconnected;
  ShipAisStats _stats = const ShipAisStats();
  final Set<int> _vesselsSeen = {};

  String? _connectedAddress;
  bool _autoReconnect = false;
  StreamSubscription<Uint8List>? _inputSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _manualDisconnect = false;
  String _lineBuffer = '';
  bool _disposed = false;

  final _stateController =
      StreamController<ShipAisConnectionState>.broadcast();
  final _resultsController = StreamController<ShipAisParseResult>.broadcast();
  final _ownShipController = StreamController<Vessel>.broadcast();
  final _statsController = StreamController<ShipAisStats>.broadcast();

  ShipAisConnectionState get connectionState => _state;
  ShipAisStats get stats => _stats;
  bool get isConnected => _state == ShipAisConnectionState.connected;
  String? get connectedAddress => _connectedAddress;
  bool get autoReconnect => _autoReconnect;

  Stream<ShipAisConnectionState> get connectionStateStream =>
      _stateController.stream;
  Stream<ShipAisParseResult> get resultsStream => _resultsController.stream;
  Stream<Vessel> get ownShipStream => _ownShipController.stream;
  Stream<ShipAisStats> get statsStream => _statsController.stream;

  /// Aktif/nonaktifkan sambung ulang otomatis (default mati).
  void setAutoReconnect(bool value) => _autoReconnect = value;

  Future<List<ShipAisBluetoothDevice>> bondedDevices() =>
      _transport.bondedDevices();

  Stream<ShipAisBluetoothDevice> startDiscovery() =>
      _transport.startDiscovery();

  Future<void> cancelDiscovery() => _transport.cancelDiscovery();

  /// Sambung ke perangkat Bluetooth (alamat MAC).
  Future<Result<void>> connect(String address) async {
    await disconnect(silent: true);
    _manualDisconnect = false;
    _reconnectAttempt = 0;
    _setState(ShipAisConnectionState.connecting);
    try {
      await _transport.connect(address);
      _connectedAddress = address;
      _inputSubscription = _transport.input.listen(
        _handleBytes,
        onError: _onTransportError,
        onDone: _onTransportDone,
        cancelOnError: true,
      );
      _setState(ShipAisConnectionState.connected);
      _updateStats(_stats.copyWith(clearError: true));
      return const Result.ok(null);
    } on Exception catch (e) {
      return _fail(e);
    }
  }

  /// Putuskan sambungan Bluetooth. Membatalkan timer reconnect.
  Future<void> disconnect({bool silent = false}) async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    await _transport.disconnect();
    _connectedAddress = null;
    _lineBuffer = '';
    if (!silent) _setState(ShipAisConnectionState.disconnected);
  }

  void _handleBytes(Uint8List bytes) {
    // NMEA 0183 adalah ASCII — latin1 tidak pernah gagal decode.
    _lineBuffer += String.fromCharCodes(bytes);
    if (_lineBuffer.length > 8192) {
      _lineBuffer = '';
      return;
    }
    final lines = _lineBuffer.split('\n');
    _lineBuffer = lines.removeLast();
    for (final line in lines) {
      _handleLine(line);
    }
  }

  void _handleLine(String line) {
    _stats = _stats.copyWith(
      sentencesReceived: _stats.sentencesReceived + 1,
    );
    final result = _parser.feed(line);
    if (result == null) return;
    _vesselsSeen.add(result.mmsi);
    _stats = _stats.copyWith(
      messagesDecoded: _stats.messagesDecoded + 1,
      vesselsSeen: _vesselsSeen.length,
      lastMessageAt: DateTime.now(),
    );
    _resultsController.add(result);
    if (result.isOwnShip) _ownShipController.add(result.updated);
    _statsController.add(_stats);
  }

  void _onTransportError(Object error) {
    if (_manualDisconnect || _disposed) return;
    _updateStats(_stats.copyWith(lastError: _shortError(error)));
    _scheduleReconnect();
  }

  void _onTransportDone() {
    if (_manualDisconnect || _disposed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _inputSubscription?.cancel();
    _inputSubscription = null;
    final address = _connectedAddress;
    _connectedAddress = null;
    if (!_autoReconnect || _manualDisconnect || _disposed) {
      _setState(ShipAisConnectionState.error);
      return;
    }
    if (address == null) {
      _setState(ShipAisConnectionState.error);
      return;
    }
    _setState(ShipAisConnectionState.reconnecting);
    const backoff = [5, 10, 20, 40, 60];
    final delay = backoff[_reconnectAttempt < backoff.length
        ? _reconnectAttempt
        : backoff.length - 1];
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      if (_manualDisconnect || _disposed) return;
      await connect(address);
    });
  }

  Result<void> _fail(Exception error) {
    _updateStats(_stats.copyWith(lastError: _shortError(error)));
    _setState(ShipAisConnectionState.error);
    return Result.error(error);
  }

  void _setState(ShipAisConnectionState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  void _updateStats(ShipAisStats stats) {
    _stats = stats;
    if (!_statsController.isClosed) _statsController.add(stats);
  }

  static String _shortError(Object error) {
    final text = error.toString();
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _inputSubscription?.cancel();
    _transport.disconnect();
    _stateController.close();
    _resultsController.close();
    _ownShipController.close();
    _statsController.close();
  }
}
