import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Notifikasi lokal (peringatan cuaca + alarm jangkar).
/// Inisialisasi malas + semua kegagalan ditelan: notifikasi adalah
/// pelengkap — bila plugin gagal, aplikasi tetap jalan dan peringatan
/// tetap tampil di dalam aplikasi (notice/banner).
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _initAttempted = false;
  bool _permissionRequested = false;

  /// Minta izin notifikasi (Android 13+). Dipanggil saat user
  /// mengaktifkan fitur yang memakai notifikasi (alarm jangkar /
  /// peringatan cuaca) — bukan saat notifikasi pertama berbunyi.
  /// Gagal/ditolak = notifikasi diam, peringatan dalam aplikasi
  /// tetap jalan.
  Future<void> requestPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    try {
      await Permission.notification.request();
    } catch (_) {
      // Izin gagal diminta — notifikasi tetap dicoba (akan diam bila
      // ditolak), peringatan dalam aplikasi tetap tampil.
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized || _initAttempted) return;
    _initAttempted = true;
    try {
      const android = AndroidInitializationSettings('ic_notification');
      await _plugin.initialize(
        const InitializationSettings(android: android),
      );
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  /// Peringatan ambang cuaca (channel peringatan cuaca).
  Future<void> showWeatherAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'petalaut_alerts',
            'Peringatan cuaca',
            channelDescription:
                'Peringatan ambang angin, gelombang, dan hujan',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {
      // Notifikasi gagal — peringatan tetap tampil di dalam aplikasi.
    }
  }

  /// Alarm jangkar (channel terpisah, prioritas maksimal).
  Future<void> showAnchorAlarm({
    required String body,
  }) async {
    await _ensureInitialized();
    if (!_initialized) return;
    try {
      await _plugin.show(
        9001,
        'Alarm jangkar!',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'petalaut_anchor',
            'Alarm jangkar',
            channelDescription: 'Peringatan kapal keluar radius jangkar',
            importance: Importance.max,
            priority: Priority.max,
          ),
        ),
      );
    } catch (_) {
      // Notifikasi gagal — banner alarm tetap tampil di aplikasi.
    }
  }
}
