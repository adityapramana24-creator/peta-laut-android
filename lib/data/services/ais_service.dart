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
class AisService {
  AisService();

  static const _endpoint = 'wss://stream.aisstream.io/v0/stream';

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  String? _apiKey;
  (double, double, double, double)? _bounds;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  final _connectionStateController =
      StreamController<AisConnectionState>.broadcast();
  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<AisConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool get isConnected => _channel != null;

  /// Mulai koneksi dengan kunci + bbox awal.
  /// bounds = (minLat, minLon, maxLat, maxLon).
  Future<void> connect(
    String apiKey, {
    required (double, double, double, double) bounds,
  }) async {
    _apiKey = apiKey;
    _bounds = bounds;
    _reconnectAttempts = 0;
    await _open();
  }

  /// Perbarui area langganan: kirim ulang subscription di koneksi
  /// yang sama (AISStream menerima subscription baru kapan pun).
  void updateBounds((double, double, double, double) bounds) {
    _bounds = bounds;
    _sendSubscription();
  }

  Future<void> _open() async {
    _cancelReconnect();
    _closeChannel();
    if (_disposed || _apiKey == null || _bounds == null) return;
    _emit(AisConnectionState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_endpoint));
      _sendSubscription();
      _subscription = _channel!.stream.listen(
        (data) {
          if (_reconnectAttempts > 0) {
            _reconnectAttempts = 0;
          }
          _emit(AisConnectionState.connected);
          if (data is String) {
            try {
              final decoded = jsonDecode(data);
              if (decoded is Map<String, dynamic>) {
                _messageController.add(decoded);
              }
            } catch (_) {
              // Abaikan satu pesan rusak.
            }
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () {
          if (!_disposed) _scheduleReconnect();
        },
        cancelOnError: false,
      );
      // Anggap terhubung setelah subscription terkirim; status
      // "connected" dikonfirmasi saat pesan pertama diterima.
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
      'FiltersShipMMSI': <int>[],
      'FilterMessageTypes': ['PositionReport', 'ShipStaticData'],
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

  /// Uji kunci: koneksi singkat, berhasil bila WebSocket terbuka dan
  /// subscription terkirim tanpa error dalam batas waktu.
  /// Mengembalikan true bila koneksi terbuka.
  Future<Result<bool>> testConnection(
    String apiKey, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(_endpoint));
      final completer = Completer<bool>();
      final sub = channel.stream.listen(
        (_) {
          if (!completer.isCompleted) completer.complete(true);
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
        'FiltersShipMMSI': <int>[],
        'FilterMessageTypes': ['PositionReport'],
      }));
      // Kunci salah -> server menutup koneksi / mengirim error segera.
      // Kunci benar -> koneksi tetap terbuka (atau pesan masuk).
      final ok = await completer.future.timeout(
        timeout,
        onTimeout: () => true,
      );
      await sub.cancel();
      if (ok) return const Result.ok(true);
      return Result.error(
        Exception('Kunci ditolak server AISStream. Periksa kunci Anda.'),
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
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _connectionStateController.close();
    await _messageController.close();
  }
}
