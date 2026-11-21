import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/vessel.dart';
import '../../utils/result.dart';
import 'nmea_ais_parser.dart';

/// Protokol transport NMEA 0183 lewat WiFi.
enum ShipAisProtocol {
  tcp,
  udp,
}

extension ShipAisProtocolLabel on ShipAisProtocol {
  String get label => switch (this) {
        ShipAisProtocol.tcp => 'TCP',
        ShipAisProtocol.udp => 'UDP',
      };

  static ShipAisProtocol fromName(String? name) =>
      name == 'udp' ? ShipAisProtocol.udp : ShipAisProtocol.tcp;
}

/// Status koneksi AIS kapal (sumber Offline).
enum ShipAisConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

extension ShipAisConnectionStateLabel on ShipAisConnectionState {
  String get label => switch (this) {
        ShipAisConnectionState.disconnected => 'Terputus',
        ShipAisConnectionState.connecting => 'Menghubungkan…',
        ShipAisConnectionState.connected => 'Terhubung',
        ShipAisConnectionState.reconnecting => 'Menyambung ulang…',
        ShipAisConnectionState.error => 'Koneksi gagal',
      };
}

/// Konfigurasi sambungan AIS kapal via WiFi.
///
/// Default = mode Ad-hoc receiver Quark-Elec QK-A027 (lihat
/// SHIP-AIS-HARDWARE.md): SSID `A027xxxx`, IP 192.168.1.100,
/// TCP port 2000. Preset lain (mis. port standar NMEA 10110)
/// tersedia di panel.
class ShipAisConfig {
  const ShipAisConfig({
    this.host = ShipAisConfig.defaultHost,
    this.port = ShipAisConfig.defaultPort,
    this.protocol = ShipAisProtocol.tcp,
    this.autoReconnect = false,
  });

  static const String defaultHost = '192.168.1.100';
  static const int defaultPort = 2000;

  /// Preset port standar IANA/IETF untuk NMEA 0183.
  static const int standardNmeaPort = 10110;

  final String host;
  final int port;
  final ShipAisProtocol protocol;

  /// Sambung ulang otomatis bila koneksi putus.
  /// DEFAULT MATI — koneksi tidak boleh menyala diam-diam;
  /// hanya aktif bila pengguna mengaktifkan eksplisit di panel.
  final bool autoReconnect;

  bool get isValid => host.trim().isNotEmpty && port >= 1 && port <= 65535;

  String get label => '$host:$port (${protocol.label})';

  ShipAisConfig copyWith({
    String? host,
    int? port,
    ShipAisProtocol? protocol,
    bool? autoReconnect,
  }) {
    return ShipAisConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }
}

/// Statistik sesi AIS kapal (untuk panel + diagnosis).
class ShipAisStats {
  const ShipAisStats({
    this.sentencesReceived = 0,
    this.messagesDecoded = 0,
    this.vesselsSeen = 0,
    this.lastMessageAt,
    this.lastError,
  });

  final int sentencesReceived;
  final int messagesDecoded;
  final int vesselsSeen;
  final DateTime? lastMessageAt;
  final String? lastError;

