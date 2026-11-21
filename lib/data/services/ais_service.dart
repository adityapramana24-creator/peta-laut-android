import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/models/vessel.dart';
import '../../utils/result.dart';

/// AISStream WebSocket (wss://stream.aisstream.io/v0/stream).
/// Aplikasi native tidak kena CORS — koneksi langsung dari app.
/// Kunci API TIDAK PERNAH di-log atau ditampilkan di mana pun.
/// Subscription dikirim < 3 detik setelah connect (syarat AISStream);
/// maks 3 koneksi per akun — service ini menjaga SATU koneksi.
///
/// FAKTA KUNCI (dokumen resmi aisstream.io/documentation, dicek
/// 2026-11-21): "The service sends binary WebSocket frames whose
/// payload is UTF-8 JSON. Decode the frame bytes before parsing
/// JSON." Di Dart, frame biner tiba sebagai List<int>, BUKAN String.
/// Versi 1.1 hanya menerima `data is String`, sehingga SEMUA pesan
/// server dibuang diam-diam dan peta kapal kosong meski kunci valid —
/// sementara status tetap "Terhubung" karena data apa pun memicu
/// connected. decodeFrame() menangani keduanya; test regresi di
/// test/ais_transport_test.dart.
///
/// BATASAN JUJUR (G6): dart:io tidak mendukung permessage-deflate,
/// jadi koneksi ini tak terkompresi — sejak Sep 2026 AISStream
/// membatasi bandwidth koneksi tak terkompresi dan pesan yang
/// melebihi batas dibuang server. Bbox yang fokus (viewport peta,
/// bukan kotak raksasa) mengurangi risiko ini.
class AisService {
  AisService();

  static const _endpoint = 'wss://stream.aisstream.io/v0/stream';

  /// Tipe pesan yang dilanggan: posisi + statis Kelas A dan B.
  /// Kelas B penting di Indonesia (kapal kecil/nelayan).
  static const List<String> messageTypes = [
    'PositionReport',
    'ShipStaticData',
    'StandardClassBPositionReport',
    'ExtendedClassBPositionReport',
    'StaticDataReport',
  ];

  /// Berapa kali koneksi boleh putus tanpa konfirmasi langganan
  /// sebelum dinyatakan error fatal (kemungkinan kunci ditolak).
  /// Di bawah itu, dianggap gangguan jaringan sesaat.
  static const int maxUnconfirmedCloses = 3;

  /// Decode satu frame WebSocket ke Map JSON, atau null bila bukan
  /// JSON objek yang valid. Menerima String (frame teks) DAN List<int>
  /// (frame biner — bentuk yang dipakai AISStream).
  static Map<String, dynamic>? decodeFrame(dynamic data) {
    try {
      if (data is String) {
        final decoded = jsonDecode(data);
        return decoded is Map<String, dynamic> ? decoded : null;
      }
      if (data is List<int>) {
        final decoded = jsonDecode(utf8.decode(data));
        return decoded is Map<String, dynamic> ? decoded : null;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Langganan yang diterima server dibalas SubscriptionConfirmation;
  /// yang tidak valid tidak dibalas (dokumen resmi §Subscribe).
  /// Konfirmasi inilah syarat status "connected" (G1/G2).
  static bool isSubscriptionConfirmation(Map<String, dynamic> msg) =>
      msg['MessageType'] == 'SubscriptionConfirmation';

  /// Pesan AIS asli (punya MetaData.MMSI) — juga bukti langganan
  /// diterima bila konfirmasi terlewat.
  static bool isAisMessage(Map<String, dynamic> msg) {
    final meta = msg['MetaData'];
    return meta is Map && meta['MMSI'] != null;
  }

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  String? _apiKey;
  (double, double, double, double)? _bounds;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _unconfirmedCloses = 0;
  bool _subscriptionConfirmed = false;
  bool _disposed = false;
  String? _lastError;

  // Statistik jalur data (untuk diagnosis di panel AIS).
  int _framesReceived = 0;
  int _framesDecoded = 0;
  int _framesDropped = 0;
  DateTime? _lastFrameAt;

  final _connectionStateController =
      StreamController<AisConnectionState>.broadcast();
  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<AisConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool get isConnected => _channel != null;

  /// true bila server sudah mengonfirmasi langganan pada koneksi ini.
  bool get subscriptionConfirmed => _subscriptionConfirmed;

  /// Pesan error terakhir yang bisa dibaca pengguna (null bila tidak
  /// ada). TIDAK PERNAH berisi kunci.
  String? get lastError => _lastError;

  int get framesReceived => _framesReceived;
  int get framesDecoded => _framesDecoded;
  int get framesDropped => _framesDropped;
  DateTime? get lastFrameAt => _lastFrameAt;

  /// Mulai koneksi dengan kunci + bbox awal.
  /// bounds = (minLat, minLon, maxLat, maxLon).
  Future<void> connect(
    String apiKey, {
    required (double, double, double, double) bounds,
  }) async {
    _apiKey = apiKey;
    _bounds = bounds;
    _reconnectAttempts = 0;
    _unconfirmedCloses = 0;
    _lastError = null;
    await _open();
  }

  /// Perbarui area langganan: kirim ulang subscription di koneksi
  /// yang sama (AISStream menerima subscription baru kapan pun,
  /// maks 1/detik — pemanggil wajib debounce, lihat MapViewModel).
  void updateBounds((double, double, double, double) bounds) {
    _bounds = bounds;
    _sendSubscription();
  }

  Future<void> _open() async {
    _cancelReconnect();
    _closeChannel();
    if (_disposed || _apiKey == null || _bounds == null) return;
    _subscriptionConfirmed = false;
    _emit(AisConnectionState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_endpoint));
      _sendSubscription();
      _subscription = _channel!.stream.listen(
        (data) {
          _framesReceived++;
          _lastFrameAt = DateTime.now();
          final decoded = decodeFrame(data);
          if (decoded == null) {
            _framesDropped++;
            return;
          }
          _framesDecoded++;
          if (isSubscriptionConfirmation(decoded) ||
              isAisMessage(decoded)) {
            if (!_subscriptionConfirmed) {
              _subscriptionConfirmed = true;
              _unconfirmedCloses = 0;
              _reconnectAttempts = 0;
              _lastError = null;
              _emit(AisConnectionState.connected);
            }
          }
          if (isSubscriptionConfirmation(decoded)) return;
          _messageController.add(decoded);
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () {
          if (_disposed) return;
          if (_subscriptionConfirmed) {
            // Putus di tengah stream: gangguan sesaat, sambung ulang.
            _scheduleReconnect();
            return;
          }
          // Putus SEBELUM konfirmasi: kunci ditolak / langganan tidak
          // valid / jaringan putus lebih awal. Beri kesempatan
          // reconnect beberapa kali, lalu nyatakan error yang jelas.
          _unconfirmedCloses++;
          if (_unconfirmedCloses >= maxUnconfirmedCloses) {
            _fatalError(
              'Server menutup koneksi sebelum langganan dikonfirmasi — '
              'kunci mungkin ditolak. Periksa kunci di Pengaturan.',
            );
          } else {
            _scheduleReconnect();
          }
        },
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _sendSubscription() {
    final channel = _channel;
    final key = _apiKey;
    final bounds = _bounds;
    if (channel == null || key == null || bounds == null) return;
    final (minLat, minLon, maxLat, maxLon) = bounds;
    final payload = {
      'APIKey': key,
      'BoundingBoxes': [
        [
          [minLat, minLon],
          [maxLat, maxLon],
        ],
      ],
      // G4: dokumen mewajibkan string 9 karakter bila diisi.
      'FiltersShipMMSI': <String>[],
      'FilterMessageTypes': messageTypes,
    };
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _closeChannel();
    if (_disposed || _apiKey == null) return;
    _emit(AisConnectionState.reconnecting);
    _reconnectAttempts++;
    // Backoff: 5 dtk, 10, 20, 40, lalu 60 dtk (maks).
    final delaySeconds = [5, 10, 20, 40, 60][
        _reconnectAttempts > 5 ? 4 : _reconnectAttempts - 1];
    _reconnectTimer = Timer(
      Duration(seconds: delaySeconds),
      () {
        if (!_disposed) _open();
      },
    );
  }

  /// Error fatal: hentikan reconnect otomatis, tampilkan pesan jelas.
  /// Pengguna bisa mencoba lagi dari panel (tombol "Coba lagi").
  void _fatalError(String message) {
    _closeChannel();
    _lastError = message;
    _emit(AisConnectionState.error);
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _closeChannel() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {
      // Abaikan error penutupan.
    }
    _channel = null;
  }

  void _emit(AisConnectionState state) {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  /// Uji kunci: koneksi singkat. Berhasil HANYA bila server
  /// mengonfirmasi langganan (atau mengirim pesan AIS nyata) dalam
  /// batas waktu. Timeout TANPA pesan = gagal (G7 — versi 1.1
  /// menganggap timeout sebagai "valid" palsu).
  Future<Result<bool>> testConnection(
    String apiKey, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(_endpoint));
      final completer = Completer<bool>();
      final sub = channel.stream.listen(
        (data) {
          if (completer.isCompleted) return;
          final decoded = decodeFrame(data);
          if (decoded == null) return;
          if (isSubscriptionConfirmation(decoded) ||
              isAisMessage(decoded)) {
            completer.complete(true);
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      // Subscription dummy bbox kecil di sekitar Jakarta.
      channel.sink.add(jsonEncode({
        'APIKey': apiKey,
        'BoundingBoxes': [
          [
            [-6.5, 106.5],
            [-6.0, 107.0],
          ],
        ],
        'FiltersShipMMSI': <String>[],
        'FilterMessageTypes': messageTypes,
      }));
      // Kunci salah -> server menutup koneksi segera.
      // Kunci benar -> SubscriptionConfirmation datang cepat.
      final ok = await completer.future.timeout(
        timeout,
        onTimeout: () => false,
      );
      await sub.cancel();
      if (ok) return const Result.ok(true);
      return Result.error(
        Exception(
          'Server tidak mengonfirmasi langganan — kunci mungkin '
          'ditolak atau jaringan bermasalah.',
        ),
      );
    } catch (e) {
      return Result.error(Exception('Uji sambungan gagal: $e'));
    } finally {
      try {
        await channel?.sink.close();
      } catch (_) {
        // Abaikan.
      }
    }
  }

  Future<void> disconnect() async {
    _cancelReconnect();
    _closeChannel();
    _apiKey = null;
    _bounds = null;
    _subscriptionConfirmed = false;
    _lastError = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _connectionStateController.close();
    await _messageController.close();
  }
}