  ShipAisStats copyWith({
    int? sentencesReceived,
    int? messagesDecoded,
    int? vesselsSeen,
    DateTime? lastMessageAt,
    String? lastError,
    bool clearError = false,
  }) {
    return ShipAisStats(
      sentencesReceived: sentencesReceived ?? this.sentencesReceived,
      messagesDecoded: messagesDecoded ?? this.messagesDecoded,
      vesselsSeen: vesselsSeen ?? this.vesselsSeen,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Klien AIS kapal sungguhan lewat WiFi (NMEA 0183, AIVDM/AIVDO).
///
/// Sumber data OFFLINE — data langsung dari antena AIS kapal lewat
/// receiver/multiplexer WiFi (mis. Quark-Elec QK-A027, Yacht Devices
/// YDWN-02, Digital Yacht WLN10). Bekerja tanpa internet di laut.
///
/// - TCP: aplikasi tersambung ke host:port gateway.
/// - UDP: aplikasi MENDENGARKAN di port lokal; gateway mengirim
///   datagram NMEA ke IP HP (host diabaikan, kecuali alamat
///   multicast 224.x–239.x — socket ikut grup multicast itu).
///
/// Hanya memakai dart:io (tanpa package baru). Bluetooth SPP
/// dipisah ke [ShipAisBluetoothService] (butuh package tambahan —
/// lihat file itu).
class ShipAisService {
  ShipAisService({
    SharedPreferences? prefs,
    NmeaAisParser? parser,
  })  : _prefs = prefs,
        _parser = parser ?? NmeaAisParser();

  final SharedPreferences? _prefs;
  final NmeaAisParser _parser;

  static const _prefHost = 'ship_ais_host';
  static const _prefPort = 'ship_ais_port';
  static const _prefProtocol = 'ship_ais_protocol';
  static const _prefAutoReconnect = 'ship_ais_auto_reconnect';

  /// Jeda reconnect (detik) — sama dengan AisService.
  static const _backoffSeconds = [5, 10, 20, 40, 60];

  /// Batas buffer baris — stream tanpa newline tidak boleh
  /// membengkak tanpa batas.
  static const _maxLineBufferLength = 8192;

  ShipAisConfig _config = const ShipAisConfig();
  ShipAisConnectionState _state = ShipAisConnectionState.disconnected;
  ShipAisStats _stats = const ShipAisStats();
  final Set<int> _vesselsSeen = {};

  Socket? _tcpSocket;
  RawDatagramSocket? _udpSocket;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
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

  ShipAisConfig get config => _config;
  ShipAisConnectionState get connectionState => _state;
  ShipAisStats get stats => _stats;
  bool get isConnected => _state == ShipAisConnectionState.connected;

  /// Port lokal yang dipakai sesi aktif (TCP: port lokal socket;
  /// UDP: port listen). Null bila tidak tersambung.
  int? get localPort => _tcpSocket?.port ?? _udpSocket?.port;

  Stream<ShipAisConnectionState> get connectionStateStream =>
      _stateController.stream;

  /// Hasil decode setiap pesan AIS (kapal parsial — lihat
  /// [NmeaAisParser.feed]).
  Stream<ShipAisParseResult> get resultsStream => _resultsController.stream;

  /// Posisi kapal SENDIRI dari AIVDO — sumber terbaik untuk CPA
  /// (lebih baik dari GPS). Di-emit terpisah agar fitur CPA bisa
  /// memakainya langsung tanpa menyaring stream utama.
  Stream<Vessel> get ownShipStream => _ownShipController.stream;

  Stream<ShipAisStats> get statsStream => _statsController.stream;

  /// Muat konfigurasi tersimpan (atau default bila belum ada).
  Future<ShipAisConfig> loadConfig() async {
    final prefs = _prefs;
    if (prefs == null) return _config;
    _config = ShipAisConfig(
      host: prefs.getString(_prefHost) ?? ShipAisConfig.defaultHost,
      port: prefs.getInt(_prefPort) ?? ShipAisConfig.defaultPort,
      protocol: ShipAisProtocolLabel.fromName(
        prefs.getString(_prefProtocol),
      ),
      autoReconnect: prefs.getBool(_prefAutoReconnect) ?? false,
    );
    return _config;
  }

  /// Simpan konfigurasi (dipanggil panel saat pengguna mengubahnya).
  Future<void> saveConfig(ShipAisConfig config) async {
    _config = config;
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_prefHost, config.host);
    await prefs.setInt(_prefPort, config.port);
    await prefs.setString(_prefProtocol, config.protocol.name);
    await prefs.setBool(_prefAutoReconnect, config.autoReconnect);
  }

  /// Tersambung ke gateway AIS kapal.
  ///
  /// Bila [config] diberikan, konfigurasi itu dipakai dan disimpan.
  /// Mengembalikan [Result.error] bila konfigurasi tidak valid atau
  /// sambungan gagal — status menjadi [ShipAisConnectionState.error]
  /// dengan pesan di [ShipAisStats.lastError].
  Future<Result<void>> connect([ShipAisConfig? config]) async {
    if (config != null) await saveConfig(config);
    if (!_config.isValid) {
      return _fail(const FormatException(
        'Host atau port tidak valid.',
      ));
    }
    await disconnect(silent: true);
    _manualDisconnect = false;
    _reconnectAttempt = 0;
    _setState(ShipAisConnectionState.connecting);
    try {
      if (_config.protocol == ShipAisProtocol.tcp) {
        await _connectTcp();
      } else {
        await _connectUdp();
      }
      _setState(ShipAisConnectionState.connected);
      _updateStats(_stats.copyWith(clearError: true));
      return const Result.ok(null);
    } on Exception catch (e) {
      return _fail(e);
    }
  }

  /// Putuskan koneksi (tombol PUTUSKAN KONEKSI di panel).
  /// Membatalkan timer reconnect — tidak ada sambungan diam-diam
  /// setelah pengguna memutuskan.
  Future<void> disconnect({bool silent = false}) async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeSockets();
    if (!silent) _setState(ShipAisConnectionState.disconnected);
  }

  /// Uji sambungan tanpa memulai sesi: tersambung (TCP) atau
  /// mendengarkan (UDP) lalu menunggu kalimat NMEA pertama.
  ///
  /// Ok(true) = data NMEA diterima. Ok(false) = tersambung tapi
  /// tidak ada data dalam [timeout] (gateway diam / salah port).
  /// Error = tidak bisa tersambung sama sekali. Menolak bila sesi
  /// sedang aktif — putuskan dulu.
  Future<Result<bool>> testConnection(
    ShipAisConfig config, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (isConnected) {
      return Result.error(Exception('Sudah tersambung — putuskan dulu.'));
    }
    if (!config.isValid) {
      return Result.error(
        const FormatException('Host atau port tidak valid.'),
      );
    }
    if (config.protocol == ShipAisProtocol.tcp) {
      return _testTcp(config, timeout);
    }
    return _testUdp(config, timeout);
  }

  Future<Result<bool>> _testTcp(
    ShipAisConfig config,
    Duration timeout,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 10),
      );
      final received = Completer<bool>();
      final subscription = socket.listen(
        (bytes) {
          final text = latin1.decode(bytes);
          if (!received.isCompleted &&
              (text.contains('AIVDM') || text.contains('AIVDO'))) {
            received.complete(true);
          }
        },
        onError: (_) {
          if (!received.isCompleted) received.complete(false);
        },
        onDone: () {
          if (!received.isCompleted) received.complete(false);
        },
      );
      final gotData = await received.future.timeout(timeout, onTimeout: () {
        return false;
      });
      await subscription.cancel();
      return Result.ok(gotData);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      await socket?.close();
    }
  }

  Future<Result<bool>> _testUdp(
    ShipAisConfig config,
    Duration timeout,
  ) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        config.port,
      );
      final received = Completer<bool>();
      final subscription = socket.listen((_) {
        final datagram = socket?.receive();
        if (datagram == null) return;
        final text = latin1.decode(datagram.data);
        if (!received.isCompleted &&
            (text.contains('AIVDM') || text.contains('AIVDO'))) {
          received.complete(true);
        }
      });
      final gotData = await received.future.timeout(timeout, onTimeout: () {
        return false;
      });
      await subscription.cancel();
      return Result.ok(gotData);
    } on Exception catch (e) {
      return Result.error(e);
    } finally {
      socket?.close();
    }
  }

  /// Proses byte mentah dari socket (dipakai internal + test).
  /// Memecah stream menjadi baris NMEA (pemisah '\n').
  void handleBytes(List<int> bytes) {
    _lineBuffer += latin1.decode(bytes);
    if (_lineBuffer.length > _maxLineBufferLength) {
      // Stream tanpa newline (sampah) — buang buffer, jangan bengkak.
      _lineBuffer = '';
      return;
    }
    final lines = _lineBuffer.split('\n');
    _lineBuffer = lines.removeLast();
    for (final line in lines) {
      handleLine(line);
    }
  }

  /// Proses satu baris NMEA (dipakai internal + test).
  void handleLine(String line) {
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

  Future<void> _connectTcp() async {
    final socket = await Socket.connect(
      _config.host,
      _config.port,
      timeout: const Duration(seconds: 10),
    );
    _tcpSocket = socket;
    socket.listen(
      handleBytes,
      onError: _onSocketError,
      onDone: _onSocketDone,
      cancelOnError: true,
    );
  }

  Future<void> _connectUdp() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _config.port,
    );
    _udpSocket = socket;
    // Host multicast (224.x–239.x): ikut grup multicast gateway.
    final host = InternetAddress.tryParse(_config.host);
    if (host != null && host.rawAddress[0] >= 224 && host.rawAddress[0] <= 239) {
      try {
        socket.joinMulticast(host);
      } on Exception {
        // Perangkat tidak mendukung multicast — tetap dengarkan unicast.
      }
    }
    _udpSubscription = socket.listen((_) {
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        handleBytes(datagram!.data);
      }
    });
  }

  Future<void> _closeSockets() async {
    await _udpSubscription?.cancel();
    _udpSubscription = null;
    _udpSocket?.close();
    _udpSocket = null;
    await _tcpSocket?.close();
    _tcpSocket = null;
    _lineBuffer = '';
  }

  void _onSocketError(Object error) {
    if (_manualDisconnect || _disposed) return;
    _updateStats(_stats.copyWith(lastError: _shortError(error)));
    _scheduleReconnect();
  }

  void _onSocketDone() {
    if (_manualDisconnect || _disposed) return;
    _scheduleReconnect();
  }

  /// Reconnect HANYA bila auto-reconnect aktif (default mati).
  /// Tanpa itu, putusnya koneksi = status error + diam.
  void _scheduleReconnect() {
    _closeSockets();
    if (!_config.autoReconnect || _manualDisconnect || _disposed) {
      _setState(ShipAisConnectionState.error);
      return;
    }
    _setState(ShipAisConnectionState.reconnecting);
    final delay = _backoffSeconds[
        _reconnectAttempt < _backoffSeconds.length
            ? _reconnectAttempt
            : _backoffSeconds.length - 1];
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      if (_manualDisconnect || _disposed) return;
      await connect();
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

  /// Pesan error singkat untuk panel (tanpa stack trace).
  static String _shortError(Object error) {
    if (error is SocketException) {
      final message = error.message;
      return message.isNotEmpty ? message : 'Tidak bisa tersambung.';
    }
    final text = error.toString();
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _closeSockets();
    _stateController.close();
    _resultsController.close();
    _ownShipController.close();
    _statsController.close();
  }
}
